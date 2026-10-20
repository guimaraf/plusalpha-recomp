"""Copy the validated S1-309 static sources without regenerating guest code."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

EXPECTED = {"dlls": 2219, "translation_units": 2086, "manifest_entries": 4748,
            "missing_entries": 0}


def current_dispatcher(data: bytes, framework: Path, native_sources=()):
    """Keep every old content gate and native target, re-emit only host glue."""
    text = data.decode("utf-8-sig")
    ranges = {}
    for name, values in re.findall(r'static const uint32_t (psx_ov_static_ranges_\d+)\[\] = \{([^}]+)\};', text):
        words = [int(v, 16) for v in re.findall(r'0x([0-9A-Fa-f]+)u', values)]
        if len(words) % 2:
            raise ValueError("Invalid retained code ranges")
        ranges[name] = list(zip(words[::2], words[1::2]))
    variants = []
    for address, body in re.findall(r'case 0x([0-9A-Fa-f]+)u:(.*?)(?=\n\s*(?:case |default:))', text, re.S):
        for name, count, crc, symbol in re.findall(
                r'if \(psx_overlay_static_code_matches\((psx_ov_static_ranges_\d+), (\d+)u, 0x([0-9A-Fa-f]+)u\)\) \{\s*'
                r'psx_ov_static_hits\+\+;\s*(ov309_\w+)\(cpu\);', body):
            if name not in ranges or len(ranges[name]) != int(count):
                raise ValueError("Retained dispatcher range count mismatch")
            variants.append(dict(addr=int(address, 16), crc=int(crc, 16),
                                 symbol=symbol, ranges=ranges[name]))
    original_gates = len(re.findall(r'if \(psx_overlay_static_code_matches\(', text))
    if not variants or len(variants) != original_gates:
        raise ValueError("Incomplete retained dispatcher extraction")
    # Restrict recovery to the measured boot hotspot. Never infer legal entry
    # points from range membership: require the retained host's explicit switch
    # arm AND label, and inherit its complete, original resident-content gate.
    host = 'ov309_cdff7e18f2b1064e17cf0a1d_func_800E7CE0'
    resume = 0x800E7CFC
    owners = [v for v in variants if v['symbol'] == host and v['addr'] == 0x800E7CE0]
    wrappers = ''
    if owners:
        if len(owners) != 1 or owners[0]['crc'] != 0x15A7FF9F or owners[0]['ranges'] != [(0xE7CE0, 0x140)]:
            raise ValueError('Unexpected boot continuation owner gate')
        bodies = []
        for source in native_sources:
            match = re.search(r'\bvoid\s+' + re.escape(host) +
                              r'\s*\(CPUState\s*\*\s*cpu\)\s*\{(.*?)(?=\nvoid\s|\Z)',
                              source.decode('utf-8-sig'), re.S)
            if match:
                bodies.append(match.group(1))
        if (len(bodies) != 1 or
                not re.search(r'case\s+0x800E7CFCu:\s*goto\s+block_800E7CFC;', bodies[0]) or
                not re.search(r'^block_800E7CFC:', bodies[0], re.M)):
            raise ValueError('Retained boot host has no verified explicit resume arm')
        if any(v['addr'] == resume for v in variants):
            raise ValueError('Boot continuation collides with an existing entry')
        wrapper = 'ov309_retained_resume_800E7CFC'
        wrappers = (f'\nstatic void {wrapper}(CPUState *cpu) {{\n'
                    f'    cpu->pc = 0x{resume:08X}u;\n    {host}(cpu);\n}}\n')
        variants.append(dict(owners[0], addr=resume, symbol=wrapper))
    generator = framework / "tools" / "compile_overlays.py"
    spec = importlib.util.spec_from_file_location("retained_codegen", generator)
    codegen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(codegen)
    glue = codegen.generate_overlay_dispatch(variants)
    # The new runtime CRC gate also arms watches; retain the baseline's eager
    # installation for the real dispatcher without changing native bodies.
    if "static void ov309_install_watches" in text:
        glue = glue.replace('int psx_overlay_dispatch(CPUState *cpu, uint32_t addr) {',
                            'int psx_overlay_dispatch(CPUState *cpu, uint32_t addr) {\n    ov309_install_watches();', 1)
    prefix = text[:text.index("extern int psx_overlay_static_code_matches")]
    identity = [{**v, "ranges": list(v["ranges"])} for v in variants]
    return (prefix + wrappers + glue + "\n").encode(), len(variants), hashlib.sha256(
        json.dumps(identity, sort_keys=True).encode()).hexdigest()


def prepare(source: Path, output: Path, framework: Path = None):
    source, output = source.resolve(), output.resolve()
    if source == output or source in output.parents or output in source.parents:
        raise ValueError("Source and output must be separate directory trees")
    report_path = source / "coverage.json"
    report = json.loads(report_path.read_text(encoding="utf-8-sig"))
    for key, value in EXPECTED.items():
        if report.get(key) != value:
            raise ValueError(f"Invalid baseline coverage: {key}={report.get(key)}, expected {value}")
    if len(report["inventory"]) != EXPECTED["dlls"]:
        raise ValueError("Incomplete DLL inventory")
    if sum(item["manifest_entries"] for item in report["inventory"]) != EXPECTED["manifest_entries"]:
        raise ValueError("Incomplete dispatch inventory")
    expected_names = {"ov309_" + item["source_sha256"][:24] + ".c"
                      for item in report["inventory"]}
    units = sorted(source.glob("ov309_*.c"))
    if {p.name for p in units} != expected_names or len(units) != EXPECTED["translation_units"]:
        raise ValueError("Retained C source set does not match the validated inventory")
    declared = re.findall(r'"([^"\r\n]+\.c)"', (source / "sources.cmake").read_text())
    if {Path(p).name for p in declared} != expected_names | {"overlays_static.c"}:
        raise ValueError("Baseline sources.cmake disagrees with the inventory")
    dispatcher = source / "overlays_static.c"
    dispatch_bytes = dispatcher.read_bytes()
    required = set(re.findall(rb"extern void (ov309_\w+)\(CPUState \*cpu\);", dispatch_bytes))
    defined = set()
    payloads = []
    for index, path in enumerate(units):
        data = path.read_bytes()
        defined.update(re.findall(rb"\bvoid\s+(ov309_\w+)\s*\(CPUState\s*\*\s*cpu\)\s*\{", data))
        payloads.append((path.name, f"overlays_static_{index:04d}.c", data))
    if not required or required - defined:
        raise ValueError(f"Dispatcher has {len(required - defined)} missing native definitions")
    framework = framework or Path(__file__).resolve().parents[2] / "psxrecomp"
    new_dispatch, gate_count, gate_hash = current_dispatcher(
        dispatch_bytes, framework, [data for _, _, data in payloads])
    payloads.append((dispatcher.name, dispatcher.name, new_dispatch))
    # Validate the complete set before creating any output. Original sources
    # are only read; destination names match the current framework's glob.
    output.mkdir(parents=True, exist_ok=True)
    entries = []
    for original, name, data in payloads:
        target = output / name
        if not target.is_file() or target.read_bytes() != data:
            target.write_bytes(data)
        entries.append(dict(original=original, file=name,
                            sha256=hashlib.sha256(data).hexdigest()))
    receipt = dict(schema=1, **EXPECTED, native_symbols=len(required),
                   baseline_coverage_sha256=hashlib.sha256(report_path.read_bytes()).hexdigest(),
                   native_code_changes=False, dispatcher_regenerated=True,
                   resident_variant_gates=gate_count, resident_gate_sha256=gate_hash,
                   original_dispatcher_sha256=hashlib.sha256(dispatch_bytes).hexdigest(), files=entries)
    text = json.dumps(receipt, indent=2) + "\n"
    receipt_path = output / "retained_coverage.json"
    if not receipt_path.is_file() or receipt_path.read_text() != text:
        receipt_path.write_text(text, encoding="utf-8")
    print(f"Retained overlays: {len(units)} C units, {len(required)} declared native symbols, "
          f"{EXPECTED['dlls']} DLL promotions; native bytes unchanged, dispatcher updated")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--framework", type=Path)
    args = parser.parse_args()
    try:
        prepare(args.source, args.output, args.framework)
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f"Retained overlay preparation refused: {error}\n")


if __name__ == "__main__":
    main()
