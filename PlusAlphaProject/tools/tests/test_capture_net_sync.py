import importlib.util
import io
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "capture_net_sync", Path(__file__).resolve().parents[1] / "capture_net_sync.py")
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


class FakeSocket:
    def __init__(self, response):
        self.response = response
        self.sent = b""

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def settimeout(self, _):
        pass

    def sendall(self, data):
        self.sent = data

    def makefile(self, _):
        return io.BytesIO(self.response)


class SyncCaptureTests(unittest.TestCase):
    def test_request_ignores_greeting_and_sends_read_only_cursor(self):
        sock = FakeSocket(b'{"hello":"debug"}\n{"id":1,"ok":true,"entries":[]}\n')
        with patch.object(capture.socket, "create_connection", return_value=sock):
            response = capture.request(4531, "net_sync_trace", after=128, count=128)
        self.assertEqual(json.loads(sock.sent),
                         dict(id=1, cmd="net_sync_trace", after=128, count=128))
        self.assertGreaterEqual(response["response_ns"], response["request_ns"])

    def test_unsupported_command_is_fatal(self):
        sock = FakeSocket(b'{"id":1,"ok":false,"error":"unknown command"}\n')
        with patch.object(capture.socket, "create_connection", return_value=sock):
            with self.assertRaises(RuntimeError):
                capture.request(4531, "net_sync_trace")

    def test_eof_does_not_look_like_empty_history(self):
        with patch.object(capture.socket, "create_connection", return_value=FakeSocket(b"")):
            with self.assertRaises(ConnectionError):
                capture.request(4531, "net_sync_trace")

    def test_common_tick_offset_uses_qpc_and_excludes_replay_and_rematch(self):
        base = dict(stage=3, generation=1, tick=10, qpc=100000,
                    running=1, resim=0, tip_hold=0, delay=9, host=1)
        a = [base, dict(base, qpc=999999), dict(base, tick=11, resim=1)]
        b = [dict(base, qpc=217000, host=0), dict(base, tick=11),
             dict(base, tick=12, generation=2)]
        result = self.summary(a, b, lost=3)
        self.assertEqual(result["matched_admits"], 1)
        self.assertAlmostEqual(result["same_tick_b_minus_a_ms"]["median"], 117)
        self.assertEqual(result["lost"], [3, 0])

    def test_different_frequencies_refuse_phase_comparison(self):
        with patch.object(capture, "read_history", side_effect=[([], 1000, 0), ([], 1001, 0)]):
            result = capture.summarize([Path("a"), Path("b")])
        self.assertIn("comparison_unavailable", result)

    def test_local_generation_ids_need_not_be_equal(self):
        a = [self.event(1, 0, 100000, 1), self.event(3, 0, 10000000, 0)]
        b = [self.event(4, 0, 105000, 0), self.event(8, 0, 10006000, 1)]
        result = self.summary(a, b)
        self.assertEqual(result["matched_admits"], 2)
        self.assertEqual([(s["generation_a"], s["generation_b"]) for s in result["sessions"]],
                         [(1, 4), (3, 8)])
        self.assertEqual(result["unpaired_generations_a"], [])

    def test_same_generation_but_distant_sessions_are_not_joined(self):
        result = self.summary([self.event(1, 0, 100000, 1)],
                              [self.event(1, 0, 10000000, 0)])
        self.assertEqual(result["matched_admits"], 0)
        self.assertEqual(result["unpaired_generations_b"], [1])

    def test_ambiguous_session_pairing_is_refused(self):
        result = self.summary([self.event(1, 0, 100000, 1)],
                              [self.event(2, 0, 101000, 0), self.event(4, 0, 102000, 0)])
        self.assertEqual(result["matched_admits"], 0)

    def test_marker_windows_and_unclosed_stages(self):
        markers = [dict(label="combat-p1", edge="begin", qpc=90000, frequency=1000000),
                   dict(label="combat-p1", edge="end", qpc=110000, frequency=1000000),
                   dict(label="drag-host", edge="begin", qpc=120000, frequency=1000000)]
        result = self.summary([self.event(1, 0, 100000, 1)],
                              [self.event(1, 0, 101000, 0)], markers=markers)
        self.assertEqual(result["marker_windows"][0]["matched_admits"], 1)
        self.assertEqual(result["marker_windows"][0]["phase_ms"]["median"], 1)
        self.assertEqual(result["unclosed_markers"][0]["label"], "drag-host")

    def test_longest_excursion_breaks_on_missing_ticks(self):
        stats = capture.phase_stats([dict(tick=t, b_minus_a_ms=50) for t in [1, 2, 4, 5, 6]])
        self.assertEqual(stats["over_2_frames_longest_ticks"], 3)

    def test_drag_plan_keeps_roles_separate_and_allows_reverse_order(self):
        plan = capture.drag_plan("both", "ClientFirst", 10, 15, 20)
        self.assertEqual([p[0] for p in plan], ["baseline-client", "drag-client",
            "recovery-client", "baseline-host", "drag-host", "recovery-host"])
        self.assertEqual(sum(p[2] for p in plan), 90)
        self.assertEqual(len(capture.drag_plan("host", "ClientFirst", 10, 15, 20)), 3)

    def test_timed_markers_use_actual_role_ports(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = [("drag-host", "host", 0), ("recovery-host", "host", 0)]
            with patch.object(capture, "marker_clock", return_value=(123456, 10000000)):
                capture.run_drag_schedule(Path(directory), plan,
                    {"host": 4532, "client": 4531}, threading.Event(), lambda: None)
            rows = [json.loads(line) for line in (Path(directory) / "markers.jsonl").read_text().splitlines()]
            self.assertEqual([r["edge"] for r in rows], ["begin", "end", "begin", "end"])
            self.assertTrue(all(r["port"] == 4532 and r["role"] == "host" for r in rows))

    def test_from_now_skips_old_events_without_reporting_old_overwrites(self):
        stop = threading.Event()
        class Ready:
            def set(self):
                stop.set()
        initial = dict(request_ns=1, response_ns=2, data=dict(
            enabled=1, total=100, frequency=10000000, lost=99, entries=[dict(seq=1)]))
        fresh = dict(data=dict(enabled=1, total=100, lost=0, entries=[]))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "peer.jsonl"
            with patch.object(capture, "request", side_effect=[initial, fresh]) as mocked:
                with patch.object(capture.time, "monotonic", return_value=0):
                    capture.collect(4531, path, stop, 1, from_now=True, ready=Ready())
            self.assertEqual(mocked.call_args_list[1].kwargs["after"], 100)
            events, _, lost = capture.read_history(path)
            self.assertEqual(events, [])
            self.assertEqual(lost, 0)
            self.assertEqual(json.loads(path.read_text().splitlines()[0])["start_after_seq"], 100)

    @staticmethod
    def event(generation, tick, qpc, host):
        return dict(stage=3, generation=generation, tick=tick, qpc=qpc,
                    running=1, resim=0, tip_hold=0, delay=3, host=host)

    def summary(self, a, b, lost=0, markers=None):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / name for name in ("a.jsonl", "b.jsonl")]
            for i, (path, events) in enumerate(zip(paths, [a, b])):
                path.write_text(json.dumps(dict(command="net_sync_trace", data=dict(
                    entries=events, frequency=1000000, lost=lost if i == 0 else 0))) + "\n",
                    encoding="utf-8")
            if markers is not None:
                (Path(directory) / "markers.jsonl").write_text(
                    "\n".join(json.dumps(m) for m in markers) + "\n", encoding="utf-8")
            with patch.object(capture.platform, "system", return_value="Windows"):
                return capture.summarize(paths)


if __name__ == "__main__":
    unittest.main()
