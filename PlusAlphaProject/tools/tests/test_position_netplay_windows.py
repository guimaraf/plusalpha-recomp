import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("position_netplay_windows",
    Path(__file__).resolve().parents[1] / "position_netplay_windows.py")
position = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(position)


class LayoutTests(unittest.TestCase):
    def test_preserves_size_and_meets_at_center(self):
        result = position.layout((0, 0, 1920, 1040), [(800, 600), (800, 600)])
        self.assertEqual(result, [(160, 220, 800, 600), (960, 220, 800, 600)])

    def test_different_heights_are_individually_centered(self):
        self.assertEqual(position.layout((0, 0, 1920, 1040), [(900, 700), (800, 600)]),
                         [(60, 170, 900, 700), (960, 220, 800, 600)])

    def test_negative_monitor_origin(self):
        self.assertEqual(position.layout((-1920, 40, 0, 1080), [(800, 600), (800, 600)]),
                         [(-1760, 260, 800, 600), (-960, 260, 800, 600)])

    def test_refuses_clipping_without_fit(self):
        with self.assertRaises(ValueError):
            position.layout((0, 0, 1920, 1040), [(1200, 900), (1200, 900)])

    def test_fit_uses_same_scale_and_fits_both_halves(self):
        self.assertEqual(position.layout((0, 0, 1920, 1040), [(1200, 900), (1200, 900)], True),
                         [(0, 160, 960, 720), (960, 160, 960, 720)])


if __name__ == "__main__":
    unittest.main()
