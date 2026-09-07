#!/usr/bin/env python3
"""
observe_menus_navigation.py

Observador de telemetria de alta velocidade para a rota de exploracao de menus:
Boot -> FMVs -> Title Screen -> Mode Select -> Character Select -> Options (Game/Sound/Key) -> Memory Card / Save -> Title Screen.

Mapeia todas as instrucoes ainda interpretadas (misses estaticos e hotspots de interprete)
sem entrar em tela de luta, fornecendo os alvos prioritarios para promocao estatica nativa.
"""

import sys
import os
import time
import socket
import json
import pathlib
import shutil
from datetime import datetime

DEFAULT_PORT = 4531

def parse_args():
    port = DEFAULT_PORT
    for arg in sys.argv[1:]:
        if arg.isdigit():
            port = int(arg)
        elif arg.startswith("--port="):
            port = int(arg.split("=", 1)[1])
    return port

def read_debug_port_from_config(project_root):
    game_toml = project_root / "game.toml"
    if not game_toml.is_file():
        return DEFAULT_PORT
    try:
        in_runtime = False
        for line in game_toml.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("[") and line.endswith("]"):
                in_runtime = (line == "[runtime]")
                continue
            if in_runtime and line.startswith("debug_port"):
                parts = line.split("=", 1)
                if len(parts) == 2:
                    return int(parts[1].strip())
    except Exception:
        pass
    return DEFAULT_PORT

def send_command(port, req_dict, timeout=5.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(("127.0.0.1", port))
    payload = (json.dumps(req_dict) + "\n").encode("utf-8")
    s.sendall(payload)

    data = bytearray()
    depth_c = 0
    depth_s = 0
    in_str = False
    esc = False
    started = False
    done = False

    try:
        while not done:
            chunk = s.recv(65536)
            if not chunk:
                break
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
                    depth_c += 1
                    started = True
                elif ch == "}":
                    depth_c -= 1
                elif ch == "[":
                    depth_s += 1
                elif ch == "]":
                    depth_s -= 1
                if started and depth_c == 0 and depth_s == 0:
                    done = True
                    break
    finally:
        s.close()

    text = data.decode("utf-8", errors="replace").strip()
    return json.loads(text)

def wait_for_debug_server(port, timeout=120.0):
    print(f"[*] Aguardando conexao com o emulador na porta {port}...")
    print("    (Inicie o jogo 'StreetFighterEXPlusAlphaRecomp.exe' se ainda nao estiver aberto)")
    start = time.time()
    dots = 0
    while time.time() - start < timeout:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                print(f"\n[+] Emulador detectado e respondendo na porta {port}!")
                return True
        except (OSError, ConnectionRefusedError):
            time.sleep(0.05)
            dots += 1
            if dots % 20 == 0:
                sys.stdout.write(".")
                sys.stdout.flush()
    return False

def get_static_text_misses(port):
    all_entries = []
    offset = 0
    limit = 256
    meta = {}
    while True:
        res = send_command(port, {"id": 1, "cmd": "static_text_misses", "class": "all", "offset": offset, "limit": limit})
        if not meta:
            meta = {k: v for k, v in res.items() if k != "entries"}
        entries = res.get("entries", [])
        all_entries.extend(entries)
        total = res.get("total", 0)
        offset += len(entries)
        if offset >= total or not entries:
            break
    meta["entries"] = all_entries
    return meta

def get_overlay_interp_hot(port):
    all_entries = []
    offset = 0
    limit = 256
    meta = {}
    while True:
        res = send_command(port, {"id": 2, "cmd": "overlay_interp_hot", "sort": "insns", "min_entries": 1, "offset": offset, "limit": limit})
        if not meta:
            meta = {k: v for k, v in res.items() if k != "entries"}
        entries = res.get("entries", [])
        all_entries.extend(entries)
        total = res.get("total", 0)
        offset += len(entries)
        if offset >= total or not entries:
            break
    meta["entries"] = all_entries
    return meta

def capture_full_snapshot(port):
    t0 = time.perf_counter()
    misses = get_static_text_misses(port)
    overlay = get_overlay_interp_hot(port)
    loader = send_command(port, {"id": 3, "cmd": "overlay_loader_status"})
    dirty = send_command(port, {"id": 4, "cmd": "dirty_ram_stats"})
    dispatch = send_command(port, {"id": 5, "cmd": "dispatch_stats"})
    t1 = time.perf_counter()

    elapsed_ms = (t1 - t0) * 1000.0
    return {
        "timestamp": time.time(),
        "elapsed_ms": elapsed_ms,
        "static_text_misses": misses,
        "overlay_interp_hot": overlay,
        "overlay_loader_status": loader,
        "dirty_ram_stats": dirty,
        "dispatch_stats": dispatch,
    }

def load_ranges(ranges_file):
    funcs = set()
    ranges = []
    if not ranges_file.is_file():
        return funcs, ranges
    try:
        for line in ranges_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if parts[0] == "F" and len(parts) >= 2:
                funcs.add(int(parts[1], 16))
            elif parts[0] == "R" and len(parts) >= 3:
                lo = int(parts[1], 16)
                sz = int(parts[2], 16)
                ranges.append((lo, lo + sz))
    except Exception as e:
        print(f"[!] Aviso ao carregar ranges: {e}")
    return funcs, ranges

def classify_pc(pc_val, funcs, ranges):
    if pc_val in funcs:
        return "ENTRY_FUNC (Já nativo)"
    for lo, hi in ranges:
        if lo <= pc_val < hi:
            return f"CORPO_NATIVO (0x{lo:08X})"
    if 0x80101000 <= pc_val < 0x801C0000:
        return "MAIN_EXE_TEXT (MISS ESTÁTICO NÃO COMPILADO)"
    return "OVERLAY_DINÂMICO"

def create_run_directory(base_dir, prefix="menus-exploration"):
    os.makedirs(base_dir, exist_ok=True)
    idx = 1
    while True:
        run_name = f"{prefix}-{idx:02d}"
        run_path = base_dir / run_name
        if not run_path.exists():
            run_path.mkdir(parents=True, exist_ok=True)
            return run_path
        idx += 1

def analyze(before, after, funcs, ranges):
    # Static text misses delta
    b_misses = {item["pc"].upper(): item for item in before["static_text_misses"].get("entries", [])}
    a_misses = {item["pc"].upper(): item for item in after["static_text_misses"].get("entries", [])}

    all_miss_pcs = sorted(set(b_misses.keys()) | set(a_misses.keys()))
    static_deltas = []
    for pc in all_miss_pcs:
        a_row = a_misses.get(pc, {})
        b_row = b_misses.get(pc, {})
        delta_hits = a_row.get("selected_hits", 0) - b_row.get("selected_hits", 0)
        delta_misses = a_row.get("misses", 0) - b_row.get("misses", 0)
        delta_modified = a_row.get("modified", 0) - b_row.get("modified", 0)
        delta_runtime = a_row.get("runtime", 0) - b_row.get("runtime", 0)
        delta_unknown = a_row.get("unknown", 0) - b_row.get("unknown", 0)
        if delta_hits > 0 or delta_misses > 0:
            pc_int = int(pc, 16)
            cls_desc = classify_pc(pc_int, funcs, ranges)
            static_deltas.append({
                "pc": pc,
                "phys": a_row.get("phys", b_row.get("phys", "")),
                "delta_selected_hits": delta_hits,
                "delta_misses": delta_misses,
                "delta_modified": delta_modified,
                "delta_runtime": delta_runtime,
                "delta_unknown": delta_unknown,
                "classification": cls_desc,
                "class": a_row.get("class", b_row.get("class", "pristine")),
                "before_hits": b_row.get("selected_hits", 0),
                "after_hits": a_row.get("selected_hits", 0),
            })
    static_deltas.sort(key=lambda x: x["delta_selected_hits"], reverse=True)

    # Overlay interpreted hot delta
    b_overlay = {item["pc"].upper(): item for item in before["overlay_interp_hot"].get("entries", [])}
    a_overlay = {item["pc"].upper(): item for item in after["overlay_interp_hot"].get("entries", [])}

    all_overlay_pcs = sorted(set(b_overlay.keys()) | set(a_overlay.keys()))
    overlay_deltas = []
    for pc in all_overlay_pcs:
        a_row = a_overlay.get(pc, {})
        b_row = b_overlay.get(pc, {})
        delta_insns = a_row.get("insns", 0) - b_row.get("insns", 0)
        delta_hits = a_row.get("hits", 0) - b_row.get("hits", 0)
        delta_entry_hits = a_row.get("entry_hits", 0) - b_row.get("entry_hits", 0)
        if delta_insns > 0 or delta_hits > 0:
            pc_int = int(pc, 16)
            cls_desc = classify_pc(pc_int, funcs, ranges)
            overlay_deltas.append({
                "pc": pc,
                "phys": a_row.get("phys", b_row.get("phys", "")),
                "delta_insns": delta_insns,
                "delta_hits": delta_hits,
                "delta_entry_hits": delta_entry_hits,
                "classification": cls_desc,
            })
    overlay_deltas.sort(key=lambda x: x["delta_insns"], reverse=True)

    # Framework deltas
    def delta_dict(a_dict, b_dict):
        res = {}
        for k, v in a_dict.items():
            if isinstance(v, (int, float)):
                res[k] = v - b_dict.get(k, 0)
        return res

    loader_deltas = delta_dict(after["overlay_loader_status"], before["overlay_loader_status"])
    dirty_deltas = delta_dict(after["dirty_ram_stats"], before["dirty_ram_stats"])
    dispatch_deltas = delta_dict(after["dispatch_stats"], before["dispatch_stats"])

    return {
        "static_text_misses": static_deltas,
        "overlay_interp_hot": overlay_deltas,
        "loader_deltas": loader_deltas,
        "dirty_deltas": dirty_deltas,
        "dispatch_deltas": dispatch_deltas,
    }

def print_table(headers, rows):
    if not rows:
        print("  (Nenhum dado registrado)")
        return
    col_widths = [len(h) for h in headers]
    for row in rows:
        for i, val in enumerate(row):
            col_widths[i] = max(col_widths[i], len(str(val)))
    fmt = "  " + " | ".join(f"{{:<{w}}}" for w in col_widths)
    sep = "  " + "-+-".join("-" * w for w in col_widths)
    print(fmt.format(*headers))
    print(sep)
    for row in rows:
        print(fmt.format(*[str(val) for val in row]))

def main():
    script_dir = pathlib.Path(__file__).resolve().parent
    project_root = script_dir.parent
    ranges_file = project_root / "generated" / "SLUS_005.48_full.ranges"
    telemetry_base = project_root / "local" / "telemetry"

    port = parse_args()
    if port == DEFAULT_PORT:
        cfg_port = read_debug_port_from_config(project_root)
        if cfg_port != DEFAULT_PORT:
            port = cfg_port

    print("======================================================================")
    print("      OBSERVADOR DE TELEMETRIA: NAVEGACAO COMPLETA DE MENUS          ")
    print("======================================================================")
    print(f"Porta TCP         : {port}")
    print(f"Diretorio projeto : {project_root}")
    print(f"Arquivo ranges    : {ranges_file.name}")
    print("======================================================================")

    funcs, ranges = load_ranges(ranges_file)
    print(f"[+] Carregadas {len(funcs)} funcoes nativas e {len(ranges)} ranges de codigo.")

    if not wait_for_debug_server(port):
        print("\n[ERRO] Tempo limite esgotado aguardando conexao com o emulador.")
        sys.exit(1)

    print("\n[+] Capturando snapshot BEFORE inicial...")
    before = capture_full_snapshot(port)
    print(f"[+] SNAPSHOT BEFORE CAPTURADO EM {before['elapsed_ms']:.1f} ms!")

    run_dir = create_run_directory(telemetry_base, prefix="menus-exploration")
    print(f"[+] Sessao criada em: {run_dir}")

    (run_dir / "before.json").write_text(json.dumps(before, indent=2), encoding="utf-8")

    print("\n" + "=" * 70)
    print("             ROTA DE NAVEGACAO DE MENUS EM ANDAMENTO                 ")
    print("=" * 70)
    print("  Instrucoes do teste:")
    print("  1. Navegue livremente por todos os menus do jogo:")
    print("     - Telas de apresentacao e Title Screen;")
    print("     - Mode Select (Arcade, Versus, Survival, Practice, etc.);")
    print("     - Telas de Selecao de Personagens;")
    print("     - Options (Game Option, Key Config, Sound Option);")
    print("     - Sistema de Save / Memory Card / Carregamento.")
    print("  2. REGRA CRUCIAL: EM NENHUM MOMENTO ENTRE EM UMA TELA DE LUTA")
    print("     (evite Round 1 / Fight para manter a analise 100% pura em menus).")
    print("  3. Ao terminar de percorrer os menus, retorne para a Title Screen.")
    print("  4. Com o jogo parado na Title Screen, volte a este terminal.")
    print("  5. Pressione [ENTER] para capturar o snapshot AFTER.")
    print("=" * 70)

    try:
        input("\n>>> Pressione [ENTER] quando estiver de volta na Title Screen... ")
    except KeyboardInterrupt:
        print("\n[!] Coleta cancelada pelo usuario.")
        sys.exit(0)

    print("\n[+] Capturando snapshot AFTER...")
    after = capture_full_snapshot(port)
    print(f"[+] SNAPSHOT AFTER CAPTURADO EM {after['elapsed_ms']:.1f} ms!")

    # Descarrega overlay_captures.json do runtime se disponivel
    try:
        cap_dump = send_command(port, {"id": 99, "cmd": "overlay_capture_dump"})
        entries_count = cap_dump.get("capture_entries", 0)
        print(f"[+] Comando overlay_capture_dump enviado ({entries_count} regiao/regioes registradas).")
    except Exception as e:
        print(f"[!] Aviso ao enviar overlay_capture_dump: {e}")

    (run_dir / "after.json").write_text(json.dumps(after, indent=2), encoding="utf-8")

    # Preserva overlay_captures.json
    possible_cap_paths = [
        project_root / "build-telemetry" / "overlay_captures.json",
        project_root / "overlay_captures.json",
        pathlib.Path.cwd() / "overlay_captures.json",
    ]
    captured_file = None
    for p in possible_cap_paths:
        if p.is_file():
            captured_file = p
            break

    if captured_file:
        dest_cap = run_dir / "overlay_captures.json"
        shutil.copyfile(captured_file, dest_cap)
        print(f"[+] Arquivo de overlays preservado em: {dest_cap}")

    print("\n[+] Processando analise diferencial (Deltas)...")
    res = analyze(before, after, funcs, ranges)
    (run_dir / "result.json").write_text(json.dumps(res, indent=2), encoding="utf-8")

    # Gera candidates.txt contendo todos os misses estaticos nao compilados
    uncompiled_misses = [
        item for item in res["static_text_misses"]
        if "MAIN_EXE_TEXT" in item["classification"]
    ]
    candidates_lines = [
        "# class PC delta before after classification",
    ]
    for item in uncompiled_misses:
        candidates_lines.append(
            f"{item['class']} {item['pc']} {item['delta_selected_hits']} {item['before_hits']} {item['after_hits']} {item['classification']}"
        )
    (run_dir / "candidates.txt").write_text("\n".join(candidates_lines) + "\n", encoding="utf-8")

    # Exibicao no terminal
    print("\n" + "=" * 70)
    print("                     RESULTADO DA OBSERVACAO                          ")
    print("=" * 70)

    print("\n--- [DISPATCH FRAMEWORK] ---")
    print(f"  Dispatch Nativo   : +{res['loader_deltas'].get('dispatch_native', 0):,}")
    print(f"  Fallback Interp   : +{res['loader_deltas'].get('dispatch_interp_fallback', 0):,}")
    print(f"  Misses Dispatch   : +{res['dispatch_deltas'].get('miss_total', 0):,}")
    print(f"  Native Handoffs   : +{res['dirty_deltas'].get('native_handoffs', 0):,}")
    print(f"  Diverged Pages    : +{res['dirty_deltas'].get('text_diverged_pages', 0):,}")

    print("\n--- [TOP STATIC TEXT MISSES (Candidatos no Main EXE para Promocao)] ---")
    static_rows = []
    for item in uncompiled_misses[:20]:
        static_rows.append([
            item["pc"],
            f"+{item['delta_selected_hits']:,}",
            item["class"],
            item["classification"]
        ])
    print_table(["PC", "Delta Hits", "Classe", "Diagnóstico"], static_rows)

    print("\n--- [TOP OVERLAY INTERPRETED HOTSPOTS] ---")
    overlay_rows = []
    for item in res["overlay_interp_hot"][:15]:
        overlay_rows.append([
            item["pc"],
            f"+{item['delta_insns']:,}",
            f"+{item['delta_hits']:,}",
            f"+{item['delta_entry_hits']:,}",
            item["classification"]
        ])
    print_table(["PC", "Delta Insns", "Delta Hits", "Entry Hits", "Diagnóstico"], overlay_rows)

    # Escreve summary.md
    summary_lines = [
        "# Telemetria: Navegacao Completa de Menus",
        "",
        f"- **Data/Hora**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"- **Snapshot Before**: {before['elapsed_ms']:.1f} ms",
        f"- **Snapshot After**: {after['elapsed_ms']:.1f} ms",
        "",
        "## Resumo de Execucao do Framework",
        "",
        f"- **Dispatch Nativo**: +{res['loader_deltas'].get('dispatch_native', 0):,}",
        f"- **Fallback Interprete**: +{res['loader_deltas'].get('dispatch_interp_fallback', 0):,}",
        f"- **Miss Total**: +{res['dispatch_deltas'].get('miss_total', 0):,}",
        f"- **Native Handoffs**: +{res['dirty_deltas'].get('native_handoffs', 0):,}",
        f"- **Paginas Divergidas**: +{res['dirty_deltas'].get('text_diverged_pages', 0):,}",
        "",
        "## Candidatos a Promocao Estatica (Main EXE Text Misses)",
        "",
        f"Total de PCs estaticos unicos nao compilados: **{len(uncompiled_misses)}**",
        "",
        "| PC | Delta Hits | Classe | Diagnóstico |",
        "|:---|-----------:|:-------|:------------|",
    ]
    for item in uncompiled_misses[:40]:
        summary_lines.append(f"| `{item['pc']}` | {item['delta_selected_hits']:,} | {item['class']} | {item['classification']} |")

    summary_lines.extend([
        "",
        "## Top Overlay Interpreted Hotspots",
        "",
        "| PC | Delta Insns | Delta Hits | Entry Hits | Diagnóstico |",
        "|:---|------------:|-----------:|-----------:|:------------|",
    ])
    for item in res["overlay_interp_hot"][:30]:
        summary_lines.append(f"| `{item['pc']}` | {item['delta_insns']:,} | {item['delta_hits']:,} | {item['delta_entry_hits']:,} | {item['classification']} |")

    (run_dir / "summary.md").write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

    print("\n" + "=" * 70)
    print(f"[CONCLUIDO] Arquivos gerados na sessao:")
    print(f"  - Resumo Markdown : {run_dir / 'summary.md'}")
    print(f"  - Lista Candidatos: {run_dir / 'candidates.txt'}")
    print(f"  - Dados Completos : {run_dir / 'result.json'}")
    print("======================================================================\n")

if __name__ == "__main__":
    main()
