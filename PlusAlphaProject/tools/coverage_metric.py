#!/usr/bin/env python3
"""Metrica oficial de cobertura da recompilacao (Fase 0 de docs/PLANO_100.md).

Somente stdlib. Le o manifesto de ranges do EXE, a tabela do despachante, as
variantes estaticas de overlay e (opcionalmente) o disco, em modo somente leitura.
"""
import argparse
import hashlib
import json
import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATEGORIES = ('dados', 'padding', 'quarentena', 'hle_bios', 'morto_provado')
DISPATCH_RE = re.compile(
    r'^\s*\{0x([0-9A-Fa-f]{8})u,\s*0x[0-9A-Fa-f]+u,\s*\d+u,\s*\d+u,\s*func_', re.M)
OV_BASES = {  # nome (maiusculo, sem ;1) -> base fisica; PLxx tratado por regra
    'OVL3/BONUS.OVL': 0x18800, 'OVL3/OPTS.OVL': 0x20800,
    'OVL3/MOV.OVL': 0xD6400, 'OVL3/QUES.PAC': 0xD6400, 'OVL3/MC_M.OVL': 0xD6400,
    'OVL3/MC_I.OVL': 0xD6400, 'OVL3/END.OVL': 0xD6400,
}


class InputMissing(Exception):
    pass


class ExclusionError(Exception):
    pass


# ---------------------------------------------------------------- EXE
def parse_ranges(text):
    """Retorna (funcoes_unicas:set, ranges:list[(lo,len_bytes)])."""
    funcs, ranges = set(), []
    for line in text.splitlines():
        p = line.split()
        if len(p) == 2 and p[0] == 'F':
            funcs.add(int(p[1], 16))
        elif len(p) == 3 and p[0] == 'R':
            ranges.append((int(p[1], 16), int(p[2], 16)))
    return funcs, ranges


def covered_word_set(ranges, text_lo, text_hi):
    words = set()
    for lo, ln in ranges:
        for a in range(lo, lo + ln, 4):
            if text_lo <= a < text_hi:
                words.add(a)
    return words


def parse_dispatch(text):
    return {int(s, 16) for s in DISPATCH_RE.findall(text)}


def load_exclusions(data):
    exe = data['exe']
    t_lo, t_hi = int(exe['text_lo'], 16), int(exe['text_hi'], 16)
    items = []
    for e in data['exclusions']:
        lo, hi = int(e['lo'], 16), int(e['hi'], 16)
        if e['category'] not in CATEGORIES:
            raise ExclusionError(f"categoria invalida: {e['category']}")
        if not (t_lo <= lo < hi <= t_hi) or lo % 4 or hi % 4:
            raise ExclusionError(f'exclusao fora do texto/desalinhada: {lo:#x}..{hi:#x}')
        items.append((lo, hi, e['category']))
    items.sort()
    for a, b in zip(items, items[1:]):
        if b[0] < a[1]:
            raise ExclusionError(
                f'exclusoes sobrepostas: {a[0]:#x}..{a[1]:#x} e {b[0]:#x}..{b[1]:#x}')
    return t_lo, t_hi, items


def exe_metrics(funcs, ranges, dispatch, t_lo, t_hi, excl):
    text_words = (t_hi - t_lo) // 4
    excluded = {c: 0 for c in CATEGORIES}
    for lo, hi, c in excl:
        excluded[c] += (hi - lo) // 4
    cov = covered_word_set(ranges, t_lo, t_hi)
    in_excl = {c: 0 for c in CATEGORIES}
    for lo, hi, c in excl:
        in_excl[c] += sum(1 for a in range(lo, hi, 4) if a in cov)
    code = text_words - sum(excluded.values())
    covered = len(cov) - sum(in_excl.values())
    disp = {a for a in dispatch if t_lo <= a < t_hi}
    return {
        'text_words': text_words,
        'excluded_words': excluded,
        'code_words': code,
        'covered_words': covered,
        'covered_raw_words': len(cov),
        'legacy_summed_words': sum(ln // 4 for _, ln in ranges),
        'functions': len(funcs),
        'dispatch_entries': len(disp),
        'entries_not_covered': len(disp - cov),
        'covered_in_exclusions': in_excl,
        'pct': round(100.0 * covered / code, 4) if code else 0.0,
    }


# ---------------------------------------------------------------- overlays
def parse_overlays_static(text):
    """Retorna lista de variantes [{ranges, crc, entry}]; entry = addr da PsxOvEntry."""
    arrays = {}
    for m in re.finditer(
            r'static const uint32_t psx_ov_static_ranges_(\d+)\[\]\s*=\s*\{([^}]*)\};', text):
        nums = [int(x, 16) for x in re.findall(r'0x([0-9A-Fa-f]+)u', m.group(2))]
        arrays[m.group(1)] = list(zip(nums[0::2], nums[1::2]))
    vm = re.search(r'psx_ov_variants\[\d+\]\s*=\s*\{(.*?)\n\};', text, re.S)
    em = re.search(r'psx_ov_entries\[\d+\]\s*=\s*\{(.*?)\n\};', text, re.S)
    if not vm or not em:
        raise InputMissing('overlays_static.c sem tabelas psx_ov_variants/psx_ov_entries')
    variants = []
    for m in re.finditer(
            r'\{\s*psx_ov_static_ranges_(\d+),\s*(\d+)u,\s*0x([0-9A-Fa-f]+)u', vm.group(1)):
        variants.append({'ranges': arrays[m.group(1)], 'crc': int(m.group(3), 16),
                         'entry': None})
    for m in re.finditer(r'\{\s*0x([0-9A-Fa-f]+)u,\s*(\d+)u,\s*(\d+)u\s*\}', em.group(1)):
        addr, first, n = int(m.group(1), 16), int(m.group(2)), int(m.group(3))
        for i in range(first, first + n):
            variants[i]['entry'] = addr
    return variants


def variant_crc(variant, data, base):
    """CRC do runtime (overlay_loader.c:715-726): crc32 padrao encadeado sobre os ranges."""
    crc = 0
    for lo, ln in variant['ranges']:
        crc = zlib.crc32(data[lo - base:lo - base + ln], crc)
    return crc & 0xFFFFFFFF


def match_variants(variants, data, base):
    """Retorna (casadas, crc_mismatch) para um 'arquivo' em bytes na base fisica."""
    hit, miss = [], []
    end = base + len(data)
    for v in variants:
        if v['ranges'] and all(lo >= base and lo + ln <= end for lo, ln in v['ranges']):
            (hit if variant_crc(v, data, base) == v['crc'] else miss).append(v)
    return hit, miss


def union_words(variants, base, size):
    iv = sorted((max(lo, base), min(lo + ln, base + size))
                for v in variants for lo, ln in v['ranges'])
    total, cur_end = 0, None
    for a, b in iv:
        if cur_end is None or a > cur_end:
            total += b - a
            cur_end = b
        elif b > cur_end:
            total += b - cur_end
            cur_end = b
    return total // 4


def overlay_base(name):
    m = re.match(r'(OVL2?)/PL([0-9A-Fa-f]{2})_([12])\.OVL$', name, re.I)
    if m:
        return 0x43000 if m.group(3) == '1' else 0x8CA00
    return OV_BASES.get(name.upper())


def overlay_metrics(variants, files):
    """files: lista de (name, lba, bytes, base)."""
    rows, matched_ids = [], set()
    for name, lba, data, base in files:
        hit, miss = match_variants(variants, data, base)
        matched_ids.update(id(v) for v in hit)
        cov = union_words(hit, base, len(data))
        words = len(data) // 4
        rows.append({
            'name': name, 'lba': lba, 'size_bytes': len(data), 'size_words': words,
            'base': f'0x{base:X}', 'covered_words': cov,
            'pct': round(100.0 * cov / words, 4) if words else 0.0,
            'variants_matched': len(hit), 'crc_mismatch': len(miss),
            'entries': len({v['entry'] for v in hit}),
        })
    rows.sort(key=lambda r: r['name'])
    tot_words = sum(r['size_words'] for r in rows)
    tot_cov = sum(r['covered_words'] for r in rows)
    unmatched = sum(1 for v in variants if id(v) not in matched_ids)
    return {
        'files': rows,
        'total': {
            'files': len(rows), 'size_words': tot_words, 'covered_words': tot_cov,
            'pct': round(100.0 * tot_cov / tot_words, 4) if tot_words else 0.0,
            'variants_total': len(variants),
            'variants_matched': len(matched_ids), 'unmatched': unmatched,
            'crc_mismatch': sum(r['crc_mismatch'] for r in rows),
            'entries': sum(r['entries'] for r in rows),
            'denominator': 'provisorio: tamanho inteiro de cada arquivo',
        },
    }


# ---------------------------------------------------------------- disco
class Disc:
    def __init__(self, bin_path):
        self.f = open(bin_path, 'rb')

    def sector(self, n):
        self.f.seek(n * 2352 + 24)
        return self.f.read(2048)

    def read(self, lba, size):
        out = bytearray()
        for i in range((size + 2047) // 2048):
            out += self.sector(lba + i)
        return bytes(out[:size])

    def files(self):
        pvd = self.sector(16)
        root = struct.unpack('<I', pvd[158:162])[0]
        rlen = struct.unpack('<I', pvd[166:170])[0]
        out = []

        def walk(lba, ln, path):
            data = self.read(lba, ln)
            p = 0
            while p < len(data):
                l = data[p]
                if l == 0:
                    p = (p // 2048 + 1) * 2048
                    continue
                e = struct.unpack('<I', data[p + 2:p + 6])[0]
                sz = struct.unpack('<I', data[p + 10:p + 14])[0]
                fl, nl = data[p + 25], data[p + 32]
                nm = data[p + 33:p + 33 + nl].decode('latin1')
                p += l
                if nm in ('\x00', '\x01'):
                    continue
                if fl & 2:
                    walk(e, sz, path + nm + '/')
                else:
                    out.append((path + nm.split(';')[0], e, sz))
        walk(root, rlen, '')
        return out

    def close(self):
        self.f.close()


def cue_bin(cue_path):
    m = re.search(r'FILE\s+"([^"]+)"', cue_path.read_text(encoding='latin1'))
    if not m:
        raise InputMissing(f'cue sem FILE: {cue_path}')
    return need(cue_path.parent / m.group(1), 'imagem .bin do disco')


def disc_cue_from_game_toml(toml_path):
    m = re.search(r'^\s*disc\s*=\s*"([^"]+)"', toml_path.read_text(encoding='utf-8'), re.M)
    if not m:
        raise InputMissing(f'game.toml sem [game] disc: {toml_path}')
    return toml_path.parent / m.group(1)


def load_overlay_files(cue):
    disc = Disc(cue_bin(cue))
    try:
        res = []
        for name, lba, size in disc.files():
            base = overlay_base(name)
            if base is not None and name.upper().split('/')[0] in ('OVL', 'OVL2', 'OVL3'):
                res.append((name, lba, disc.read(lba, size), base))
        return res
    finally:
        disc.close()


# ---------------------------------------------------------------- relatorio
def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def need(path, what):
    if not Path(path).is_file():
        raise InputMissing(f'entrada obrigatoria ausente ({what}): {path}')
    return Path(path)


def build_report(args):
    ranges_p = need(args.ranges, 'ranges do EXE')
    disp_p = need(args.dispatch, 'tabela do despachante')
    excl_p = need(args.exclusions, 'exclusoes')
    funcs, ranges = parse_ranges(ranges_p.read_text())
    dispatch = parse_dispatch(disp_p.read_text(encoding='utf-8', errors='replace'))
    t_lo, t_hi, excl = load_exclusions(json.loads(excl_p.read_text()))
    report = {
        'exe': exe_metrics(funcs, ranges, dispatch, t_lo, t_hi, excl),
        'inputs_sha256': {'ranges': sha256(ranges_p), 'dispatch': sha256(disp_p),
                          'exclusions': sha256(excl_p)},
    }
    if not args.skip_overlays:
        ov_p = need(args.overlays, 'overlays_static.c')
        cue = need(args.cue, 'cue do disco')
        variants = parse_overlays_static(ov_p.read_text(encoding='utf-8', errors='replace'))
        files = load_overlay_files(cue)
        if not files:
            raise InputMissing('nenhum arquivo OVL/OVL2/OVL3 encontrado no disco')
        report['overlays'] = overlay_metrics(variants, files)
        report['inputs_sha256']['overlays_static'] = sha256(ov_p)
        report['inputs_sha256']['cue'] = sha256(cue)
        report['inputs_sha256']['overlay_images'] = {
            n: hashlib.sha256(d).hexdigest() for n, _, d, _ in sorted(files)}
    return report


def baseline_from(report):
    e = report['exe']
    b = {'schema': 1,
         'exe': {k: e[k] for k in ('covered_words', 'dispatch_entries', 'functions')}}
    if 'overlays' in report:
        b['overlays'] = {r['name']: {'covered_words': r['covered_words'],
                                     'entries': r['entries']}
                         for r in report['overlays']['files']}
    return b


def check(report, base, skip_overlays):
    errs = []
    for k in ('covered_words', 'dispatch_entries', 'functions'):
        if report['exe'][k] < base['exe'][k]:
            errs.append(f"exe.{k}: {report['exe'][k]} < baseline {base['exe'][k]}")
    bad = {c: n for c, n in report['exe']['covered_in_exclusions'].items() if n > 0}
    if bad:
        errs.append(f'palavras cobertas dentro de exclusoes: {bad}')
    if not skip_overlays and 'overlays' in report:
        cur = {r['name']: r for r in report['overlays']['files']}
        for name, b in sorted(base.get('overlays', {}).items()):
            r = cur.get(name)
            if r is None:
                errs.append(f'overlay {name}: ausente no relatorio')
                continue
            for k in ('covered_words', 'entries'):
                if r[k] < b[k]:
                    errs.append(f'overlay {name}.{k}: {r[k]} < baseline {b[k]}')
    return errs


def print_table(report):
    e = report['exe']
    print('== EXE ==')
    for k in ('text_words', 'code_words', 'covered_words', 'legacy_summed_words',
              'functions', 'dispatch_entries', 'entries_not_covered'):
        print(f'  {k:22s} {e[k]:>9,}')
    print(f"  excluded_words         {e['excluded_words']}")
    print(f"  covered_in_exclusions  {e['covered_in_exclusions']}")
    print(f"  pct                    {e['pct']:.4f}%")
    if 'overlays' in report:
        print('== Overlays (denominador provisorio: arquivo inteiro) ==')
        print(f"  {'arquivo':18s} {'lba':>7s} {'palavras':>8s} {'cobertas':>8s} {'pct':>8s} "
              f"{'match':>5s} {'crcX':>4s} {'entr':>5s}")
        for r in report['overlays']['files']:
            print(f"  {r['name']:18s} {r['lba']:7d} {r['size_words']:8d} "
                  f"{r['covered_words']:8d} {r['pct']:7.2f}% {r['variants_matched']:5d} "
                  f"{r['crc_mismatch']:4d} {r['entries']:5d}")
        t = report['overlays']['total']
        print(f"  TOTAL: {t['covered_words']}/{t['size_words']} palavras ({t['pct']:.4f}%), "
              f"variantes {t['variants_matched']}/{t['variants_total']}, "
              f"unmatched={t['unmatched']}, crc_mismatch={t['crc_mismatch']}, "
              f"entries={t['entries']}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--ranges', default=ROOT / 'generated-online/SLUS_005.48_full.ranges')
    ap.add_argument('--dispatch', default=ROOT / 'generated-online/SLUS_005.48_dispatch.c')
    ap.add_argument('--overlays',
                    default=ROOT / 'generated-online/retained-overlays/overlays_static.c')
    ap.add_argument('--exclusions', default=ROOT / 'coverage/exclusions.json')
    ap.add_argument('--baseline', default=ROOT / 'coverage/baseline.json')
    ap.add_argument('--game-toml', default=ROOT / 'game.toml')
    ap.add_argument('--cue', default=None, help='sobrescreve o cue de game.toml')
    ap.add_argument('--json', default=None)
    ap.add_argument('--skip-overlays', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--update-baseline', action='store_true')
    args = ap.parse_args(argv)
    try:
        if args.cue is None and not args.skip_overlays:
            args.cue = disc_cue_from_game_toml(need(args.game_toml, 'game.toml'))
        report = build_report(args)
        base = None
        if args.check:
            base = json.loads(need(args.baseline, 'baseline').read_text())
    except InputMissing as ex:
        print(f'ERRO: {ex}', file=sys.stderr)
        return 2
    except ExclusionError as ex:
        print(f'ERRO exclusoes invalidas: {ex}', file=sys.stderr)
        return 1 if args.check else 2
    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    if args.update_baseline:
        Path(args.baseline).parent.mkdir(parents=True, exist_ok=True)
        Path(args.baseline).write_text(
            json.dumps(baseline_from(report), indent=2, sort_keys=True) + '\n')
        print(f'baseline gravado: {args.baseline}')
    if args.check:
        errs = check(report, base, args.skip_overlays)
        if errs:
            print('REGRESSAO DE COBERTURA:')
            for e in errs:
                print('  - ' + e)
            return 1
        print('check: OK (sem regressao)')
        return 0
    if not (args.json or args.update_baseline):
        print_table(report)
    return 0


if __name__ == '__main__':
    sys.exit(main())
