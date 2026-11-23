"""Benchmark faster-whisper on live-call sized chunks.

Cuts AUDIO into 6 s pieces (16 kHz mono) and prints seconds per chunk for tiny/base/small,
using the same settings as POST /transcribe (beam_size=1, vad_filter=True,
condition_on_previous_text=False, CPU int8).

Usage:
    python bench.py path/to/call.mp3 [--lang hi|en|auto] [--models tiny,base,small] [--chunk 6]
"""

from __future__ import annotations

import argparse
import statistics
import time

import av

# Same PyAV compatibility fix as main.py (faster-whisper passes an argument newer PyAV removed).
_av_open = av.open


def _safe_av_open(*args, **kwargs):
    kwargs.pop("metadata_errors", None)
    return _av_open(*args, **kwargs)


av.open = _safe_av_open

from faster_whisper import WhisperModel, decode_audio  # noqa: E402

SR = 16000


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("audio")
    ap.add_argument("--lang", default="auto", choices=["hi", "en", "auto"])
    ap.add_argument("--models", default="tiny,base,small")
    ap.add_argument("--chunk", type=float, default=6.0, help="chunk length in seconds")
    args = ap.parse_args()

    audio = decode_audio(args.audio, sampling_rate=SR)
    step = int(args.chunk * SR)
    chunks = [audio[i : i + step] for i in range(0, len(audio), step)]
    chunks = [c for c in chunks if len(c) > SR // 2]  # drop a tail shorter than 0.5 s
    print(f"{args.audio}: {len(audio) / SR:.1f} s -> {len(chunks)} chunks of {args.chunk:g} s")
    hint = None if args.lang == "auto" else args.lang

    for name in [m.strip() for m in args.models.split(",") if m.strip()]:
        t0 = time.perf_counter()
        model = WhisperModel(name, device="cpu", compute_type="int8")
        load_s = time.perf_counter() - t0
        times = []
        for i, c in enumerate(chunks):
            t = time.perf_counter()
            segs, _ = model.transcribe(
                c, language=hint, beam_size=1, vad_filter=True, condition_on_previous_text=False
            )
            text = " ".join(s.text.strip() for s in segs).strip()
            times.append(time.perf_counter() - t)
            print(f"  [{name}] chunk {i + 1:>3}: {times[-1]:5.2f} s  {text[:70]}")
        if times:
            rt = statistics.mean(times) / args.chunk
            print(
                f"{name}: load {load_s:.1f} s, mean {statistics.mean(times):.2f} s/chunk, "
                f"max {max(times):.2f} s, real-time factor {rt:.2f} ({'OK' if rt < 1 else 'too slow'} for live)"
            )
        del model


if __name__ == "__main__":
    main()
