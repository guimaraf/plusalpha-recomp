#!/usr/bin/env python3
"""Pre-visualizacao de um lote de seeds (docs/PLANO_100.md, Fase 2, etapa 2.0).

Gera, fora do repositorio, a base (seeds atuais) e a base+candidatas com o emitter
(`psxrecomp-game.exe --config`, ~1 s) e relata, por seed e no total: palavras, funcoes e
entradas novas; palavras perdidas (devem ser 0); checagem de borda (prologo ou `jr ra`+delay);
`jalr` e `jr` nao-$ra no fechamento; stores em texto (SMC); intersecao com coverage/exclusions.json
(deve ser 0); e a metrica oficial (coverage_metric.py --skip-overlays) do candidato.
Orcamento padrao: <= 1200 palavras e <= 10 funcoes por lote (--allow-over-budget para exceder).
Saida 1 se houver perda, quarentena ou orcamento estourado. Nunca escreve no repositorio.

Uso: seed_preview.py 0x8010A5FC 0x8010ABC8 ...   |   seed_preview.py --seeds-file lote.txt
"""
import argparse
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TOOLS_DIR.parent
REPO_ROOT = PROJECT_ROOT.parent
sys.path.insert(0, str(TOOLS_DIR))
import coverage_metric as cm  # noqa: E402

EMITTER = REPO_ROOT / "psxrecomp" / "recompiler" / "build" / "psxrecomp-game.exe"
TEXT_LO, EXE_FILE_OFF = 0x80101000, 0x800
SMC_HI = 0x801AB3E8
MAX_WORDS, MAX_FUNCS = 1200, 10
STORE_OPS = (0x28, 0x29, 0x2B, 0x2A, 0x2E, 0x3A)  # sb sh sw swl swr swc2
JR_RA_WORD = 0x03E00008


# ---------------------------------------------------------------- logica pura
def parse_seed_lines(lines):
    """[(addr, comentario)] de linhas `0xADDR  # comentario` (linha so de comentario ignorada)."""
    out = []
    for raw in lines:
        code, _, comment = raw.partition("#")
        for tok in code.split():
            out.append((int(tok, 16), comment.strip()))
    return out


def callable_boundary(word_at, addr):
    """'prologo' (addiu sp,sp,-N nas 4 primeiras palavras), 'jr_ra+delay' (word[a-8] e jr ra,
    o delay slot e a-4) ou None. word_at(addr) -> int; None fora do texto."""
    for i in range(4):
        w = word_at(addr + 4 * i)
        if w is not None and (w >> 26) == 9 and ((w >> 21) & 31) == 29 \
                and ((w >> 16) & 31) == 29 and (w & 0x8000):
            return "prologo"
    if word_at(addr - 8) == JR_RA_WORD:
        return "jr_ra+delay"
    return None


def scan_words(word_at, addrs):
    """jalr, jr nao-$ra e stores com destino em texto (lui+offset) entre `addrs`."""
    r = {"jalr": [], "jr_nonra": [], "smc": []}
    for a in sorted(addrs):
        v = word_at(a)
        if v is None:
            continue
        op, fn, rs = v >> 26, v & 0x3F, (v >> 21) & 31
        if op == 0 and fn == 9:
            r["jalr"].append(a)
        if op == 0 and fn == 8 and rs != 31:
            r["jr_nonra"].append(a)
        if op in STORE_OPS:
            for k in range(1, 13):
                u = word_at(a - 4 * k)
                if u is None:
                    break
                if (u >> 26) == 15 and ((u >> 16) & 31) == rs:
                    off = v & 0xFFFF
                    off -= 0x10000 if off & 0x8000 else 0
                    t = (((u & 0xFFFF) << 16) + off) & 0xFFFFFFFF
                    if TEXT_LO <= t < SMC_HI:
                        r["smc"].append((a, t))
                    break
                if (u >> 26) in (8, 9, 13, 0x23, 0x21, 0x25, 0x24) and ((u >> 16) & 31) == rs:
                    break
    return r


def exclusion_hits(addrs, exclusions):
    """Palavras de `addrs` dentro de alguma exclusao [(lo, hi, categoria)]."""
    return sorted(a for a in addrs for lo, hi, _c in exclusions if lo <= a < hi)


def budget_errors(new_words, new_funcs, allow_over=False,
                  max_words=MAX_WORDS, max_funcs=MAX_FUNCS):
    if allow_over:
        return []
    errs = []
    if new_words > max_words:
        errs.append(f"palavras novas {new_words} > {max_words}")
    if new_funcs > max_funcs:
        errs.append(f"funcoes novas {new_funcs} > {max_funcs}")
    return errs


def diff_runs(base, cand):
    """base/cand: dict(words:set, funcs:set, entries:set). Delta e perdas."""
    return {"new_words": sorted(cand["words"] - base["words"]),
            "lost_words": sorted(base["words"] - cand["words"]),
            "new_funcs": sorted(cand["funcs"] - base["funcs"]),
            "lost_funcs": sorted(base["funcs"] - cand["funcs"]),
            "new_entries": sorted(cand["entries"] - base["entries"]),
            "lost_entries": sorted(base["entries"] - cand["entries"])}


def run_exit_code(total, quarantined, over_budget_errs):
    return 1 if (total["lost_words"] or total["lost_funcs"] or total["lost_entries"]
                 or quarantined or over_budget_errs) else 0


# ------------------------------------------------------------------ geracao
def make_toml(work, seeds_path, out_dir):
    """game.toml temporario (caminhos absolutos); .gitignore marca a raiz do projeto."""
    def f(p):
        return str(Path(p).resolve()).replace("\\", "/")
    t = (PROJECT_ROOT / "game.toml").read_text(encoding="utf-8")
    subs = {"exe": f(PROJECT_ROOT / "local" / "SLUS_005.48"),
            "disc": f(PROJECT_ROOT / "disc-a" / "Street Fighter EX Plus Alpha (USA).cue"),
            "bios_config": f(REPO_ROOT / "psxrecomp" / "bios" / "SCPH1001.toml"),
            "seeds": f(seeds_path), "out_dir": f(out_dir)}
    for key, val in subs.items():
        t, n = re.subn(rf'(?m)^{key}\s*=\s*"generated-online"\s*$' if key == "out_dir"
                      else rf'(?m)^{key}\s*=.*$', lambda m, k=key, v=val: f'{k} = "{v}"', t)
        if n != 1:
            raise RuntimeError(f"game.toml: chave {key} encontrada {n}x")
    (Path(work) / ".gitignore").write_text("*\n", encoding="utf-8")
    path = Path(work) / "game.toml"
    path.write_text(t, encoding="utf-8")
    return path


def generate(work, name, extra_seeds):
    """Roda o emitter para base (+ seeds extras); devolve dict(words, funcs, entries, out)."""
    d = Path(work) / name
    out = d / "out"
    out.mkdir(parents=True, exist_ok=True)
    base_text = (PROJECT_ROOT / "seeds" / "entry_funcs.txt").read_text(encoding="utf-8")
    body = base_text + ("\n# preview\n" + "".join(f"0x{a:08X}\n" for a in extra_seeds)
                        if extra_seeds else "")
    (d / "seeds.txt").write_text(body, encoding="utf-8")
    toml = make_toml(d, d / "seeds.txt", out)
    p = subprocess.run([str(EMITTER), "--config", str(toml)], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", creationflags=0x4000)
    (d / "emitter.log").write_text(p.stdout + p.stderr, encoding="utf-8")
    if p.returncode:
        raise RuntimeError(f"emitter falhou em {name}: rc={p.returncode} {p.stderr[-300:]}")
    funcs, ranges = cm.parse_ranges((out / "SLUS_005.48_full.ranges").read_text(encoding="utf-8"))
    return {"words": cm.covered_word_set(ranges, TEXT_LO, 0x801C0000), "funcs": funcs,
            "entries": cm.parse_dispatch((out / "SLUS_005.48_dispatch.c").read_text(encoding="utf-8")),
            "out": out}


def exe_word_reader():
    data = (PROJECT_ROOT / "local" / "SLUS_005.48").read_bytes()

    def word_at(a):
        o = a - TEXT_LO + EXE_FILE_OFF
        if a < TEXT_LO or o + 4 > len(data):
            return None
        return struct.unpack_from("<I", data, o)[0]
    return word_at


def load_exclusions():
    d = json.loads((PROJECT_ROOT / "coverage" / "exclusions.json").read_text(encoding="utf-8"))
    return [(int(e["lo"], 16), int(e["hi"], 16), e.get("category", "?")) for e in d["exclusions"]]


def analyse(word_at, exclusions, base, cand):
    d = diff_runs(base, cand)
    nw = set(d["new_words"])
    scan = scan_words(word_at, nw)
    d.update(jalr=scan["jalr"], jr_nonra=scan["jr_nonra"], smc=scan["smc"],
             quarantine=exclusion_hits(nw, exclusions))
    return d


def metric(work, name, cand):
    js = Path(work) / name / "coverage.json"
    p = subprocess.run([sys.executable, str(TOOLS_DIR / "coverage_metric.py"), "--skip-overlays",
                        "--ranges", str(cand["out"] / "SLUS_005.48_full.ranges"),
                        "--dispatch", str(cand["out"] / "SLUS_005.48_dispatch.c"),
                        "--json", str(js)], capture_output=True, text=True)
    if p.returncode:
        return {"error": (p.stdout + p.stderr)[-300:]}
    return json.loads(js.read_text(encoding="utf-8"))["exe"]


# --------------------------------------------------------------------- CLI
def fmt_list(xs, n=6):
    def one(x):
        return f"{x:08X}" if isinstance(x, int) else f"{x[0]:08X}->{x[1]:08X}"
    return " ".join(one(x) for x in xs[:n]) + (f" (+{len(xs) - n})" if len(xs) > n else "")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("seeds", nargs="*", help="seeds candidatas (hex)")
    ap.add_argument("--seeds-file", help="arquivo com `0xADDR  # comentario`")
    ap.add_argument("--allow-over-budget", action="store_true")
    ap.add_argument("--keep", action="store_true", help="mantem o diretorio temporario")
    ap.add_argument("--json", help="grava o relatorio em JSON")
    args = ap.parse_args(argv)
    cands = [(int(s, 16), "") for s in args.seeds]
    if args.seeds_file:
        cands += parse_seed_lines(Path(args.seeds_file).read_text(encoding="utf-8").splitlines())
    if not cands:
        ap.error("nenhuma seed candidata")
    if not EMITTER.is_file():
        print(f"ERRO: emitter ausente: {EMITTER}", file=sys.stderr)
        return 2
    work = tempfile.mkdtemp(prefix="seed_preview_")
    try:
        word_at, excl = exe_word_reader(), load_exclusions()
        base = generate(work, "base", [])
        total_run = generate(work, "candidato", [a for a, _ in cands])
        rows = []
        for i, (a, comment) in enumerate(cands):
            one = generate(work, f"seed_{i}", [a])
            r = analyse(word_at, excl, base, one)
            r.update(seed=a, comment=comment, boundary=callable_boundary(word_at, a),
                     in_closure=a in total_run["funcs"])
            rows.append(r)
        total = analyse(word_at, excl, base, total_run)
        m_base, m_cand = metric(work, "base", base), metric(work, "candidato", total_run)
        berr = budget_errors(len(total["new_words"]), len(total["new_funcs"]), args.allow_over_budget)
        print(f"== seed_preview: base {len(base['words'])} palavras, {len(base['funcs'])} funcoes, "
              f"{len(base['entries'])} entradas ==")
        for r in rows:
            print(f"0x{r['seed']:08X}  +{len(r['new_words']):4d} palavras  +{len(r['new_funcs']):2d} func  "
                  f"+{len(r['new_entries']):3d} entradas  perdas={len(r['lost_words'])}  "
                  f"borda={r['boundary'] or 'NAO'}  jalr={len(r['jalr'])} jr!ra={len(r['jr_nonra'])} "
                  f"smc={len(r['smc'])}  quarentena={len(r['quarantine'])}"
                  + (f"  # {r['comment']}" if r['comment'] else ""))
        print(f"-- TOTAL: +{len(total['new_words'])} palavras, +{len(total['new_funcs'])} funcoes, "
              f"+{len(total['new_entries'])} entradas")
        print(f"   perdas: palavras={len(total['lost_words'])} funcoes={len(total['lost_funcs'])} "
              f"entradas={len(total['lost_entries'])}")
        print(f"   jalr no fechamento: {len(total['jalr'])} {fmt_list(total['jalr'])}")
        print(f"   jr nao-ra no fechamento: {len(total['jr_nonra'])} {fmt_list(total['jr_nonra'])}")
        print(f"   stores em texto (SMC): {len(total['smc'])} {fmt_list(total['smc'])}")
        print(f"   quarentena (exclusoes): {len(total['quarantine'])} {fmt_list(total['quarantine'])}")
        bad = ["0x%08X" % r["seed"] for r in rows if not r["boundary"]]
        print(f"   bordas fora do padrao: {bad}")
        if "error" in m_cand:
            print(f"   metrica: ERRO {m_cand['error']}")
        else:
            print(f"   metrica EXE: base {m_base['covered_words']} palavras/{m_base['dispatch_entries']} "
                  f"entradas ({m_base['pct']:.4f}%) -> candidato {m_cand['covered_words']}/"
                  f"{m_cand['dispatch_entries']} ({m_cand['pct']:.4f}%)")
        print(f"   orcamento: {'OK' if not berr else 'ESTOURADO ' + '; '.join(berr)}"
              + (" (--allow-over-budget)" if args.allow_over_budget else ""))
        if args.json:
            Path(args.json).write_text(json.dumps(
                {"rows": rows, "total": total, "metric_base": m_base, "metric_candidate": m_cand,
                 "budget_errors": berr}, indent=1, default=str), encoding="utf-8")
        rc = run_exit_code(total, total["quarantine"], berr)
        print("RESULTADO:", "OK" if rc == 0 else "REPROVADO")
        return rc
    finally:
        if args.keep:
            print(f"temporario mantido: {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
