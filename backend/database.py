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
                records.append((fraud_type, district, ts))

    cursor.executemany(
        "INSERT INTO reports (type, district, ts) VALUES (?, ?, ?);", records
    )
    return len(records)


def create_report(
    report_type: str, district: str, ts: Optional[str] = None
) -> int:
    """Inserts a new user report into the database."""
    if not ts:
        ts = datetime.datetime.now(datetime.timezone.utc).isoformat()

    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO reports (type, district, ts) VALUES (?, ?, ?);",
            (report_type.strip().lower(), district.strip(), ts),
        )
        conn.commit()
        return cursor.lastrowid or 0


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
