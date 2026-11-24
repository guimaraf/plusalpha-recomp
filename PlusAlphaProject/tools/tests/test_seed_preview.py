import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import seed_preview as sp  # noqa: E402

ADDIU_SP = 0x27BDFFE8  # addiu sp,sp,-24


def reader(mem):
    return lambda a: mem.get(a)


class PureLogic(unittest.TestCase):
    def test_parse_seed_lines(self):
        got = sp.parse_seed_lines(["# so comentario", "0x8010A5FC  # funcao A", "", "0x80101008"])
        self.assertEqual(got, [(0x8010A5FC, "funcao A"), (0x80101008, "")])

    def test_boundary_prologue(self):
        mem = {0x80102000: 0, 0x80102004: ADDIU_SP}
        self.assertEqual(sp.callable_boundary(reader(mem), 0x80102000), "prologo")

    def test_boundary_jr_ra_delay(self):
        mem = {0x80102000: 0x1234, 0x80101FF8: sp.JR_RA_WORD, 0x80101FFC: 0}
        self.assertEqual(sp.callable_boundary(reader(mem), 0x80102000), "jr_ra+delay")

    def test_boundary_none(self):
        mem = {a: 0x00000021 for a in range(0x80101FF0, 0x80102010, 4)}
        self.assertIsNone(sp.callable_boundary(reader(mem), 0x80102000))

    def test_scan_words(self):
        mem = {
            0x80102000: 0x0040F809,  # jalr v0
            0x80102004: 0x01200008,  # jr t1
            0x80102008: 0x03E00008,  # jr ra
            0x8010200C: 0x3C018010,  # lui at,0x8010
            0x80102010: 0xAC221800,  # sw v0,0x1800(at) -> 0x80101800 (texto)
        }
        r = sp.scan_words(reader(mem), mem.keys())
        self.assertEqual(r["jalr"], [0x80102000])
        self.assertEqual(r["jr_nonra"], [0x80102004])
        self.assertEqual(r["smc"], [(0x80102010, 0x80101800)])

    def test_exclusion_hits(self):
        ex = [(0x80100000, 0x80100010, "dados")]
        self.assertEqual(sp.exclusion_hits({0x8010000C, 0x80100010}, ex), [0x8010000C])

    def test_budget(self):
        self.assertEqual(sp.budget_errors(1200, 10), [])
        self.assertEqual(len(sp.budget_errors(1201, 11)), 2)
        self.assertEqual(sp.budget_errors(5000, 50, allow_over=True), [])

    def test_diff_and_exit_code(self):
        base = {"words": {1, 2}, "funcs": {1}, "entries": {1}}
        cand = {"words": {2, 3}, "funcs": {1, 5}, "entries": {1, 7}}
        d = sp.diff_runs(base, cand)
        self.assertEqual((d["new_words"], d["lost_words"], d["new_funcs"]), ([3], [1], [5]))
        self.assertEqual(sp.run_exit_code(d, [], []), 1)  # perda
        ok = sp.diff_runs(base, {"words": {1, 2, 3}, "funcs": {1}, "entries": {1}})
        self.assertEqual(sp.run_exit_code(ok, [], []), 0)
        self.assertEqual(sp.run_exit_code(ok, [3], []), 1)  # quarentena
        self.assertEqual(sp.run_exit_code(ok, [], ["x"]), 1)  # orcamento


if __name__ == "__main__":
    unittest.main()
