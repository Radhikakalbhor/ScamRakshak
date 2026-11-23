"""Live Call Guard checks for POST /transcribe (runs the real faster-whisper model, no network server).

    cd backend
    venv\\Scripts\\python -m unittest test_live_transcribe -v
    venv\\Scripts\\python test_live_transcribe.py --dump   # also writes real Whisper transcripts
                                                           # of the demo clips to test/engine/fixtures/whisper/
"""

from __future__ import annotations

import io
import os
import sys
import unittest
import wave
from pathlib import Path

BACKEND = Path(__file__).resolve().parent
ROOT = BACKEND.parent
CLIPS = ROOT / "assets" / "samples" / "live" / "audio"
FIXTURES = ROOT / "test" / "engine" / "fixtures" / "whisper"
sys.path.insert(0, str(BACKEND))

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402


def wav_bytes(seconds: float, rate: int = 16000) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x00\x00" * int(seconds * rate))
    return buf.getvalue()


class TranscribeLiveTest(unittest.TestCase):
    client: TestClient

    @classmethod
    def setUpClass(cls):
        cls._ctx = TestClient(main.app)
        cls.client = cls._ctx.__enter__()  # runs lifespan: loads the model once

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def post(self, data: bytes, name: str, lang: str | None = None):
        params = {"lang": lang} if lang else None
        return self.client.post("/transcribe", params=params, files={"file": (name, data, "application/octet-stream")})

    def test_health(self):
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["model_loaded"])

    def test_silent_chunk_is_empty_text_not_error(self):
        for lang in (None, "auto", "hi", "en"):
            r = self.post(wav_bytes(6), "silence.wav", lang)
            self.assertEqual(r.status_code, 200, r.text)
            self.assertEqual(r.json()["text"], "")
            self.assertIn(r.json()["lang"], {"hi", "en"} if lang in (None, "auto") else {lang})

    def test_empty_file_is_empty_text(self):
        r = self.post(b"", "empty.wav", "hi")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json(), {"text": "", "lang": "hi"})

    def test_bad_lang_and_bad_format_are_400(self):
        self.assertEqual(self.post(wav_bytes(1), "a.wav", "fr").status_code, 400)
        self.assertEqual(self.post(wav_bytes(1), "a.txt").status_code, 400)

    def test_demo_clips_are_transcribed(self):
        cases = {
            # Small Whisper models often write Hindi speech in English words; both are fine for the rules.
            "scam_digital_arrest_04.mp3": ("hi", ["डिजिटल", "अरेस्ट", "digital arrest"]),
            "scam_fake_kyc_otp_05.mp3": ("auto", ["otp"]),
            "scam_courier_customs_02.mp3": ("en", ["parcel", "customs"]),
        }
        if main.WHISPER_MODEL_NAME in ("tiny", "base"):
            # Known limit: these sizes garble Hindi speech, so only the English clips are checked.
            cases.pop("scam_digital_arrest_04.mp3")
        for clip, (lang, words) in cases.items():
            r = self.post((CLIPS / clip).read_bytes(), clip, lang)
            self.assertEqual(r.status_code, 200, r.text)
            text = r.json()["text"].lower()
            print(f"  {clip} [{lang}] -> {text}")
            self.assertTrue(any(w.lower() in text for w in words), f"{clip}: {text!r}")


def dump() -> None:
    """Writes Whisper's transcript of every demo clip (one line per clip) for the Dart engine test."""
    (FIXTURES / main.WHISPER_MODEL_NAME).mkdir(parents=True, exist_ok=True)
    with TestClient(main.app) as c:
        for script in sorted({p.stem.rsplit("_", 1)[0] for p in CLIPS.glob("*.mp3")}):
            lines = []
            for clip in sorted(CLIPS.glob(f"{script}_*.mp3")):
                src = (ROOT / "assets" / "samples" / "live" / f"{script}.txt").read_text(encoding="utf-8")
                n = int(clip.stem.rsplit("_", 1)[1])
                spoken = [l for l in src.splitlines() if l.strip()][n - 1]
                lang = "hi" if any("ऀ" <= ch <= "ॿ" for ch in spoken) else "en"
                r = c.post("/transcribe", params={"lang": lang}, files={"file": (clip.name, clip.read_bytes())})
                r.raise_for_status()
                lines.append(r.json()["text"].replace("\n", " ").strip())
            (FIXTURES / main.WHISPER_MODEL_NAME / f"{script}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
            print(f"{script}: model={main.WHISPER_MODEL_NAME}")
            for l in lines:
                print("   ", l)


if __name__ == "__main__":
    if "--dump" in sys.argv:
        dump()
    else:
        unittest.main(verbosity=2)
