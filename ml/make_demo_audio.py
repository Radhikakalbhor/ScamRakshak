"""Make the Live Call Guard demo audio with gTTS (needs internet once; the app plays it offline).

For every script in assets/samples/live/*.txt (one ~6 s chunk per line):
  - assets/samples/live/audio/<script>_<NN>.mp3  one clip per line, bundled in the app.
    Devanagari lines use the Hindi voice, other lines the Indian-English voice, so each clip
    says exactly the text that Demo mode shows.
  - ml/demo_audio/<script>.mp3  the whole call in one file (play it near the phone to test
    microphone mode, or feed it to backend/bench.py).

Exits quietly (code 0) when gTTS is missing or there is no internet.

    pip install gTTS && python ml/make_demo_audio.py
"""

from __future__ import annotations

import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "samples" / "live"
CLIPS = SRC / "audio"
OUT = Path(__file__).resolve().parent / "demo_audio"
DEVANAGARI = re.compile(r"[ऀ-ॿ]")


def voice(line: str) -> dict:
    return {"lang": "hi"} if DEVANAGARI.search(line) else {"lang": "en", "tld": "co.in"}


def main() -> int:
    try:
        from gtts import gTTS
    except ImportError:
        print("gTTS not installed (pip install gTTS); skipping.")
        return 0
    CLIPS.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(exist_ok=True)
    for txt in sorted(SRC.glob("*.txt")):
        name = txt.stem
        lines = [l.strip() for l in txt.read_text(encoding="utf-8").splitlines() if l.strip()]
        whole = bytearray()
        for i, line in enumerate(lines, 1):
            buf = io.BytesIO()
            try:
                gTTS(line, slow=False, **voice(line)).write_to_fp(buf)
            except Exception as exc:  # no internet / blocked
                print(f"Could not reach gTTS ({exc.__class__.__name__}: {exc}); skipping.")
                return 0
            clip = CLIPS / f"{name}_{i:02d}.mp3"
            clip.write_bytes(buf.getvalue())
            whole += buf.getvalue()  # MP3 frames can be concatenated
        (OUT / f"{name}.mp3").write_bytes(bytes(whole))
        print(f"{name}: {len(lines)} clips, {len(whole) // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
