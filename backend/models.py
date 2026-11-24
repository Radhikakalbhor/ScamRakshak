"""Pydantic schemas and models for ScamRakshak backend API."""

from __future__ import annotations

import datetime
from typing import List, Literal, Optional
from pydantic import BaseModel, Field, field_validator

# Valid report types as strictly defined in AGENTS.md
ReportType = Literal["otp", "fake_qr", "loan_app", "call", "other"]
AppLocale = Literal["en", "hi", "chh"]
DetectionKind = Literal["message", "qr", "call"]

# Maximum allowed items per collection in sync payload
MAX_SYNC_ITEMS = 500


def _validate_utc_iso8601_str(v: str) -> str:
    """Validates that a string is a valid UTC ISO-8601 timestamp ending in 'Z' or '+00:00'."""
    if not isinstance(v, str):
        raise ValueError("Timestamp must be a string")
    s = v.strip()
    if not (s.endswith("Z") or s.endswith("+00:00") or s.endswith("-00:00")):
        raise ValueError("Timestamp must be a UTC ISO-8601 string ending in 'Z' or '+00:00'")
    try:
        dt = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception as exc:
        raise ValueError(f"Malformed ISO-8601 timestamp: {exc}")
    if dt.tzinfo is None or dt.utcoffset() != datetime.timedelta(0):
        raise ValueError("Timestamp must be in UTC timezone (+00:00)")
    return s


class ReportCreate(BaseModel):
    """Schema for submitting a fraud incident report.

    Contract in AGENTS.md:
    POST /reports {"type": "otp|fake_qr|loan_app|call|other", "district": "...", "ts": "..."}
    """

    type: ReportType = Field(
        ...,
        description="Type of fraud: otp | fake_qr | loan_app | call | other",
        examples=["otp"],
    )
    district: str = Field(
        ...,
        min_length=1,
        description="District name in Chhattisgarh",
        examples=["Raipur"],
    )
    ts: Optional[str] = Field(
        None,
        description="ISO 8601 timestamp string (optional, defaults to current UTC timestamp)",
        examples=["2026-11-23T02:00:00Z"],
    )


class ReportResponse(BaseModel):
    """Response returned upon successful report submission."""

    status: str = Field("success", description="Status string")
    id: int = Field(..., description="Unique report database ID")
    user_report: Optional[str] = Field(
        None, description="'recorded', 'skipped', or 'anonymous'"
    )
    user_report_skipped: Optional[bool] = Field(
        None,
        description="True if a token was provided but invalid/expired, skipping user_reports",
    )


class TrendItem(BaseModel):
    """Schema for a single district fraud trend entry.

    Contract in AGENTS.md:
    GET /trends -> [{"district": "...", "type": "...", "count": 12}]
    """

    district: str = Field(..., description="Chhattisgarh district name")
    type: str = Field(..., description="Fraud category: otp, fake_qr, loan_app, call, other")
    count: int = Field(..., description="Total aggregated report count")


class TranscribeResponse(BaseModel):
    """Response returned from speech transcription endpoint.

    Contract in AGENTS.md:
    POST /transcribe -> {"text": "...", "lang": "hi"}
    """

    text: str = Field(..., description="Recognized speech text")
    lang: str = Field(..., description="Detected language code (e.g., 'hi' or 'en')")


class HealthResponse(BaseModel):
    """Response schema for server health check."""

    status: str = Field("ok", description="Server health status")
    model_loaded: bool = Field(..., description="Whether Whisper model is loaded")
    reports_count: int = Field(..., description="Current count of fraud reports in SQLite")


class FingerprintCreate(BaseModel):
    """Schema for submitting an anonymous 16-hex SimHash fingerprint of a scam message."""

    fp: str = Field(..., min_length=16, max_length=16, description="16-character hex string of 64-bit SimHash")
    category: str = Field(..., description="Scam category label")


# ============================================================================
# USER AUTHENTICATION, PROFILE & SYNC SCHEMAS
# ============================================================================


class SessionCreate(BaseModel):
    """Request payload for POST /auth/session.

    Username is submitted on sign-in (stored on first registration only).
    Locale sets initial language on first registration (default: 'en').
    Verified phone number and UID are extracted strictly from Bearer token.
    """

    username: str = Field(..., min_length=1, max_length=50, description="Display name for user")
    locale: AppLocale = Field("en", description="Current app locale: en | hi | chh")


class UserProfileResponse(BaseModel):
    """Response returned for user profile endpoints.

    Phone number is read-only / immutable.
    """

    uid: str = Field(..., description="Firebase UID")
    phone: str = Field(..., description="Verified phone number (immutable)")
    username: str = Field(..., description="User display name")
    district: str = Field(..., description="District in Chhattisgarh or 'unknown'")
    language: str = Field(..., description="Preferred language code ('en', 'hi', 'chh')")
    created_at: str = Field(..., description="ISO 8601 registration timestamp")
    updated_at: str = Field(..., description="ISO 8601 profile update timestamp")
    is_new_user: Optional[bool] = Field(None, description="Whether this login created a new account")


class ProfileUpdate(BaseModel):
    """Request payload for PUT /profile.

    Only district and language may be updated. Phone is strictly immutable.
    """

    district: Optional[str] = Field(None, min_length=1, description="Chhattisgarh district name or 'unknown'")
    language: Optional[AppLocale] = Field(None, description="Language code: en | hi | chh")


class DetectionHistoryItem(BaseModel):
    """Detection event metadata for sync.

    CRITICAL PRIVACY RULE: Stores verdict, score, category, and timestamp.
    NEVER stores raw message text or transcript.
    """

    id: Optional[int] = None
    kind: DetectionKind = Field(..., description="message | qr | call")
    verdict: str = Field(..., description="'scam' or 'genuine' or 'high'/'medium'/'low'")
    score: float = Field(..., ge=0.0, le=1.0, description="Risk probability score (0.0 to 1.0)")
    category: str = Field(..., description="Scam category or type")
    ts: str = Field(..., description="UTC ISO-8601 timestamp string (e.g. 2026-11-24T03:15:00Z)")

    @field_validator("ts")
    @classmethod
    def validate_ts(cls, v: str) -> str:
        return _validate_utc_iso8601_str(v)


class QuizProgressItem(BaseModel):
    """User progress for a single quiz topic."""

    topic: str = Field(..., description="Quiz topic identifier")
    attempts: int = Field(..., ge=0, description="Total attempts")
    correct: int = Field(..., ge=0, description="Total correct answers")
    total: int = Field(..., ge=1, description="Total questions per attempt")
    updated_at: str = Field(..., description="UTC ISO-8601 timestamp of latest attempt")

    @field_validator("updated_at")
    @classmethod
    def validate_updated_at(cls, v: str) -> str:
        return _validate_utc_iso8601_str(v)


class LessonProgressItem(BaseModel):
    """User completion status for a lesson."""

    lesson_id: str = Field(..., description="Lesson identifier")
    completed_at: str = Field(..., description="UTC ISO-8601 completion timestamp")

    @field_validator("completed_at")
    @classmethod
    def validate_completed_at(cls, v: str) -> str:
        return _validate_utc_iso8601_str(v)


class UserReportItem(BaseModel):
    """User report entry associated with the user account."""

    id: Optional[int] = None
    type: str = Field(..., description="otp | fake_qr | loan_app | call | other")
    district: str = Field(..., description="District where fraud occurred")
    ts: str = Field(..., description="UTC ISO-8601 timestamp string")

    @field_validator("ts")
    @classmethod
    def validate_ts(cls, v: str) -> str:
        return _validate_utc_iso8601_str(v)


class SyncPayload(BaseModel):
    """Full data payload for GET /sync and PUT /sync (capped at MAX_SYNC_ITEMS)."""

    detection_history: List[DetectionHistoryItem] = Field(
        default_factory=list,
        max_length=MAX_SYNC_ITEMS,
        description="Detection event records (capped at 500)",
    )
    quiz_progress: List[QuizProgressItem] = Field(
        default_factory=list,
        max_length=MAX_SYNC_ITEMS,
        description="Quiz topic progress records (capped at 500)",
    )
    lesson_progress: List[LessonProgressItem] = Field(
        default_factory=list,
        max_length=MAX_SYNC_ITEMS,
        description="Lesson progress records (capped at 500)",
    )
    user_reports: List[UserReportItem] = Field(
        default_factory=list,
        max_length=MAX_SYNC_ITEMS,
        description="User incident reports (capped at 500)",
    )


class AccountDeleteResponse(BaseModel):
    """Response returned for DELETE /account."""

    status: str = Field("success", description="Status string")
    message: str = Field(..., description="Confirmation message")
