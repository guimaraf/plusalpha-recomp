"""Collector checks only; no compiler, game process or real TCP connection."""
import sys
import argparse
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import capture_versus_result as capture


class CaptureChecks(unittest.TestCase):
    def test_full_frame_window_is_split(self):
        calls = []
        def query(cmd, **kw):
            calls.append(kw)
            if kw['frame_lo'] != kw['frame_hi']:
                return dict(emitted=2048, entries=[])
            return dict(emitted=1, entries=[dict(frame=kw['frame_lo'])])
        warnings = set()
        self.assertEqual(capture.frame_entries(query, 10, 11, warnings),
                         [dict(frame=10), dict(frame=11)])
        self.assertFalse(warnings)
        self.assertEqual(len(calls), 3)

    def test_single_frame_limit_is_not_silently_accepted(self):
        warnings = set()
        capture.frame_entries(lambda *a, **k: dict(emitted=2048, entries=[]), 10, 10, warnings)
        self.assertTrue(warnings)

    def test_no_completed_frame_does_not_query(self):
        def forbidden(*a, **k):
            self.fail('No completed frame should issue no request')
        self.assertEqual(capture.frame_entries(forbidden, 10, 9, set()), [])

    def test_candidates_exclude_dma_and_nonincrements(self):
        def event(old, new, dma=-1):
            return dict(addr='0x001D39CC', w=1, pc='0x80100000', old=hex(old), new=hex(new), dma_ch=dma)
        result = capture.increment_candidates([event(0, 1), event(1, 2), event(1, 0),
                                               event(2, 3, 2), event(255, 0)])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['occurrences'], 2)

    def test_cleanup_requires_unchanged_range_order(self):
        before = [dict(slot=0, lo='0x100', hi='0x200')]
        same = [dict(slot=0, lo=256, hi=512)]
        changed = [dict(slot=0, lo=256, hi=513)]
        self.assertTrue(capture.ranges_equal(before, same))
        self.assertFalse(capture.ranges_equal(before, changed))

    def test_capture_exports_and_removes_only_own_range(self):
        calls = []
        ram = bytearray(65536)
        ram[0x39B8] = ram[0xC9D0] = 1
        original = [dict(slot=0, lo='0x10', hi='0x20')]
        ranges_calls, frame_calls = 0, 0
        def request(port, cmd, **kw):
            nonlocal ranges_calls, frame_calls
            calls.append((cmd, kw))
            if cmd == 'read_ram':
                return dict(hex=ram.hex())
            if cmd == 'get_registers':
                frame_calls += 1
                return dict(frame=frame_calls*10)
            if cmd == 'capture_freeze':
                return dict(freeze_frame=0, frozen=0)
            if cmd == 'wtrace_ranges':
                ranges_calls += 1
                extra = [dict(slot=1, lo=hex(capture.RAM_LO), hi=hex(capture.RAM_HI))]
                return dict(ranges=original if ranges_calls == 1 else original+extra)
            if cmd == 'wtrace_arm':
                return dict(slot=1)
            if cmd == 'wtrace_stats':
                return dict(total=5, oldest_seq=0)
            if cmd == 'wtrace_dump':
                return dict(entries=[], emitted=0)
            return dict(ok=True)
        scratch = Path(__file__).resolve().parents[2] / 'captures'
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='versus-result-test-', dir=scratch) as temporary:
            # Explicitly verify the target before TemporaryDirectory cleanup.
            self.assertTrue(Path(temporary).resolve().is_relative_to(scratch.resolve()))
            output = Path(temporary) / 'capture'
            args = argparse.Namespace(output=output, port=4531, winner='P1', kind='match')
            with patch.object(capture, 'request', side_effect=request), \
                    patch.object(capture.time, 'monotonic', side_effect=[0, 0, 10, 10, 10.01]), \
                    patch.object(capture.time, 'sleep'):
                self.assertEqual(capture.capture(args), 0)
            self.assertTrue(json.loads((output/'status.json').read_text())['complete'])
            self.assertEqual((output/'before.bin').stat().st_size, 65536)
            self.assertEqual((output/'after.bin').stat().st_size, 65536)
            archives = list(output.glob('versus-result-P1-*.zip'))
            self.assertEqual(len(archives), 1)
            with zipfile.ZipFile(archives[0]) as archive:
                self.assertIn('writes.jsonl', archive.namelist())
                self.assertIn('status.json', archive.namelist())
                self.assertIsNone(archive.testzip())
            second = capture.archive_capture(output, 'P1')
            self.assertNotEqual(second, archives[0])
            with zipfile.ZipFile(second) as archive:
                self.assertFalse(any(name.endswith('.zip') for name in archive.namelist()))
        self.assertEqual(calls[-1], ('wtrace_disarm', dict(slot=1)))
        self.assertNotIn('wtrace_reset', [cmd for cmd, _ in calls])
        self.assertNotIn('write_ram', [cmd for cmd, _ in calls])


if __name__ == '__main__':
    unittest.main()
