"""Coverage gate must recognize executable rows, not references or comments."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    'coverage_gate', Path(__file__).resolve().parents[1] / 'check_main_coverage.py')
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class CoverageTest(unittest.TestCase):
    @staticmethod
    def row(addr):
        return f'    {{0x{addr:08X}u, 0x00000000u, 0u, 1u, func_{addr:08X}}},\n'

    def test_all_recovered_rows(self):
        self.assertEqual(set(), gate.missing_entries(''.join(
            self.row(a) for a in gate.RECOVERED)))

    def test_reports_single_missing_entry(self):
        missing = 0x801942C4
        self.assertEqual({missing}, gate.missing_entries(''.join(
            self.row(a) for a in gate.RECOVERED if a != missing)))

    def test_references_do_not_count(self):
        self.assertEqual(gate.RECOVERED, gate.missing_entries(''.join(
            f'extern void func_{a:08X}(CPUState* cpu); /* 0x{a:08X}u */\n'
            for a in gate.RECOVERED)))


if __name__ == '__main__':
    unittest.main()
