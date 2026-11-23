"""Database module for ScamRakshak backend.

Handles SQLite connection, schema initialization, report storage,
trend aggregation, and initial seeding of realistic Chhattisgarh fraud data.
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
    """Creates a connection to the SQLite database."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def init_db(force_reseed: bool = False) -> None:
    """Initializes tables and seeds initial 300 realistic reports if database is empty or force_reseed=True."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with get_db_connection() as conn:
        cursor = conn.cursor()
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
    records: List[tuple[str, str, str]] = []

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
    """Inserts a new user report (type, district, time only) into the database."""
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
