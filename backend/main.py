"""ScamRakshak FastAPI Backend.

Provides:
- GET /health
- POST /transcribe (multipart file upload for wav/mp3/m4a/ogg using faster-whisper base on CPU int8)
- POST /reports (submit fraud report stored in SQLite backend/data.db)
- GET /trends (district fraud trend aggregation from backend/data.db)
- CORS enabled for mobile and web clients
- Runs on 0.0.0.0:8000
"""

from __future__ import annotations

from contextlib import asynccontextmanager
import logging
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any, Dict, List, Optional

# Ensure backend directory is in sys.path
_BACKEND_DIR = Path(__file__).resolve().parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

# Compatibility fix for PyAV 14+/19+ with faster-whisper on Python 3.13:
# faster-whisper calls av.open(..., metadata_errors="ignore"), which was removed in newer av versions.
import av

_orig_av_open = av.open


def _safe_av_open(*args: Any, **kwargs: Any) -> Any:
    kwargs.pop("metadata_errors", None)
    return _orig_av_open(*args, **kwargs)


av.open = _safe_av_open  # type: ignore[assignment]

from fastapi import FastAPI, File, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from faster_whisper import WhisperModel
import uvicorn

from database import (
    CHHATTISGARH_DISTRICTS,
    REPORT_TYPES,
    create_report,
    get_reports_count,
    get_trends,
    init_db,
)
from models import (
    HealthResponse,
    ReportCreate,
    ReportResponse,
    TranscribeResponse,
    TrendItem,
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("scamrakshak.backend")

# Global WhisperModel reference loaded once at startup
whisper_model: Optional[WhisperModel] = None

# Supported audio extensions strictly per task instructions
SUPPORTED_AUDIO_EXTENSIONS = {
    ".wav",
    ".mp3",
    ".m4a",
    ".ogg",
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI lifespan event handler to load model and database once at startup."""
    global whisper_model
    logger.info("Initializing ScamRakshak database...")
    init_db()
    logger.info(
        "Database ready. Total pre-seeded reports: %d", get_reports_count()
    )

    logger.info("Loading faster-whisper 'base' model on CPU (int8)...")
    try:
        whisper_model = WhisperModel("base", device="cpu", compute_type="int8")
        logger.info("faster-whisper 'base' model loaded successfully.")
    except Exception as exc:
        logger.error("Failed to load faster-whisper model: %s", exc, exc_info=True)
        raise exc

    yield

    logger.info("Shutting down ScamRakshak backend...")
    whisper_model = None


# Initialize FastAPI App
app = FastAPI(
    title="ScamRakshak Backend API",
    description="Offline-first fraud protection backend: speech transcription, reporting, and district trends.",
    version="1.0.0",
    lifespan=lifespan,
)

# Enable CORS for all origins (Android emulator 10.0.2.2, phone on LAN, web preview)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get(
    "/health",
    response_model=HealthResponse,
    tags=["Health"],
    summary="Health check endpoint",
)
async def health_check() -> HealthResponse:
    """Returns the operational status of the service, model status, and report database count."""
    return HealthResponse(
        status="ok",
        model_loaded=(whisper_model is not None),
        reports_count=get_reports_count(),
    )


@app.post(
    "/transcribe",
    response_model=TranscribeResponse,
    tags=["Transcription"],
    summary="Transcribe audio file using faster-whisper",
)
async def transcribe_audio(
    file: UploadFile = File(
        ...,
        description="Audio file to transcribe (supported formats: wav, mp3, m4a, ogg)",
    ),
) -> TranscribeResponse:
    """Uploads an audio recording and transcribes it using faster-whisper 'base' (CPU int8).

    Auto-detects spoken language (such as Hindi 'hi' or English 'en').
    Returns:
        {"text": "...", "lang": "hi"}
    """
    if whisper_model is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Whisper transcription model is not ready.",
        )

    # Validate file extension
    filename = file.filename or "recording.wav"
    suffix = Path(filename).suffix.lower()

    if not suffix or suffix not in SUPPORTED_AUDIO_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Unsupported audio format '{suffix}'. "
                f"Supported formats: {', '.join(sorted(ext.lstrip('.') for ext in SUPPORTED_AUDIO_EXTENSIONS))}"
            ),
        )

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp_file.name

    try:
        # Write uploaded chunks to disk
        file.file.seek(0)
        shutil.copyfileobj(file.file, temp_file)
        temp_file.close()

        logger.info(
            "Transcribing audio file '%s' (temp: %s)...", filename, temp_path
        )

        # Transcribe using loaded WhisperModel (auto-detects language hi/en)
        segments, info = whisper_model.transcribe(
            temp_path,
            beam_size=5,
        )

        # Collect segment texts
        segment_list = list(segments)
        transcript_text = " ".join(seg.text.strip() for seg in segment_list).strip()
        detected_language = info.language if (info and info.language) else "en"

        logger.info(
            "Transcription completed: lang=%s, segments=%d, text_len=%d",
            detected_language,
            len(segment_list),
            len(transcript_text),
        )

        return TranscribeResponse(
            text=transcript_text,
            lang=detected_language,
        )

    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Error during audio transcription: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Transcription failed: {str(exc)}",
        ) from exc
    finally:
        # Ensure temporary file is always cleaned up
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass


@app.post(
    "/reports",
    response_model=ReportResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["Reports"],
    summary="Submit a fraud report",
)
async def post_report(payload: ReportCreate) -> ReportResponse:
    """Submits a fraud incident report.

    Contract:
    POST /reports {"type": "otp|fake_qr|loan_app|call|other", "district": "...", "ts": "..."}
    """
    clean_type = payload.type.strip().lower()
    clean_district = payload.district.strip()

    if not clean_district:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="District must not be blank.",
        )

    if clean_type not in REPORT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid report type '{clean_type}'. Allowed types: {', '.join(REPORT_TYPES)}",
        )

    try:
        report_id = create_report(
            report_type=clean_type,
            district=clean_district,
            ts=payload.ts,
        )
        logger.info(
            "Report created: id=%d, type=%s, district=%s",
            report_id,
            clean_type,
            clean_district,
        )
        return ReportResponse(status="success", id=report_id)
    except Exception as exc:
        logger.error("Failed to save report: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record report.",
        ) from exc


@app.get(
    "/trends",
    response_model=List[TrendItem],
    tags=["Trends"],
    summary="Get aggregated fraud trends by district",
)
async def get_district_trends() -> List[Dict[str, Any]]:
    """Fetches aggregated district fraud trends from backend/data.db.

    Contract:
    GET /trends -> [{"district": "...", "type": "...", "count": 12}]
    """
    try:
        trends = get_trends()
        return trends
    except Exception as exc:
        logger.error("Failed to query trends: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load fraud trends.",
        ) from exc


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
