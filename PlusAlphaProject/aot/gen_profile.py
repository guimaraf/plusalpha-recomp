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


def ptr(*idx):
    return [hex(4 * i) for i in idx]


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
    images = [
        dict(method='fixed_address_files', files=pl1, load_addr='0x80043000', allow_missing=True,
             entry_pointer_offsets=ptr(0, 1, 2, 3, 4)),
        dict(method='fixed_address_files', files=pl2, load_addr='0x8008CA00', allow_missing=True,
             entry_pointer_offsets=ptr(0, 1, 2, 3, 4)),
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
                    0x800E8BF8, 0x800E8C60]),
            extent('OVL3/QUES.PAC', 0x800E64D8, 0x2FA4),
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
