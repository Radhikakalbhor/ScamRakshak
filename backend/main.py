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

from fastapi import FastAPI, File, HTTPException, Query, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from faster_whisper import WhisperModel
import uvicorn

from database import (
    CHHATTISGARH_DISTRICTS,
    FINGERPRINT_CATEGORIES,
    REPORT_TYPES,
    add_fingerprint,
    canonical_district,
    create_report,
    get_cluster_alerts,
    get_reports_count,
    get_spike_alerts,
    get_trend_summary,
    get_trends,
    init_db,
)
from models import (
    FingerprintCreate,
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

# Model size from env (tiny|base|small|...); see bench.py for per-chunk speed.
# 'base' is faster but writes Hindi speech as garbled text the scam rules cannot read (see
# test_live_transcribe.py); 'small' (~2 s per 6 s chunk on a laptop CPU) is the default for Live Call Guard.
WHISPER_MODEL_NAME = os.environ.get("WHISPER_MODEL", "small").strip() or "small"

# Steers Whisper to write Hindi in Devanagari (the script used by assets/rules/call_rules.json).
HINDI_PROMPT = "यह एक फ़ोन कॉल है। बातचीत हिंदी में है, देवनागरी लिपि में लिखें।"

# Optional ?lang= values accepted by /transcribe ("auto" = detect).
TRANSCRIBE_LANGS = {"hi", "en", "auto"}

# Audio formats phone call recorders produce (decoded by PyAV/FFmpeg, including AMR-NB/WB and 3GP).
SUPPORTED_AUDIO_EXTENSIONS = {
    ".wav",
    ".mp3",
    ".m4a",
    ".ogg",
    ".amr",
    ".aac",
    ".3gp",
    ".opus",
    ".flac",
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

    logger.info("Loading faster-whisper '%s' model on CPU (int8)...", WHISPER_MODEL_NAME)
    try:
        whisper_model = WhisperModel(WHISPER_MODEL_NAME, device="cpu", compute_type="int8")
        logger.info("faster-whisper '%s' model loaded successfully.", WHISPER_MODEL_NAME)
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
    lang: str = Query("auto", description="Language hint: hi, en or auto (detect)"),
) -> TranscribeResponse:
    """Transcribes an audio recording with faster-whisper (CPU int8), tuned for 5-6 s live chunks.

    beam_size=1, VAD filter on, no conditioning on previous text. A silent chunk returns
    {"text": "", "lang": ...} instead of an error.
    Returns:
        {"text": "...", "lang": "hi"}
    """
    lang = (lang or "auto").strip().lower()
    if lang not in TRANSCRIBE_LANGS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported lang '{lang}'. Use one of: hi, en, auto",
        )
    hint = None if lang == "auto" else lang

    # Validate file extension (before the model check, so a wrong file is always a clear 400)
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

    if whisper_model is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Whisper transcription model is not ready.",
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

        if os.path.getsize(temp_path) == 0:
            return TranscribeResponse(text="", lang=hint or "en")

        try:
            segment_list, info = _run_whisper(temp_path, hint)
            detected_language = hint or (info.language if (info and info.language) else "en")
            # Whisper often labels Hindi speech as Urdu and then writes Urdu script, which the
            # app's Devanagari/English rules cannot read: redo such chunks as Hindi.
            if hint is None and detected_language in ("hi", "ur") and segment_list:
                segment_list, info = _run_whisper(temp_path, "hi")
                detected_language = "hi"
        except Exception as exc:
            # VAD can leave nothing to decode (silence); that is an empty chunk, not an error.
            if _is_silence_error(exc):
                logger.info("Silent chunk '%s' (%s)", filename, exc)
                return TranscribeResponse(text="", lang=hint or "en")
            raise

        transcript_text = " ".join(_clean_segments(segment_list)).strip()

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


def _run_whisper(path: str, language: Optional[str]):
    """Live-chunk settings. Hindi gets a Devanagari prompt, otherwise small models write Urdu/Latin script."""
    kwargs: Dict[str, Any] = dict(beam_size=1, vad_filter=True, condition_on_previous_text=False)
    if language == "hi":
        kwargs["initial_prompt"] = HINDI_PROMPT
    segments, info = whisper_model.transcribe(path, language=language, **kwargs)
    return list(segments), info


def _clean_segments(segments) -> List[str]:
    """Drops likely non-speech segments and echoes of the prompt."""
    out = []
    for seg in segments:
        text = seg.text.strip()
        if not text or text in HINDI_PROMPT:
            continue
        if getattr(seg, "no_speech_prob", 0.0) > 0.6 and getattr(seg, "avg_logprob", 0.0) < -1.0:
            continue
        out.append(text)
    return out


def _is_silence_error(exc: Exception) -> bool:
    """True for the errors faster-whisper raises when a chunk has no speech left after VAD."""
    msg = str(exc).lower()
    return isinstance(exc, (ValueError, IndexError, RuntimeError)) and any(
        k in msg for k in ("empty", "zero", "out of range", "no speech", "size 0", "0 elements")
    )


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
    # Only known district names (or "unknown"): no free text, so no personal data, can be stored.
    known = canonical_district(clean_district)
    if known is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Unknown district. Use a Chhattisgarh district name or 'unknown'.",
        )
    clean_district = known

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


@app.get("/trends/summary", tags=["Trends"], summary="Synthetic vs live report aggregates with a weekly trend")
async def get_trends_summary() -> Dict[str, Any]:
    """{"min_count": 5, "synthetic": {...}, "live": {...}}; each part has total, by_district_type,
    by_district, by_type, weekly (12 weeks, Monday start) and suppressed_cells. Counts below 5 are hidden."""
    try:
        return get_trend_summary()
    except Exception as exc:
        logger.error("Failed to build trend summary: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to load fraud trends.") from exc


@app.get("/alerts", tags=["Trends"], summary="Emerging-scam alerts")
async def get_alerts(include_synthetic: bool = Query(False)) -> Dict[str, Any]:
    """Spikes per district/type (last 7 days vs the 4 weeks before) on live reports, plus clusters of
    near-identical opt-in message fingerprints. {"window_days": 7, "alerts": [...]}"""
    try:
        alerts = get_spike_alerts(include_synthetic=include_synthetic) + get_cluster_alerts()
        return {"window_days": 7, "alerts": alerts}
    except Exception as exc:
        logger.error("Failed to compute alerts: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to compute alerts.") from exc


@app.post("/fingerprints", status_code=status.HTTP_201_CREATED, tags=["Trends"],
          summary="Opt-in anonymous fingerprint of a scam message")
async def post_fingerprint(payload: FingerprintCreate) -> Dict[str, Any]:
    if payload.category not in FINGERPRINT_CATEGORIES:
        raise HTTPException(status_code=422, detail="Unknown category.")
    return {"status": "success", "id": add_fingerprint(payload.fp, payload.category)}


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
