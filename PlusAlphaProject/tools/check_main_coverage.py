"""Refuse a runtime build that lost any retained S1-309 main function."""
import argparse
from pathlib import Path
import re

RECOVERED = frozenset(int(s, 16) for s in (
    "801504CC 80150808 80154978 80154B24 80154C7C 80154E14 80154FA8 801550C8 801551D4 80169384 8016AE18 8016B7A8 8016BAE4 8016C334 8016C748 8016CEB8 8016D0B8 8016D430 8016D898 8016E784 8018B360 8018C010 801910A4 801914C0 80191C84 80192D6C 80194274 801942C4 801A6654"
).split())


def missing_entries(dispatch: str):
    # Require a real dispatch row, not a mention in a comment/call site.
    entries = {int(s, 16) for s in re.findall(
        r'^\s*\{0x([0-9A-Fa-f]{8})u,\s*0x[0-9A-Fa-f]+u,\s*\d+u,\s*\d+u,\s*func_',
        dispatch, re.M)}
    return RECOVERED - entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dispatch', type=Path)
    args = parser.parse_args()
    missing = missing_entries(args.dispatch.read_text(encoding='utf-8-sig'))
    if missing:
        parser.exit(1, 'Main EXE coverage missing: ' + ', '.join(
            f'0x{x:08X}' for x in sorted(missing)) +
            '\nRun tools/build_online.ps1 -Generate to emit the restored seeds.\n')
    print('Retained main EXE coverage: all 29 recovered entries present')


if __name__ == '__main__':
    main()
