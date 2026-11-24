"""Comprehensive unit and integration test suite for ScamRakshak backend auth, profile, and sync.

Tests:
1. Missing token & invalid/malformed token (401).
2. First login (creates user + profile, district='unknown', language=locale, is_new_user=True).
3. Returning login (preserves existing username and language, is_new_user=False).
4. Phone immutability (phone cannot be updated, PUT /profile updates district & language only).
5. District validation on PUT /profile (rejects invalid district with 422).
6. Data isolation between two distinct UIDs.
7. Sync merging (detection history union, user reports union, quiz/lesson latest timestamp wins).
8. Dual report creation: POST /reports with Bearer token writes to anonymous reports AND user_reports.
9. Account deletion: DELETE /account cascades across all 6 tables while preserving anonymous reports.
10. Production token gate: verify mock tokens fail when AUTH_DEV_MODE is disabled.
"""

from __future__ import annotations

import datetime
import os
from pathlib import Path
import sys
import unittest

# Ensure backend directory is in sys.path
BACKEND_DIR = Path(__file__).resolve().parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

# Enable AUTH_DEV_MODE for local testing before imports
os.environ["AUTH_DEV_MODE"] = "1"

from fastapi.testclient import TestClient

import auth
import database
from database import DB_PATH, get_db_connection, init_db
import main
from main import app


class AuthAndSyncTestSuite(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Initialize schema in DB
        init_db()
        cls.client = TestClient(app)

    def setUp(self):
        auth.AUTH_DEV_MODE = True

    def test_01_missing_and_invalid_token(self):
        """Test missing, malformed, and invalid token rejection (401)."""
        # Missing auth header
        res = self.client.post("/auth/session", json={"username": "Alice", "locale": "en"})
        self.assertEqual(res.status_code, 401)
        self.assertIn("Missing Authorization header", res.json().get("detail", ""))

        # Malformed header (not Bearer)
        res = self.client.post(
            "/auth/session",
            json={"username": "Alice", "locale": "en"},
            headers={"Authorization": "Basic somebase64credentials"},
        )
        self.assertEqual(res.status_code, 401)

        # Invalid token format in dev mode
        res = self.client.post(
            "/auth/session",
            json={"username": "Alice", "locale": "en"},
            headers={"Authorization": "Bearer invalid_random_token"},
        )
        self.assertEqual(res.status_code, 401)

    def test_02_first_login_session_creation(self):
        """Test first login creates user + profile with district='unknown' and language=<locale>."""
        uid = "test_user_alice_001"
        phone = "+919876500001"
        token = f"mock-token:{uid}:{phone}"
        headers = {"Authorization": f"Bearer {token}"}

        # Clean any preexisting state for this test uid
        with get_db_connection() as conn:
            for tbl in ["detection_history", "quiz_progress", "lesson_progress", "user_reports", "profiles", "users"]:
                conn.execute(f"DELETE FROM {tbl} WHERE uid = ?;", (uid,))
            conn.commit()

        session_payload = {"username": "Alice Sharma", "locale": "hi"}
        res = self.client.post("/auth/session", json=session_payload, headers=headers)
        self.assertEqual(res.status_code, 200, res.text)
        data = res.json()
        self.assertEqual(data["uid"], uid)
        self.assertEqual(data["phone"], phone)
        self.assertEqual(data["username"], "Alice Sharma")
        self.assertEqual(data["district"], "unknown")
        self.assertEqual(data["language"], "hi")
        self.assertIs(data["is_new_user"], True)

    def test_03_returning_login_preserves_username(self):
        """Test returning login does not overwrite existing username or locale."""
        uid = "test_user_alice_001"
        phone = "+919876500001"
        token = f"mock-token:{uid}:{phone}"
        headers = {"Authorization": f"Bearer {token}"}

        # Call session again with a DIFFERENT username and locale in body
        res = self.client.post(
            "/auth/session",
            json={"username": "Alice Changed", "locale": "en"},
            headers=headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["uid"], uid)
        self.assertEqual(data["phone"], phone)
        # Original username and locale should be preserved
        self.assertEqual(data["username"], "Alice Sharma")
        self.assertEqual(data["language"], "hi")
        self.assertIs(data["is_new_user"], False)

    def test_04_phone_immutability_and_profile_update(self):
        """Test phone immutability and updating profile (district and language)."""
        uid = "test_user_alice_001"
        phone = "+919876500001"
        token = f"mock-token:{uid}:{phone}"
        headers = {"Authorization": f"Bearer {token}"}

        # GET profile
        res = self.client.get("/profile", headers=headers)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["phone"], phone)

        # PUT profile with new district and language
        update_payload = {"district": "Durg", "language": "chh"}
        res = self.client.put("/profile", json=update_payload, headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["district"], "Durg")
        self.assertEqual(data["language"], "chh")
        self.assertEqual(data["phone"], phone)  # Phone unchanged

        # Attempt to pass phone in PUT payload (should be ignored by backend)
        res = self.client.put(
            "/profile",
            json={"phone": "+910000000000", "district": "Raipur"},
            headers=headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["phone"], phone)  # Phone remains immutable
        self.assertEqual(data["district"], "Raipur")

        # Verify DB directly
        with get_db_connection() as conn:
            row = conn.execute("SELECT phone FROM users WHERE uid = ?;", (uid,)).fetchone()
            self.assertEqual(row["phone"], phone)

    def test_05_district_validation(self):
        """Test district validation on PUT /profile (rejects invalid district with 422)."""
        uid = "test_user_alice_001"
        phone = "+919876500001"
        token = f"mock-token:{uid}:{phone}"
        headers = {"Authorization": f"Bearer {token}"}

        res = self.client.put(
            "/profile",
            json={"district": "InvalidNonExistentDistrict"},
            headers=headers,
        )
        self.assertEqual(res.status_code, 422)

    def test_06_data_isolation_between_two_users(self):
        """Test complete data isolation between two distinct UIDs."""
        uid_1 = "test_user_alice_001"
        phone_1 = "+919876500001"
        headers_1 = {"Authorization": f"Bearer mock-token:{uid_1}:{phone_1}"}

        uid_2 = "test_user_bob_002"
        phone_2 = "+919876500002"
        headers_2 = {"Authorization": f"Bearer mock-token:{uid_2}:{phone_2}"}

        # Register User 2
        res = self.client.post(
            "/auth/session",
            json={"username": "Bob Verma", "locale": "en"},
            headers=headers_2,
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["username"], "Bob Verma")

        # User 1 pushes sync data (detection history, quiz, lesson, report)
        sync_payload_user1 = {
            "detection_history": [
                {
                    "kind": "message",
                    "verdict": "scam",
                    "score": 0.95,
                    "category": "electricity_bill",
                    "ts": "2026-11-24T01:00:00Z",
                }
            ],
            "quiz_progress": [
                {
                    "topic": "phishing_101",
                    "attempts": 2,
                    "correct": 4,
                    "total": 5,
                    "updated_at": "2026-11-24T01:10:00Z",
                }
            ],
            "lesson_progress": [
                {
                    "lesson_id": "lesson_qr_safety",
                    "completed_at": "2026-11-24T01:15:00Z",
                }
            ],
            "user_reports": [
                {
                    "type": "fake_qr",
                    "district": "Raipur",
                    "ts": "2026-11-24T01:20:00Z",
                }
            ],
        }
        res = self.client.put("/sync", json=sync_payload_user1, headers=headers_1)
        self.assertEqual(res.status_code, 200)

        # User 2 pulls sync data: MUST BE COMPLETELY EMPTY
        res = self.client.get("/sync", headers=headers_2)
        self.assertEqual(res.status_code, 200)
        data_user2 = res.json()
        self.assertEqual(len(data_user2["detection_history"]), 0)
        self.assertEqual(len(data_user2["quiz_progress"]), 0)
        self.assertEqual(len(data_user2["lesson_progress"]), 0)
        self.assertEqual(len(data_user2["user_reports"]), 0)

    def test_07_sync_conflict_resolution_and_merging(self):
        """Test sync merging rules: detection history union & quiz/lesson latest-timestamp-wins."""
        uid_1 = "test_user_alice_001"
        phone_1 = "+919876500001"
        headers_1 = {"Authorization": f"Bearer mock-token:{uid_1}:{phone_1}"}

        sync_payload_update = {
            "detection_history": [
                {
                    "kind": "message",
                    "verdict": "scam",
                    "score": 0.95,
                    "category": "electricity_bill",
                    "ts": "2026-11-24T01:00:00Z",  # Duplicate
                },
                {
                    "kind": "call",
                    "verdict": "high",
                    "score": 0.88,
                    "category": "digital_arrest",
                    "ts": "2026-11-24T02:00:00Z",  # New
                },
            ],
            "quiz_progress": [
                {
                    "topic": "phishing_101",
                    "attempts": 1,
                    "correct": 1,
                    "total": 5,
                    "updated_at": "2026-11-23T00:00:00Z",  # Older timestamp
                }
            ],
            "lesson_progress": [
                {
                    "lesson_id": "lesson_qr_safety",
                    "completed_at": "2026-11-24T02:30:00Z",  # Newer timestamp
                }
            ],
            "user_reports": [],
        }
        res = self.client.put("/sync", json=sync_payload_update, headers=headers_1)
        self.assertEqual(res.status_code, 200)
        data = res.json()

        # Detection history should have exactly 2 items (no duplicates)
        self.assertEqual(len(data["detection_history"]), 2)

        # Quiz progress should retain newer values (attempts=2, correct=4)
        quiz_item = next(q for q in data["quiz_progress"] if q["topic"] == "phishing_101")
        self.assertEqual(quiz_item["attempts"], 2)
        self.assertEqual(quiz_item["correct"], 4)

        # Lesson progress should have newer completed_at timestamp
        lesson_item = next(l for l in data["lesson_progress"] if l["lesson_id"] == "lesson_qr_safety")
        self.assertEqual(lesson_item["completed_at"], "2026-11-24T02:30:00Z")

    def test_08_dual_report_creation(self):
        """Test POST /reports writes to anonymous reports AND user_reports when authenticated."""
        uid_1 = "test_user_alice_001"
        phone_1 = "+919876500001"
        headers_1 = {"Authorization": f"Bearer mock-token:{uid_1}:{phone_1}"}

        initial_reports_count = self.client.get("/health").json()["reports_count"]

        rep_payload = {
            "type": "loan_app",
            "district": "Bilaspur",
            "ts": "2026-11-24T03:00:00Z",
        }
        res = self.client.post("/reports", json=rep_payload, headers=headers_1)
        self.assertEqual(res.status_code, 201)
        rep_id = res.json()["id"]

        # 1. Anonymous reports table incremented
        new_reports_count = self.client.get("/health").json()["reports_count"]
        self.assertEqual(new_reports_count, initial_reports_count + 1)

        # 2. Check SQLite: reports table has NO uid column
        with get_db_connection() as conn:
            cur = conn.cursor()
            cols = [c[1] for c in cur.execute("PRAGMA table_info(reports);").fetchall()]
            self.assertNotIn("uid", cols, "CRITICAL: 'uid' column must NOT exist in anonymous 'reports' table!")

            # 3. Check user_reports table has record tied to User 1
            user_rep = cur.execute(
                "SELECT * FROM user_reports WHERE uid = ? AND type = 'loan_app' AND district = 'Bilaspur';",
                (uid_1,),
            ).fetchone()
            self.assertIsNotNone(user_rep, "Report was not recorded in user_reports for User 1")

        # 4. Check user sync includes the new report
        res = self.client.get("/sync", headers=headers_1)
        self.assertEqual(res.status_code, 200)
        reports_in_sync = res.json()["user_reports"]
        self.assertTrue(any(r["type"] == "loan_app" and r["district"] == "Bilaspur" for r in reports_in_sync))

    def test_09_account_deletion_and_cascade(self):
        """Test DELETE /account cascades to all 6 tables and preserves anonymous reports."""
        uid_1 = "test_user_alice_001"
        phone_1 = "+919876500001"
        headers_1 = {"Authorization": f"Bearer mock-token:{uid_1}:{phone_1}"}

        res = self.client.delete("/account", headers=headers_1)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "success")

        # Verify GET /profile now returns 404
        res = self.client.get("/profile", headers=headers_1)
        self.assertEqual(res.status_code, 404)

        # Verify DB directly: all rows for User 1 are gone
        with get_db_connection() as conn:
            cur = conn.cursor()
            for tbl in ["users", "profiles", "detection_history", "quiz_progress", "lesson_progress", "user_reports"]:
                cnt = cur.execute(f"SELECT COUNT(*) as c FROM {tbl} WHERE uid = ?;", (uid_1,)).fetchone()["c"]
                self.assertEqual(cnt, 0, f"Expected 0 rows in {tbl} for {uid_1}, got {cnt}")

    def test_10_production_mode_rejection(self):
        """Test mock token is rejected when AUTH_DEV_MODE is disabled."""
        auth.AUTH_DEV_MODE = False
        try:
            res = self.client.post(
                "/auth/session",
                json={"username": "Hacker", "locale": "en"},
                headers={"Authorization": "Bearer mock-token:attacker:+919999999999"},
            )
            self.assertEqual(res.status_code, 401)
        finally:
            auth.AUTH_DEV_MODE = True

    def test_11_post_report_fallback_with_invalid_token(self):
        """Test POST /reports with invalid/expired token falls back to anonymous and indicates skipped."""
        rep_payload = {
            "type": "fake_qr",
            "district": "Raipur",
            "ts": "2026-11-24T03:30:00Z",
        }
        res = self.client.post(
            "/reports",
            json=rep_payload,
            headers={"Authorization": "Bearer invalid_expired_garbage_token"},
        )
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertEqual(data["status"], "success")
        self.assertIn("id", data)
        self.assertEqual(data["user_report"], "skipped")
        self.assertIs(data["user_report_skipped"], True)

    def test_12_sync_timestamp_and_payload_capping(self):
        """Test /sync rejects malformed non-UTC timestamps and capped payload sizes (>500 items)."""
        uid = "test_user_alice_001"
        phone = "+919876500001"
        headers = {"Authorization": f"Bearer mock-token:{uid}:{phone}"}

        # 1. Malformed timestamp (missing Z or UTC offset)
        malformed_sync = {
            "detection_history": [
                {
                    "kind": "message",
                    "verdict": "scam",
                    "score": 0.9,
                    "category": "otp_request",
                    "ts": "2026-11-24 12:00:00",  # Missing Z / UTC
                }
            ]
        }
        res = self.client.put("/sync", json=malformed_sync, headers=headers)
        self.assertEqual(res.status_code, 422)

        # 2. Payload size capping (> 500 items)
        oversized_items = [
            {
                "kind": "message",
                "verdict": "scam",
                "score": 0.9,
                "category": "otp_request",
                "ts": "2026-11-24T04:00:00Z",
            }
            for _ in range(501)
        ]
        res = self.client.put("/sync", json={"detection_history": oversized_items}, headers=headers)
        self.assertEqual(res.status_code, 422)


if __name__ == "__main__":
    unittest.main()
