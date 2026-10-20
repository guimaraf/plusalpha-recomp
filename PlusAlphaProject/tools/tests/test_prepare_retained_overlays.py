"""Preparation preserves C bytes and refuses incomplete promotion sets."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "retained", Path(__file__).resolve().parents[1] / "prepare_retained_overlays.py")
retained = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(retained)


class PreparationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source, self.output = self.root / "baseline", self.root / "candidate"
        self.source.mkdir()
        self.digest = "a" * 64
        self.name = "ov309_" + self.digest[:24] + ".c"
        self.symbol = self.name[:-2] + "_func_80010000"
        self.data = ("#include \"psx_runtime.h\"\r\nvoid " + self.symbol +
                     "(CPUState *cpu) { cpu->pc = 0; }\r\n").encode()
        (self.source / self.name).write_bytes(self.data)
        (self.source / "overlays_static.c").write_text(
            "#include \"psx_runtime.h\"\nextern void " + self.symbol + "(CPUState *cpu);\n"
            "extern int psx_overlay_static_code_matches(const uint32_t *, uint32_t, uint32_t);\n"
            "static const uint32_t psx_ov_static_ranges_00000[] = { 0x00010000u, 0x10u };\n"
            "int psx_overlay_dispatch(CPUState *cpu, uint32_t addr) { switch (addr) {\n"
            "case 0x80010000u:\n"
            "if (psx_overlay_static_code_matches(psx_ov_static_ranges_00000, 1u, 0x12345678u)) {\n"
            "psx_ov_static_hits++;\n" + self.symbol + "(cpu); return 1; }\n"
            "default: return 0; } }\n")
        (self.source / "sources.cmake").write_text(
            'set(SOURCES "' + self.name + '" "overlays_static.c")\n')
        self.report = dict(dlls=1, translation_units=1, manifest_entries=1,
                           missing_entries=0, inventory=[dict(source_sha256=self.digest,
                                                             manifest_entries=1)])
        self.write_report()
        self.counts = patch.dict(retained.EXPECTED, dlls=1, translation_units=1,
                                 manifest_entries=1, missing_entries=0)
        self.counts.start()
        self.addCleanup(self.counts.stop)

    def write_report(self):
        (self.source / "coverage.json").write_text(json.dumps(self.report))

    def test_preserves_source_bytes_and_is_idempotent(self):
        receipt = retained.prepare(self.source, self.output)
        target = self.output / "overlays_static_0000.c"
        self.assertEqual(target.read_bytes(), self.data)
        self.assertEqual((self.source / self.name).read_bytes(), self.data)
        self.assertFalse(receipt["native_code_changes"])
        self.assertTrue(receipt["dispatcher_regenerated"])
        dispatcher = (self.output / "overlays_static.c").read_text()
        self.assertIn("psx_overlay_static_can_dispatch", dispatcher)
        self.assertIn("psx_overlay_static_entry_stats", dispatcher)
        before = target.stat().st_mtime_ns
        retained.prepare(self.source, self.output)
        self.assertEqual(target.stat().st_mtime_ns, before)

    def test_missing_source_does_not_create_output(self):
        (self.source / self.name).unlink()
        with self.assertRaises(ValueError):
            retained.prepare(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_incomplete_coverage_preserves_existing_output(self):
        self.output.mkdir()
        sentinel = self.output / "keep.c"
        sentinel.write_text("preserve")
        self.report["missing_entries"] = 1
        self.write_report()
        with self.assertRaises(ValueError):
            retained.prepare(self.source, self.output)
        self.assertEqual(sentinel.read_text(), "preserve")

    def test_missing_dispatch_definition_is_rejected(self):
        (self.source / self.name).write_text("/* no definition */")
        with self.assertRaises(ValueError):
            retained.prepare(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_output_inside_baseline_is_rejected(self):
        with self.assertRaises(ValueError):
            retained.prepare(self.source, self.source / "nested")

    def test_current_dispatcher_keeps_exact_gate_and_native_target(self):
        receipt = retained.prepare(self.source, self.output)
        text = (self.output / "overlays_static.c").read_text()
        self.assertEqual(receipt["resident_variant_gates"], 1)
        for value in (self.symbol, "0x80010000u", "0x00010000u", "0x10u", "0x12345678u"):
            self.assertIn(value, text)

    def test_unknown_dispatcher_format_is_rejected_before_writing(self):
        path = self.source / "overlays_static.c"
        path.write_text(path.read_text().replace("psx_ov_static_hits++;", "unknown_format();"))
        with self.assertRaises(ValueError):
            retained.prepare(self.source, self.output)
        self.assertFalse(self.output.exists())

    def boot_fixture(self):
        host = 'ov309_cdff7e18f2b1064e17cf0a1d_func_800E7CE0'
        path = self.source / 'overlays_static.c'
        path.write_text(path.read_text().replace(self.symbol, host)
                        .replace('80010000', '800E7CE0')
                        .replace('00010000', '000E7CE0')
                        .replace('0x10u', '0x140u')
                        .replace('12345678', '15A7FF9F'))
        body = (f'void {host}(CPUState *cpu) {{\n'
                'if (cpu->pc != 0u) { uint32_t pc = cpu->pc; cpu->pc = 0;\n'
                'switch (pc) { case 0x800E7CFCu: goto block_800E7CFC; } }\n'
                'block_800E7CFC:\nreturn;\n}\n').encode()
        (self.source / self.name).write_bytes(body)
        return body

    def test_boot_resume_inherits_owner_gate_without_changing_body(self):
        body = self.boot_fixture()
        receipt = retained.prepare(self.source, self.output)
        text = (self.output / 'overlays_static.c').read_text()
        self.assertEqual(receipt['resident_variant_gates'], 2)
        self.assertEqual((self.output / 'overlays_static_0000.c').read_bytes(), body)
        self.assertIn('cpu->pc = 0x800E7CFCu;', text)
        self.assertIn('0x800E7CFCu, 1u, 1u', text)
        self.assertEqual(text.count('0x000E7CE0u, 0x140u'), 2)
        self.assertEqual(text.count('0x15A7FF9Fu,'), 2)
        self.assertIn('ov309_retained_resume_800E7CFC },', text)

    def test_boot_resume_rejects_missing_switch_or_label_and_changed_gate(self):
        body = self.boot_fixture()
        for old, new in [(b'case 0x800E7CFCu:', b'case 0x800E7D04u:'),
                         (b'\nblock_800E7CFC:', b'\nwrong_label:')]:
            with self.subTest(old=old):
                (self.source / self.name).write_bytes(body.replace(old, new))
                with self.assertRaises(ValueError):
                    retained.prepare(self.source, self.output)
                self.assertFalse(self.output.exists())
        (self.source / self.name).write_bytes(body)
        path = self.source / 'overlays_static.c'
        path.write_text(path.read_text().replace('15A7FF9F', '15A7FF9E'))
        with self.assertRaises(ValueError):
            retained.prepare(self.source, self.output)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
