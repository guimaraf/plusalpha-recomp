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

    def test_build_command_overlay_source(self):
        cmd = au.build_powershell_command('build-auto-1', 4, 'x')
        self.assertEqual(cmd[cmd.index('-OverlaySource') + 1], 'aot')
        cmd = au.build_powershell_command('build-auto-1', 4, 'x', 'retained')
        self.assertEqual(cmd[cmd.index('-OverlaySource') + 1], 'retained')
        with self.assertRaises(ValueError):
            au.build_powershell_command('build-auto-1', 4, 'x', 'other')
        self.assertEqual(au.static_overlay_dir_for('b', 'aot'), Path('b/static-overlays'))
        self.assertEqual(au.static_overlay_dir_for('b', 'retained'), Path('b/retained-overlays'))

    def test_detect_overlay_source(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            self.assertEqual(au.detect_overlay_source(root), 'unknown')
            (root / 'retained-overlays').mkdir()
            (root / 'retained-overlays' / 'retained_coverage.json').write_text('{}')
            self.assertEqual(au.detect_overlay_source(root), 'retained')
            (root / 'static-overlays').mkdir()
            (root / 'static-overlays' / 'AOT_STATIC_AUDIT.json').write_text('{}')
            self.assertEqual(au.detect_overlay_source(root), 'aot')

    def test_perf_indicators(self):
        perf = au.perf_indicators(
            1200, 110.0, (600, 100.0),
            dict(ok=True, insns_run=2400000, native_handoffs=600),
            dict(ok=True, interp_share=0.1, native_share=0.2, static_share=0.3),
            dict(ok=True, static_hits=5, static_rehashes=2, static_crc_misses=1))
        self.assertEqual(perf['guest_fps_since_prev'], 60.0)
        self.assertEqual(perf['insns_per_frame'], 2000.0)
        self.assertEqual(perf['native_handoffs_per_frame'], 0.5)
        self.assertEqual(perf['interp_share'], 0.1)
        self.assertEqual(perf['static_crc_cache']['capacity'], 16384)
        self.assertEqual(perf['static_crc_cache']['static_rehashes'], 2)
        self.assertEqual(au.perf_indicators(0, 1.0, None, None, None, None), {})


class Phase2StepsTest(unittest.TestCase):
    def test_parse_addr_and_le_value(self):
        self.assertEqual(au.parse_addr('0x801D39B8'), 0x801D39B8)
        self.assertEqual(au.parse_addr(5), 5)
        with self.assertRaises(ValueError):
            au.parse_addr('zz')
        self.assertEqual(au.le_value('0a', 1), 10)
        self.assertEqual(au.le_value('78563412', 4), 0x12345678)

    def test_exe_misses_filters_and_sorts(self):
        rows = [{'phys': '0x0010A5FC', 'count': 3}, {'phys': '0x00020000', 'count': 99},
                {'phys': '0x00169B78', 'count': 7}, {'phys': '0x001C0000', 'count': 1}]
        got = au.exe_misses(rows)
        self.assertEqual([r['pc'] for r in got], ['0x80169B78', '0x8010A5FC'])
        self.assertEqual(au.exe_misses(None), [])

    def test_exe_interp_pcs(self):
        rows = [{'pc': '0x0010A5FC', 'hits': 2, 'insns': 50}, {'pc': '0x00020000', 'hits': 9, 'insns': 999},
                {'pc': '0x00169B78', 'hits': 1, 'insns': 70}]
        got = au.exe_interp_pcs(rows)
        self.assertEqual([r['pc'] for r in got], ['0x80169B78', '0x8010A5FC'])
        self.assertEqual(au.exe_interp_pcs(None), [])

    def test_count_fntrace_hits(self):
        ents = [{'target': '0x8010A5FC', 'frame': 30}, {'target': '0x8010A5FC', 'frame': 10},
                {'target': '0x80169B78', 'frame': 5}, {'target': '0x80000000', 'frame': 1}]
        h = au.count_fntrace_hits(ents, [0x8010A5FC, 0x80169B78, 0x8010ABC8])
        self.assertEqual(h['0x8010A5FC'], {'hits': 2, 'first_frame': 10, 'last_frame': 30})
        self.assertEqual(h['0x8010ABC8'], {'hits': 0})

    def test_validate_new_steps(self):
        ok = {'steps': [
            {'type': 'read_ram', 'addr': '0x801D39B8', 'size': 1, 'name': 'cena'},
            {'type': 'wait_ram', 'addr': '0x801D39B8', 'values': [3], 'timeout_frames': 60},
            {'type': 'fntrace', 'op': 'arm', 'pcs': ['0x8010A5FC']},
            {'type': 'fntrace', 'op': 'dump', 'name': 'x'},
            {'type': 'dispatch_misses', 'name': 'm'}]}
        self.assertIs(au.validate_route(ok), ok)
        for bad in ({'type': 'read_ram', 'addr': '0x1'},
                    {'type': 'read_ram', 'addr': 'zz', 'name': 'a'},
                    {'type': 'wait_ram', 'addr': '0x1'},
                    {'type': 'fntrace', 'op': 'arm', 'pcs': []},
                    {'type': 'fntrace', 'op': 'arm', 'pcs': ['0x1'] * 33},
                    {'type': 'fntrace', 'op': 'dump'},
                    {'type': 'dispatch_misses'}):
            with self.assertRaises(ValueError):
                au.validate_route({'steps': [bad]})

    def test_build_command_isolated(self):
        cmd = au.build_powershell_command('build-auto-1', 4, 'x', 'aot', Path('g'), Path('s.txt'))
        self.assertEqual(cmd[cmd.index('-GeneratedDir') + 1], 'g')
        self.assertEqual(cmd[cmd.index('-SeedsFile') + 1], 's.txt')
        plain = au.build_powershell_command('build-auto-1', 4, 'x')
        self.assertNotIn('-GeneratedDir', plain)
        self.assertNotIn('-SeedsFile', plain)

    def test_resolve_reuse_name(self):
        self.assertEqual(au.resolve_reuse_name('PlusAlphaProject/build-auto-9'), 'build-auto-9')
        with self.assertRaises(ValueError):
            au.resolve_reuse_name('build-release-online-1')

    def test_survey_route_valid(self):
        self.assertTrue(au.load_route('survey_post_fight')['steps'])


if __name__ == '__main__':
    unittest.main()
