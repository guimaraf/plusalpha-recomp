"""Convert retained overlay C into static translation units; never compile.

All manifest entries must have a matching retained definition. This checks
coverage, not behavioral equivalence: gameplay remains a local validation gate.
"""
import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path


def read_source(path):
    data = path.read_bytes()
    try:
        return data.decode('utf-8-sig')
    except UnicodeDecodeError:
        return data.decode('cp1252')


def manifest(path):
    entries = []
    current = None
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        fields = line.split()
        if not fields or fields[0].startswith('#'):
            continue
        if fields[0] == 'F' and len(fields) == 3:
            current = dict(addr=int(fields[1], 16), crc=int(fields[2], 16), ranges=[])
            entries.append(current)
        elif fields[0] == 'R' and len(fields) == 3 and current is not None:
            lo, length = int(fields[1], 16) & 0x1fffffff, int(fields[2], 16)
            if not length or lo + length > 2 * 1024 * 1024:
                raise ValueError(f'Invalid code range: {path}: {line}')
            current['ranges'].append((lo, length))
        else:
            raise ValueError(f'Unsupported manifest: {path}: {line}')
    if not entries or any(not entry['ranges'] for entry in entries):
        raise ValueError(f'Missing exact CRC/ranges: {path}')
    return entries


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--cache', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--framework', required=True, type=Path)
    args = ap.parse_args()
    spec = importlib.util.spec_from_file_location(
        'overlay_codegen', args.framework / 'tools' / 'compile_overlays.py')
    codegen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(codegen)
    # Only use the validated 309 namespace; never mix TCC/other codegen vaults.
    vault = args.cache / 'SLUS-00548' / 'gcc' / 'win-x64' / 'cg5_562d908f'
    dlls = sorted(vault.glob('*.dll'))
    if not dlls:
        raise ValueError(f'No stable DLLs found: {vault}')
    units, variants, audit = {}, [], []
    for dll in dlls:
        _, crc = dll.stem.split('_')
        choices = [dll.with_name(dll.stem + '_patched.c'),
                   dll.with_name(crc + '_fragment_patched.c'),
                   dll.with_name(crc + '_patched.c')]
        source = next((path for path in choices if path.is_file()), None)
        if source is None:
            raise ValueError(f'Missing retained C for {dll.name}')
        text = read_source(source).replace('\r\n', '\n')
        definitions = {int(addr, 16) for addr in re.findall(
            r'^void func_([0-9A-Fa-f]{8})\(CPUState\* cpu\)\s*\n\{', text, re.M)}
        entries = manifest(dll.with_suffix('.ranges'))
        missing = [entry['addr'] for entry in entries if entry['addr'] not in definitions]
        if missing:
            raise ValueError(f'{dll.name}: definitions missing: {missing}')
        digest = hashlib.sha256(text.encode('utf-8')).hexdigest()
        namespace = 'ov309_' + digest[:24]
        if digest not in units:
            # Remove the entire DLL callback shim, then use the existing static
            # namespace logic. Internal calls/CPS blocks remain as retained.
            text, count = re.subn(
                r'/\* ---- Overlay dispatch shim.*?/\* -{20,} \*/', '', text,
                count=1, flags=re.S)
            if count != 1:
                raise ValueError(f'Unknown DLL shim format: {source}')
            text = re.sub(r'^#include "overlay_api.h"\s*', '', text, flags=re.M)
            text = re.sub(
                r'#ifdef _WIN32\s+__declspec\(dllexport\)\s+#else\s+'
                r'__attribute__\(\(visibility\("default"\)\)\)\s+#endif\s*', '', text)
            if 'OverlayCallbacks' in text or '__declspec(dllexport)' in text:
                raise ValueError(f'DLL machinery remains: {source}')
            text, symbols = codegen.namespace_generated_static(text, namespace, definitions)
            units[digest] = dict(name=namespace + '.c', text=text, symbols=symbols)
        symbols = units[digest]['symbols']
        for entry in entries:
            variants.append(dict(entry, symbol=symbols[entry['addr']]))
        audit.append(dict(dll=dll.name, source=str(source.resolve()),
                          source_sha256=digest, manifest_entries=len(entries)))
    args.output.mkdir(parents=True, exist_ok=True)
    sources = []
    for unit in units.values():
        path = args.output / unit['name']
        path.write_text(unit['text'], encoding='utf-8', newline='\n')
        sources.append(path.resolve().as_posix())
    prototypes = sorted({variant['symbol'] for variant in variants})
    dispatcher = '#include "psx_runtime.h"\n'
    dispatcher += '\n'.join(f'extern void {name}(CPUState *cpu);' for name in prototypes)
    # The DLL path installs page watches during candidate registration. Static
    # dispatch has no such registration: install the same watches before its
    # first CRC check so later guest writes invalidate the generation fast path.
    intervals = sorted({(lo, lo + length) for item in variants for lo, length in item['ranges']})
    merged = []
    for lo, hi in intervals:
        if merged and lo <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], hi))
        else:
            merged.append((lo, hi))
    dispatcher += '\nextern void overlay_watch_set_range(uint32_t, uint32_t);\n'
    dispatcher += 'static void ov309_install_watches(void) {\n    static int ready;\n'
    dispatcher += '    if (ready) return;\n'
    dispatcher += ''.join(f'    overlay_watch_set_range(0x{lo:X}u, 0x{hi-lo:X}u);\n'
                          for lo, hi in merged)
    dispatcher += '    ready = 1;\n}\n'
    dispatch_body = codegen.generate_overlay_dispatch(variants)
    if dispatch_body.count('int psx_overlay_dispatch(CPUState *cpu, uint32_t addr) {') != 1:
        raise ValueError('Unknown static dispatcher entry format')
    dispatch_body = dispatch_body.replace(
        'int psx_overlay_dispatch(CPUState *cpu, uint32_t addr) {',
        'int psx_overlay_dispatch(CPUState *cpu, uint32_t addr) {\n    ov309_install_watches();')
    dispatcher += dispatch_body
    dispatch_path = args.output / 'overlays_static.c'
    dispatch_path.write_text(dispatcher, encoding='utf-8', newline='\n')
    cmake = f'set(PSX_STATIC_OVERLAY_DISPATCH "{dispatch_path.resolve().as_posix()}")\n'
    cmake += 'set(PSX_STATIC_OVERLAY_SOURCES\n'
    cmake += ''.join(f'    "{path}"\n' for path in sources) + ')\n'
    (args.output / 'sources.cmake').write_text(cmake, encoding='utf-8', newline='\n')
    report = dict(dlls=len(dlls), translation_units=len(units),
                  manifest_entries=len(variants), missing_entries=0,
                  mode='static direct runtime calls; exact manifest CRC gates', inventory=audit)
    (args.output / 'coverage.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f'Static preparation: {len(dlls)} DLLs, {len(units)} C units, '
          f'{len(variants)} manifest entries, zero missing definitions.')


if __name__ == '__main__':
    main()
