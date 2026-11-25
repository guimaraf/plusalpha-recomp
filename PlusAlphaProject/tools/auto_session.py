#!/usr/bin/env python3
"""Sessao autonoma: build isolado + execucao no monitor 1 + rota de input via TCP.

Subcomandos: build | run --build-dir X --route NOME | all --route NOME.
Somente stdlib + ctypes. Nunca usa SendInput, foco, nem captura de desktop: toda
entrada vai pela porta TCP de debug do runtime; as imagens vem do framebuffer
emulado (screenshot_file). Ver docs/PLANO_100.md, Fase A.
"""
import argparse
import ctypes
import datetime
import hashlib
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TOOLS_DIR.parent
REPO_ROOT = PROJECT_ROOT.parent
ROUTES_DIR = TOOLS_DIR / "auto_routes"
EVIDENCE_BASE = REPO_ROOT.parent / "relatorios"
DEFAULT_PORT = 4631
BELOW_NORMAL = 0x00004000
EXE_NAME = "exPlusAlpha.exe"

# Bits do pad PSX. O runtime recebe a palavra ATIVO-BAIXO (bit 0 = pressionado;
# 0xFFFF = nada pressionado; Start = 0xFFF7). Ver psxrecomp/runtime/src/debug_server.c
# (press/set_input/input_route_append; idle 0xFFFF em ~16547).
BUTTON_BITS = {
    "select": 0x0001, "start": 0x0008, "up": 0x0010, "right": 0x0020,
    "down": 0x0040, "left": 0x0080, "l2": 0x0100, "r2": 0x0200,
    "l1": 0x0400, "r1": 0x0800, "triangle": 0x1000, "circle": 0x2000,
    "cross": 0x4000, "square": 0x8000,
}
BUTTON_ALIASES = {"x": "cross", "o": "circle", "sq": "square", "tri": "triangle"}
IDLE_WORD = 0xFFFF

STEP_TYPES = {"wait_frames", "press", "screenshot", "savestate", "telemetry", "expect",
              "read_ram", "wait_ram", "fntrace", "dispatch_misses"}
FNTRACE_ARM_MAX = 32  # runtime/include/fntrace.h
EXE_PHYS_LO, EXE_PHYS_HI = 0x00101000, 0x001C0000  # texto do EXE principal (fisico)
EXPECT_CHECKS = {"frame_min", "fmv_field", "shot_differs", "shot_equals", "ok"}
TELEMETRY_KEYS = {"dispatch_stats", "overlay_interp_hot", "static_text_misses",
                  "frame_perf", "fmv_state", "frame", "overlay_loader_status",
                  "dirty_ram_stats", "segment_misses", "phase_profile", "latency",
                  "dispatch_misses"}
OVERLAY_SOURCES = ("aot", "retained")
SHOT_DISPLAY_RETRIES = 8  # novas tentativas se o guest apagou o display (GP1 03h)
SHOT_DISPLAY_WAIT_FRAMES = 15
STATIC_MATCH_CACHE_CAP = 16384  # overlay_loader.c: cache de CRC dos overlays estaticos


# ---------------------------------------------------------------- logica pura

def pick_monitor1(rects):
    """rects: lista (left, top, right, bottom) ja em ordem de enumeracao
    (primario primeiro). Devolve o retangulo do monitor 1; recusa sem ele."""
    if len(rects) < 2:
        raise RuntimeError("Monitor 1 ausente: nao executo (o monitor 0 e do usuario).")
    r = tuple(rects[1])
    if r[2] <= r[0] or r[3] <= r[1]:
        raise RuntimeError(f"Retangulo invalido para o monitor 1: {r}")
    if tuple(rects[0]) == r:
        raise RuntimeError("Monitor 1 identico ao monitor 0 (espelhado?): nao executo.")
    return r


def parse_addr(value):
    """Endereco como int ou string ('0x801D39B8'); levanta ValueError se invalido."""
    if isinstance(value, bool):
        raise ValueError(f"endereco invalido: {value!r}")
    if isinstance(value, int):
        return value
    return int(str(value), 0)


def le_value(hex_str, size):
    """Valor little-endian (ate 8 bytes) de uma string hex devolvida por read_ram."""
    raw = bytes.fromhex(hex_str)[:size]
    return int.from_bytes(raw, "little")


def exe_misses(summary):
    """Linhas de unknown_dispatch_log (phys, count) que caem no texto do EXE principal,
    como [{"pc": "0x80xxxxxx", "count": n}] ordenadas por contagem."""
    out = []
    for row in summary or []:
        phys = int(str(row.get("phys", "0")), 0)
        if EXE_PHYS_LO <= phys < EXE_PHYS_HI:
            out.append({"pc": f"0x{0x80000000 | phys:08X}", "count": int(row.get("count", 0))})
    return sorted(out, key=lambda r: -r["count"])


def exe_interp_pcs(per_pc):
    """PCs do texto do EXE principal que rodaram interpretados (dirty_ram_stats.per_pc, fisicos):
    [{"pc": "0x80xxxxxx", "hits": n, "insns": n}] por insns decrescente. Sao os misses reais
    de compilacao estatica neste runtime (unknown_dispatch_log so conta despachos sem alvo)."""
    out = []
    for e in per_pc or []:
        phys = int(str(e.get("pc", "0")), 0) & 0x1FFFFFFF
        if EXE_PHYS_LO <= phys < EXE_PHYS_HI:
            out.append({"pc": f"0x{0x80000000 | phys:08X}", "hits": e.get("hits", 0),
                        "insns": e.get("insns", 0)})
    return sorted(out, key=lambda r: -r["insns"])


def count_fntrace_hits(entries, pcs):
    """{pc: {"hits": n, "first_frame": f, "last_frame": f}} para cada PC armado."""
    res = {f"0x{pc:08X}": {"hits": 0} for pc in pcs}
    for e in entries or []:
        key = f"0x{int(str(e['target']), 0):08X}"
        if key not in res:
            continue
        r = res[key]
        r["hits"] += 1
        fr = e.get("frame")
        if fr is not None:
            r["first_frame"] = fr if "first_frame" not in r else min(r["first_frame"], fr)
            r["last_frame"] = fr if "last_frame" not in r else max(r["last_frame"], fr)
    return res


def button_mask(names):
    mask = 0
    for raw in names:
        key = str(raw).strip().lower()
        key = BUTTON_ALIASES.get(key, key)
        if key not in BUTTON_BITS:
            raise ValueError(f"botao desconhecido: {raw!r}")
        mask |= BUTTON_BITS[key]
    return mask


def buttons_word(names):
    """Palavra ativo-baixo para o runtime (nenhum botao = 0xFFFF)."""
    return IDLE_WORD & ~button_mask(names)


def validate_route(route):
    """Levanta ValueError se a rota for invalida; devolve a rota."""
    if not isinstance(route, dict):
        raise ValueError("rota deve ser um objeto JSON")
    steps = route.get("steps")
    if not isinstance(steps, list) or not steps:
        raise ValueError("rota sem 'steps'")
    for i, step in enumerate(steps):
        where = f"passo {i}"
        if not isinstance(step, dict):
            raise ValueError(f"{where}: deve ser objeto")
        kind = step.get("type")
        if kind not in STEP_TYPES:
            raise ValueError(f"{where}: type invalido {kind!r}")
        if kind == "wait_frames":
            if not isinstance(step.get("frames"), int) or step["frames"] <= 0:
                raise ValueError(f"{where}: frames deve ser inteiro positivo")
        elif kind == "press":
            buttons = step.get("buttons")
            if not isinstance(buttons, list) or not buttons:
                raise ValueError(f"{where}: buttons deve ser lista nao vazia")
            button_mask(buttons)
            if not isinstance(step.get("frames", 4), int) or step.get("frames", 4) <= 0:
                raise ValueError(f"{where}: frames deve ser inteiro positivo")
            if step.get("wait_after", 0) < 0:
                raise ValueError(f"{where}: wait_after negativo")
        elif kind == "screenshot":
            if not step.get("name"):
                raise ValueError(f"{where}: screenshot requer name")
        elif kind == "savestate":
            if step.get("op", "save") not in ("save", "load"):
                raise ValueError(f"{where}: op deve ser save|load")
            if not isinstance(step.get("slot", 0), int) or step.get("slot", 0) < 0:
                raise ValueError(f"{where}: slot invalido")
        elif kind == "read_ram":
            if not step.get("name"):
                raise ValueError(f"{where}: read_ram requer name")
            try:
                parse_addr(step.get("addr"))
            except (ValueError, TypeError):
                raise ValueError(f"{where}: read_ram requer addr valido")
            if not isinstance(step.get("size", 1), int) or not 1 <= step.get("size", 1) <= 4096:
                raise ValueError(f"{where}: size deve ficar entre 1 e 4096")
        elif kind == "wait_ram":
            try:
                parse_addr(step.get("addr"))
            except (ValueError, TypeError):
                raise ValueError(f"{where}: wait_ram requer addr valido")
            if not isinstance(step.get("size", 1), int) or not 1 <= step.get("size", 1) <= 4:
                raise ValueError(f"{where}: wait_ram size deve ficar entre 1 e 4")
            if not (isinstance(step.get("values"), list) or isinstance(step.get("not_values"), list)):
                raise ValueError(f"{where}: wait_ram requer values ou not_values")
            if not isinstance(step.get("timeout_frames", 600), int) or step.get("timeout_frames", 600) <= 0:
                raise ValueError(f"{where}: timeout_frames deve ser inteiro positivo")
        elif kind == "fntrace":
            op = step.get("op")
            if op not in ("arm", "dump"):
                raise ValueError(f"{where}: fntrace op deve ser arm|dump")
            if op == "arm":
                pcs = step.get("pcs")
                if not isinstance(pcs, list) or not pcs or len(pcs) > FNTRACE_ARM_MAX:
                    raise ValueError(f"{where}: fntrace arm requer 1..{FNTRACE_ARM_MAX} pcs")
                for pc in pcs:
                    parse_addr(pc)
            elif not step.get("name"):
                raise ValueError(f"{where}: fntrace dump requer name")
        elif kind == "dispatch_misses":
            if not step.get("name"):
                raise ValueError(f"{where}: dispatch_misses requer name")
        elif kind == "telemetry":
            if not step.get("name"):
                raise ValueError(f"{where}: telemetry requer name")
            unknown = set(step.get("which", [])) - TELEMETRY_KEYS
            if unknown:
                raise ValueError(f"{where}: telemetria desconhecida {sorted(unknown)}")
        elif kind == "expect":
            check = step.get("check")
            if check not in EXPECT_CHECKS:
                raise ValueError(f"{where}: check invalido {check!r}")
            if check in ("shot_differs", "shot_equals") and not (step.get("a") and step.get("b")):
                raise ValueError(f"{where}: {check} requer a e b")
            if check == "frame_min" and not isinstance(step.get("value"), int):
                raise ValueError(f"{where}: frame_min requer value inteiro")
            if check == "fmv_field" and not (step.get("field") and "value" in step):
                raise ValueError(f"{where}: fmv_field requer field e value")
    return route


def load_route(name_or_path):
    p = Path(name_or_path)
    if not p.is_file():
        p = ROUTES_DIR / (str(name_or_path) + ".json")
    if not p.is_file():
        raise FileNotFoundError(f"rota nao encontrada: {name_or_path}")
    return validate_route(json.loads(p.read_text(encoding="utf-8")))


def build_game_command(exe, game_toml, memcard_dir, port, disc=None, bios=None):
    """Linha de comando: sem launcher, janela oculta, estado isolado."""
    cmd = [str(exe), "--hidden-window", "--no-launcher",
           "--game", str(game_toml), "--memcard-dir", str(memcard_dir),
           "--debug-port", str(port)]
    if disc:
        cmd += ["--disc", str(disc)]
    if bios:
        cmd += ["--bios", str(bios)]
    return cmd


def build_powershell_command(build_dir_name, jobs, static_overlay_dir, overlay_source="aot",
                             generated_dir=None, seeds_file=None):
    if not build_dir_name.startswith("build-auto-"):
        raise ValueError("o build autonomo deve usar build-auto-<timestamp>")
    if not 1 <= jobs <= 4:
        raise ValueError("jobs deve ficar entre 1 e 4")
    if overlay_source not in OVERLAY_SOURCES:
        raise ValueError(f"overlay_source deve ser um de {OVERLAY_SOURCES}")
    cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
           str(TOOLS_DIR / "build_online.ps1"),
           "-BuildDirName", build_dir_name, "-Jobs", str(jobs),
           "-StaticOverlayDir", str(static_overlay_dir),
           "-OverlaySource", overlay_source]
    if generated_dir:  # geracao isolada por lote (fontes em <build>/generated)
        cmd += ["-GeneratedDir", str(generated_dir)]
        if seeds_file:
            cmd += ["-SeedsFile", str(seeds_file)]
    return cmd


def static_overlay_dir_for(build_dir, overlay_source):
    """AOT grava <build>/static-overlays; as retidas mantem <build>/retained-overlays."""
    return Path(build_dir) / ("static-overlays" if overlay_source == "aot" else "retained-overlays")


def detect_overlay_source(build_dir):
    """Fonte dos overlays de um build existente (para run.json)."""
    build_dir = Path(build_dir)
    if (build_dir / "static-overlays" / "AOT_STATIC_AUDIT.json").is_file():
        return "aot"
    if (build_dir / "retained-overlays" / "retained_coverage.json").is_file():
        return "retained"
    return "unknown"


def perf_indicators(frame, wall_s, prev, dirty, phase, loader):
    """Indicadores de desempenho por frame, a partir da telemetria bruta.

    guest_fps_since_prev: frames emulados por segundo de parede desde a telemetria anterior
    (prev = (frame, wall_s) ou None). insns_per_frame / native_handoffs_per_frame:
    dirty_ram_stats acumulado / frame. interp_share etc.: phase_profile (amostrador de fase).
    static_crc_cache: contadores do cache de CRC estatico (capacidade fixa no runtime).
    """
    out = {}
    if prev and frame > prev[0] and wall_s > prev[1]:
        out["guest_fps_since_prev"] = round((frame - prev[0]) / (wall_s - prev[1]), 2)
    if isinstance(dirty, dict) and dirty.get("ok") and frame > 0:
        out["insns_per_frame"] = round(dirty.get("insns_run", 0) / frame, 1)
        out["native_handoffs_per_frame"] = round(dirty.get("native_handoffs", 0) / frame, 2)
    if isinstance(phase, dict) and phase.get("ok"):
        for key in ("interp_share", "native_share", "static_share", "gpu_share", "other_share"):
            if key in phase:
                out[key] = phase[key]
    if isinstance(loader, dict) and loader.get("ok"):
        cache = {k: loader.get(k) for k in ("static_checks", "static_hits", "static_variant_misses",
                                            "static_address_misses", "static_rehashes",
                                            "static_crc_misses", "static_gen_fastpath")}
        cache["capacity"] = STATIC_MATCH_CACHE_CAP
        out["static_crc_cache"] = cache
    return out


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ------------------------------------------------------------------- Windows

class Win:
    """Acesso minimo a user32: enumeracao de monitores/janelas e foreground.
    Nunca ativa, foca nem envia input."""

    def __init__(self):
        from ctypes import wintypes as w
        self.w = w
        self.user = ctypes.WinDLL("user32", use_last_error=True)
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        u = self.user
        self.enum_window = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
        self.enum_monitor = ctypes.WINFUNCTYPE(
            w.BOOL, w.HANDLE, w.HDC, ctypes.POINTER(w.RECT), w.LPARAM)
        u.EnumWindows.argtypes = [self.enum_window, w.LPARAM]
        u.EnumWindows.restype = w.BOOL
        u.GetWindowThreadProcessId.argtypes = [w.HWND, ctypes.POINTER(w.DWORD)]
        u.GetWindowThreadProcessId.restype = w.DWORD
        u.GetForegroundWindow.restype = w.HWND
        u.GetWindowTextW.argtypes = [w.HWND, w.LPWSTR, ctypes.c_int]
        u.GetWindowRect.argtypes = [w.HWND, ctypes.POINTER(w.RECT)]
        u.GetWindowRect.restype = w.BOOL
        u.IsWindowVisible.argtypes = [w.HWND]
        u.IsWindowVisible.restype = w.BOOL
        u.SetWindowPos.argtypes = [w.HWND, w.HWND, ctypes.c_int, ctypes.c_int,
                                   ctypes.c_int, ctypes.c_int, w.UINT]
        u.SetWindowPos.restype = w.BOOL
        u.EnumDisplayMonitors.argtypes = [w.HDC, ctypes.POINTER(w.RECT),
                                          self.enum_monitor, w.LPARAM]
        u.EnumDisplayMonitors.restype = w.BOOL
        try:
            u.SetProcessDpiAwarenessContext.argtypes = [w.HANDLE]
            u.SetProcessDpiAwarenessContext.restype = w.BOOL
            u.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
        except (AttributeError, OSError):
            pass

        class MonitorInfo(ctypes.Structure):
            _fields_ = [("cbSize", w.DWORD), ("rcMonitor", w.RECT),
                        ("rcWork", w.RECT), ("dwFlags", w.DWORD)]
        self.MonitorInfo = MonitorInfo
        u.GetMonitorInfoW.argtypes = [w.HANDLE, ctypes.POINTER(MonitorInfo)]
        u.GetMonitorInfoW.restype = w.BOOL

    def monitors(self):
        """Retangulos completos em ordem de enumeracao (primario primeiro)."""
        found = []

        def cb(handle, *_):
            info = self.MonitorInfo()
            info.cbSize = ctypes.sizeof(info)
            if self.user.GetMonitorInfoW(handle, ctypes.byref(info)):
                r = info.rcMonitor
                found.append((not bool(info.dwFlags & 1), (r.left, r.top, r.right, r.bottom)))
            return True
        if not self.user.EnumDisplayMonitors(None, None, self.enum_monitor(cb), 0):
            raise ctypes.WinError(ctypes.get_last_error())
        found.sort()
        return [rect for _, rect in found]

    def foreground(self):
        w = self.w
        hwnd = self.user.GetForegroundWindow()
        if not hwnd:
            return {"hwnd": 0, "pid": 0, "title": ""}
        pid = w.DWORD()
        self.user.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        title = ctypes.create_unicode_buffer(256)
        self.user.GetWindowTextW(hwnd, title, len(title))
        return {"hwnd": int(hwnd), "pid": int(pid.value), "title": title.value}

    def windows_of(self, pid):
        w = self.w
        found = []

        def cb(hwnd, _):
            p = w.DWORD()
            self.user.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
            if p.value == pid:
                r = w.RECT()
                self.user.GetWindowRect(hwnd, ctypes.byref(r))
                title = ctypes.create_unicode_buffer(128)
                self.user.GetWindowTextW(hwnd, title, len(title))
                found.append({"hwnd": int(hwnd), "title": title.value, "visible": bool(self.user.IsWindowVisible(hwnd)),
                              "rect": (r.left, r.top, r.right, r.bottom)})
            return True
        self.user.EnumWindows(self.enum_window(cb), 0)
        return found

    def place_noactivate(self, hwnd, x, y, width, height, show=False):
        # SWP_NOZORDER 0x4 | SWP_NOACTIVATE 0x10 | SWP_SHOWWINDOW 0x40
        flags = 0x0004 | 0x0010 | (0x0040 if show else 0)
        ok = self.user.SetWindowPos(self.w.HWND(hwnd), None, x, y, width, height, flags)
        if not ok:
            raise ctypes.WinError(ctypes.get_last_error())


def fit_window(monitor, width, height):
    """Centra (width x height) no monitor, reduzindo proporcionalmente se preciso."""
    left, top, right, bottom = monitor
    mw, mh = right - left, bottom - top
    scale = min(1.0, mw / width, mh / height)
    width, height = max(1, int(width * scale)), max(1, int(height * scale))
    return left + (mw - width) // 2, top + (mh - height) // 2, width, height


# ----------------------------------------------------------------------- TCP

def send_command(port, req, timeout=15.0):
    """Uma linha JSON por requisicao; le um objeto JSON completo (balanceado)."""
    s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    try:
        s.sendall((json.dumps(req) + "\n").encode("utf-8"))
        data = bytearray()
        depth, in_str, esc, started = 0, False, False, False
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            done = False
            for b in chunk:
                data.append(b)
                ch = chr(b)
                if in_str:
                    if esc:
                        esc = False
                    elif ch == "\\":
                        esc = True
                    elif ch == '"':
                        in_str = False
                    continue
                if ch == '"':
                    in_str = True
                elif ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
                    if started and depth == 0:
                        done = True
                        break
            if done:
                break
    finally:
        s.close()
    return json.loads(data.decode("utf-8", errors="replace").strip())


def port_is_free(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.3):
            return False
    except OSError:
        return True


# --------------------------------------------------------------------- build

def now_stamp():
    return datetime.datetime.now().strftime("%Y%m%d-%H%M%S")


def make_evidence_dir(run_id=None):
    day = datetime.datetime.now().strftime("%Y%m%d")
    run_id = run_id or now_stamp()
    d = EVIDENCE_BASE / f"auto-{day}" / run_id
    d.mkdir(parents=True, exist_ok=True)
    return d


def no_concurrent_build():
    """Recusa se ja houver ninja/cmake/cc1 em execucao (builds nunca concorrem)."""
    out = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True,
                         text=True).stdout.lower()
    busy = [n for n in ("ninja.exe", "cmake.exe", "cc1.exe", "cc1plus.exe") if f'"{n}"' in out]
    if busy:
        raise RuntimeError(f"build concorrente detectado ({', '.join(busy)}); aguarde.")


def resolve_reuse_name(value):
    """Nome (build-auto-*) de um build a reaproveitar; aceita caminho ou nome."""
    name = Path(value).name
    if not name.startswith("build-auto-"):
        raise ValueError("--reuse-build deve ser um build-auto-*")
    return name


def do_build(evidence, jobs=4, overlay_source="aot", reuse_build=None, seeds=None):
    """reuse_build: nome de um build-auto-* (criado se nao existir) reaproveitado entre lotes; o
    ninja recompila so os shards alterados. Com reuse_build ou seeds, as fontes do EXE vao para
    <build>/generated (geracao isolada), a partir de `seeds` (padrao seeds/entry_funcs.txt)."""
    no_concurrent_build()
    name = resolve_reuse_name(reuse_build) if reuse_build else "build-auto-" + now_stamp()
    build_dir = PROJECT_ROOT / name
    overlays = static_overlay_dir_for(build_dir, overlay_source)
    isolated = bool(reuse_build or seeds)
    generated = build_dir / "generated" if isolated else None
    seeds_file = Path(seeds).resolve() if seeds else (
        PROJECT_ROOT / "seeds" / "entry_funcs.txt" if isolated else None)
    cmd = build_powershell_command(name, jobs, overlays, overlay_source, generated, seeds_file)
    log = evidence / "build.log"
    t0 = time.time()
    with open(log, "w", encoding="utf-8", errors="replace") as lf:
        lf.write("$ " + " ".join(cmd) + "\n")
        lf.flush()
        proc = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT,
                              creationflags=BELOW_NORMAL, cwd=str(PROJECT_ROOT))
    dur = time.time() - t0
    info = {"build_dir": str(build_dir), "overlay_source": overlay_source,
            "static_overlay_dir": str(overlays), "generated_dir": str(generated) if generated else None,
            "seeds_file": str(seeds_file) if seeds_file else None,
            "reused_build": bool(reuse_build), "command": cmd, "exit_code": proc.returncode,
            "duration_s": round(dur, 1), "log": str(log)}
    (evidence / "build.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    if proc.returncode != 0 or not (build_dir / EXE_NAME).is_file():
        raise RuntimeError(f"build falhou (exit {proc.returncode}); veja {log}")
    return build_dir, info


# ----------------------------------------------------------------------- run

class Session:
    def __init__(self, build_dir, evidence, port, show_window=False):
        self.build_dir = Path(build_dir)
        self.evidence = evidence
        self.port = port
        self.show_window = show_window
        self.win = Win()
        self.proc = None
        self.pid = None
        self.focus = []
        self.shots = {}
        self.record = {"steps": [], "focus": {}, "timings": {}}
        self.tele_prev = None
        self.vars = {}        # valores de read_ram/wait_ram por nome
        self.scene_log = []   # sequencia de leituras read_ram
        self.miss_log = []    # sequencia de dispatch_misses
        self.armed_pcs = []

    # foco -------------------------------------------------------------
    def sample_focus(self, label):
        fg = self.win.foreground()
        fg["label"] = label
        fg["is_game"] = bool(self.pid) and fg["pid"] == self.pid
        fg["t"] = round(time.time(), 3)
        self.focus.append(fg)
        return fg

    # tcp --------------------------------------------------------------
    def cmd(self, name, **kw):
        req = {"id": 1, "cmd": name}
        req.update(kw)
        return send_command(self.port, req)

    def frame(self):
        return int(self.cmd("frame").get("frame", 0))

    def wait_frames(self, n, timeout=None):
        timeout = timeout or max(30.0, n / 20.0)
        start = self.frame()
        t0 = time.time()
        while time.time() - t0 < timeout:
            cur = self.frame()
            if cur - start >= n:
                return cur
            time.sleep(0.05)
        raise TimeoutError(f"wait_frames {n}: so avancou {cur - start} em {timeout}s")

    # ciclo de vida ----------------------------------------------------
    def launch(self, monitor):
        exe = self.build_dir / EXE_NAME
        game_toml = self.build_dir / "game.toml"
        if not exe.is_file() or not game_toml.is_file():
            raise FileNotFoundError(f"build incompleto em {self.build_dir}")
        memcard = self.evidence / "memcard"
        memcard.mkdir(parents=True, exist_ok=True)
        disc = PROJECT_ROOT / "disc-a" / "Street Fighter EX Plus Alpha (USA).cue"
        bios = REPO_ROOT / "gameFiles" / "bios" / "SCPH1001.BIN"  # somente leitura
        cmd = build_game_command(exe, game_toml, memcard, self.port,
                                 disc if disc.is_file() else None,
                                 bios if bios.is_file() else None)
        if not port_is_free(self.port):
            raise RuntimeError(f"porta {self.port} ocupada; nao lanco.")
        env = dict(os.environ, SDL_AUDIO_DRIVER="dummy")
        self.sample_focus("antes_do_lancamento")
        self.record["command"] = cmd
        self.record["env_extra"] = {"SDL_AUDIO_DRIVER": "dummy"}
        out = open(self.evidence / "game_stdout.log", "w", encoding="utf-8", errors="replace")
        err = open(self.evidence / "game_stderr.log", "w", encoding="utf-8", errors="replace")
        t0 = time.time()
        self.proc = subprocess.Popen(cmd, cwd=str(self.build_dir), env=env, stdout=out,
                                     stderr=err, creationflags=BELOW_NORMAL)
        self.pid = self.proc.pid
        self.record["pid"] = self.pid
        self.record["port"] = self.port
        # espera TCP
        deadline = time.time() + 180
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"jogo encerrou cedo (exit {self.proc.returncode}); veja game_stderr.log")
            try:
                self.cmd("ping")
                break
            except OSError:
                time.sleep(0.25)
            self.sample_focus("aguardando_tcp")
        else:
            raise TimeoutError("debug server nao respondeu em 180s")
        self.record["timings"]["tcp_ready_s"] = round(time.time() - t0, 1)
        self.sample_focus("tcp_pronto")
        self.place_window(monitor)

    def place_window(self, monitor):
        wins, game_wins = [], []
        for _ in range(60):
            wins = self.win.windows_of(self.pid)
            game_wins = [x for x in wins if x["title"].startswith("Ex Plus Alpha")]
            if game_wins:
                break
            time.sleep(0.25)
        self.record["windows_before"] = wins
        if not game_wins:
            self.record["window_note"] = "janela 'Ex Plus Alpha' do PID nao encontrada"
            return
        target = game_wins[0]
        left, top, right, bottom = target["rect"]
        width, height = max(1, right - left), max(1, bottom - top)
        x, y, w, h = fit_window(monitor, width, height)
        self.record["window_target"] = {"hwnd": target["hwnd"], "x": x, "y": y, "w": w, "h": h}
        # Padrao: a janela segue oculta (screenshots vem do framebuffer emulado),
        # apenas posicionada no monitor 1. Mostra-la fez o jogo assumir o primeiro
        # plano durante a luta (run7), entao so com --show-window.
        self.record["window_note"] = ("mostrada no monitor 1 (--show-window)" if self.show_window
                                      else "oculta, apenas posicionada no monitor 1")
        self.win.place_noactivate(target["hwnd"], x, y, w, h, show=self.show_window)
        time.sleep(0.5)
        self.record["windows_after"] = self.win.windows_of(self.pid)
        self.sample_focus("apos_mostrar_janela")

    def shutdown(self):
        res = {}
        if self.proc is None:
            return res
        try:
            res["quit_response"] = self.cmd("quit")
            if not (isinstance(res["quit_response"], dict) and res["quit_response"].get("ok")):
                print("AVISO: quit respondeu sem ok; aguardando o processo sair",
                      file=sys.stderr)
        except Exception as exc:  # noqa: BLE001
            res["quit_error"] = repr(exc)
        try:
            self.proc.wait(timeout=20)
            res["exit_code"] = self.proc.returncode
        except subprocess.TimeoutExpired:
            res["forced_kill_pid"] = self.pid
            self.proc.kill()  # somente o PID que este script iniciou
            self.proc.wait(timeout=10)
        return res

    # passos -----------------------------------------------------------
    def telemetry(self, name, which):
        # static_text_misses/overlay_interp_hot so existem no runtime do fork
        # psxrecomp-plusalpha; aqui o erro "unknown command" fica registrado.
        which = which or ["dispatch_stats", "dispatch_misses", "overlay_interp_hot",
                          "frame_perf", "fmv_state", "frame", "overlay_loader_status",
                          "dirty_ram_stats", "segment_misses", "phase_profile", "latency"]
        out = {"name": name, "frame_at": self.frame(), "wall_s": round(time.time(), 3)}
        for key in which:
            try:
                if key == "dispatch_misses":
                    r = self.dispatch_misses()
                elif key == "static_text_misses":
                    r = self.cmd("static_text_misses", **{"class": "all", "offset": 0, "limit": 256})
                elif key == "phase_profile":
                    r = self.cmd("phase_profile", window=10)
                elif key == "overlay_interp_hot":
                    r = self.cmd("overlay_interp_hot", sort="insns", min_entries=1,
                                 offset=0, limit=64)
                else:
                    r = self.cmd(key)
            except Exception as exc:  # noqa: BLE001
                r = {"ok": False, "error": repr(exc)}
            out[key] = r
        dirty = out.get("dirty_ram_stats")
        if isinstance(dirty, dict) and dirty.get("ok"):
            # substituto de overlay_interp_hot neste runtime: PCs interpretados por insns
            top = sorted(dirty.get("per_pc", []), key=lambda e: e.get("insns", 0), reverse=True)[:10]
            out["top_interp_pcs"] = top
        out["perf"] = perf_indicators(out["frame_at"], out["wall_s"], self.tele_prev,
                                      out.get("dirty_ram_stats"), out.get("phase_profile"),
                                      out.get("overlay_loader_status"))
        self.tele_prev = (out["frame_at"], out["wall_s"])
        path = self.evidence / f"telemetry_{name}.json"
        path.write_text(json.dumps(out, indent=1), encoding="utf-8")
        return out

    def read_ram(self, addr, size):
        r = self.cmd("read_ram", addr=f"0x{addr:08X}", len=size)
        if not r.get("ok"):
            raise RuntimeError(f"read_ram falhou: {r}")
        return le_value(r["hex"], size), r["hex"]

    def wait_ram(self, step):
        addr, size = parse_addr(step["addr"]), step.get("size", 1)
        want = [parse_addr(v) for v in step.get("values", [])]
        avoid = [parse_addr(v) for v in step.get("not_values", [])]
        deadline = self.frame() + step.get("timeout_frames", 600)
        t0 = time.time()
        while True:
            val, _ = self.read_ram(addr, size)
            if (want and val in want) or (avoid and val not in avoid):
                return True, val
            if self.frame() >= deadline or time.time() - t0 > max(60.0, step.get("timeout_frames", 600) / 5.0):
                return False, val
            time.sleep(0.1)

    def dispatch_misses(self, tail=256):
        """Misses de despacho (PCs sem funcao compilada), filtrados para o texto do EXE."""
        stats = self.cmd("dispatch_stats")
        summ = self.cmd("unknown_dispatch_log")
        out = {"ok": bool(summ.get("ok")), "miss_total": stats.get("miss_total"),
               "miss_unique": stats.get("miss_unique"),
               "segment_miss_total": stats.get("segment_miss_total"),
               "exe_misses": exe_misses(summ.get("summary")),
               "all_summary_rows": len(summ.get("summary") or [])}
        dirty = self.cmd("dirty_ram_stats")
        out["dirty_ok"] = bool(dirty.get("ok"))
        out["exe_interp_pcs"] = exe_interp_pcs(dirty.get("per_pc"))
        if tail:
            log = self.cmd("unknown_dispatch_log", tail=tail)
            out["exe_tail"] = [e for e in (log.get("entries") or [])
                               if EXE_PHYS_LO <= int(str(e.get("phys", "0")), 0) < EXE_PHYS_HI]
        return out

    def fntrace_arm(self, pcs, clear=True):
        if clear:
            self.cmd("fntrace_arm_clear")
            self.cmd("fntrace_clear")
        res = []
        for pc in pcs:
            r = self.cmd("fntrace_arm", target=f"0x{parse_addr(pc):08X}")
            res.append({"pc": f"0x{parse_addr(pc):08X}", "ok": r.get("ok"), "armed": r.get("armed")})
        self.armed_pcs = [parse_addr(p) for p in pcs]
        return res

    def fntrace_dump(self, name):
        pcs = list(getattr(self, "armed_pcs", []))
        hits = {f"0x{pc:08X}": {"hits": 0} for pc in pcs}
        entries_all = []
        for pc in pcs:
            r = self.cmd("fntrace_dump", target_lo=f"0x{pc:08X}", target_hi=f"0x{pc + 4:08X}",
                         count=4096)
            ents = r.get("entries") or []
            entries_all += ents
            hits.update(count_fntrace_hits(ents, [pc]))
        path = self.evidence / f"fntrace_{name}.json"
        path.write_text(json.dumps({"name": name, "frame_at": self.frame(), "hits": hits,
                                    "entries": entries_all[:512]}, indent=1), encoding="utf-8")
        return hits

    def shot(self, name):
        path = self.evidence / f"{name}.png"
        r = self.cmd("screenshot_file", path=str(path).replace("\\", "/"))
        retries = 0
        while (not r.get("ok") and r.get("error") == "display disabled"
               and retries < SHOT_DISPLAY_RETRIES):
            self.wait_frames(SHOT_DISPLAY_WAIT_FRAMES)
            retries += 1
            r = self.cmd("screenshot_file", path=str(path).replace("\\", "/"))
        if not r.get("ok"):
            raise RuntimeError(f"screenshot_file falhou: {r}")
        digest = sha256_file(path)
        self.shots[name] = digest
        out = {"path": str(path), "sha256": digest, "w": r.get("width"), "h": r.get("height"),
               "display_retries": retries}
        if retries:
            out["frame_after_retries"] = self.frame()
        return out

    def savestate(self, op, slot):
        before = self.cmd("savestate_status")
        gen0 = before.get("generation", 0)
        r = self.cmd("savestate", op=op, slot=slot)
        if not r.get("ok"):
            raise RuntimeError(f"savestate {op} recusado: {r}")
        for _ in range(200):
            st = self.cmd("savestate_status")
            if st.get("generation", 0) != gen0 and not st.get("pending"):
                return {"request": r, "status": st}
            time.sleep(0.05)
        raise TimeoutError("savestate nao concluiu")

    def expect(self, step):
        check = step["check"]
        if check == "frame_min":
            f = self.frame()
            return f >= step["value"], {"frame": f}
        if check == "fmv_field":
            r = self.cmd("fmv_state")
            v = r.get(step["field"])
            op = step.get("op", "==")
            ok = {"==": v == step["value"], ">": v is not None and v > step["value"],
                  ">=": v is not None and v >= step["value"]}[op]
            return ok, {"field": step["field"], "value": v}
        if check in ("shot_differs", "shot_equals"):
            a, b = self.shots.get(step["a"]), self.shots.get(step["b"])
            same = a is not None and a == b
            return (same if check == "shot_equals" else (a is not None and b is not None and not same)), {"a": a, "b": b}
        return True, {}

    def run_step(self, i, step):
        kind = step["type"]
        t0 = time.time()
        rec = {"i": i, "type": kind, "note": step.get("note", "")}
        if kind == "wait_frames":
            rec["frame"] = self.wait_frames(step["frames"])
        elif kind == "press":
            word = buttons_word(step["buttons"])
            frames = step.get("frames", 4)
            r = self.cmd("press", buttons=word, frames=frames)
            rec.update(buttons=step["buttons"], word=f"0x{word:04X}", frames=frames, ok=r.get("ok"))
            if not r.get("ok"):
                raise RuntimeError(f"press recusado: {r}")
            self.wait_frames(frames + step.get("wait_after", 30))
        elif kind == "screenshot":
            rec.update(self.shot(step["name"]))
        elif kind == "savestate":
            rec.update(self.savestate(step.get("op", "save"), step.get("slot", 0)))
        elif kind == "read_ram":
            addr, size = parse_addr(step["addr"]), step.get("size", 1)
            val, hexs = self.read_ram(addr, size)
            self.vars[step["name"]] = val
            self.scene_log.append({"name": step["name"], "value": val, "frame": self.frame(),
                                   "step": i, "note": step.get("note", "")})
            rec.update(addr=f"0x{addr:08X}", size=size, value=val, hex=hexs[:64],
                       var=step["name"], frame=self.frame())
        elif kind == "wait_ram":
            ok, val = self.wait_ram(step)
            rec.update(addr=step["addr"], value=val, matched=ok, frame=self.frame())
            if step.get("name"):
                self.vars[step["name"]] = val
            if not ok and not step.get("optional"):
                rec["failed"] = True
        elif kind == "fntrace":
            if step["op"] == "arm":
                rec["armed"] = self.fntrace_arm(step["pcs"], step.get("clear", True))
            else:
                rec["hits"] = self.fntrace_dump(step["name"])
                rec["file"] = f"fntrace_{step['name']}.json"
        elif kind == "dispatch_misses":
            m = self.dispatch_misses(step.get("tail", 256))
            self.miss_log.append({"name": step["name"], "frame": self.frame(), **m})
            path = self.evidence / f"misses_{step['name']}.json"
            path.write_text(json.dumps(m, indent=1), encoding="utf-8")
            rec.update(file=path.name, miss_total=m["miss_total"], miss_unique=m["miss_unique"],
                       exe_miss_count=len(m["exe_misses"]),
                       exe_misses=[r["pc"] for r in m["exe_misses"][:40]],
                       exe_interp_count=len(m["exe_interp_pcs"]),
                       exe_interp_pcs=[r["pc"] for r in m["exe_interp_pcs"][:40]])
        elif kind == "telemetry":
            t = self.telemetry(step["name"], step.get("which"))
            rec["file"] = f"telemetry_{step['name']}.json"
            rec["frame_at"] = t["frame_at"]
        elif kind == "expect":
            ok, detail = self.expect(step)
            rec.update(ok=ok, detail=detail, check=step["check"])
            if not ok and not step.get("optional"):
                rec["failed"] = True
        rec["focus"] = self.sample_focus(f"passo_{i}_{kind}")
        rec["dur_s"] = round(time.time() - t0, 2)
        return rec

    def run_route(self, route):
        failed = None
        for i, step in enumerate(route["steps"]):
            try:
                rec = self.run_step(i, step)
            except Exception as exc:  # noqa: BLE001
                rec = {"i": i, "type": step["type"], "error": repr(exc)}
                if not step.get("optional"):
                    failed = rec
                    self.record["steps"].append(rec)
                    break
            self.record["steps"].append(rec)
            print(f"[{i:02d}] {rec['type']} {step.get('note') or step.get('name') or ''} "
                  f"{'ERRO ' + rec['error'] if 'error' in rec else 'ok'}", flush=True)
            if rec.get("failed"):
                failed = rec
                break
        return failed


def do_run(build_dir, route_name, evidence, port, show_window=False):
    win = Win()
    monitor = pick_monitor1(win.monitors())
    route = load_route(route_name)
    sess = Session(build_dir, evidence, port, show_window=show_window)
    sess.record["monitor1"] = monitor
    sess.record["monitors_all"] = win.monitors()
    sess.record["route"] = route_name
    sess.record["build_dir"] = str(build_dir)
    sess.record["overlay_source"] = detect_overlay_source(build_dir)
    t0 = time.time()
    failed = None
    try:
        sess.launch(monitor)
        failed = sess.run_route(route)
    except Exception as exc:  # noqa: BLE001
        failed = {"error": repr(exc)}
    finally:
        sess.record["shutdown"] = sess.shutdown()
        sess.sample_focus("apos_quit")
        sess.record["timings"]["run_total_s"] = round(time.time() - t0, 1)
        sess.record["vars"] = sess.vars
        sess.record["reads"] = sess.scene_log
        sess.record["miss_log"] = sess.miss_log
        sess.record["failed"] = failed
        sess.record["focus"] = {
            "samples": sess.focus,
            "game_pid": sess.pid,
            "game_was_foreground": any(s["is_game"] for s in sess.focus),
        }
        (evidence / "run.json").write_text(json.dumps(sess.record, indent=2), encoding="utf-8")
    if sess.record["focus"]["game_was_foreground"]:
        print("AVISO: a janela do jogo ficou em primeiro plano; veja run.json", file=sys.stderr)
        return 3
    return 1 if failed else 0


def resolve_build_dir(value):
    p = Path(value)
    if not p.is_absolute():
        # Aceita caminho relativo ao cwd (ex.: PlusAlphaProject/build-auto-X)
        # ou ao PlusAlphaProject (ex.: build-auto-X).
        p = (Path.cwd() / value) if (Path.cwd() / value).is_dir() else PROJECT_ROOT / value
    p = p.resolve()
    if not p.name.startswith("build-auto-") or p.parent != PROJECT_ROOT.resolve():
        raise ValueError("--build-dir deve ser um PlusAlphaProject/build-auto-*")
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="mode", required=True)
    for name in ("build", "run", "all"):
        sp = sub.add_parser(name)
        sp.add_argument("--evidence-dir", type=Path)
        if name != "run":
            sp.add_argument("--jobs", type=int, default=4)
            sp.add_argument("--overlay-source", choices=OVERLAY_SOURCES, default="aot",
                            help="aot: overlays gerados do disco (padrao); retained: retidas")
            sp.add_argument("--reuse-build", metavar="BUILD_AUTO",
                            help="reaproveita (ou cria) este build-auto-*: o ninja recompila so os "
                                 "shards alterados; fontes em <build>/generated")
            sp.add_argument("--seeds", type=Path,
                            help="arquivo de seeds do lote (geracao isolada em <build>/generated); "
                                 "padrao com --reuse-build: seeds/entry_funcs.txt")
        if name != "build":
            sp.add_argument("--route", default="boot_to_fight")
            sp.add_argument("--port", type=int, default=DEFAULT_PORT)
            sp.add_argument("--show-window", action="store_true",
                            help="mostra a janela no monitor 1 (pode roubar o foco)")
        if name == "run":
            sp.add_argument("--build-dir", required=True)
    args = ap.parse_args(argv)
    if sys.platform != "win32":
        ap.error("Windows requerido")
    evidence = (args.evidence_dir or make_evidence_dir()).resolve()  # o jogo roda em outro cwd
    evidence.mkdir(parents=True, exist_ok=True)
    print(f"Evidencias: {evidence}", flush=True)
    try:
        if args.mode == "build":
            build_dir, info = do_build(evidence, args.jobs, args.overlay_source,
                                       args.reuse_build, args.seeds)
            print(f"Build ok em {info['duration_s']}s: {build_dir}")
            return 0
        if args.mode == "run":
            return do_run(resolve_build_dir(args.build_dir), args.route, evidence,
                          args.port, args.show_window)
        build_dir, info = do_build(evidence, args.jobs, args.overlay_source,
                                   args.reuse_build, args.seeds)
        print(f"Build ok em {info['duration_s']}s: {build_dir}", flush=True)
        return do_run(build_dir, args.route, evidence, args.port, args.show_window)
    except (RuntimeError, ValueError, FileNotFoundError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
