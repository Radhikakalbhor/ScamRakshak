"""Synthetic vs live trends, small-cell suppression, emerging-scam alerts, fingerprints, district validation
and accepted call-recording formats. Uses a temporary SQLite file; the Whisper model is not loaded.

    cd backend
    venv\\Scripts\\python -m unittest test_trends_alerts -v
"""

from __future__ import annotations

import datetime
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

BACKEND = Path(__file__).resolve().parent
sys.path.insert(0, str(BACKEND))

from fastapi.testclient import TestClient  # noqa: E402

import database  # noqa: E402
import main  # noqa: E402

UTC = datetime.timezone.utc


class _TempDb(unittest.TestCase):
    def setUp(self):
        # sqlite3's context manager commits but does not close, so Windows may still hold the file.
        self._dir = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self._old = database.DB_PATH
        database.DB_PATH = Path(self._dir.name) / "test.db"
        self.client = TestClient(main.app)  # no lifespan: no Whisper model

    def tearDown(self):
        database.DB_PATH = self._old
        self._dir.cleanup()

    def add(self, rtype, district, when, source="user"):
        with database.get_db_connection() as c:
            c.execute("INSERT INTO reports (type, district, ts, source) VALUES (?, ?, ?, ?);",
                      (rtype, district, when.isoformat(), source))
            c.commit()


class TrendsTest(_TempDb):
    def test_old_database_is_migrated_and_seed_rows_are_labelled(self):
        with sqlite3.connect(database.DB_PATH) as c:
            c.execute("CREATE TABLE reports (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, "
                      "district TEXT NOT NULL, ts TEXT NOT NULL);")
            c.executemany("INSERT INTO reports (type, district, ts) VALUES (?, ?, ?);",
                          [("otp", "Raipur", "2026-01-01T00:00:00+00:00")] * 302)
        database.init_db()
        with database.get_db_connection() as c:
            got = dict(c.execute("SELECT source, COUNT(*) FROM reports GROUP BY source;").fetchall())
        self.assertEqual(got, {"seed": 300, "user": 2})

    def test_summary_separates_synthetic_and_live_and_hides_small_cells(self):
        database.init_db()  # seeds 300 synthetic rows
        now = datetime.datetime.now(UTC)
        for _ in range(6):
            self.add("otp", "Raipur", now - datetime.timedelta(hours=2))
        for _ in range(3):
            self.add("call", "Durg", now - datetime.timedelta(hours=2))
        r = self.client.get("/trends/summary")
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j["min_count"], 5)
        self.assertEqual(j["synthetic"]["total"], 300)
        self.assertEqual(j["live"]["total"], 9)
        live = j["live"]
        self.assertEqual(live["by_district_type"], [{"district": "Raipur", "type": "otp", "count": 6}])
        self.assertEqual(live["by_district"], [{"district": "Raipur", "count": 6}])
        self.assertNotIn("Durg", [d["district"] for d in live["by_district"]])
        self.assertGreaterEqual(live["suppressed_cells"], 1)
        self.assertEqual(len(live["weekly"]), 12)
        self.assertEqual(live["weekly"][-1]["count"], 9)
        for part in (j["synthetic"], j["live"]):
            for cell in part["by_district_type"] + part["by_district"] + part["by_type"]:
                self.assertGreaterEqual(cell["count"], 5)
            for w in part["weekly"]:
                self.assertTrue(w["count"] is None or w["count"] == 0 or w["count"] >= 5)
        # The original contract is unchanged.
        self.assertEqual(self.client.get("/trends").status_code, 200)

    def test_reports_only_accept_known_districts(self):
        database.init_db()
        bad = self.client.post("/reports", json={"type": "otp", "district": "Ramesh 9876543210"})
        self.assertEqual(bad.status_code, 422)
        ok = self.client.post("/reports", json={"type": "otp", "district": "raipur"})
        self.assertEqual(ok.status_code, 201, ok.text)
        self.assertEqual(self.client.post("/reports", json={"type": "call", "district": "unknown"}).status_code, 201)
        with database.get_db_connection() as c:
            rows = c.execute("SELECT district, source FROM reports WHERE source = 'user';").fetchall()
        self.assertEqual(sorted(r["district"] for r in rows), ["Raipur", "unknown"])


class AlertsTest(_TempDb):
    def test_spike_against_trailing_baseline(self):
        database.init_db()
        now = datetime.datetime.now(UTC)
        for i in range(6):  # new this week, nothing before
            self.add("fake_qr", "Durg", now - datetime.timedelta(days=1, hours=i))
        for i in range(6):  # 6 this week but ~4 per week before: not a spike
            self.add("otp", "Raipur", now - datetime.timedelta(days=2, hours=i))
        for i in range(16):
            self.add("otp", "Raipur", now - datetime.timedelta(days=8 + i))
        for i in range(4):  # below the minimum count
            self.add("call", "Korba", now - datetime.timedelta(days=1, hours=i))
        alerts = self.client.get("/alerts").json()["alerts"]
        spikes = [a for a in alerts if a["kind"] == "spike"]
        self.assertEqual([(a["district"], a["type"]) for a in spikes], [("Durg", "fake_qr")])
        self.assertEqual(spikes[0]["recent"], 6)

    def test_synthetic_data_does_not_raise_alerts_by_default(self):
        database.init_db()
        now = datetime.datetime.now(UTC)
        for i in range(8):
            self.add("loan_app", "Bastar", now - datetime.timedelta(hours=i), source="seed")
        self.assertEqual([a for a in self.client.get("/alerts").json()["alerts"] if a["kind"] == "spike"], [])
        with_seed = self.client.get("/alerts", params={"include_synthetic": "true"}).json()["alerts"]
        self.assertIn(("Bastar", "loan_app"), [(a.get("district"), a.get("type")) for a in with_seed])

    def test_fingerprint_clusters(self):
        database.init_db()
        base = 0x0F0F_1234_ABCD_9876
        for i in range(5):  # near-identical: 1 bit differs
            r = self.client.post("/fingerprints", json={"fp": f"{base ^ (1 << i):016x}", "category": "otp_request"})
            self.assertEqual(r.status_code, 201, r.text)
        for i in range(4):  # a different, smaller group
            self.client.post("/fingerprints", json={"fp": f"{(~base & (2**64 - 1)) ^ (1 << i):016x}",
                                                    "category": "phishing_link"})
        clusters = [a for a in self.client.get("/alerts").json()["alerts"] if a["kind"] == "cluster"]
        self.assertEqual(len(clusters), 1)
        self.assertEqual((clusters[0]["category"], clusters[0]["size"]), ("otp_request", 5))

    def test_fingerprint_validation_and_no_text_column(self):
        database.init_db()
        self.assertEqual(self.client.post("/fingerprints", json={"fp": "hello", "category": "otp_request"}).status_code, 422)
        self.assertEqual(self.client.post("/fingerprints", json={"fp": "0" * 16, "category": "x"}).status_code, 422)
        with database.get_db_connection() as c:
            cols = {r["name"] for r in c.execute("PRAGMA table_info(fingerprints);").fetchall()}
        self.assertEqual(cols, {"id", "fp", "category", "ts"})


class FormatsTest(unittest.TestCase):
    def test_call_recording_formats_are_accepted(self):
        client = TestClient(main.app)
        for ext in ("m4a", "mp3", "wav", "amr", "ogg", "aac", "3gp"):
            r = client.post("/transcribe", files={"file": (f"call.{ext}", b"x", "application/octet-stream")})
            # Past the format check; without a loaded model the server answers 503, never 400.
            self.assertEqual(r.status_code, 503, f"{ext}: {r.text}")
        r = client.post("/transcribe", files={"file": ("notes.txt", b"x", "text/plain")})
        self.assertEqual(r.status_code, 400)
        self.assertIn("amr", r.json()["detail"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
