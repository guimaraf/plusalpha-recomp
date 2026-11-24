"""auto_session: logica pura (monitor, botoes, rota, linha de comando)."""
import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    'auto_session', Path(__file__).resolve().parents[1] / 'auto_session.py')
au = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(au)

M0 = (0, 0, 1920, 1080)
M1 = (1920, 0, 3840, 1080)


class MonitorTest(unittest.TestCase):
    def test_picks_second_monitor(self):
        self.assertEqual(au.pick_monitor1([M0, M1]), M1)

    def test_refuses_without_monitor1(self):
        with self.assertRaises(RuntimeError):
            au.pick_monitor1([M0])
        with self.assertRaises(RuntimeError):
            au.pick_monitor1([])

    def test_refuses_mirrored(self):
        with self.assertRaises(RuntimeError):
            au.pick_monitor1([M0, M0])

    def test_fit_window_centers_and_scales(self):
        self.assertEqual(au.fit_window(M1, 640, 480), (1920 + 640, 300, 640, 480))
        x, y, w, h = au.fit_window(M1, 3840, 2160)
        self.assertEqual((w, h), (1920, 1080))
        self.assertEqual((x, y), (1920, 0))


class ButtonTest(unittest.TestCase):
    def test_active_low_polarity(self):
        self.assertEqual(au.buttons_word([]), 0xFFFF)
        self.assertEqual(au.buttons_word(['start']), 0xFFF7)
        self.assertEqual(au.buttons_word(['cross']), 0xBFFF)
        self.assertEqual(au.buttons_word(['Down', 'left']), 0xFFFF & ~0x00C0)

    def test_aliases_and_unknown(self):
        self.assertEqual(au.button_mask(['x']), 0x4000)
        self.assertEqual(au.button_mask(['o']), 0x2000)
        with self.assertRaises(ValueError):
            au.button_mask(['turbo'])

    def test_all_bits_distinct(self):
        self.assertEqual(len(set(au.BUTTON_BITS.values())), 14)
        self.assertEqual(au.button_mask(list(au.BUTTON_BITS)), 0xFFF9)


class RouteTest(unittest.TestCase):
    def good(self):
        return {'steps': [
            {'type': 'wait_frames', 'frames': 10},
            {'type': 'press', 'buttons': ['start'], 'frames': 4},
            {'type': 'screenshot', 'name': 'a'},
            {'type': 'screenshot', 'name': 'b'},
            {'type': 'savestate', 'slot': 1},
            {'type': 'telemetry', 'name': 't', 'which': ['dispatch_stats']},
            {'type': 'expect', 'check': 'shot_differs', 'a': 'a', 'b': 'b'},
        ]}

    def test_valid(self):
        self.assertTrue(au.validate_route(self.good()))

    def test_invalid_variants(self):
        bad = [
            {}, {'steps': []}, {'steps': [{'type': 'nope'}]},
            {'steps': [{'type': 'wait_frames', 'frames': 0}]},
            {'steps': [{'type': 'press', 'buttons': ['zzz']}]},
            {'steps': [{'type': 'press', 'buttons': []}]},
            {'steps': [{'type': 'screenshot'}]},
            {'steps': [{'type': 'savestate', 'op': 'x'}]},
            {'steps': [{'type': 'telemetry', 'name': 't', 'which': ['bogus']}]},
            {'steps': [{'type': 'expect', 'check': 'shot_differs', 'a': 'a'}]},
        ]
        for route in bad:
            with self.subTest(route=route), self.assertRaises(ValueError):
                au.validate_route(route)

    def test_shipped_route_is_valid(self):
        route = au.load_route('boot_to_fight')
        self.assertTrue(route['steps'])


class CommandTest(unittest.TestCase):
    def test_game_command(self):
        cmd = au.build_game_command('g/exPlusAlpha.exe', 'g/game.toml', 'ev/memcard', 4631)
        self.assertIn('--hidden-window', cmd)
        self.assertIn('--no-launcher', cmd)
        self.assertNotIn('--launcher', cmd)
        self.assertEqual(cmd[cmd.index('--debug-port') + 1], '4631')
        self.assertEqual(cmd[cmd.index('--memcard-dir') + 1], 'ev/memcard')
        self.assertNotIn('--disc', cmd)
        cmd = au.build_game_command('e', 'g', 'm', 1, disc='d.cue', bios='b.bin')
        self.assertEqual(cmd[cmd.index('--bios') + 1], 'b.bin')
        self.assertEqual(cmd[cmd.index('--disc') + 1], 'd.cue')

    def test_build_command_isolated(self):
        cmd = au.build_powershell_command('build-auto-1', 4, Path('x/retained-overlays'))
        self.assertIn('-StaticOverlayDir', cmd)
        self.assertNotIn('-Generate', cmd)
        self.assertNotIn('-Release', cmd)
        self.assertEqual(cmd[cmd.index('-Jobs') + 1], '4')
        with self.assertRaises(ValueError):
            au.build_powershell_command('build-release-online-1', 4, 'x')
        with self.assertRaises(ValueError):
            au.build_powershell_command('build-auto-1', 8, 'x')


if __name__ == '__main__':
    unittest.main()
