"""Position two existing Windows game windows. No input, config writes or build."""
import argparse
import ctypes
from ctypes import wintypes as w
import os
from pathlib import Path
import sys
import time


def layout(work, sizes, fit=False):
    left, top, right, bottom = work
    half = (right - left) // 2
    height = bottom - top
    if half <= 0 or height <= 0 or any(x <= 0 or y <= 0 for x, y in sizes):
        raise ValueError("Invalid monitor/window size")
    scale = min(1.0, *(half / x for x, _ in sizes), *(height / y for _, y in sizes))
    if scale < 1 and not fit:
        raise ValueError("As janelas nao cabem nas duas metades. Execute novamente com -Fit para reduzir proporcionalmente.")
    center = left + half
    result = []
    for i, (width, high) in enumerate(sizes):
        width, high = max(1, int(width * scale)), max(1, int(high * scale))
        result.append((center - width if i == 0 else center,
                       top + (height - high) // 2, width, high))
    return result


def windows_api():
    user = ctypes.WinDLL("user32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    dwm = ctypes.WinDLL("dwmapi", use_last_error=True)
    enum_window = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
    enum_monitor = ctypes.WINFUNCTYPE(w.BOOL, w.HANDLE, w.HDC, ctypes.POINTER(w.RECT), w.LPARAM)
    signatures = [
        (user.EnumWindows, [enum_window, w.LPARAM], w.BOOL),
        (user.IsWindowVisible, [w.HWND], w.BOOL),
        (user.IsIconic, [w.HWND], w.BOOL),
        (user.IsZoomed, [w.HWND], w.BOOL),
        (user.GetWindow, [w.HWND, w.UINT], w.HWND),
        (user.GetWindowThreadProcessId, [w.HWND, ctypes.POINTER(w.DWORD)], w.DWORD),
        (user.GetWindowRect, [w.HWND, ctypes.POINTER(w.RECT)], w.BOOL),
        (user.GetWindowTextW, [w.HWND, w.LPWSTR, ctypes.c_int], ctypes.c_int),
        (user.SetWindowPos, [w.HWND, w.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, w.UINT], w.BOOL),
        (user.EnumDisplayMonitors, [w.HDC, ctypes.POINTER(w.RECT), enum_monitor, w.LPARAM], w.BOOL),
        (kernel.OpenProcess, [w.DWORD, w.BOOL, w.DWORD], w.HANDLE),
        (kernel.QueryFullProcessImageNameW, [w.HANDLE, w.DWORD, w.LPWSTR, ctypes.POINTER(w.DWORD)], w.BOOL),
        (kernel.CloseHandle, [w.HANDLE], w.BOOL),
        (dwm.DwmGetWindowAttribute, [w.HWND, w.DWORD, w.LPVOID, w.DWORD], ctypes.c_long),
    ]
    for function, args, result in signatures:
        function.argtypes, function.restype = args, result
    # Physical monitor coordinates, including mixed DPI and negative origins.
    user.SetProcessDpiAwarenessContext.argtypes = [w.HANDLE]
    user.SetProcessDpiAwarenessContext.restype = w.BOOL
    if not user.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4)):
        raise ctypes.WinError(ctypes.get_last_error())
    return user, kernel, dwm, enum_window, enum_monitor


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--first-exe", type=Path, required=True)
    parser.add_argument("--second-exe", type=Path, required=True)
    parser.add_argument("--monitor", type=int, default=0)
    parser.add_argument("--swap", action="store_true")
    parser.add_argument("--fit", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if sys.platform != "win32":
        parser.error("Windows required")
    targets = [os.path.normcase(str(p.resolve(strict=True))) for p in [args.first_exe, args.second_exe]]
    if targets[0] == targets[1]:
        parser.error("Use duas pastas diferentes")
    if args.swap:
        targets.reverse()
    user, kernel, dwm, enum_window, enum_monitor = windows_api()

    class MonitorInfo(ctypes.Structure):
        _fields_ = [("cbSize", w.DWORD), ("rcMonitor", w.RECT), ("rcWork", w.RECT), ("dwFlags", w.DWORD)]
    user.GetMonitorInfoW.argtypes = [w.HANDLE, ctypes.POINTER(MonitorInfo)]
    user.GetMonitorInfoW.restype = w.BOOL
    monitors = []
    def monitor_cb(handle, *_):
        info = MonitorInfo()
        info.cbSize = ctypes.sizeof(info)
        if user.GetMonitorInfoW(handle, ctypes.byref(info)):
            r = info.rcWork
            monitors.append((not bool(info.dwFlags & 1), (r.left, r.top, r.right, r.bottom)))
        return True
    if not user.EnumDisplayMonitors(None, None, enum_monitor(monitor_cb), 0):
        raise ctypes.WinError(ctypes.get_last_error())
    monitors.sort()
    if not 0 <= args.monitor < len(monitors):
        parser.error(f"Monitor inexistente; indices disponiveis: 0..{len(monitors)-1}")
    found = {name: [] for name in targets}
    def window_cb(hwnd, _):
        if not user.IsWindowVisible(hwnd) or user.GetWindow(hwnd, 4):
            return True
        process_id = w.DWORD()
        user.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
        handle = kernel.OpenProcess(0x1000, False, process_id.value)
        if not handle:
            return True
        try:
            name, length = ctypes.create_unicode_buffer(32768), w.DWORD(32768)
            if kernel.QueryFullProcessImageNameW(handle, 0, name, ctypes.byref(length)):
                key = os.path.normcase(name.value)
                if key in found:
                    found[key].append((hwnd, process_id.value))
        finally:
            kernel.CloseHandle(handle)
        return True
    if not user.EnumWindows(enum_window(window_cb), 0):
        raise ctypes.WinError(ctypes.get_last_error())
    windows = []
    def bounds(hwnd):
        outer, visible = w.RECT(), w.RECT()
        if not user.GetWindowRect(hwnd, ctypes.byref(outer)):
            raise ctypes.WinError(ctypes.get_last_error())
        if dwm.DwmGetWindowAttribute(hwnd, 9, ctypes.byref(visible), ctypes.sizeof(visible)) != 0:
            visible = outer
        return outer, visible
    for target in targets:
        if len(found[target]) != 1:
            raise RuntimeError(f"Esperada uma janela visivel para {target}; encontradas {len(found[target])}. Entre no versus e feche janelas auxiliares/instancias duplicadas.")
        hwnd, process_id = found[target][0]
        if user.IsIconic(hwnd) or user.IsZoomed(hwnd):
            raise RuntimeError("Use janelas normais, sem minimizar/maximizar. Ajuste o modo de janela antes do teste.")
        outer, visible = bounds(hwnd)
        windows.append((hwnd, process_id, outer, visible))
    work = monitors[args.monitor][1]
    positions = layout(work, [(v.right-v.left, v.bottom-v.top) for _, _, _, v in windows], args.fit)
    # Resolve and validate both windows before moving either one.
    for i, ((hwnd, process_id, outer, visible), (x, y, width, height)) in enumerate(zip(windows, positions)):
        title = ctypes.create_unicode_buffer(512)
        user.GetWindowTextW(hwnd, title, len(title))
        print(f"{'ESQUERDA' if i == 0 else 'DIREITA'}: PID {process_id}, {targets[i]}, {title.value!r}, borda visivel ({x}, {y}), {width}x{height}", flush=True)
        if args.dry_run:
            continue
        dx, dy = x-visible.left, y-visible.top
        resize = width != visible.right-visible.left or height != visible.bottom-visible.top
        outer_width = width + (outer.right-outer.left) - (visible.right-visible.left)
        outer_height = height + (outer.bottom-outer.top) - (visible.bottom-visible.top)
        flags = 0x4000 | 0x0010 | 0x0004 | (0 if resize else 0x0001)
        if not user.SetWindowPos(hwnd, None, outer.left+dx, outer.top+dy, outer_width, outer_height, flags):
            raise ctypes.WinError(ctypes.get_last_error())
    if not args.dry_run:
        # Asynchronous window requests avoid hanging if one process is busy.
        for _ in range(20):
            actual = [bounds(item[0])[1] for item in windows]
            if all(abs(v.left-pos[0]) <= 2 and abs(v.top-pos[1]) <= 2 and
                   abs((v.right-v.left)-pos[2]) <= 2 and abs((v.bottom-v.top)-pos[3]) <= 2
                   for v, pos in zip(actual, positions)):
                print("Janelas posicionadas. Aguarde 5 segundos antes de iniciar a captura.")
                return 0
            time.sleep(.1)
        raise RuntimeError("A janela nao manteve a posicao/tamanho solicitado. Confira se o jogo esta em fullscreen; use modo janela e execute novamente.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
