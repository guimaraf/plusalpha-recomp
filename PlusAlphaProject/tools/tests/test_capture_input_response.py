import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'capture_input_response.py'
spec = importlib.util.spec_from_file_location('response_capture', SCRIPT)
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class ResponseAnalysisTests(unittest.TestCase):
    def setUp(self):
        self.status = dict(phase=3, cancelled=0, overflow=0, unexpected_inputs=0,
                           presses=1, initial_idle=1, frequency=1_000_000,
                           start_qpc=1_000_000, stop_qpc=6_000_000,
                           start_frame=100, stop_frame=400)
        self.events = [dict(kind=1, qpc=1_000_000, frame=100),
                       dict(kind=2, qpc=1_016_667, frame=101),
                       dict(kind=3, qpc=1_066_667, frame=104)]

    def test_measure_is_causal_and_uses_runtime_time(self):
        result = capture.analyze(self.status, self.events, 'measure')
        self.assertTrue(result['valid_measurement'])
        self.assertEqual(result['latency_frames'], 4)
        self.assertAlmostEqual(result['latency_ms'], 66.667)
        self.assertEqual(result['game_accept_to_state_frames'], 3)

    def test_bundled_profile_matches_immutable_real_evidence(self):
        params, profile = capture.profile_config(SCRIPT.parent / 'input_response_ryu_p1_square.json')
        self.assertEqual(params['state_addr'], 0x1D5076)
        self.assertEqual(params['input_addr'], 0x1E9968)
        self.assertEqual(profile['button'], 'square')

    def test_frame_indices_are_distinct_from_elapsed_time(self):
        events = [self.events[0], self.events[1],
                  {**self.events[2], 'frame': 101, 'qpc': 1_025_000}]
        result = capture.analyze(self.status, events, 'measure')
        self.assertEqual(result['latency_frames'], 1)
        self.assertEqual(result['latency_ms'], 25)
        self.assertAlmostEqual(result['elapsed_frame_equivalents'], 1.5)

    def test_collect_only_accepts_multiple_inputs_without_computing_latency(self):
        result = capture.collection_summary({**self.status, 'presses': 5})
        self.assertTrue(result['valid_capture'])
        self.assertFalse(result['valid_measurement'])
        self.assertIsNone(result['latency_ms'])
        self.assertEqual(capture.result_exit_code(result, 'measure'), 0)

    def test_collect_only_flags_incomplete_or_contaminated_data(self):
        for key, value in [('phase', 2), ('overflow', 1), ('cancelled', 1),
                           ('initial_idle', 0), ('presses', 0), ('unexpected_inputs', 1)]:
            result = capture.collection_summary({**self.status, key: value})
            self.assertFalse(result['valid_capture'])
            self.assertEqual(capture.result_exit_code(result, 'measure'), 2)

    def test_discovery_never_claims_latency(self):
        result = capture.analyze(self.status, self.events, 'discovery')
        self.assertTrue(result['valid_capture'])
        self.assertFalse(result['valid_measurement'])
        self.assertIsNone(result['latency_frames'])
        self.assertEqual(capture.result_exit_code(result, 'discovery'), 0)

    def test_multiple_presses_are_usable_discovery_but_not_measurement(self):
        status = {**self.status, 'presses': 5}
        result = capture.analyze(status, self.events, 'discovery')
        self.assertTrue(result['valid_capture'])
        self.assertTrue(result['warnings'])
        self.assertEqual(result['reasons'], [])
        self.assertEqual(capture.result_exit_code(result, 'discovery'), 0)
        self.assertFalse(capture.analyze(status, self.events, 'measure')['valid_measurement'])

    def test_discovery_without_input_still_fails(self):
        result = capture.analyze({**self.status, 'presses': 0}, [], 'discovery')
        self.assertFalse(result['valid_capture'])
        self.assertEqual(capture.result_exit_code(result, 'discovery'), 2)

    def test_later_actions_cannot_supply_first_action_candidates(self):
        sample = dict(events=[dict(kind=1, qpc=100), dict(kind=1, qpc=200)],
                      candidates=[dict(qpc=99), dict(qpc=101), dict(qpc=201)])
        self.assertEqual(capture.first_action_candidates(sample), [dict(qpc=101)])

    def test_incomplete_or_contaminated_captures_refuse_result(self):
        for key, value in [('phase', 2), ('cancelled', 1), ('overflow', 1),
                           ('unexpected_inputs', 1), ('presses', 0),
                           ('presses', 2), ('initial_idle', 0)]:
            with self.subTest(key=key, value=value):
                status = {**self.status, key: value}
                result = capture.analyze(status, self.events, 'measure')
                self.assertFalse(result['valid_measurement'])
                self.assertIsNone(result['latency_ms'])

    def test_slow_diagnostic_capture_is_not_representative(self):
        status = {**self.status, 'stop_frame': 200}
        self.assertFalse(capture.analyze(status, self.events, 'measure')['valid_measurement'])

    def test_missing_duplicate_or_out_of_order_markers_refuse_result(self):
        bad = [self.events[:2], self.events + [self.events[-1]],
               [self.events[0], self.events[1], {**self.events[2], 'qpc': 999_999}]]
        for events in bad:
            self.assertFalse(capture.analyze(self.status, events, 'measure')['valid_measurement'])

    def test_unreviewed_profile_is_rejected(self):
        with patch.object(Path, 'read_text', return_value=json.dumps({'verified': False})):
            with self.assertRaises(ValueError):
                capture.profile_config(Path('unreviewed.json'))

    def test_export_requires_progress_and_surfaces_errors(self):
        with patch.object(capture, 'command', return_value={'records': [], 'done': False, 'next': 0}):
            with self.assertRaises(RuntimeError):
                capture.read_pages(4531)


if __name__ == '__main__':
    unittest.main()
