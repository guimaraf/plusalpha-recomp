"""Coleta comparativa de tempos internos; nao mede button-to-photon nem inicia o jogo."""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import socket
import statistics
import sys
import time
from datetime import datetime, timezone

try:
    import tomllib
except ImportError:
    raise SystemExit("Este coletor requer Python 3.11 ou mais recente.")


MODES = {"immediate": 0, "vsync": 1, "adaptive": -1}
METRICS = ("frame_period", "input_to_swap", "swap_block", "sample_to_present_end")


def command(port, payload):
    with socket.create_connection(("127.0.0.1", port), timeout=3) as connection:
        connection.settimeout(3)
        connection.sendall((json.dumps(payload) + "\n").encode())
        data = bytearray()
        while len(data) < 1024 * 1024:
            packet = connection.recv(65536)
            if not packet:
                break
            data.extend(packet)
            try:
                reply = json.loads(data.decode("utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if not reply.get("ok"):
                raise RuntimeError(f"Telemetria recusou a consulta: {reply}")
            return reply
    raise RuntimeError("Resposta de telemetria incompleta ou muito grande.")


def latency(port):
    return command(port, {"id": 1, "cmd": "latency", "window": 120, "raw": 1, "count": 120})


def validate_mode(summary, mode):
    if summary.get("present_mode") != MODES[mode]:
        raise RuntimeError(
            f"Modo informado {mode}, mas o runtime reportou present_mode={summary.get('present_mode')}. "
            "Feche o jogo, selecione o modo no launcher e inicie novamente."
        )


def frame_samples(reply, first_frame):
    records = reply.get("frames", [])
    samples = []
    for index, record in enumerate(records):
        if record["f"] < first_frame:
            continue
        ti, begin, end = (record[key] for key in ("input", "swap_begin", "swap_end"))
        if not all(math.isfinite(value) for value in (ti, begin, end)) or begin < ti or end < begin:
            continue  # frames ainda incompletos ou sem apresentacao
        period = None
        if index and records[index - 1]["f"] == record["f"] - 1:
            period = (ti - records[index - 1]["input"]) / 1000
            if period <= 0:
                period = None
        samples.append({
            "frame": record["f"], "frame_period": period,
            "input_to_swap": (begin - ti) / 1000,
            "swap_block": (end - begin) / 1000,
            "sample_to_present_end": (end - ti) / 1000,
        })
    return samples


def stats(values):
    values = sorted(values)
    if not values:
        return {"n": 0, "mean_ms": None, "p50_ms": None, "p95_ms": None, "max_ms": None}
    return {
        "n": len(values), "mean_ms": statistics.mean(values),
        "p50_ms": statistics.median(values),
        "p95_ms": values[max(0, math.ceil(len(values) * .95) - 1)], "max_ms": values[-1],
    }


def write_comparison(output):
    columns = ["run", "mode", "repetition", "backend", "scenario", "config_group", "samples", "errors"]
    columns += [f"{metric}_{stat}_ms" for metric in METRICS for stat in ("mean", "p95", "max")]
    reports = []
    with (output / "comparison.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        for path in sorted(output.glob("*/summary.json")):
            report = json.loads(path.read_text(encoding="utf-8"))
            reports.append(report)
            row = {key: report[key] for key in columns[:8]}
            for metric in METRICS:
                for stat in ("mean", "p95", "max"):
                    row[f"{metric}_{stat}_ms"] = report["metrics"][metric][f"{stat}_ms"]
            writer.writerow(row)
    return reports


def main(argv=None):
    project = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", required=True, choices=MODES)
    parser.add_argument("--build-dir", type=Path, default=project / "buildTele-s1-309-bezeus")
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--repetition", type=int, default=1)
    parser.add_argument("--scenario", default="mesmo personagem e cenario; ciclo de 20s: esquerda 5s, direita 5s, socos 10s")
    parser.add_argument("--output", type=Path, default=project.parent / "local/telemetry/vsync-latency")
    args = parser.parse_args(argv)
    if not 10 <= args.seconds <= 600 or not 5 <= args.warmup <= 120 or args.repetition < 1:
        parser.error("seconds: 10 a 600; warmup: 5 a 120; repetition: pelo menos 1.")

    settings_path, game_path = (args.build_dir / name for name in ("settings.toml", "game.toml"))
    settings_bytes, game_bytes = settings_path.read_bytes(), game_path.read_bytes()
    settings = tomllib.loads(settings_bytes.decode("utf-8-sig"))
    game = tomllib.loads(game_bytes.decode("utf-8-sig"))
    video = settings.get("video", {})
    saved_mode = video.get("vsync", "on")
    saved_mode = ("on" if saved_mode else "immediate") if isinstance(saved_mode, bool) else saved_mode
    expected = {"on": "vsync", "immediate": "immediate", "adaptive": "adaptive"}.get(saved_mode)
    if expected != args.mode:
        raise RuntimeError(f"settings.toml possui vsync={saved_mode!r}. Selecione {args.mode} no launcher e reinicie o jogo.")
    if not video.get("low_latency_input", True) or video.get("frame_interpolation", False):
        raise RuntimeError("Para esta comparacao, mantenha Low-latency input On e Frame interpolation Off.")
    port = int(game.get("runtime", {}).get("debug_port", 4531))
    initial = latency(port)
    validate_mode(initial["summary"], args.mode)
    backend = initial["summary"]["backend"]
    print(f"Modo: {args.mode}; backend reportado: {backend}; porta: {port}")
    if backend == "software" and args.mode == "adaptive":
        print("ATENCAO: no caminho SDL/Software, Adaptive habilita VSync como o modo VSync.")
    print("Este teste mede tempos internos; nao mede a resposta fisica do botao na tela.")
    print("Use uma luta de treino com o mesmo personagem/cenario e sem menus ou carregamentos.")
    print("Mantenha o mesmo controle, conexao, resolucao, Hz, fullscreen, bezel e demais opcoes.")
    print(f"Roteiro: {args.scenario}")
    input("Com o jogo pronto para o teste, pressione ENTER aqui; depois volte o foco para o jogo: ")
    print(f"Aquecimento de {args.warmup}s. Em seguida jogue por {args.seconds}s seguindo o roteiro.", flush=True)
    time.sleep(args.warmup)
    start_reply = latency(port)
    validate_mode(start_reply["summary"], args.mode)
    first_frame = start_reply["summary"]["frames"]
    if start_reply["summary"]["backend"] != backend:
        raise RuntimeError("Backend mudou durante o aquecimento.")

    run_name = f"{datetime.now(timezone.utc):%Y%m%dT%H%M%S%fZ}-{args.mode}-r{args.repetition}"
    run_dir = args.output / run_name
    run_dir.mkdir(parents=True, exist_ok=False)
    (run_dir / "settings.toml").write_bytes(settings_bytes)
    (run_dir / "game.toml").write_bytes(game_bytes)
    samples, errors = {}, []
    started = time.monotonic()
    print("Coleta iniciada. Continue no jogo ate completar o periodo.", flush=True)
    with (run_dir / "raw.jsonl").open("w", encoding="utf-8") as raw:
        while True:
            elapsed = time.monotonic() - started
            try:
                reply = latency(port)
                validate_mode(reply["summary"], args.mode)
                if reply["summary"]["backend"] != backend or reply["summary"]["frames"] < first_frame:
                    raise RuntimeError("Backend mudou ou o jogo foi reiniciado durante a coleta.")
                raw.write(json.dumps({"elapsed_s": elapsed, "response": reply}) + "\n")
                raw.flush()
                for sample in frame_samples(reply, first_frame):
                    samples[sample["frame"]] = sample  # janelas sobrepostas nao duplicam frames
            except (OSError, ValueError) as error:
                errors.append({"elapsed_s": elapsed, "error": str(error)})
            if time.monotonic() - started >= args.seconds:
                break
            time.sleep(max(0, min(1, args.seconds - (time.monotonic() - started))))

    ordered = sorted(samples.values(), key=lambda sample: sample["frame"])
    signature_settings = json.loads(json.dumps(settings))
    signature_settings.get("video", {}).pop("vsync", None)
    signature = {"settings": signature_settings, "game": game, "backend": backend, "scenario": args.scenario}
    group = hashlib.sha256(json.dumps(signature, sort_keys=True).encode()).hexdigest()[:12]
    metrics = {metric: stats([row[metric] for row in ordered if row[metric] is not None]) for metric in METRICS}
    report = {
        "run": run_name, "mode": args.mode, "repetition": args.repetition, "backend": backend,
        "scenario": args.scenario, "config_group": group, "samples": len(ordered), "errors": len(errors),
        "duration_s": time.monotonic() - started, "metrics": metrics, "connection_errors": errors,
        "missing_frame_ids": sum(max(0, b["frame"] - a["frame"] - 1) for a, b in zip(ordered, ordered[1:])),
        "limitations": "Tempos internos, sem correlacao causal com a resposta do jogo e sem medir dispositivo ou scanout. Comparar apenas o mesmo config_group.",
    }
    (run_dir / "summary.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    with (run_dir / "frames.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=("frame",) + METRICS)
        writer.writeheader()
        writer.writerows(ordered)
    reports = write_comparison(args.output)
    print(f"Coleta encerrada: {len(ordered)} frames; {len(errors)} erros de conexao.")
    print(f"Resultados: {run_dir}\nComparacao: {args.output / 'comparison.csv'}")
    if not ordered:
        raise RuntimeError("Nenhum frame completo foi coletado. Verifique se o jogo estava ativo e com debug habilitado.")
    if errors or report["missing_frame_ids"]:
        print("ATENCAO: existem erros ou lacunas. Confira summary.json antes de comparar.")
    print("Comparacao do mesmo grupo de configuracoes (p95 em ms):")
    print("Modo        Rodada  Frames  Input->swap  Bloqueio swap  Periodo frame")
    for previous in reports:
        if previous["config_group"] != group:
            continue
        values = [previous["metrics"][key]["p95_ms"] for key in ("input_to_swap", "swap_block", "frame_period")]
        formatted = [f"{value:.3f}" if value is not None else "-" for value in values]
        print(f"{previous['mode']:<11} {previous['repetition']:>6} {previous['samples']:>7} "
              f"{formatted[0]:>12} {formatted[1]:>14} {formatted[2]:>14}")
    if any(previous["config_group"] != group for previous in reports):
        print("Rodadas com outras configuracoes constam no CSV, mas foram separadas desta tabela.")
    print("Compare media/p95 de swap_block e frame_period; valores menores nao provam menor button-to-photon.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyboardInterrupt) as error:
        print(f"Teste interrompido: {error}", file=sys.stderr)
        sys.exit(1)
