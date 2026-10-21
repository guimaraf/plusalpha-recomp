import importlib.util
import json
from pathlib import Path
import unittest
import tempfile
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

    def test_timing_capability_refuses_old_or_sync_sio_runtime(self):
        for status in ({'probe_version': 1},
                       dict(timing_supported=1, timing_schema=1, timing_sio_supported=0)):
            with self.assertRaises(RuntimeError):
                capture.require_timing_support(status)
        capture.require_timing_support(dict(timing_supported=1, timing_schema=1,
                                           timing_sio_supported=1))

    def test_timing_export_uses_separate_stream_selector(self):
        with patch.object(capture, 'command', return_value=dict(records=[], done=True)) as cmd:
            self.assertEqual(capture.read_pages(4531, events=2), [])
            self.assertEqual(cmd.call_args.args[1]['events'], 2)

    def test_timing_integrity_checks_both_clocks_and_sequence(self):
        status = dict(timing=1, timing_events=2, timing_overflow=0)
        rows = [dict(seq=0, kind=19, qpc=100, cycle=200, aux=0, value=0),
                dict(seq=1, kind=21, qpc=110, cycle=200, aux=0, value=0)]
        self.assertEqual(capture.timing_integrity(status, rows), [])
        for key, value in [('seq', 3), ('qpc', 99), ('cycle', 199), ('kind', 99)]:
            bad = [rows[0], {**rows[1], key: value}]
            self.assertTrue(capture.timing_integrity(status, bad))
        self.assertTrue(capture.timing_integrity({**status, 'timing_overflow': 1}, rows))
        self.assertTrue(capture.timing_integrity(status, rows[:1]))
        threaded = [{**rows[0], 'kind': 10, 'aux': 1, 'value': 4}, rows[1]]
        self.assertTrue(capture.timing_integrity(status, threaded))

    def test_timing_collection_exports_raw_data_without_matching_actions(self):
        profile = SCRIPT.parent / 'input_response_ryu_p1_square.json'
        timeline = [dict(seq=0, kind=19, qpc=100, cycle=200, aux=0, value=0)]
        status = {**self.status, 'presses': 5, 'timing': 1, 'timing_events': 1,
                  'timing_overflow': 0, 'timing_supported': 1, 'timing_schema': 1,
                  'timing_sio_supported': 1, 'probe_version': 1}
        with tempfile.TemporaryDirectory(dir=SCRIPT.parent) as temp:
            output = Path(temp) / 'new-capture'
            with patch.object(capture, 'command', return_value=status), \
                 patch.object(capture, 'countdown'), \
                 patch.object(capture, 'read_pages', side_effect=[self.events, timeline]), \
                 patch.object(capture, 'analyze', side_effect=AssertionError('must not calculate')):
                code = capture.main(['--mode', 'measure', '--button', 'square',
                                     '--profile', str(profile), '--output', str(output),
                                     '--collect-only', '--timing'])
            self.assertEqual(code, 0)
            saved = json.loads((output / 'capture.json').read_text(encoding='utf-8'))
            self.assertEqual(saved['events'], self.events)
            self.assertEqual(saved['timeline'], timeline)
            self.assertIsNone(saved['analysis']['latency_ms'])
            self.assertTrue((output / 'timeline.csv').is_file())

    def test_timing_mode_rejects_incompatible_scenario_before_connecting(self):
        with patch.object(capture, 'command') as cmd:
            with self.assertRaises(SystemExit):
                capture.main(['--timing', '--mode', 'measure', '--button', 'cross',
                              '--collect-only', '--output', 'unused'])
            cmd.assert_not_called()

    def test_deferred_pacer_events_and_post_irq_sample_remain_observations(self):
        rows = [dict(seq=0, kind=32, qpc=100, cycle=200, aux=0, value=1),
                dict(seq=1, kind=33, qpc=110, cycle=300, aux=0, value=1),
                dict(seq=2, kind=10, qpc=120, cycle=300, aux=3, value=0)]
        self.assertEqual(capture.timing_integrity(
            dict(timing=1, timing_events=3, timing_overflow=0), rows), [])
        self.assertEqual(capture.TIMING_KINDS[32], 'pacer_defer')
        self.assertEqual(capture.TIMING_KINDS[33], 'pacer_resume')
        result = capture.collection_summary(self.status)
        self.assertIsNone(result['latency_ms'])

    def test_frame_end_samples_do_not_get_confused_with_thread_flags(self):
        rows = [dict(seq=0, kind=32, qpc=100, cycle=200, aux=0, value=2),
                dict(seq=1, kind=33, qpc=110, cycle=560000, aux=2, value=0),
                dict(seq=2, kind=10, qpc=120, cycle=560000, aux=5, value=0),
                dict(seq=3, kind=13, qpc=125, cycle=560000, aux=2, value=0),
                dict(seq=4, kind=14, qpc=200, cycle=560000, aux=2, value=0),
                dict(seq=5, kind=10, qpc=210, cycle=560000, aux=4, value=0)]
        self.assertEqual(capture.timing_integrity(
            dict(timing=1, timing_events=6, timing_overflow=0), rows), [])

    def test_cancelled_frame_end_wait_does_not_claim_clean_experiment(self):
        rows = [dict(seq=0, kind=34, qpc=100, cycle=200, aux=0, value=1)]
        self.assertTrue(capture.timing_integrity(
            dict(timing=1, timing_events=1, timing_overflow=0), rows))
        self.assertEqual(capture.TIMING_KINDS[34], 'pacer_cancel')


if __name__ == '__main__':
    unittest.main()
