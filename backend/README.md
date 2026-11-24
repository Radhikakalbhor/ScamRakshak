# ScamRakshak Backend

Python FastAPI backend providing speech transcription using `faster-whisper`, fraud incident report storage, and district-level fraud trend analytics for the ScamRakshak Android application.

---

## Features
- **Speech-to-Text Transcription (`POST /transcribe`)**: High-performance local speech recognition using `faster-whisper` (`base` model, CPU, `int8` quantization) with automatic language detection (Hindi `hi`, English `en`, and other Indian languages). Supports `wav`, `mp3`, `m4a`, and `ogg`.
- **Incident Reporting (`POST /reports`)**: Validates and saves scam reports (`otp`, `fake_qr`, `loan_app`, `call`, `other`) into an SQLite database (`backend/data.db`).
- **District Trends (`GET /trends`)**: Computes real-time fraud aggregations grouped by district and scam type.
- **Initial Dataset**: Pre-seeds exactly 300 realistic, anonymized fraud reports across 10 major Chhattisgarh districts on first launch.
- **Cross-Origin Resource Sharing (CORS)**: Enabled to allow seamless communication with Android emulators, LAN physical devices, and web tools.
- **Firebase Authentication & User Profiles**: Mandatory phone-number sign-in with immutable phone identity, per-user profiles (`district`, `language`), and data persistence across devices.
- **Full Offline Sync (`/sync`)**: Two-way synchronization of detection metadata (privacy-first: scores, verdicts, categories, timestamps; NO raw message text), quiz progress, lesson progress, and personal reports.
- **Account Privacy & Deletion (`DELETE /account`)**: Complete GDPR/privacy-compliant erasure of all personal data across all user tables while preserving anonymous aggregate threat trends.

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

Accepted recording formats: wav, mp3, m4a, ogg, amr, aac, 3gp, opus, flac.

Other endpoints (added; `/trends` is unchanged):
- `GET /trends/summary`: seeded "synthetic" rows and user "live" reports kept apart, per district/type,
  12-week weekly series. Counts below 5 are hidden.
- `GET /alerts`: spikes (a district and type with at least 5 live reports in the last 7 days and at least 2x the
  weekly average of the 4 weeks before) and clusters of opt-in message fingerprints.
- `POST /fingerprints`: `{"fp": "<16 hex>", "category": "..."}`.
- `POST /reports`: only the 33 district names or `unknown` are accepted.

Run `python -m unittest test_trends_alerts -v` (no Whisper model needed).

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
- **Dual Reporting Note**: When called with a valid `Authorization: Bearer <token>`, both the anonymous `reports` row and the authenticated `user_reports` row share the exact same timestamp (`ts`). If the token is expired or invalid, the backend safely falls back to anonymous submission (`reports` row only) and reports `user_report_skipped=true`.
- **Response**:
```json
{
  "status": "success",
  "id": 301,
  "user_report": "recorded",
  "user_report_skipped": false
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

### 5. Authentication & Session Initialization
- **Method**: `POST /auth/session`
- **Header**: `Authorization: Bearer <Firebase_ID_Token>`
- **Payload**:
```json
{
  "username": "Ramesh Kumar",
  "locale": "hi"
}
```
- **Rules**:
  - `uid` and verified `phone` are extracted strictly from the Firebase ID token.
  - `username` is saved on first registration only; returning logins preserve existing username.
  - Initial profile sets `district = "unknown"` and `language = <locale>`.
- **Response**:
```json
{
  "uid": "FIREBASE_UID_123",
  "phone": "+919876543210",
  "username": "Ramesh Kumar",
  "district": "unknown",
  "language": "hi",
  "created_at": "2026-11-24T04:00:00Z",
  "updated_at": "2026-11-24T04:00:00Z",
  "is_new_user": true
}
```

### 6. User Profile (Read & Update)
- **Method**: `GET /profile`
- **Header**: `Authorization: Bearer <Firebase_ID_Token>`
- **Response**: Returns the current user profile object.
- **Method**: `PUT /profile`
- **Header**: `Authorization: Bearer <Firebase_ID_Token>`
- **Payload**:
```json
{
  "district": "Durg",
  "language": "chh"
}
```
- **Rules**:
  - Only `district` (must be a valid Chhattisgarh district or `"unknown"`) and `language` (`"en"`, `"hi"`, or `"chh"`) can be updated.
  - `phone` is strictly **immutable** and cannot be modified.

### 7. User Data Sync
- **Method**: `GET /sync`
- **Header**: `Authorization: Bearer <Firebase_ID_Token>`
- **Response**: Full snapshot of `detection_history`, `quiz_progress`, `lesson_progress`, and `user_reports`.
- **Method**: `PUT /sync`
- **Header**: `Authorization: Bearer <Firebase_ID_Token>`
- **Payload**:
```json
{
  "detection_history": [
    {
      "kind": "message",
      "verdict": "scam",
      "score": 0.94,
      "category": "electricity_bill",
      "ts": "2026-11-24T03:15:00Z"
    }
  ],
  "quiz_progress": [
    {
      "topic": "phishing_basics",
      "attempts": 3,
      "correct": 5,
      "total": 5,
      "updated_at": "2026-11-24T03:20:00Z"
    }
  ],
  "lesson_progress": [
    {
      "lesson_id": "qr_safety",
      "completed_at": "2026-11-24T03:25:00Z"
    }
  ],
  "user_reports": []
}
```
- **Conflict Resolution Rules**:
  - `detection_history`: Union of records (deduplicated on `kind`, `category`, `ts`). **Privacy rule**: stores metadata only; NEVER stores raw message text or call audio.
  - `user_reports`: Union of records (deduplicated on `type`, `district`, `ts`).
  - `quiz_progress`: Latest timestamp (`updated_at`) wins per topic.
  - `lesson_progress`: Latest timestamp (`completed_at`) wins per lesson ID.

### 8. Account Deletion
- **Method**: `DELETE /account`
- **Header**: `Authorization: Bearer <Firebase_ID_Token>`
- **Rules**: Permanently deletes the user record and cascades to erase `profiles`, `detection_history`, `quiz_progress`, `lesson_progress`, and `user_reports`. Anonymous incident reports in the aggregate `reports` table are retained.
- **Response**:
```json
{
  "status": "success",
  "message": "Account and all associated personal data for FIREBASE_UID_123 deleted successfully."
}
```

---

## Firebase Configuration & Local Development Mode

### Firebase Service Account Key (Production Mode)
1. Download your service account JSON key from Firebase Console (`Project Settings -> Service Accounts -> Generate new private key`).
2. Save it at:
   ```
   backend/service-account.json
   ```
   *(Or specify the path via the `FIREBASE_SERVICE_ACCOUNT_PATH` environment variable).*
3. **Note on Connectivity**: Firebase Admin SDK requires outbound HTTPS connectivity to Google's public x509 cert servers to verify JWT signatures.
4. **Security Notice**: `service-account*.json` is gitignored. **NEVER commit service account keys to source control.**

### AUTH_DEV_MODE (Local Mock Mode)
For local testing without internet access or without a service account key, enable mock authentication mode:

#### On Windows (PowerShell):
```powershell
$env:AUTH_DEV_MODE="1"
uvicorn main:app --host 0.0.0.0 --port 8000
```

#### On Linux / macOS:
```bash
AUTH_DEV_MODE=1 uvicorn main:app --host 0.0.0.0 --port 8000
```

- When enabled, the backend accepts mock tokens in the format:
  ```
  Bearer mock-token:<uid>:<phone>
  ```
  *(Example: `Bearer mock-token:test_user_123:+919876543210`)*
- A loud, visible warning banner is printed in the server logs on startup when `AUTH_DEV_MODE` is active.

---

## Testing

### Run Auth & Sync Test Suite
```bash
python test_auth.py
```
Verifies 10 comprehensive test scenarios:
- Missing and invalid token rejection (401)
- First-time user creation (`district='unknown'`, `language=<locale>`, `is_new_user=True`)
- Returning login idempotency and username preservation (`is_new_user=False`)
- Phone immutability and profile update via `PUT /profile`
- District validation on profile update (rejects non-Chhattisgarh districts with 422)
- Multi-user data isolation between distinct UIDs
- Sync conflict resolution (union for history/reports, latest timestamp wins for quiz/lessons)
- Dual reporting: `POST /reports` with Bearer token writes to anonymous `reports` AND `user_reports`
- Account deletion (`DELETE /account`) cascading across all 6 user tables
- Production gate verification: mock tokens rejected when `AUTH_DEV_MODE` is disabled

### Run Full Integration Test Suite
```bash
python test_all_endpoints.py
```

### Run Live Call Guard & Trends Tests
```bash
python -m unittest test_trends_alerts -v
python -m unittest test_live_transcribe -v
```

---

## Testing with cURL

### Health Check
```bash
curl http://127.0.0.1:8000/health
```

### Mock Auth Session (Requires AUTH_DEV_MODE=1)
```bash
curl -X POST http://127.0.0.1:8000/auth/session \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer mock-token:user123:+919876543210" \
     -d "{\"username\": \"Aman\", \"locale\": \"hi\"}"
```

### Update Profile
```bash
curl -X PUT http://127.0.0.1:8000/profile \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer mock-token:user123:+919876543210" \
     -d "{\"district\": \"Durg\", \"language\": \"hi\"}"
```

### Pull Sync Data
```bash
curl -H "Authorization: Bearer mock-token:user123:+919876543210" \
     http://127.0.0.1:8000/sync
```

### Submit Authenticated Report
```bash
curl -X POST http://127.0.0.1:8000/reports \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer mock-token:user123:+919876543210" \
     -d "{\"type\": \"fake_qr\", \"district\": \"Durg\", \"ts\": \"2026-11-24T03:00:00Z\"}"
```

### Delete Account
```bash
curl -X DELETE http://127.0.0.1:8000/account \
     -H "Authorization: Bearer mock-token:user123:+919876543210"
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
