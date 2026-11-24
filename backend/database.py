"""Database module for ScamRakshak backend.

Handles SQLite connection, schema initialization, report storage,
trend aggregation, initial seeding of realistic Chhattisgarh fraud data,
and per-user authentication, profile, sync, and account data storage.
"""

from __future__ import annotations

import datetime
from pathlib import Path
import random
import sqlite3
from typing import Any, Dict, List, Optional

DB_PATH = Path(__file__).resolve().parent / "data.db"

# 10 Chhattisgarh districts specified in requirements
CHHATTISGARH_DISTRICTS = [
    "Raipur",
    "Durg",
    "Bilaspur",
    "Korba",
    "Raigarh",
    "Bastar",
    "Rajnandgaon",
    "Dhamtari",
    "Surguja",
    "Janjgir-Champa",
]

# 5 fraud types specified in requirements
REPORT_TYPES = ["otp", "fake_qr", "loan_app", "call", "other"]

# All 33 districts the app offers (lib/features/report/report_data.dart) plus "unknown".
# POST /reports only accepts these, so no free text (names, numbers) can be stored in `district`.
ALL_DISTRICTS = [
    "Balod", "Baloda Bazar", "Balrampur", "Bastar", "Bemetara", "Bijapur", "Bilaspur",
    "Dantewada", "Dhamtari", "Durg", "Gariaband", "Gaurela-Pendra-Marwahi", "Janjgir-Champa",
    "Jashpur", "Kabirdham", "Kanker", "Khairagarh-Chhuikhadan-Gandai", "Kondagaon", "Korba",
    "Korea", "Mahasamund", "Manendragarh-Chirmiri-Bharatpur", "Mohla-Manpur-Ambagarh Chowki",
    "Mungeli", "Narayanpur", "Raigarh", "Raipur", "Rajnandgaon", "Sakti", "Sarangarh-Bilaigarh",
    "Sukma", "Surajpur", "Surguja", "unknown",
]
_DISTRICT_LOOKUP = {d.lower(): d for d in ALL_DISTRICTS}

# Rows inserted by seed_initial_reports() are synthetic demo data; rows from POST /reports are "user".
SOURCE_SEED = "seed"
SOURCE_USER = "user"

# Aggregates with fewer reports than this are not shown (small cells can identify people).
MIN_CELL_COUNT = 5

# Message fingerprint categories accepted by POST /fingerprints (the app's message categories).
FINGERPRINT_CATEGORIES = [
    "otp_request", "upi_collect", "fake_kyc", "digital_arrest", "courier_customs", "remote_access",
    "lottery_prize", "loan_threat", "phishing_link", "electricity_bill", "telecom_threat", "pressure", "other",
]


def canonical_district(name: str) -> Optional[str]:
    """Exact district name from the allowed list (case-insensitive), or None."""
    return _DISTRICT_LOOKUP.get((name or "").strip().lower())


# Realistic fraud distribution per district reflecting local demographics:
# - Raipur (Metro/Commerce hub): OTP & Fake QR dominant in busy markets
# - Durg (Bhilai industrial & student hub): Fake QR & predatory loan apps
# - Bilaspur (Railway zone & legal center): Impersonation calls & OTP scams
# - Korba (Mining/Industrial sector): Pension/lottery call scams & loan apps
# - Raigarh (Industrial/Trade corridor): Loan apps & QR phishing
# - Bastar (Rural/tribal branch banking): Social engineering calls & fake QR
# - Rajnandgaon (Border commerce/trading): OTP scams & quick loan apps
# - Dhamtari (Agricultural Mandis): Fake merchant QR codes & OTP theft
# - Surguja (Northern plateau): Call frauds & unverified loan apps
# - Janjgir-Champa (Rural agriculture/crafts): OTP theft & call scams
# Total records: exactly 300 (55+44+40+31+28+23+23+20+17+19 = 300)
DISTRICT_TYPE_DISTRIBUTIONS: Dict[str, Dict[str, int]] = {
    "Raipur": {
        "otp": 23,
        "fake_qr": 14,
        "loan_app": 10,
        "call": 5,
        "other": 3,
    },  # Total: 55
    "Durg": {
        "fake_qr": 15,
        "loan_app": 13,
        "otp": 10,
        "call": 4,
        "other": 2,
    },  # Total: 44
    "Bilaspur": {
        "call": 14,
        "otp": 12,
        "fake_qr": 8,
        "loan_app": 4,
        "other": 2,
    },  # Total: 40
    "Korba": {
        "call": 13,
        "loan_app": 7,
        "otp": 6,
        "other": 3,
        "fake_qr": 2,
    },  # Total: 31
    "Raigarh": {
        "loan_app": 10,
        "fake_qr": 7,
        "call": 5,
        "otp": 4,
        "other": 2,
    },  # Total: 28
    "Bastar": {
        "call": 10,
        "fake_qr": 5,
        "otp": 4,
        "loan_app": 2,
        "other": 2,
    },  # Total: 23
    "Rajnandgaon": {
        "otp": 8,
        "loan_app": 7,
        "call": 4,
        "fake_qr": 3,
        "other": 1,
    },  # Total: 23
    "Dhamtari": {
        "fake_qr": 8,
        "otp": 5,
        "call": 4,
        "loan_app": 2,
        "other": 1,
    },  # Total: 20
    "Surguja": {
        "call": 7,
        "loan_app": 4,
        "other": 3,
        "otp": 2,
        "fake_qr": 1,
    },  # Total: 17
    "Janjgir-Champa": {
        "otp": 7,
        "call": 5,
        "fake_qr": 4,
        "loan_app": 2,
        "other": 1,
    },  # Total: 19
}


def get_db_connection() -> sqlite3.Connection:
    """Creates a connection to the SQLite database with row factory and foreign keys enabled."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn


def init_db(force_reseed: bool = False) -> None:
    """Initializes tables, indices, and seeds initial 300 realistic reports if database is empty."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with get_db_connection() as conn:
        cursor = conn.cursor()

        # Anonymous aggregate fraud reports table
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT NOT NULL,
                district TEXT NOT NULL,
                ts TEXT NOT NULL
            );
            """
        )
        cursor.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_reports_district_type
            ON reports (district, type);
            """
        )

        # Additive migration: label seeded (synthetic) vs real user reports.
        columns = {row["name"] for row in cursor.execute("PRAGMA table_info(reports);").fetchall()}
        if "source" not in columns:
            cursor.execute(f"ALTER TABLE reports ADD COLUMN source TEXT NOT NULL DEFAULT '{SOURCE_USER}';")
            # Older databases: the seed always ran first on an empty table, so it owns ids 1..300.
            cursor.execute(f"UPDATE reports SET source = '{SOURCE_SEED}' WHERE id <= 300;")

        # Anonymous message fingerprints table
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS fingerprints (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fp TEXT NOT NULL,
                category TEXT NOT NULL,
                ts TEXT NOT NULL
            );
            """
        )

        # --------------------------------------------------------------------
        # PER-USER TABLES (AUTHENTICATION, PROFILE, SYNC)
        # --------------------------------------------------------------------

        # Users table (uid PK from Firebase, verified phone number UNIQUE, username)
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                uid TEXT PRIMARY KEY,
                phone TEXT UNIQUE NOT NULL,
                username TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """
        )
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_users_phone ON users (phone);")

        # Profiles table (district and language NOT NULL; district defaults to 'unknown')
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS profiles (
                uid TEXT PRIMARY KEY,
                district TEXT NOT NULL,
                language TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY (uid) REFERENCES users (uid) ON DELETE CASCADE
            );
            """
        )

        # Detection history (metadata only: kind, verdict, score, category, ts; NO raw text)
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS detection_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uid TEXT NOT NULL,
                kind TEXT NOT NULL CHECK(kind IN ('message', 'qr', 'call')),
                verdict TEXT NOT NULL,
                score REAL NOT NULL,
                category TEXT NOT NULL,
                ts TEXT NOT NULL,
                FOREIGN KEY (uid) REFERENCES users (uid) ON DELETE CASCADE
            );
            """
        )
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_detection_history_uid ON detection_history (uid);")

        # Quiz progress (per topic progress)
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS quiz_progress (
                uid TEXT NOT NULL,
                topic TEXT NOT NULL,
                attempts INTEGER NOT NULL,
                correct INTEGER NOT NULL,
                total INTEGER NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (uid, topic),
                FOREIGN KEY (uid) REFERENCES users (uid) ON DELETE CASCADE
            );
            """
        )

        # Lesson progress (completed lessons)
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS lesson_progress (
                uid TEXT NOT NULL,
                lesson_id TEXT NOT NULL,
                completed_at TEXT NOT NULL,
                PRIMARY KEY (uid, lesson_id),
                FOREIGN KEY (uid) REFERENCES users (uid) ON DELETE CASCADE
            );
            """
        )

        # User reports (reports submitted by authenticated users, separate from anonymous reports)
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS user_reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uid TEXT NOT NULL,
                type TEXT NOT NULL,
                district TEXT NOT NULL,
                ts TEXT NOT NULL,
                FOREIGN KEY (uid) REFERENCES users (uid) ON DELETE CASCADE
            );
            """
        )
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_user_reports_uid ON user_reports (uid);")

        conn.commit()

        if force_reseed:
            cursor.execute("DELETE FROM reports;")
            conn.commit()

        # Check existing count
        cursor.execute("SELECT COUNT(*) AS cnt FROM reports;")
        count = cursor.fetchone()["cnt"]

        if count == 0:
            seed_initial_reports(cursor)
            conn.commit()


def seed_initial_reports(cursor: sqlite3.Cursor) -> int:
    """Seeds exactly 300 realistic anonymized fraud reports across Chhattisgarh districts."""
    rng = random.Random(42)  # Fixed seed for reproducibility
    now = datetime.datetime.now(datetime.timezone.utc)
    records: List[tuple[str, str, str, str]] = []

    for district, type_counts in DISTRICT_TYPE_DISTRIBUTIONS.items():
        for fraud_type, count in type_counts.items():
            for _ in range(count):
                # Anonymized timestamps scattered over the last 90 days
                days_ago = rng.randint(0, 90)
                hours_ago = rng.randint(0, 23)
                minutes_ago = rng.randint(0, 59)
                seconds_ago = rng.randint(0, 59)
                ts = (
                    now
                    - datetime.timedelta(
                        days=days_ago,
                        hours=hours_ago,
                        minutes=minutes_ago,
                        seconds=seconds_ago,
                    )
                ).isoformat()
                records.append((fraud_type, district, ts, SOURCE_SEED))

    cursor.executemany(
        "INSERT INTO reports (type, district, ts, source) VALUES (?, ?, ?, ?);", records
    )
    return len(records)


def create_report(
    report_type: str, district: str, ts: Optional[str] = None
) -> int:
    """Inserts a new user report (type, district, time only) into the anonymous database."""
    if not ts:
        ts = datetime.datetime.now(datetime.timezone.utc).isoformat()

    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO reports (type, district, ts, source) VALUES (?, ?, ?, ?);",
            (report_type.strip().lower(), district.strip(), ts, SOURCE_USER),
        )
        conn.commit()
        return cursor.lastrowid or 0


# ============================================================================
# USER & PROFILE MANAGEMENT
# ============================================================================


def get_or_create_user(
    uid: str, phone: str, username: str, locale: str = "en"
) -> tuple[Dict[str, Any], bool]:
    """Retrieves existing user or creates a new user and profile on first login.

    Contract:
    - Username comes from request and is stored on first creation only.
    - Profiles district defaults to 'unknown' and language to the app's current locale.
    - Phone number is taken strictly from verified token.
    Returns:
        (profile_dict, is_new_user)
    """
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with get_db_connection() as conn:
        cur = conn.cursor()
        user_row = cur.execute("SELECT * FROM users WHERE uid = ?;", (uid,)).fetchone()

        if user_row is None:
            # First-time registration
            cur.execute(
                "INSERT INTO users (uid, phone, username, created_at) VALUES (?, ?, ?, ?);",
                (uid, phone, username.strip(), now),
            )
            cur.execute(
                "INSERT INTO profiles (uid, district, language, updated_at) VALUES (?, ?, ?, ?);",
                (uid, "unknown", locale, now),
            )
            conn.commit()

            return {
                "uid": uid,
                "phone": phone,
                "username": username.strip(),
                "district": "unknown",
                "language": locale,
                "created_at": now,
                "updated_at": now,
                "is_new_user": True,
            }, True
        else:
            # Returning user: username in request is ignored; existing user is loaded
            prof_row = cur.execute("SELECT * FROM profiles WHERE uid = ?;", (uid,)).fetchone()
            return {
                "uid": user_row["uid"],
                "phone": user_row["phone"],
                "username": user_row["username"],
                "district": prof_row["district"] if prof_row else "unknown",
                "language": prof_row["language"] if prof_row else locale,
                "created_at": user_row["created_at"],
                "updated_at": prof_row["updated_at"] if prof_row else user_row["created_at"],
                "is_new_user": False,
            }, False


def get_user_profile(uid: str) -> Optional[Dict[str, Any]]:
    """Fetches user profile details for authenticated uid."""
    with get_db_connection() as conn:
        row = conn.execute(
            """
            SELECT u.uid, u.phone, u.username, u.created_at,
                   p.district, p.language, p.updated_at
            FROM users u
            LEFT JOIN profiles p ON u.uid = p.uid
            WHERE u.uid = ?;
            """,
            (uid,),
        ).fetchone()

        if not row:
            return None

        return {
            "uid": row["uid"],
            "phone": row["phone"],
            "username": row["username"],
            "district": row["district"] or "unknown",
            "language": row["language"] or "en",
            "created_at": row["created_at"],
            "updated_at": row["updated_at"] or row["created_at"],
        }


def update_user_profile(
    uid: str, district: Optional[str] = None, language: Optional[str] = None
) -> Optional[Dict[str, Any]]:
    """Updates district and/or language for authenticated user. Phone number is immutable."""
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with get_db_connection() as conn:
        cur = conn.cursor()
        prof = cur.execute("SELECT * FROM profiles WHERE uid = ?;", (uid,)).fetchone()
        if not prof:
            return None

        new_district = district if district is not None else prof["district"]
        new_language = language if language is not None else prof["language"]

        cur.execute(
            """
            UPDATE profiles
            SET district = ?, language = ?, updated_at = ?
            WHERE uid = ?;
            """,
            (new_district, new_language, now, uid),
        )
        conn.commit()

    return get_user_profile(uid)


def delete_user_account(uid: str) -> bool:
    """Deletes all user rows across all 6 tables for this account."""
    with get_db_connection() as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM detection_history WHERE uid = ?;", (uid,))
        cur.execute("DELETE FROM quiz_progress WHERE uid = ?;", (uid,))
        cur.execute("DELETE FROM lesson_progress WHERE uid = ?;", (uid,))
        cur.execute("DELETE FROM user_reports WHERE uid = ?;", (uid,))
        cur.execute("DELETE FROM profiles WHERE uid = ?;", (uid,))
        res = cur.execute("DELETE FROM users WHERE uid = ?;", (uid,))
        conn.commit()
        return (res.rowcount or 0) > 0


def add_user_report(uid: str, report_type: str, district: str, ts: str) -> int:
    """Stores a user-associated incident report in user_reports."""
    with get_db_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO user_reports (uid, type, district, ts) VALUES (?, ?, ?, ?);",
            (uid, report_type.strip().lower(), district.strip(), ts),
        )
        conn.commit()
        return cur.lastrowid or 0


# ============================================================================
# USER DATA SYNC (DETECTION HISTORY, QUIZ, LESSONS, REPORTS)
# ============================================================================


def get_user_sync_data(uid: str) -> Dict[str, Any]:
    """Retrieves all sync data for the given user."""
    with get_db_connection() as conn:
        hist_rows = conn.execute(
            """
            SELECT id, kind, verdict, score, category, ts
            FROM detection_history
            WHERE uid = ?
            ORDER BY ts ASC;
            """,
            (uid,),
        ).fetchall()

        quiz_rows = conn.execute(
            """
            SELECT topic, attempts, correct, total, updated_at
            FROM quiz_progress
            WHERE uid = ?;
            """,
            (uid,),
        ).fetchall()

        lesson_rows = conn.execute(
            """
            SELECT lesson_id, completed_at
            FROM lesson_progress
            WHERE uid = ?;
            """,
            (uid,),
        ).fetchall()

        report_rows = conn.execute(
            """
            SELECT id, type, district, ts
            FROM user_reports
            WHERE uid = ?
            ORDER BY ts ASC;
            """,
            (uid,),
        ).fetchall()

        return {
            "detection_history": [
                {
                    "id": r["id"],
                    "kind": r["kind"],
                    "verdict": r["verdict"],
                    "score": float(r["score"]),
                    "category": r["category"],
                    "ts": r["ts"],
                }
                for r in hist_rows
            ],
            "quiz_progress": [
                {
                    "topic": r["topic"],
                    "attempts": int(r["attempts"]),
                    "correct": int(r["correct"]),
                    "total": int(r["total"]),
                    "updated_at": r["updated_at"],
                }
                for r in quiz_rows
            ],
            "lesson_progress": [
                {
                    "lesson_id": r["lesson_id"],
                    "completed_at": r["completed_at"],
                }
                for r in lesson_rows
            ],
            "user_reports": [
                {
                    "id": r["id"],
                    "type": r["type"],
                    "district": r["district"],
                    "ts": r["ts"],
                }
                for r in report_rows
            ],
        }


def sync_user_data(uid: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    """Merges client sync payload into database per conflict rules:

    - Detection History: Union of records (deduplicate on kind, category, ts).
    - User Reports: Union of records (deduplicate on type, district, ts).
    - Quiz Progress: Latest timestamp wins per topic.
    - Lesson Progress: Latest timestamp wins per lesson_id.
    """
    with get_db_connection() as conn:
        cur = conn.cursor()

        # 1. Detection History: Union
        existing_hist = cur.execute(
            "SELECT kind, category, ts FROM detection_history WHERE uid = ?;",
            (uid,),
        ).fetchall()
        existing_hist_keys = {(r["kind"], r["category"], r["ts"]) for r in existing_hist}

        for item in payload.get("detection_history", []):
            key = (item["kind"], item["category"], item["ts"])
            if key not in existing_hist_keys:
                cur.execute(
                    """
                    INSERT INTO detection_history (uid, kind, verdict, score, category, ts)
                    VALUES (?, ?, ?, ?, ?, ?);
                    """,
                    (
                        uid,
                        item["kind"],
                        item["verdict"],
                        float(item["score"]),
                        item["category"],
                        item["ts"],
                    ),
                )
                existing_hist_keys.add(key)

        # 2. User Reports: Union
        existing_reports = cur.execute(
            "SELECT type, district, ts FROM user_reports WHERE uid = ?;", (uid,)
        ).fetchall()
        existing_report_keys = {(r["type"], r["district"], r["ts"]) for r in existing_reports}

        for item in payload.get("user_reports", []):
            key = (item["type"], item["district"], item["ts"])
            if key not in existing_report_keys:
                cur.execute(
                    """
                    INSERT INTO user_reports (uid, type, district, ts)
                    VALUES (?, ?, ?, ?);
                    """,
                    (uid, item["type"], item["district"], item["ts"]),
                )
                existing_report_keys.add(key)

        # 3. Quiz Progress: Latest timestamp wins per topic
        existing_quiz = {
            r["topic"]: r["updated_at"]
            for r in cur.execute(
                "SELECT topic, updated_at FROM quiz_progress WHERE uid = ?;",
                (uid,),
            ).fetchall()
        }

        for item in payload.get("quiz_progress", []):
            topic = item["topic"]
            client_ts = item["updated_at"]
            if topic not in existing_quiz:
                cur.execute(
                    """
                    INSERT INTO quiz_progress (uid, topic, attempts, correct, total, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?);
                    """,
                    (
                        uid,
                        topic,
                        item["attempts"],
                        item["correct"],
                        item["total"],
                        client_ts,
                    ),
                )
                existing_quiz[topic] = client_ts
            elif client_ts > existing_quiz[topic]:
                cur.execute(
                    """
                    UPDATE quiz_progress
                    SET attempts = ?, correct = ?, total = ?, updated_at = ?
                    WHERE uid = ? AND topic = ?;
                    """,
                    (
                        item["attempts"],
                        item["correct"],
                        item["total"],
                        client_ts,
                        uid,
                        topic,
                    ),
                )
                existing_quiz[topic] = client_ts

        # 4. Lesson Progress: Latest timestamp wins per lesson_id
        existing_lessons = {
            r["lesson_id"]: r["completed_at"]
            for r in cur.execute(
                "SELECT lesson_id, completed_at FROM lesson_progress WHERE uid = ?;",
                (uid,),
            ).fetchall()
        }

        for item in payload.get("lesson_progress", []):
            lid = item["lesson_id"]
            client_ts = item["completed_at"]
            if lid not in existing_lessons:
                cur.execute(
                    """
                    INSERT INTO lesson_progress (uid, lesson_id, completed_at)
                    VALUES (?, ?, ?);
                    """,
                    (uid, lid, client_ts),
                )
                existing_lessons[lid] = client_ts
            elif client_ts > existing_lessons[lid]:
                cur.execute(
                    """
                    UPDATE lesson_progress
                    SET completed_at = ?
                    WHERE uid = ? AND lesson_id = ?;
                    """,
                    (client_ts, uid, lid),
                )
                existing_lessons[lid] = client_ts

        conn.commit()

    return get_user_sync_data(uid)


# ============================================================================
# AGGREGATE STATS, TRENDS & ALERTS
# ============================================================================


def _parse_ts(ts: str) -> Optional[datetime.datetime]:
    try:
        t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None
    return t if t.tzinfo else t.replace(tzinfo=datetime.timezone.utc)


def _rows(source: str) -> List[sqlite3.Row]:
    with get_db_connection() as conn:
        return conn.execute(
            "SELECT district, type, ts FROM reports WHERE source = ?;", (source,)
        ).fetchall()


def _ranked(counts: Dict[str, int], min_count: int) -> List[Dict[str, Any]]:
    return [
        {"key": k, "count": c}
        for k, c in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
        if c >= min_count
    ]


def summarize_source(
    source: str, now: Optional[datetime.datetime] = None, weeks: int = 12, min_count: int = MIN_CELL_COUNT
) -> Dict[str, Any]:
    """Aggregates for one source. Every count below `min_count` is suppressed (left out, or null in
    the weekly series) and only counted in `suppressed_cells`."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    rows = _rows(source)
    cells: Dict[tuple, int] = {}
    by_d: Dict[str, int] = {}
    by_t: Dict[str, int] = {}
    week_start = (now - datetime.timedelta(days=now.weekday())).date()  # Monday of this week
    starts = [week_start - datetime.timedelta(weeks=w) for w in range(weeks - 1, -1, -1)]
    weekly = {s: 0 for s in starts}
    for r in rows:
        cells[(r["district"], r["type"])] = cells.get((r["district"], r["type"]), 0) + 1
        by_d[r["district"]] = by_d.get(r["district"], 0) + 1
        by_t[r["type"]] = by_t.get(r["type"], 0) + 1
        t = _parse_ts(r["ts"])
        if t is None:
            continue
        d = t.astimezone(datetime.timezone.utc).date()
        monday = d - datetime.timedelta(days=d.weekday())
        if monday in weekly:
            weekly[monday] += 1
    suppressed = sum(1 for c in cells.values() if 0 < c < min_count)
    suppressed += sum(1 for c in weekly.values() if 0 < c < min_count)
    return {
        "total": len(rows),
        "by_district_type": [
            {"district": d, "type": t, "count": c}
            for (d, t), c in sorted(cells.items(), key=lambda kv: (kv[0][0], -kv[1], kv[0][1]))
            if c >= min_count
        ],
        "by_district": [{"district": e["key"], "count": e["count"]} for e in _ranked(by_d, min_count)],
        "by_type": [{"type": e["key"], "count": e["count"]} for e in _ranked(by_t, min_count)],
        "weekly": [
            {"week_start": s.isoformat(), "count": (c if c == 0 or c >= min_count else None)}
            for s, c in weekly.items()
        ],
        "suppressed_cells": suppressed,
    }


def get_trend_summary(now: Optional[datetime.datetime] = None, weeks: int = 12) -> Dict[str, Any]:
    """Synthetic (seeded demo) and live (user) data, kept apart and labelled."""
    return {
        "min_count": MIN_CELL_COUNT,
        "synthetic": summarize_source(SOURCE_SEED, now, weeks),
        "live": summarize_source(SOURCE_USER, now, weeks),
    }


def get_spike_alerts(
    now: Optional[datetime.datetime] = None,
    window_days: int = 7,
    baseline_weeks: int = 4,
    min_count: int = MIN_CELL_COUNT,
    ratio: float = 2.0,
    include_synthetic: bool = False,
) -> List[Dict[str, Any]]:
    """Emerging scams: a district/type whose reports in the last `window_days` reach `min_count` and are at
    least `ratio` times its weekly average over the `baseline_weeks` weeks before that."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    recent_from = now - datetime.timedelta(days=window_days)
    base_from = recent_from - datetime.timedelta(weeks=baseline_weeks)
    rows = _rows(SOURCE_USER) + (_rows(SOURCE_SEED) if include_synthetic else [])
    recent: Dict[tuple, int] = {}
    base: Dict[tuple, int] = {}
    for r in rows:
        t = _parse_ts(r["ts"])
        if t is None or t > now:
            continue
        k = (r["district"], r["type"])
        if t >= recent_from:
            recent[k] = recent.get(k, 0) + 1
        elif t >= base_from:
            base[k] = base.get(k, 0) + 1
    alerts = []
    for (district, rtype), n in recent.items():
        weekly_base = base.get((district, rtype), 0) / baseline_weeks
        if n >= min_count and n >= ratio * max(weekly_base, 1.0):
            alerts.append({
                "kind": "spike",
                "district": district,
                "type": rtype,
                "recent": n,
                "baseline_weekly": round(weekly_base, 2),
                "ratio": round(n / max(weekly_base, 1.0), 2),
            })
    alerts.sort(key=lambda a: (-a["ratio"], -a["recent"], a["district"], a["type"]))
    return alerts


def add_fingerprint(fp: str, category: str, ts: Optional[str] = None) -> int:
    """Stores one anonymous, opt-in 64-bit SimHash of a scam message (never the text)."""
    ts = ts or datetime.datetime.now(datetime.timezone.utc).isoformat()
    with get_db_connection() as conn:
        cur = conn.execute(
            "INSERT INTO fingerprints (fp, category, ts) VALUES (?, ?, ?);", (fp.lower(), category, ts)
        )
        conn.commit()
        return cur.lastrowid or 0


def get_cluster_alerts(
    now: Optional[datetime.datetime] = None,
    window_days: int = 7,
    max_distance: int = 6,
    min_size: int = MIN_CELL_COUNT,
) -> List[Dict[str, Any]]:
    """Groups recent fingerprints whose SimHashes differ in at most `max_distance` bits (greedy, oldest
    first). A group of at least `min_size` means many people received a near-identical scam message."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    since = now - datetime.timedelta(days=window_days)
    with get_db_connection() as conn:
        rows = conn.execute("SELECT fp, category, ts FROM fingerprints ORDER BY ts ASC;").fetchall()
    items = []
    for r in rows:
        t = _parse_ts(r["ts"])
        if t is None or t < since or t > now:
            continue
        try:
            items.append((int(r["fp"], 16), r["category"], t))
        except ValueError:
            continue
    clusters: List[Dict[str, Any]] = []
    for fp, cat, t in items:
        for c in clusters:
            if bin(fp ^ c["center"]).count("1") <= max_distance:
                c["size"] += 1
                c["categories"][cat] = c["categories"].get(cat, 0) + 1
                c["last"] = t
                break
        else:
            clusters.append({"center": fp, "size": 1, "categories": {cat: 1}, "first": t, "last": t})
    alerts = []
    for c in clusters:
        if c["size"] >= min_size:
            top = sorted(c["categories"].items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
            alerts.append({
                "kind": "cluster",
                "category": top,
                "size": c["size"],
                "first_seen": c["first"].isoformat(),
                "last_seen": c["last"].isoformat(),
            })
    alerts.sort(key=lambda a: -a["size"])
    return alerts


def get_trends() -> List[Dict[str, Any]]:
    """Returns aggregated fraud trends per district and fraud type."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT district, type, COUNT(*) AS count
            FROM reports
            GROUP BY district, type
            ORDER BY district ASC, count DESC;
            """
        )
        rows = cursor.fetchall()
        return [
            {
                "district": row["district"],
                "type": row["type"],
                "count": int(row["count"]),
            }
            for row in rows
        ]


def get_reports_count() -> int:
    """Returns total number of reports in the database."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) AS cnt FROM reports;")
        row = cursor.fetchone()
        return int(row["cnt"]) if row else 0
