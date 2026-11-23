# ScamRakshak Backend

Python FastAPI backend providing speech transcription using `faster-whisper`, fraud incident report storage, and district-level fraud trend analytics for the ScamRakshak Android application.

---

## Features
- **Speech-to-Text Transcription (`POST /transcribe`)**: High-performance local speech recognition using `faster-whisper` (`base` model, CPU, `int8` quantization) with automatic language detection (Hindi `hi`, English `en`, and other Indian languages). Supports `wav`, `mp3`, `m4a`, and `ogg`.
- **Incident Reporting (`POST /reports`)**: Validates and saves scam reports (`otp`, `fake_qr`, `loan_app`, `call`, `other`) into an SQLite database (`backend/data.db`).
- **District Trends (`GET /trends`)**: Computes real-time fraud aggregations grouped by district and scam type.
- **Initial Dataset**: Pre-seeds exactly 300 realistic, anonymized fraud reports across 10 major Chhattisgarh districts on first launch.
- **Cross-Origin Resource Sharing (CORS)**: Enabled to allow seamless communication with Android emulators, LAN physical devices, and web tools.

---

## Prerequisites
- **Python**: 3.10, 3.11, 3.12, or 3.13
- **FFmpeg**: Required by `faster-whisper` and audio decoders (available via system PATH).

---

## Setup Instructions

### 1. Navigate to the backend directory
```bash
cd backend
```

### 2. Create and Activate a Virtual Environment
#### On Windows (PowerShell):
```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
```

*(If PowerShell blocks script execution, run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`)*

#### On Windows (Command Prompt `cmd`):
```cmd
python -m venv venv
venv\Scripts\activate.bat
```

#### On Linux / macOS:
```bash
python3 -m venv venv
source venv/bin/activate
```

### 3. Install Dependencies
```bash
pip install -r requirements.txt
```

---

## Running the Server

Start the server using `uvicorn` listening on all interfaces (`0.0.0.0`) on port `8000`:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

Alternatively, you can run the application directly with Python:
```bash
python main.py
```

Upon startup:
1. SQLite database `backend/data.db` is initialized.
2. If empty, exactly 300 realistic fraud reports across Chhattisgarh districts are seeded.
3. The `faster-whisper` model is loaded once into memory on CPU with `int8` quantization.
   The size comes from the `WHISPER_MODEL` environment variable (default `small`, about 460 MB,
   downloaded on first start). `base` is faster but turns Hindi speech into text the scam rules
   cannot read, so Live Call Guard needs `small`. Compare speeds with `python bench.py some_call.mp3`.

Live Call Guard sends 6-second chunks to `POST /transcribe?lang=hi|en|auto`. Run
`python -m unittest test_live_transcribe -v` to check transcription on the bundled demo clips.

---

## Finding Laptop IP for Android Phone Connection

To connect the ScamRakshak Android app to this backend:

### 1. Find Your Laptop's Local IP Address

#### Windows (PowerShell or CMD):
```powershell
ipconfig
```
- Look for your active network connection:
  - Wi-Fi: **Wireless LAN adapter Wi-Fi** -> `IPv4 Address: 192.168.x.x`
  - Ethernet: **Ethernet adapter Ethernet** -> `IPv4 Address: 192.168.x.x`

#### macOS:
```bash
ipconfig getifaddr en0
```

#### Linux:
```bash
hostname -I
```

### 2. Configure ScamRakshak App

- **Android Studio Emulator**:
  - The emulator accesses the host machine via the special loopback alias:
    ```
    http://10.0.2.2:8000
    ```
- **Physical Android Phone**:
  - Connect your phone and laptop to the **same Wi-Fi network**.
  - Use your laptop's IPv4 address:
    ```
    http://<LAPTOP_IP>:8000
    ```
    *(Example: `http://192.168.1.45:8000`)*
  - In the app open **Live Call Guard**, turn Demo mode off, tap **Change address**, enter this URL
    and tap **Save and test**. The address is saved and also used by Check Call, Report and Scam Trends.

> **Windows Firewall Tip**: If the phone cannot reach the backend, allow port 8000 through Windows Defender Firewall:
> ```powershell
> New-NetFirewallRule -DisplayName "ScamRakshak Backend Port 8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow
> ```

---

## API Endpoints & Specifications

### 1. Health Check
- **Method**: `GET /health`
- **Response**:
```json
{
  "status": "ok",
  "model_loaded": true,
  "reports_count": 300
}
```

### 2. Audio Transcription
- **Method**: `POST /transcribe`
- **Content-Type**: `multipart/form-data`
- **Field**: `file` (supports `.wav`, `.mp3`, `.m4a`, `.ogg`)
- **Response**:
```json
{
  "text": "This is scam rock shack security alert. Do not share your bank OTP with anyone.",
  "lang": "en"
}
```

### 3. Submit Fraud Report
- **Method**: `POST /reports`
- **Content-Type**: `application/json`
- **Payload**:
```json
{
  "type": "otp",
  "district": "Raipur",
  "ts": "2026-11-23T02:00:00Z"
}
```
*(Types: `otp`, `fake_qr`, `loan_app`, `call`, `other`)*
- **Response**:
```json
{
  "status": "success",
  "id": 301
}
```

### 4. District Trends
- **Method**: `GET /trends`
- **Response**:
```json
[
  {
    "district": "Raipur",
    "type": "otp",
    "count": 24
  },
  {
    "district": "Raipur",
    "type": "fake_qr",
    "count": 16
  },
  {
    "district": "Durg",
    "type": "fake_qr",
    "count": 15
  }
]
```

---

## Testing with cURL

### Health Check
```bash
curl http://127.0.0.1:8000/health
```

### Transcription Test
```bash
curl -X POST http://127.0.0.1:8000/transcribe -F "file=@sample.wav"
```

### Submit Report
```bash
curl -X POST http://127.0.0.1:8000/reports \
     -H "Content-Type: application/json" \
     -d "{\"type\": \"otp\", \"district\": \"Raipur\", \"ts\": \"2026-11-23T02:00:00Z\"}"
```

### Get Trends
```bash
curl http://127.0.0.1:8000/trends
```
