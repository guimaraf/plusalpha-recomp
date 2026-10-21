"""Read-only dual-process startup trace. No input, pause or timing commands."""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import platform
import socket
import statistics
import sys
import threading
import time
from pathlib import Path


def request(port, command, **args):
    start = time.perf_counter_ns()
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall((json.dumps(dict(id=1, cmd=command, **args)) + "\n").encode())
        with sock.makefile("rb") as stream:
            while True:
                line = stream.readline(2 * 1024 * 1024)
                if not line:
                    raise ConnectionError("debug server closed before reply")
                data = json.loads(line)
                if data.get("id") == 1:
                    if not data.get("ok"):
                        raise RuntimeError(f"{command}: {data}")
                    return dict(command=command, request_ns=start,
                                response_ns=time.perf_counter_ns(), data=data)


def collect(port, path, stop, deadline, from_now=False, ready=None):
    cursor = 0
    last_video = 0
    announced = False
    with path.open("x", encoding="utf-8", buffering=1) as output:
        if from_now:
            initial = request(port, "net_sync_trace", after=0, count=1)
            if not initial["data"].get("enabled"):
                raise RuntimeError(f"port {port}: restart with PSX_NET_SYNC_TRACE=1")
            cursor = initial["data"]["total"]
            output.write(json.dumps(dict(command="trace_start", start_after_seq=cursor,
                frequency=initial["data"]["frequency"], request_ns=initial["request_ns"],
                response_ns=initial["response_ns"])) + "\n")
        while not stop.is_set() and time.monotonic() < deadline:
            try:
                batch = request(port, "net_sync_trace", after=cursor, count=128)
                output.write(json.dumps(batch) + "\n")
                data = batch["data"]
                if not data.get("enabled"):
                    raise RuntimeError(f"port {port}: restart with PSX_NET_SYNC_TRACE=1")
                if not announced:
                    print(f"Porta {port}: captura ativa" + (" desde agora." if from_now else "; pode criar/entrar na sala."), flush=True)
                    announced = True
                if ready is not None:
                    ready.set()
                if data["total"] < cursor:
                    raise RuntimeError(f"port {port}: process restarted; begin a new capture")
                entries = data["entries"]
                if entries:
                    cursor = entries[-1]["seq"]
                if data.get("lost"):
                    print(f"Porta {port}: {data['lost']} eventos perdidos!", file=sys.stderr)
                # Drain history before slow GL diagnostics. Never change settings.
                if cursor < data["total"]:
                    continue
                if time.monotonic() - last_video >= 2:
                    for command in ("netplay_status", "video_info"):
                        output.write(json.dumps(request(port, command)) + "\n")
                    last_video = time.monotonic()
                stop.wait(0.25)
            except (OSError, ConnectionError) as error:
                output.write(json.dumps(dict(connection_error=str(error),
                                             collector_ns=time.perf_counter_ns())) + "\n")
                stop.wait(0.5)


def read_history(path):
    events = []
    frequency = None
    lost = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        if row.get("command") != "net_sync_trace":
            continue
        data = row["data"]
        frequency = data.get("frequency")
        lost += data.get("lost", 0)
        events.extend(data.get("entries", []))
    return events, frequency, lost


def phase_stats(pairs):
    if not pairs:
        return None
    offsets = [p["b_minus_a_ms"] for p in pairs]
    absolute = sorted(abs(v) for v in offsets)
    longest = current = 0
    previous = None
    for pair in pairs:
        if abs(pair["b_minus_a_ms"]) > 2 * 1000 / 59.94:
            current = current + 1 if previous is not None and pair["tick"] == previous + 1 else 1
            longest = max(longest, current)
        else:
            current = 0
        previous = pair["tick"]
    return dict(min=min(offsets), max=max(offsets), median=statistics.median(offsets),
                abs_p95=absolute[int(.95 * (len(absolute) - 1))],
                abs_p99=absolute[int(.99 * (len(absolute) - 1))],
                over_2_frames_longest_ticks=longest)


def session_groups(events):
    groups = {}
    for e in events:
        if e["stage"] == 3 and e["running"] and not e["resim"] and not e["tip_hold"]:
            values = groups.setdefault(e["generation"], {})
            values.setdefault(e["tick"], e)
    return groups


def summarize(paths):
    histories = [read_history(path) for path in paths]
    result = dict(schema=2, events=[len(h[0]) for h in histories],
                  lost=[h[2] for h in histories],
                  warning="Same Windows PC only. Tick is admission cursor, not displayed frame. "
                          "Input lead is runway, not phase. Session pairing refuses ambiguity.")
    a, b = histories
    if platform.system() != "Windows" or not a[1] or a[1] != b[1]:
        result["comparison_unavailable"] = "Requires same-PC Windows QPC and equal frequency"
        return result
    # Generation is local to each process: a host switch may produce unequal IDs.
    # Pair by common ticks, opposite roles and nearby time at the first common tick.
    # Never silently pair ambiguous/restarted sessions.
    groups = [session_groups(h[0]) for h in histories]
    candidates = []
    for ga, left in groups[0].items():
        for gb, right in groups[1].items():
            common = sorted(left.keys() & right.keys())
            if not common:
                continue
            t = common[0]
            if left[t]["host"] == right[t]["host"]:
                continue
            if abs(left[t]["qpc"] - right[t]["qpc"]) > a[1] * 5:
                continue
            candidates.append((ga, gb, common))
    unique = [(ga, gb, ticks) for ga, gb, ticks in candidates
              if sum(x[0] == ga for x in candidates) == 1
              and sum(x[1] == gb for x in candidates) == 1]
    all_pairs = []
    result["sessions"] = []
    for ga, gb, common in unique:
        left, right = groups[0][ga], groups[1][gb]
        pairs = [dict(generation=ga, generation_b=gb, tick=t,
                      qpc_a=left[t]["qpc"], qpc_b=right[t]["qpc"],
                      b_minus_a_ms=(right[t]["qpc"] - left[t]["qpc"]) * 1000 / a[1],
                      delay_a=left[t]["delay"], delay_b=right[t]["delay"],
                      host_a=left[t]["host"], host_b=right[t]["host"]) for t in common]
        all_pairs.extend(pairs)
        result["sessions"].append(dict(generation_a=ga, generation_b=gb,
            first_tick=common[0], last_tick=common[-1], matched_admits=len(pairs),
            host_a=pairs[0]["host_a"], host_b=pairs[0]["host_b"],
            phase_ms=phase_stats(pairs), first_20=pairs[:20], last_20=pairs[-20:]))
    result["unpaired_generations_a"] = sorted(set(groups[0]) - {x[0] for x in unique})
    result["unpaired_generations_b"] = sorted(set(groups[1]) - {x[1] for x in unique})
    result["matched_admits"] = len(all_pairs)
    result["first_20_matching_admits"] = all_pairs[:20]
    result["last_20_matching_admits"] = all_pairs[-20:]
    if all_pairs:
        result["same_tick_b_minus_a_ms"] = phase_stats(all_pairs)
    # Markers are external QPC timestamps. Keep unclosed windows explicit.
    marker_file = paths[0].parent / "markers.jsonl"
    result["marker_windows"] = []
    if marker_file.exists():
        markers = [json.loads(line) for line in marker_file.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
        result["markers"] = markers
        pending = {}
        for marker in markers:
            label = marker["label"]
            if marker.get("frequency") != a[1]:
                continue
            if marker["edge"] == "begin":
                pending.setdefault(label, []).append(marker)
            elif marker["edge"] == "end" and pending.get(label):
                start = pending[label].pop()
                window = [p for p in all_pairs if start["qpc"] <= p["qpc_a"] <= marker["qpc"]]
                result["marker_windows"].append(dict(label=label, begin=start, end=marker,
                    matched_admits=len(window), phase_ms=phase_stats(window)))
        result["unclosed_markers"] = [m for values in pending.values() for m in values]
    return result


def drag_plan(target, order, baseline, drag, recovery):
    roles = ["host", "client"] if order == "HostFirst" else ["client", "host"]
    if target != "both":
        roles = [target]
    return [(label, role, seconds) for role in roles for label, seconds in
            [("baseline-" + role, baseline), ("drag-" + role, drag),
             ("recovery-" + role, recovery)]]


def marker_clock():
    if platform.system() == "Windows":
        import ctypes
        stamp, frequency = ctypes.c_longlong(), ctypes.c_longlong()
        kernel = ctypes.windll.kernel32
        if not kernel.QueryPerformanceCounter(ctypes.byref(stamp)) or not kernel.QueryPerformanceFrequency(ctypes.byref(frequency)):
            raise RuntimeError("QPC unavailable")
        return stamp.value, frequency.value
    return time.perf_counter_ns(), 1000000000


def run_drag_schedule(output, plan, roles, stop, check_workers, beep=False):
    # Timed external markers; no focus changes, window operations or game input.
    with (output / "markers.jsonl").open("x", encoding="utf-8", buffering=1) as stream:
        for label, role, seconds in plan:
            if stop.is_set():
                return
            action = "ARRASTE SOMENTE" if label.startswith("drag-") else "SOLTE / NAO ARRASTE"
            print(f"\n{action}: {role.upper()} = porta {roles[role]} | {seconds:g} segundos | {label}", flush=True)
            if beep and platform.system() == "Windows":
                import winsound
                try:
                    winsound.MessageBeep()
                except (RuntimeError, OSError):
                    print("Aviso sonoro indisponivel; acompanhe o texto no console.", flush=True)
            for edge in ["begin", "end"]:
                qpc, frequency = marker_clock()
                stream.write(json.dumps(dict(schema=1,
                    utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    qpc=qpc, frequency=frequency, label=label, edge=edge,
                    role=role, port=roles[role], note="Automatic timed phase; user performs drag")) + "\n")
                if edge == "begin":
                    until = time.monotonic() + seconds
                    while time.monotonic() < until and not stop.is_set():
                        check_workers()
                        stop.wait(min(.1, max(0, until - time.monotonic())))
                    if stop.is_set():
                        return
    print("\nArrastos concluidos. Mantenha as janelas paradas; finalizando captura.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, nargs=2, default=[4531, 4532])
    parser.add_argument("--seconds", type=float, default=300)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--executables", type=Path, nargs=2)
    parser.add_argument("--label", default="T01")
    parser.add_argument("--open-order", default="FirstThenSecond")
    parser.add_argument("--drag-test", choices=["host", "client", "both"])
    parser.add_argument("--drag-order", choices=["HostFirst", "ClientFirst"], default="HostFirst")
    parser.add_argument("--drag-seconds", type=float, default=15)
    parser.add_argument("--recovery-seconds", type=float, default=20)
    parser.add_argument("--baseline-seconds", type=float, default=10)
    parser.add_argument("--beep", action="store_true")
    args = parser.parse_args()
    if args.seconds <= 0 or len(set(args.ports)) != 2 or any(not 0 < p < 65536 for p in args.ports):
        parser.error("Use positive seconds and two distinct valid ports")
    plan, roles, preflight = [], {}, []
    if args.drag_test:
        if min(args.drag_seconds, args.recovery_seconds, args.baseline_seconds) <= 0:
            parser.error("Phase durations must be positive")
        for port in args.ports:
            snapshot = request(port, "netplay_status")
            status = snapshot["data"]
            if not status.get("active") or status.get("players") != 2 or not status.get("rollback") or status.get("fmv_media_active"):
                parser.error(f"Port {port}: prepare the online versus match before this test")
            role = "host" if status["host"] else "client"
            if role in roles:
                parser.error("Expected one host and one client")
            roles[role] = port
            preflight.append(dict(port=port, **snapshot))
        plan = drag_plan(args.drag_test, args.drag_order, args.baseline_seconds,
                         args.drag_seconds, args.recovery_seconds)
        args.seconds = sum(p[2] for p in plan) + 15
        print(f"HOST: porta {roles['host']} | CLIENTE: porta {roles['client']}", flush=True)
        print("Volte ao jogo. Siga os avisos de inicio/fim; nao precisa voltar ao PowerShell.", flush=True)
    args.output.mkdir(parents=True, exist_ok=False)
    builds = []
    for exe in args.executables or []:
        digest = hashlib.sha256()
        with exe.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        builds.append(dict(path=str(exe.resolve()), sha256=digest.hexdigest()))
    (args.output / "manifest.json").write_text(json.dumps(dict(
        schema=2, label=args.label, open_order=args.open_order,
        utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        platform=platform.platform(), ports=args.ports, seconds=args.seconds, builds=builds,
        from_now=bool(args.drag_test), drag_plan=plan, role_ports=roles, preflight=preflight,
        argv=sys.argv, stages={1: "barrier_enter", 2: "barrier_wait", 3: "barrier_exit",
                             4: "present_begin", 5: "present_end", 6: "pacer_begin", 7: "pacer_end", 8: "session_started"}
    ), indent=2), encoding="utf-8")
    paths = [args.output / f"peer-{p}.jsonl" for p in args.ports]
    stop = threading.Event()
    deadline = time.monotonic() + args.seconds
    errors = []
    print(f"Aguardando as duas instancias. Saida: {args.output}", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        readiness = [threading.Event(), threading.Event()]
        futures = [pool.submit(collect, port, path, stop, deadline, bool(args.drag_test), ready)
                   for port, path, ready in zip(args.ports, paths, readiness)]
        def check_workers():
            for f in futures:
                if f.done():
                    if f.exception():
                        raise f.exception()
                    if args.drag_test:
                        raise RuntimeError("Collector stopped before timed test finished")
        try:
            if args.drag_test:
                ready_deadline = time.monotonic() + 10
                while not all(e.is_set() for e in readiness):
                    check_workers()
                    if time.monotonic() >= ready_deadline:
                        raise RuntimeError("Both collectors must be ready before timed test")
                    stop.wait(.1)
                run_drag_schedule(args.output, plan, roles, stop, check_workers, args.beep)
                stop.wait(.5)
                check_workers()
                stop.set()
            while any(not f.done() for f in futures):
                for f in futures:
                    if f.done() and f.exception():
                        raise f.exception()
                time.sleep(0.2)
        except KeyboardInterrupt:
            print("Finalizando e preservando a captura...", flush=True)
        except Exception as error:
            errors.append(str(error))
        finally:
            stop.set()
        for f in futures:
            try:
                f.result()
            except Exception as error:
                if str(error) not in errors:
                    errors.append(str(error))
    summary = summarize(paths)
    summary["errors"] = errors
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2), flush=True)
    # A waiting-only/disabled/overwritten trace must not look like a successful study.
    return 1 if errors or any(summary["lost"]) or any(n == 0 for n in summary["events"]) or not summary.get("matched_admits") or summary.get("unpaired_generations_a") or summary.get("unpaired_generations_b") else 0


if __name__ == "__main__":
    raise SystemExit(main())
