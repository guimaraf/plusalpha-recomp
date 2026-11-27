"""Gera aot/overlays.json (perfil "psxrecomp AOT methods v1") a partir do disco original.

Reprodutivel: o disco e lido somente para leitura (hashes sha256 dos extents de MOV e
QUES.PAC) e a unica escrita e o perfil, por padrao ao lado deste script. O perfil nao
declara `static_output`: a saida estatica fica por build, via `--out-dir` do pipeline.

Uso: python aot/gen_profile.py [--disc <cue>] [--out <overlays.json>]
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
FRAMEWORK = PROJECT.parent / 'psxrecomp'
BASE = 0x800D6400
PL_P1_BASE = 0x80043000
PL_P2_BASE = 0x8008CA00
PL_MIRROR = PL_P2_BASE - PL_P1_BASE  # 0x49A00

# Entradas interiores do PL0E (F3.0b): epilogos compartilhados alcancados por `j` a partir de
# funcoes vizinhas (0x800466C0 -> 0x800466E4 e 0x80046738 -> 0x80046768). Valem so para o
# proprio arquivo e so para o despacho (sem seeds/discovery). P2 e o espelho exato de P1.
PL_INTERIOR_P1 = {'OVL/PL0E_1.OVL': [0x800466E4, 0x80046768]}
PL_INTERIOR_P2 = {'OVL2/PL0E_2.OVL': [0x800900E4, 0x80090168]}


def ptr(*idx):
    return [hex(4 * i) for i in idx]


def validate_interior(disc, p1, p2):
    """P2 = P1 + 0x49A00, palavras iguais nos dois espelhos e conjuntos iguais em
    arquivos de corpo identico; erro (ValueError) em qualquer divergencia."""
    import struct
    if len(p1) != len(p2):
        raise ValueError('interior P1/P2: numero de arquivos diferente')
    for (n1, e1), (n2, e2) in zip(sorted(p1.items()), sorted(p2.items())):
        if n1.replace('OVL/', '').replace('_1', '') != n2.replace('OVL2/', '').replace('_2', ''):
            raise ValueError(f'interior P1/P2: arquivos nao correspondem: {n1} {n2}')
        if sorted(e + PL_MIRROR for e in e1) != sorted(e2):
            raise ValueError(f'interior P1/P2 inconsistente: {n1} {n2}')
        b1, b2 = disc.read(n1), disc.read(n2)
        for a1, a2 in zip(sorted(e1), sorted(e2)):
            # Palavras sem relocacao (sem j/jal) devem coincidir nos dois espelhos.
            w1 = [struct.unpack_from('<I', b1, a1 - PL_P1_BASE + 4 * i)[0] for i in range(4)]
            w2 = [struct.unpack_from('<I', b2, a2 - PL_P2_BASE + 4 * i)[0] for i in range(4)]
            if w1 != w2:
                raise ValueError(f'interior P1/P2: palavras divergentes em {a1:#x}/{a2:#x}')
    everything = {**p1, **p2}
    for name, entries in everything.items():
        body = disc.read(name)
        for other in everything.keys() | {n for n in disc.files if n.startswith(('OVL/PL', 'OVL2/PL'))}:
            if (other != name and disc.read(other) == body
                    and sorted(everything.get(other, [])) != sorted(entries)):
                raise ValueError(f'imagens identicas com entradas diferentes: {name} {other}')


def build_profile(disc):
    def extent(name, lo, size, entries=()):
        data = disc.read(name)[lo - BASE:lo - BASE + size]
        item = dict(file=name, base=hex(BASE), address=hex(lo), size=size, load_addr=hex(lo),
                    sha256=hashlib.sha256(data).hexdigest())
        if entries:
            item['entries'] = [hex(e) for e in entries]
        return item

    pl1 = [f'OVL/PL{k:02X}_1.OVL' for k in range(26)]
    pl2 = [f'OVL2/PL{k:02X}_2.OVL' for k in range(26)]
    validate_interior(disc, PL_INTERIOR_P1, PL_INTERIOR_P2)
    interior = lambda table: {k: [hex(e) for e in v] for k, v in table.items()}
    images = [
        dict(method='fixed_address_files', files=pl1, load_addr=hex(PL_P1_BASE), allow_missing=True,
             entry_pointer_offsets=ptr(0, 1, 2, 3, 4),
             interior_entries_by_file=interior(PL_INTERIOR_P1)),
        dict(method='fixed_address_files', files=pl2, load_addr='0x8008CA00', allow_missing=True,
             entry_pointer_offsets=ptr(0, 1, 2, 3, 4),
             interior_entries_by_file=interior(PL_INTERIOR_P2)),
        dict(method='fixed_address_files', files=['OVL3/BONUS.OVL'], load_addr='0x80018800',
             allow_missing=True, entry_pointer_offsets=ptr(0, 1)),
        dict(method='fixed_address_files', files=['OVL3/OPTS.OVL'], load_addr='0x80020800',
             allow_missing=True, entry_pointer_offsets=ptr(0, 1, 2, 3, 4)),
        dict(method='fixed_address_files', files=['OVL3/MC_I.OVL', 'OVL3/END.OVL'],
             load_addr='0x800D6400', allow_missing=True, entry_pointer_offsets=ptr(0)),
        dict(method='fixed_address_files', files=['OVL3/MC_M.OVL'], load_addr='0x800D6400',
             allow_missing=True, entry_pointer_offsets=ptr(0, 1, 2)),
        dict(method='fixed_address_extents', allow_missing=True, extents=[
            extent('OVL3/MOV.OVL', 0x800E76A0, 0x1664,
                   [0x800E76A0, 0x800E8A78, 0x800E8AE4, 0x800E8B98, 0x800E8B9C, 0x800E8BA8,
                    0x800E8BF8, 0x800E8C60, 0x800E8994, 0x800E8140]),
            # 0x3134 (ate 0x800E960C) cobre as jump tables de 0x800E954C, antes fora do extent.
            extent('OVL3/QUES.PAC', 0x800E64D8, 0x3134),
        ]),
    ]
    return {
        'schema': 'psxrecomp AOT methods v1',
        'game_id': 'SLUS-00548',
        'disc_hashes': {
            'sha256': 'e1050b3b8a3d26e04d4bbe196a7ded17cd0ff1e7de944d0fd7e161c48d60f9ca',
            'sha1': '4a25dab2bdc11372ab8496c807c28d49a476137d',
            'md5': '2a57b43b0b2f3f094ce203d32e910e2a'},
        'expected_records': 59,
        'images': images,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--disc', type=Path,
                        default=PROJECT / 'disc-a' / 'Street Fighter EX Plus Alpha (USA).cue')
    parser.add_argument('--out', type=Path, default=HERE / 'overlays.json')
    args = parser.parse_args()
    sys.path.insert(0, str(FRAMEWORK / 'tools'))
    import aot_overlay_pipeline as pipeline
    profile = build_profile(pipeline.Disc(args.disc))
    args.out.write_text(json.dumps(profile, indent=2) + '\n', encoding='utf-8')
    print('escrito', args.out)


if __name__ == '__main__':
    main()
