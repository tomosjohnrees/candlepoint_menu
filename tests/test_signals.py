import tempfile
import unittest
from pathlib import Path

from scanner import MAX_SAFE_UNIVERSE, should_request_scan
from signals import SignalMonitor, read_signals


def state(stamp, *, is_new=False, status="Ready"):
    return {
        "status": status, "updated_at": stamp, "comparison_available": True,
        "matches": [{"symbol": "NEARUSDT", "stage": "Breaking out", "is_new": is_new}],
        "watchlist": [], "key_levels": [], "hourly_extremes": [], "btc_weekly": [],
    }


class SignalTests(unittest.TestCase):
    def test_notification_cursor_survives_restart_and_only_emits_new_scans(self):
        with tempfile.TemporaryDirectory() as directory:
            cursor = Path(directory) / "state.json"
            monitor = SignalMonitor(cursor)
            self.assertEqual(monitor.update(state("2026-09-30T12:00:00+00:00", is_new=True)), [])
            fresh = state("2026-09-30T12:10:00+00:00", is_new=True)
            self.assertEqual([signal.symbol for signal in monitor.update(fresh)], ["NEARUSDT"])
            self.assertEqual(monitor.update(fresh), [])
            self.assertEqual(SignalMonitor(cursor).update(fresh), [])

    def test_signal_identity_tracks_candlepoint_stage_and_weekly_conditions(self):
        a = read_signals({"matches": [{"symbol": "NEARUSDT", "stage": "Near breakout"}]})[0]
        b = read_signals({"matches": [{"symbol": "NEARUSDT", "stage": "Breaking out"}]})[0]
        self.assertNotEqual(a.key, b.key)
        self.assertEqual(b.url("http://127.0.0.1:8765"), "http://127.0.0.1:8765/coin/NEARUSDT")
        self.assertEqual(read_signals({"matches": [{"symbol": "../evil", "stage": "X"}]}), [])

    def test_failed_scan_does_not_advance_cursor(self):
        with tempfile.TemporaryDirectory() as directory:
            monitor = SignalMonitor(Path(directory) / "state.json")
            self.assertEqual(monitor.update(state("2026-09-30T12:00:00+00:00", status="Scanning")), [])
            self.assertIsNone(monitor.last_scan)

    def test_scan_budget_and_interval(self):
        from datetime import datetime, timezone
        now = datetime(2026, 9, 30, 12, 10, tzinfo=timezone.utc)
        payload = state("2026-09-30T12:00:00+00:00")
        payload["universe"] = MAX_SAFE_UNIVERSE
        self.assertTrue(should_request_scan(payload, now))
        payload["universe"] += 1
        self.assertFalse(should_request_scan(payload, now))
        payload["universe"] = 100
        payload["last_error"] = "HTTP Error 429"
        self.assertFalse(should_request_scan(payload, now))
        payload["last_error"] = None
        payload["errors"] = 1
        self.assertFalse(should_request_scan(payload, now))
        payload["errors"] = 0
        payload["updated_at"] = "2026-09-30T12:01:00+00:00"
        self.assertFalse(should_request_scan(payload, now))


if __name__ == "__main__":
    unittest.main()
