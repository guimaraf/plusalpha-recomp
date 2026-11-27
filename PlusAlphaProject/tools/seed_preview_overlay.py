#!/usr/bin/env python3
"""Pre-auditoria de entradas de overlay (docs/PLANO_100.md, Fase 3), sem gcc nem build.

Para cada PC informado de um arquivo de overlay do disco, relata: se ja e entrada no
despachante (overlays_static.c); se esta em range coberto; a borda (entrada existente, prologo,
apos `jr ra`+delay, lider de bloco, ou interior sem evidencia); o fecho do walk do compilador
(palavras, alvos de branch, delay slots e palavras invalidas); jal/jalr/jr nao-ra e jump tables
(resolvidas ou nao, alvos sem entrada); stores que caem no texto do overlay (SMC); o espelho
P1/P2 (+0x49A00) e os aliases (outros arquivos com os mesmos bytes); e jump tables que so se
resolvem fora do extent declarado.

Codigo de saida 1 em palavra invalida, delay slot invalido, borda ruim ou SMC (com --strict,
tambem em tabela fora do extent e jr nao resolvido). Saida deterministica (sem datas). Nunca
escreve no repositorio.

Uso: seed_preview_overlay.py --file OVL/PL0E_1.OVL --entries 0x800466e4 0x80046768
         [--dispatcher overlays_static.c] [--profile aot/overlays.json] [--extent 0xLO:0xSIZE]
         [--json saida.json]
       seed_preview_overlay.py --check-profile [aot/overlays.json] [--dispatcher overlays_static.c]
         Guarda das entradas declaradas (interior_entries_by_file e entries dos extents): cada uma
         precisa existir no despachante com ao menos uma variante cujo CRC case com os bytes do
         arquivo do disco. Codigo 1 se faltar alguma.
"""
import argparse
import json
import struct
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TOOLS_DIR.parent
REPO_ROOT = PROJECT_ROOT.parent
sys.path.insert(0, str(TOOLS_DIR))
sys.path.insert(0, str(REPO_ROOT / 'psxrecomp' / 'tools'))
import coverage_metric as cm  # noqa: E402
import compile_overlays as co  # noqa: E402

KSEG0 = 0x80000000
PL_MIRROR = 0x8CA00 - 0x43000  # 0x49A00
STORE_OPS = (0x28, 0x29, 0x2B, 0x2A, 0x2E, 0x3A)  # sb sh sw swl swr swc2
JR_RA_WORD = 0x03E00008
CF_KINDS = ('branch', 'branch_never', 'branch_never_likely', 'j', 'jal', 'jalr', 'jr', 'jr_ra')
ERROR_KEYS = ('palavra_invalida', 'delay_invalido', 'borda_ruim', 'smc')


class Image:
    """Arquivo de overlay em endereco virtual + a regiao de codigo (extent) analisavel."""

    def __init__(self, name, data, base, extent=None):
        self.name, self.data, self.base = name, data, base
        lo, size = extent if extent else (base, len(data))
        self.lo, self.hi = lo, lo + size
        self.view = data[lo - base:lo - base + size]

    def word(self, addr, whole=False):
        data, base = (self.data, self.base) if whole else (self.view, self.lo)
        return co._word_at(data, base, addr)


def parse_addr(text):
    return int(str(text), 16) if str(text).lower().startswith('0x') else int(text, 0)


# ---------------------------------------------------------------- logica pura
def boundary_kind(img, addr):
    """'prologo' (addiu sp,sp,-N nas 4 primeiras palavras), 'jr_ra+delay'
    (com ou sem palavras invalidas de padding no meio) ou None."""
    for i in range(4):
        w = img.word(addr + 4 * i)
        if w is None or co._classify_cf(addr + 4 * i, w)[0] != 'normal':
            break  # o prologo de OUTRA funcao depois de um jr/branch nao conta
        if (w >> 26) == 9 and ((w >> 21) & 31) == 29 and ((w >> 16) & 31) == 29 and (w & 0x8000):
            return 'prologo'
    if img.word(addr - 8) == JR_RA_WORD:
        return 'jr_ra+delay'
    # Palavras de dado/padding invalidas (ex.: 0x00FFFFFF) entre o delay slot e a entrada.
    q = addr - 4
    while (q > img.lo and addr - q <= 32 and img.word(q) is not None
           and not co._is_valid_mips_word(img.word(q))):
        q -= 4
    if q != addr - 4 and img.word(q - 4) == JR_RA_WORD:
        return 'jr_ra+delay+padding'
    return None


def static_references(img):
    """{alvo: [(pc, tipo)]} de branch/j/jal diretos na regiao."""
    refs = {}
    for pc in range(img.lo, img.hi, 4):
        w = img.word(pc)
        kind, target = co._classify_cf(pc, w)
        if kind in ('branch', 'j', 'jal') and img.lo <= target < img.hi and target % 4 == 0:
            refs.setdefault(target, []).append((pc, kind))
    return refs


def host_candidates(img, jr_pc, entries, limit=16):
    """Hospedeiros possiveis de um jr: entradas anteriores (mais proximas primeiro) e prologos.
    A entrada mais proxima pode ser de uma funcao posterior ao host real do switch."""
    found = sorted((e for e in entries if img.lo <= e <= jr_pc), reverse=True)[:limit]
    pc = jr_pc
    while pc >= img.lo and len(found) < 2 * limit:
        w = img.word(pc)
        if (pc not in found and w is not None and (w >> 26) == 9 and ((w >> 21) & 31) == 29
                and ((w >> 16) & 31) == 29 and (w & 0x8000)):
            found.append(pc)
        pc -= 4
    return found or [img.lo]


def table_references(img, entries):
    """Jump tables resolvidas no extent: ({alvo: [(jr_pc, tabela)]}, [jr_pc nao resolvidos],
    {jr_pc: alvos resolvidos so com o arquivo inteiro})."""
    refs, unresolved, outside = {}, [], {}
    for pc in range(img.lo, img.hi, 4):
        w = img.word(pc)
        if w is None or (w >> 26) != 0 or (w & 0x3F) != 8 or ((w >> 21) & 31) in (0, 31):
            continue
        rs = (w >> 21) & 31
        hosts = host_candidates(img, pc, entries)
        proofs, found = [], set()
        for host in hosts:
            proofs = []
            found = co._find_jump_table_targets(img.view, img.lo, len(img.view), host, img.hi, pc,
                                                rs, (img.lo, img.hi), proofs)
            if found:
                break
        if found:
            for proof in proofs:
                for t in proof['targets']:
                    refs.setdefault(t, []).append((pc, proof['table_base']))
            continue
        unresolved.append(pc)
        for host in hosts:
            proofs = []
            whole = co._find_jump_table_targets(img.data, img.base, len(img.data), host, img.hi,
                                                pc, rs, None, proofs)
            if whole:
                outside[pc] = sorted(whole)
                break
    return refs, unresolved, outside


def store_targets(img, pcs):
    """Stores com destino (lui+offset) dentro do texto do overlay inteiro -> [(pc, destino)]."""
    out = []
    lo, hi = img.base, img.base + len(img.data)
    for a in sorted(pcs):
        v = img.word(a, whole=True)
        if v is None or (v >> 26) not in STORE_OPS:
            continue
        rs = (v >> 21) & 31
        for k in range(1, 13):
            u = img.word(a - 4 * k, whole=True)
            if u is None:
                break
            if (u >> 26) == 15 and ((u >> 16) & 31) == rs:
                off = v & 0xFFFF
                off -= 0x10000 if off & 0x8000 else 0
                t = (((u & 0xFFFF) << 16) + off) & 0xFFFFFFFF
                if lo <= t < hi:
                    out.append((a, t))
                break
            if (u >> 26) in (8, 9, 13, 0x23, 0x21, 0x25, 0x24) and ((u >> 16) & 31) == rs:
                break
    return out


def analyze_entry(img, addr, entries, covered, tables):
    """Analise de um PC. entries: entradas do despachante neste arquivo (virtuais);
    covered: palavras (virtuais) cobertas; tables: resultado de table_references + refs."""
    refs, table_refs, jr_unresolved, jr_outside = tables
    r = {'pc': f'0x{addr:08X}', 'erros': [], 'avisos': []}
    r['ja_e_entrada'] = addr in entries
    r['em_range_coberto'] = addr in covered
    if addr % 4 or not (img.lo <= addr < img.hi):
        r['erros'].append('borda_ruim')
        r['borda'] = 'fora_da_regiao'
        r['detalhe_borda'] = f'fora de 0x{img.lo:08X}..0x{img.hi:08X} ou desalinhado'
        return r
    # ---- borda
    bnd = boundary_kind(img, addr)
    evidence = [f'{kind}@0x{pc:08X}' for pc, kind in refs.get(addr, [])]
    evidence += [f'jump_table@0x{pc:08X}(tabela 0x{base:08X})' for pc, base in table_refs.get(addr, [])]
    if r['ja_e_entrada']:
        r['borda'] = 'entrada_existente'
    elif bnd:
        r['borda'] = bnd
    elif evidence:
        r['borda'] = 'lider_de_bloco'
    else:
        r['borda'] = 'interior'
        r['erros'].append('borda_ruim')
    r['referencias'] = sorted(evidence)
    beyond = sorted(f'jr@0x{pc:08X}' for pc, targets in jr_outside.items() if addr in targets)
    r['referencias_tabela_fora_do_extent'] = beyond
    if beyond:
        r['avisos'].append('tabela_fora_do_extent')
    # ---- fecho
    walk = co._walk_overlay_function(img.view, img.lo, len(img.view), addr, img.hi,
                                     [(img.lo, img.hi)])
    visited = sorted(walk['visited'])
    r['palavras'] = len(visited)
    r['palavras_enderecos'] = [f'0x{a:08X}' for a in visited]
    invalid = [a for a in visited if not co._is_valid_mips_word(img.word(a))]
    if invalid:
        r['erros'].append('palavra_invalida')
    r['palavras_invalidas'] = [f'0x{a:08X}' for a in invalid]
    bad_delay = []
    jals, jalrs, jr_nonra, jr_const = [], [], [], []
    for pc in visited:
        w = img.word(pc)
        kind, target = co._classify_cf(pc, w)
        if kind == 'normal':
            continue
        if kind in ('branch', 'branch_never', 'j', 'jal', 'jalr', 'jr', 'jr_ra'):
            d = img.word(pc + 4)
            dk = co._classify_cf(pc + 4, d)[0] if d is not None else None
            if d is None or not co._is_valid_mips_word(d) or dk != 'normal':
                bad_delay.append(pc)
        if kind == 'jal':
            jals.append(target)
        elif kind == 'jalr':
            const = co._resolve_constant_transfer(img.view, img.lo, addr, pc, (w >> 21) & 31)
            jalrs.append((pc, const))
        elif kind == 'jr':
            const = co._resolve_constant_transfer(img.view, img.lo, addr, pc, (w >> 21) & 31)
            proofs = [p for p in walk['jump_table_proofs'] if p['jr_pc'] == pc]
            jr_nonra.append((pc, const, proofs))
    if bad_delay:
        r['erros'].append('delay_invalido')
    r['delay_slots_invalidos'] = [f'0x{a:08X}' for a in bad_delay]
    r['jal'] = sorted({f'0x{t:08X}' for t in jals})
    r['jalr'] = [{'pc': f'0x{pc:08X}', 'alvo_constante': f'0x{c:08X}' if c else None}
                 for pc, c in jalrs]
    jr_rows, tables_out = [], []
    for pc, const, proofs in jr_nonra:
        row = {'pc': f'0x{pc:08X}'}
        if const:
            row['resolucao'] = f'constante 0x{const:08X}'
        elif proofs:
            row['resolucao'] = 'jump_table'
            for p in proofs:
                tables_out.append({'jr': f'0x{pc:08X}', 'tabela': f'0x{p["table_base"]:08X}',
                                   'entradas': p['count'],
                                   'alvos_sem_entrada': sorted(
                                       f'0x{t:08X}' for t in p['targets']
                                       if t not in entries and t not in walk['visited'])})
        else:
            row['resolucao'] = 'nao_resolvido'
            if pc in jr_outside:
                row['tabela_fora_do_extent'] = True
                r['avisos'].append('tabela_fora_do_extent')
            r['avisos'].append('jr_nao_resolvido')
        jr_rows.append(row)
    r['jr_nao_ra'] = jr_rows
    r['jump_tables'] = tables_out
    outside_targets = sorted(
        (set(walk['direct_jals']) | set(walk['static_indirect_targets']) |
         set(walk['forward_branch_targets'])) - set(entries) - set(visited) - {addr})
    r['alvos_fora_do_fecho_sem_entrada'] = [f'0x{t:08X}' for t in outside_targets]
    # ---- SMC
    smc = store_targets(img, visited)
    if smc:
        r['erros'].append('smc')
    r['stores_no_texto'] = [f'0x{a:08X}->0x{t:08X}' for a, t in smc]
    r['erros'] = sorted(set(r['erros']))
    r['avisos'] = sorted(set(r['avisos']))
    return r


# ---------------------------------------------------------------- disco / despachante
def virtual_extent(extents, name):
    ext = extents.get(name.upper())
    return (KSEG0 | ext[0], ext[1]) if ext else None


def dispatcher_context(variants, data, base):
    """(entradas virtuais, palavras cobertas virtuais) das variantes que casam com o arquivo."""
    hit, _miss = cm.match_variants(variants, data, base)
    entries = {KSEG0 | v['entry'] for v in hit if v['entry'] is not None}
    covered = set()
    for v in hit:
        for lo, ln in v['ranges']:
            covered.update(range(KSEG0 | lo, (KSEG0 | lo) + ln, 4))
    return entries, covered


def mirror_report(files, name, addr, words, variants):
    """Espelho P1/P2 (+/-0x49A00): entrada correspondente e igualdade das palavras do fecho."""
    upper = name.upper()
    if upper.startswith('OVL/PL') and upper.endswith('_1.OVL'):
        other, delta = 'OVL2/' + upper[4:-6] + '_2.OVL', PL_MIRROR
    elif upper.startswith('OVL2/PL') and upper.endswith('_2.OVL'):
        other, delta = 'OVL/' + upper[5:-6] + '_1.OVL', -PL_MIRROR
    else:
        return None
    if other not in files:
        return {'arquivo': other, 'presente': False}
    (mine, mbase), (theirs, obase) = files[upper], files[other]
    diff = []
    for a in words:
        w1 = co._word_at(mine, mbase | KSEG0, a)
        w2 = co._word_at(theirs, obase | KSEG0, a + delta)
        # j/jal carregam alvos absolutos relocados; so o opcode precisa coincidir neles.
        if (w1 is None or w2 is None
                or ((w1 >> 26) in (2, 3) and (w2 >> 26) != (w1 >> 26))
                or ((w1 >> 26) not in (2, 3) and w1 != w2)):
            diff.append(f'0x{a:08X}')
    twin = addr + delta
    return {'arquivo': other, 'presente': True, 'espelho_pc': f'0x{twin:08X}',
            'palavras_divergentes': diff,
            'ja_e_entrada_no_espelho': twin in dispatcher_context(variants, theirs, obase)[0]}


def alias_report(files, name, base, words):
    """Outros arquivos na mesma base com as mesmas palavras do fecho."""
    mine = files[name.upper()][0]
    out = []
    for other, (data, obase) in sorted(files.items()):
        if other == name.upper() or obase != base:
            continue
        same = all(co._word_at(data, obase | KSEG0, a) == co._word_at(mine, base | KSEG0, a)
                   and co._word_at(data, obase | KSEG0, a) is not None for a in words)
        if same:
            out.append(other)
    return out


def load_files(cue):
    return {name.upper(): (data, base)
            for name, _lba, data, base in cm.load_overlay_files(cue)}


def preview(name, addrs, files, variants, extents, override_extent=None):
    key = name.upper()
    if key not in files:
        raise cm.InputMissing(f'arquivo de overlay ausente no disco: {name}')
    data, base = files[key]
    extent = override_extent or virtual_extent(extents, key)
    img = Image(key, data, KSEG0 | base, extent)
    entries, covered = dispatcher_context(variants, data, base)
    matched = len(cm.match_variants(variants, data, base)[0])
    refs = static_references(img)
    table_refs, unresolved, outside = table_references(img, entries)
    tables = (refs, table_refs, unresolved, outside)
    rows = []
    vfiles = files
    for addr in addrs:
        row = analyze_entry(img, addr, entries, covered, tables)
        if row.get('palavras_enderecos'):
            words = [parse_addr(a) for a in row['palavras_enderecos']]
            m = mirror_report(vfiles, key, addr, words, variants)
            if m:
                row['espelho'] = m
                if m.get('palavras_divergentes'):
                    row['avisos'] = sorted(set(row['avisos'] + ['espelho_divergente']))
            row['aliases'] = alias_report(vfiles, key, base, words)
        rows.append(row)
    return {'arquivo': key, 'regiao': f'0x{img.lo:08X}..0x{img.hi:08X}',
            'extent_declarado': extent is not None,
            'entradas_no_despachante': len(entries), 'variantes_casadas': matched,
            'entradas': rows}


def exit_code(report, strict=False):
    if strict and report.get('variantes_casadas') == 0:
        return 1
    bad = ERROR_KEYS + (('tabela_fora_do_extent', 'jr_nao_resolvido') if strict else ())
    for row in report['entradas']:
        if any(k in row['erros'] or k in row['avisos'] for k in bad):
            return 1
    return 0


def print_report(report, dispatcher_label):
    print(f"arquivo: {report['arquivo']}  regiao: {report['regiao']}"
          f"{' (extent)' if report['extent_declarado'] else ' (arquivo inteiro)'}")
    print(f'despachante: {dispatcher_label}  entradas do arquivo: {report["entradas_no_despachante"]}')
    if report.get('variantes_casadas') == 0:
        print('AVISO: nenhuma variante do despachante casa com os bytes deste arquivo '
              '(despachante de outra build/disco?); ja_e_entrada e cobertura nao sao confiaveis '
              '(falha com --strict)')
    for r in report['entradas']:
        status = 'ERRO ' + ','.join(r['erros']) if r['erros'] else \
            ('AVISO ' + ','.join(r['avisos']) if r['avisos'] else 'OK')
        print(f"\n{r['pc']}  [{status}]")
        print(f"  ja_e_entrada: {'sim' if r['ja_e_entrada'] else 'nao'}   "
              f"em_range_coberto: {'sim' if r['em_range_coberto'] else 'nao'}   "
              f"borda: {r['borda']}")
        if r.get('detalhe_borda'):
            print(f"  {r['detalhe_borda']}")
        if r['referencias']:
            print('  referencias: ' + ', '.join(r['referencias']))
        if r.get('referencias_tabela_fora_do_extent'):
            print('  jump table so resolvida com o arquivo inteiro (tabela alem do extent) via '
                  + ', '.join(r['referencias_tabela_fora_do_extent']))
        if 'palavras' not in r:
            continue
        print(f"  fecho: {r['palavras']} palavras "
              f"{r['palavras_enderecos'][0]}..{r['palavras_enderecos'][-1]}"
              if r['palavras'] else '  fecho: vazio')
        if r['palavras_invalidas']:
            print('  palavras invalidas: ' + ' '.join(r['palavras_invalidas']))
        if r['delay_slots_invalidos']:
            print('  delay slots invalidos (pc do branch): ' + ' '.join(r['delay_slots_invalidos']))
        print(f"  jal: {len(r['jal'])}  jalr: {len(r['jalr'])} "
              f"(nao resolvidos: {sum(1 for j in r['jalr'] if not j['alvo_constante'])})  "
              f"jr nao-ra: {len(r['jr_nao_ra'])}")
        for j in r['jr_nao_ra']:
            extra = '  [tabela alem do extent]' if j.get('tabela_fora_do_extent') else ''
            print(f"    jr@{j['pc']}: {j['resolucao']}{extra}")
        for t in r['jump_tables']:
            sem = ', '.join(t['alvos_sem_entrada']) or 'nenhum'
            print(f"    tabela {t['tabela']} ({t['entradas']} entradas) via jr@{t['jr']}; "
                  f'alvos sem entrada: {sem}')
        if r['alvos_fora_do_fecho_sem_entrada']:
            print('  alvos fora do fecho sem entrada: ' + ' '.join(r['alvos_fora_do_fecho_sem_entrada']))
        print('  stores no texto (SMC): ' + (' '.join(r['stores_no_texto']) or 'nenhum'))
        m = r.get('espelho')
        if m:
            if m.get('presente'):
                print(f"  espelho: {m['arquivo']} em {m['espelho_pc']}; "
                      f"entrada no espelho: {'sim' if m['ja_e_entrada_no_espelho'] else 'nao'}; "
                      f"palavras divergentes: {len(m['palavras_divergentes'])}")
            else:
                print(f"  espelho: {m['arquivo']} ausente")
        if r.get('aliases'):
            print('  aliases (mesmos bytes do fecho): ' + ' '.join(r['aliases']))


def declared_entries(profile_path):
    """[(arquivo MAIUSCULO, [entradas virtuais])] de interior_entries_by_file e dos extents."""
    profile = json.loads(Path(profile_path).read_text(encoding='utf-8-sig'))
    out = []
    for image in profile.get('images', []):
        for name, entries in sorted(image.get('interior_entries_by_file', {}).items()):
            out.append((name.upper(), [parse_addr(e) for e in entries]))
        for ext in image.get('extents', []):
            if ext.get('entries'):
                out.append((ext['file'].upper(), [parse_addr(e) for e in ext['entries']]))
    return out


def check_profile(declared, files, variants):
    """Linhas (entrada, arquivo, ok, motivo): a entrada declarada precisa existir no despachante
    em ao menos uma variante cujo CRC case com os bytes do arquivo do disco."""
    rows = []
    for name, entries in declared:
        if name not in files:
            rows.extend((e, name, False, 'arquivo ausente no disco') for e in entries)
            continue
        data, base = files[name]
        hit = cm.match_variants(variants, data, base)[0]
        have = {KSEG0 | v['entry'] for v in hit if v['entry'] is not None}
        for e in entries:
            if e in have:
                rows.append((e, name, True, ''))
            elif not hit:
                rows.append((e, name, False, 'nenhuma variante casa com o arquivo'))
            else:
                rows.append((e, name, False, 'entrada sem variante casada com o arquivo'))
    return rows


def print_check_profile(rows, dispatcher_label):
    print(f'despachante: {dispatcher_label}')
    print(f'{"entrada":<12} {"arquivo":<18} ok')
    for entry, name, ok, why in rows:
        print(f'0x{entry:08X}   {name:<18} {"sim" if ok else "NAO  " + why}')
    bad = sum(1 for r in rows if not r[2])
    print(f'\n{len(rows)} entradas, {bad} ausentes: '
          f"{'REPROVADO (codigo 1)' if bad else 'sem erros'}")
    return 1 if bad else 0


def _label(dispatcher):
    try:
        return Path(dispatcher).resolve().relative_to(PROJECT_ROOT).as_posix()
    except ValueError:
        return str(dispatcher)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument('--file', help='arquivo no disco, ex.: OVL/PL0E_1.OVL')
    ap.add_argument('--entries', nargs='+', help='PCs virtuais em hex')
    ap.add_argument('--check-profile', nargs='?', const=str(PROJECT_ROOT / 'aot/overlays.json'),
                    default=None, metavar='PERFIL',
                    help='confere as entradas declaradas do perfil contra o despachante')
    ap.add_argument('--dispatcher', default=None,
                    help='overlays_static.c; padrao: build-auto-* mais recente')
    ap.add_argument('--profile', default=PROJECT_ROOT / 'aot/overlays.json',
                    help='perfil AOT com os extents de MOV/QUES.PAC')
    ap.add_argument('--extent', default=None, help='sobrescreve o extent: 0xLO:0xSIZE (virtual)')
    ap.add_argument('--game-toml', default=PROJECT_ROOT / 'game.toml')
    ap.add_argument('--cue', default=None)
    ap.add_argument('--json', default=None, help='grava o relatorio JSON (fora do repositorio)')
    ap.add_argument('--strict', action='store_true',
                    help='tambem falha em tabela fora do extent e jr nao resolvido')
    args = ap.parse_args(argv)
    if not args.check_profile and not (args.file and args.entries):
        ap.error('--file e --entries sao obrigatorios (exceto com --check-profile)')
    try:
        cue = Path(args.cue) if args.cue else cm.disc_cue_from_game_toml(
            cm.need(args.game_toml, 'game.toml'))
        dispatcher = Path(args.dispatcher) if args.dispatcher else cm.latest_build_overlays()
        if dispatcher is None:
            raise cm.InputMissing('nenhum overlays_static.c de build-auto-* encontrado')
        variants = cm.parse_overlays_static(cm.need(dispatcher, 'overlays_static.c')
                                            .read_text(encoding='utf-8', errors='replace'))
        if args.check_profile:
            declared = declared_entries(cm.need(Path(args.check_profile), 'perfil AOT'))
            rows = check_profile(declared, load_files(cue), variants)
            return print_check_profile(rows, _label(dispatcher))
        extents = cm.load_extents(args.profile)
        override = None
        if args.extent:
            lo, size = args.extent.split(':')
            override = (parse_addr(lo), parse_addr(size))
        report = preview(args.file, [parse_addr(a) for a in args.entries], load_files(cue),
                         variants, extents, override)
    except cm.InputMissing as ex:
        print(f'ERRO: {ex}', file=sys.stderr)
        return 2
    print_report(report, _label(dispatcher))
    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    code = exit_code(report, args.strict)
    print(f"\nresultado: {'REPROVADO (codigo 1)' if code else 'sem erros'}")
    return code


if __name__ == '__main__':
    sys.exit(main())
