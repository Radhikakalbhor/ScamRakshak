"""Full integration verification script using curl.exe against live ScamRakshak FastAPI server."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

BACKEND_DIR = Path(__file__).resolve().parent
SAMPLE_WAV = BACKEND_DIR / "sample.wav"

if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import uvicorn
from main import app


def run_tests():
    config = uvicorn.Config(
        app,
        host="127.0.0.1",
        port=8000,
        log_level="info",
    )
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()

    print("[INFO] Waiting for uvicorn server to start...")
    for _ in range(30):
        time.sleep(1)
        if server.started:
            break

    if not server.started:
        print("[ERROR] Server did not start within timeout.")
        server.should_exit = True
        sys.exit(1)

    print("[SUCCESS] Server is running on http://127.0.0.1:8000\n")

    try:
        # 1. Test GET /health
        print("=" * 65)
        print("1. TEST: GET /health")
        print("=" * 65)
        cmd_health = ["curl.exe", "-s", "-i", "http://127.0.0.1:8000/health"]
        print("Command:", " ".join(cmd_health))
        res_health = subprocess.run(cmd_health, capture_output=True, text=True)
        print(res_health.stdout)
        assert "200 OK" in res_health.stdout, "GET /health failed"
        assert '"status":"ok"' in res_health.stdout or '"status": "ok"' in res_health.stdout
        assert '"reports_count":300' in res_health.stdout or '"reports_count": 300' in res_health.stdout

        # 2. Test POST /reports (Valid payload)
        print("=" * 65)
        print("2. TEST: POST /reports (Valid payload)")
        print("=" * 65)
        report_data = json.dumps({
            "type": "otp",
            "district": "Raipur",
            "ts": "2026-11-23T02:30:00Z"
        })
        cmd_report = [
            "curl.exe",
            "-s",
            "-i",
            "-X", "POST",
            "http://127.0.0.1:8000/reports",
            "-H", "Content-Type: application/json",
            "-d", report_data
        ]
        print("Command:", " ".join(cmd_report))
        res_report = subprocess.run(cmd_report, capture_output=True, text=True)
        print(res_report.stdout)
        assert "201 Created" in res_report.stdout, "POST /reports failed"
        assert '"status":"success"' in res_report.stdout or '"status": "success"' in res_report.stdout

        # 3. Test POST /reports (Invalid fraud type)
        print("=" * 65)
        print("3. TEST: POST /reports (Invalid type validation)")
        print("=" * 65)
        invalid_report_data = json.dumps({
            "type": "unsupported_crypto_scam",
            "district": "Raipur",
        })
        cmd_invalid_report = [
            "curl.exe",
            "-s",
            "-i",
            "-X", "POST",
            "http://127.0.0.1:8000/reports",
            "-H", "Content-Type: application/json",
            "-d", invalid_report_data
        ]
        print("Command:", " ".join(cmd_invalid_report))
        res_invalid_report = subprocess.run(cmd_invalid_report, capture_output=True, text=True)
        print(res_invalid_report.stdout)
        assert "422 Unprocessable" in res_invalid_report.stdout or "422" in res_invalid_report.stdout, "Expected 422 for invalid type"

        # 4. Test GET /trends
        print("=" * 65)
        print("4. TEST: GET /trends")
        print("=" * 65)
        cmd_trends = ["curl.exe", "-s", "http://127.0.0.1:8000/trends"]
        print("Command:", " ".join(cmd_trends))
        res_trends = subprocess.run(cmd_trends, capture_output=True, text=True)
        trends_json = json.loads(res_trends.stdout)
        print(f"Total Trend Records Grouped: {len(trends_json)}")
        print("Sample trends (first 5):")
        print(json.dumps(trends_json[:5], indent=2))
        assert len(trends_json) > 0, "No trends returned"
        assert "district" in trends_json[0]
        assert "type" in trends_json[0]
        assert "count" in trends_json[0]

        # 5. Test POST /transcribe with sample.wav (genuine speech)
        print("=" * 65)
        print("5. TEST: POST /transcribe (genuine speech in sample.wav)")
        print("=" * 65)
        cmd_transcribe = [
            "curl.exe",
            "-s",
            "-i",
            "-X", "POST",
            "http://127.0.0.1:8000/transcribe",
            "-F", f"file=@{SAMPLE_WAV}"
        ]
        print("Command:", " ".join(cmd_transcribe))
        res_transcribe = subprocess.run(cmd_transcribe, capture_output=True, text=True)
        print(res_transcribe.stdout)
        assert "200 OK" in res_transcribe.stdout, "POST /transcribe failed"
        assert '"text"' in res_transcribe.stdout
        assert '"lang"' in res_transcribe.stdout
        # Extract transcribed text and verify meaningful speech content
        body_line = [line for line in res_transcribe.stdout.splitlines() if line.startswith("{")][-1]
        transcribe_json = json.loads(body_line)
        print(f"[VERIFIED TRANSCRIPTION] text='{transcribe_json['text']}', lang='{transcribe_json['lang']}'")
        assert len(transcribe_json["text"].strip()) > 10, "Transcription should contain full recognized speech"

        # 6. Test POST /transcribe with invalid file format
        print("=" * 65)
        print("6. TEST: POST /transcribe (Invalid file type rejected)")
        print("=" * 65)
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
            f.write(b"this is plain text not audio")
            invalid_file = Path(f.name)

        try:
            cmd_invalid_transcribe = [
                "curl.exe",
                "-s",
                "-i",
                "-X", "POST",
                "http://127.0.0.1:8000/transcribe",
                "-F", f"file=@{invalid_file}"
            ]
            print("Command:", " ".join(cmd_invalid_transcribe))
            res_invalid_transcribe = subprocess.run(cmd_invalid_transcribe, capture_output=True, text=True)
            print(res_invalid_transcribe.stdout)
            assert "400 Bad Request" in res_invalid_transcribe.stdout or "400" in res_invalid_transcribe.stdout
        finally:
            invalid_file.unlink(missing_ok=True)

        print("\n" + "=" * 65)
        print("ALL FASTAPI BACKEND CONTRACTS VERIFIED AND PASSING!")
        print("=" * 65)

    finally:
        print("\n[INFO] Shutting down uvicorn server...")
        server.should_exit = True
        thread.join(timeout=5)
        print("[INFO] Server stopped.")


if __name__ == "__main__":
    run_tests()
