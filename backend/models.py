"""Pydantic schemas and models for ScamRakshak backend API."""

from __future__ import annotations

from typing import Literal, Optional
from pydantic import BaseModel, Field

# Valid report types as strictly defined in AGENTS.md
ReportType = Literal["otp", "fake_qr", "loan_app", "call", "other"]


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
