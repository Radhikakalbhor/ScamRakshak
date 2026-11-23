# ScamRakshak: Comprehensive Project Documentation & Technical Architecture

> **Offline-first Android application designed to detect scam messages and calls, inspect fake UPI QR codes, teach digital payment safety in English, Hindi, and Chhattisgarhi, and assist in reporting cyber fraud.**

---

## Table of Contents
1. [Executive Summary & Problem Statement](#1-executive-summary--problem-statement)
2. [Architecture & Technology Stack](#2-architecture--technology-stack)
3. [Folder Ownership, Contracts & Team Boundaries](#3-folder-ownership-contracts--team-boundaries)
4. [Complete Feature Breakdown & Implementation](#4-complete-feature-breakdown--implementation)
   - [4.1 Offline Message Scam Detector & SimHash Fingerprinting](#41-offline-message-scam-detector--simhash-fingerprinting)
   - [4.2 Fake UPI QR Code Scanner & Detector](#42-fake-upi-qr-code-scanner--detector)
   - [4.3 Call Scam Transcript & Audio Analyzer](#43-call-scam-transcript--audio-analyzer)
   - [4.4 Live Call Guard (Real-Time Audio Stream)](#44-live-call-guard-real-time-audio-stream)
   - [4.5 Automatic Background Call Recording Analyzer](#45-automatic-background-call-recording-analyzer)
   - [4.6 Android Share Intent Integration (Text & Audio)](#46-android-share-intent-integration-text--audio)
   - [4.7 Fraud Incident Reporting & Offline Report Queue](#47-fraud-incident-reporting--offline-report-queue)
   - [4.8 Digital Financial Literacy Score & Tracker](#48-digital-financial-literacy-score--tracker)
   - [4.9 Interactive Safety Lessons (11 Scenarios)](#49-interactive-safety-lessons-11-scenarios)
   - [4.10 Fraud Awareness Quiz System](#410-fraud-awareness-quiz-system)
   - [4.11 District Scam Trends, Summary & Emerging Alerts](#411-district-scam-trends-summary--emerging-alerts)
   - [4.12 Trilingual Accessibility & Localization Engine](#412-trilingual-accessibility--localization-engine)
5. [End-to-End Data & Execution Flows](#5-end-to-end-data--execution-flows)
6. [Machine Learning Pipeline & Engine Implementation](#6-machine-learning-pipeline--engine-implementation)
   - [6.1 TF-IDF + Logistic Regression Architecture](#61-tf-idf--logistic-regression-architecture)
   - [6.2 Pure-Dart JSON Inference Engine](#62-pure-dart-json-inference-engine)
   - [6.3 Empirical Performance & Held-Out 2026 Evaluation](#63-empirical-performance--held-out-2026-evaluation)
   - [6.4 Script-Rule Engine & Phonetic Devanagari Normalization](#64-script-rule-engine--phonetic-devanagari-normalization)
7. [Backend Architecture & API Specifications](#7-backend-architecture--api-specifications)
   - [7.1 Server Runtime & faster-whisper Configuration](#71-server-runtime--faster-whisper-configuration)
   - [7.2 REST API Endpoints Specification](#72-rest-api-endpoints-specification)
   - [7.3 SQLite Database Schema & Seeding](#73-sqlite-database-schema--seeding)
8. [Complete Repository Directory & File Catalog](#8-complete-repository-directory--file-catalog)
9. [Setup, Execution & Testing Guide](#9-setup-execution--testing-guide)
10. [Feature Verification & Implementation Status Matrix](#10-feature-verification--implementation-status-matrix)
11. [Known Limitations, Constraints & Future Roadmap](#11-known-limitations-constraints--future-roadmap)

---

## 1. Executive Summary & Problem Statement

### 1.1 Problem Statement
Digital financial infrastructure (Unified Payments Interface [UPI], Aadhaar-Enabled Payment System [AePS], mobile banking) has expanded exponentially across India, reaching tier-2/3 towns, rural communities, and first-time smartphone owners. However, financial cyber fraud has escalated at a comparable velocity. Fraudsters frequently target vulnerable populations using:
- **Social Engineering & Coercion:** Phishing SMS regarding electricity disconnection, lottery scams (KBC), fake KYC expiry, "digital arrest" impersonation of police/CBI, and predatory loan app blackmail.
- **Payment Gateway Deception:** Malicious UPI QR codes engineered to collect money while deceiving the victim into believing they are scanning to *receive* a refund, prize, or subsidy.
- **Linguistic Barriers:** Critical security advisories and fraud prevention literature are predominantly drafted in formal English or academic Hindi, alienating non-native speakers and regional dialect speakers (e.g., Chhattisgarhi).
- **Network Unreliability:** Rural and remote areas experience intermittent or nonexistent mobile internet connectivity. Cloud-dependent cybersecurity tools become completely non-functional when connectivity drops.
- **Delayed Reporting:** The critical "golden hour" for freezing stolen funds via the National Cyber Crime Helpline (`1930`) is often lost because victims do not know where or how to report incidents.

### 1.2 The ScamRakshak Solution
**ScamRakshak** ("Scam Protector") is an **offline-first Android cybersecurity platform** engineered for regional resilience, accessibility, and proactive defense:
1. **100% Offline Core Detection:** SMS/WhatsApp message classification, UPI QR code inspection, call transcript rule analysis, lessons, quizzes, and financial literacy scoring execute locally on-device without internet access.
2. **Trilingual Regional Experience:** Native multi-language architecture supporting **English**, **Hindi** (हिन्दी), and **Chhattisgarhi** (छत्तीसगढ़ी) in genuine Devanagari script.
3. **Multi-Vector Fraud Protection:**
   - **Text:** TF-IDF + Logistic Regression NLP model running locally in pure Dart.
   - **QR Code:** Instant offline UPI URL parsing, handle validation, payee name mismatch detection, and reverse-payment deception checks.
   - **Audio/Voice:** Live speakerphone call monitoring (Live Call Guard) and background automated call recording scanning.
4. **Action & Remediation:** Direct 1-tap dialing to the **1930** national helpline, official cybercrime portal redirection, evidence checklists, and an offline-resilient report queue.
5. **Gamified Financial Literacy:** Interactive flashcards, scenario quizzes, and a composite Digital Financial Literacy (DFL) score tracking user progress.

---

## 2. Architecture & Technology Stack

```mermaid
flowchart TD
    subgraph MobileDevice["Android Device (Offline-First Flutter Client)"]
        subgraph UI["Presentation Layer (GoRouter & Riverpod)"]
            Home["HomeScreen (DFL Score & 8 Core Action Tiles)"]
            Screens["Message / Call / Live / QR / Report / Lessons / Quiz / Trends"]
            Lang["Trilingual Strings Engine (en, hi, chh)"]
        end

        subgraph Engines["On-Device AI & Rule Engines (Zero Network Required)"]
            ML["ScamClassifier\n(assets/models/scam_model.json)\nPure Dart TF-IDF + Sigmoid"]
            QR["UpiQr\n(UPI Regex, 90+ Handles, Name Mismatch)"]
            Rules["CallAnalyzer\n(assets/rules/call_rules.json)\n10 Script Categories & Negation"]
            LiveRules["LiveCallAnalyzer\nPhonetic Normalization & ASR Tolerance"]
            SimHash["MessageFingerprint\n64-bit SimHash (16 hex)"]
        end

        subgraph LocalData["Persistent Local Storage (SharedPreferences & Filesystem)"]
            Prefs["Settings (Locale, Server URL, Opt-in)"]
            Queue["ReportQueue ('report_queue_v1')\nOffline resilient FIFO queue"]
            DFLStore["LiteracyStore ('dfl_topic_quiz_v1')"]
            Hist["DetectionHistory & EvidenceStore"]
            AutoStore["AutoAnalyzeStore (Call records cache)"]
        end

        subgraph NativeBridge["Android Native Integrations"]
            ShareIntent["MainActivity.kt (ACTION_SEND Text & Audio)"]
            Lockscreen["USE_FULL_SCREEN_INTENT & setShowWhenLocked"]
            FGS["Foreground Service (Auto-Analyze Call Recordings)"]
            Camera["Camera (mobile_scanner)"]
            Mic["Microphone (record) / Audio Player"]
        end
    end

    subgraph BackendCloud["ScamRakshak Backend (FastAPI + SQLite)"]
        API["FastAPI REST Server (Port 8000)\nGET /health | POST /reports | GET /trends\nGET /trends/summary | GET /alerts | POST /fingerprints"]
        STT["faster-whisper (model: small, CPU int8)\nPOST /transcribe?lang=hi|en|auto\nSupports wav, mp3, m4a, ogg, amr, aac, 3gp, opus, flac"]
        DB[(SQLite backend/data.db\nPre-seeded Chhattisgarh Records\nK-Anonymity & Spike/Cluster Alerts)]
    end

    UI --> Engines
    UI --> LocalData
    NativeBridge --> UI
    NativeBridge --> LocalData
    Engines --> LocalData

    LocalData -.->|When Online (ApiClient)| API
    NativeBridge -.->|Audio Chunks / Files| STT
    API --> DB
    STT --> DB
```

### 2.1 Technology Stack Details

| Layer | Component | Version / Spec | Role in ScamRakshak |
| :--- | :--- | :--- | :--- |
| **Mobile Framework** | Flutter SDK | `^3.14.0` (Dart 3.5+) | Cross-platform client targeting Android. |
| **State Management** | `flutter_riverpod` | `^2.5.1` | Reactive state injection, locale management, provider scopes. |
| **Routing** | `go_router` | `^14.2.0` | Declarative routing with deep linking across 15 routes. |
| **Charts** | `fl_chart` | `^0.68.0` | Offline interactive bar and pie charts for scam trends. |
| **Camera & QR** | `mobile_scanner` | `7.0.1` | Real-time camera QR scanning for payment verification. |
| **Audio Processing** | `record`, `audioplayers` | `^6.1.1`, `^6.1.0` | Audio stream capture (6s chunks) and sample playback. |
| **Background Tasks** | `flutter_foreground_task` | `^9.1.0` | Persistent Android foreground service watching call directory. |
| **Notifications** | `flutter_local_notifications`| `^19.4.0` | Heads-up and lockscreen alerts for threat detection. |
| **Permissions** | `permission_handler` | `^12.0.1` | Runtime permissions (Microphone, Storage, Camera, Notifications). |
| **Typography** | `Noto Sans Devanagari` | Bundled asset | Offline Devanagari font rendering across all Android versions. |
| **Backend Server** | FastAPI | `^0.115.0` (Python 3.10+) | High-performance asynchronous REST backend. |
| **Speech-to-Text** | `faster-whisper` | `^1.1.0` (CTranslate2) | CPU `int8` quantized Whisper (`small` model default). |
| **Database** | SQLite3 | Python stdlib | Threat logs, pre-seeded synthetic data, live user reports. |
| **ML Training** | `scikit-learn` | 1.6+ | TF-IDF (1,2-grams) + Logistic Regression, exported to pure JSON. |

---

## 3. Folder Ownership, Contracts & Team Boundaries

Per `AGENTS.md`, responsibilities are strictly isolated to allow collaborative feature delivery without merge conflicts:

```
+-----------------------------------------------------------------------------------+
| ScamRakshak Team Ownership Structure                                              |
+-----------------------------------------------------------------------------------+
| Sayanthan:                                                                        |
|   lib/core/                                -> Theme, Localization, Routing,       |
|                                               ApiClient, Providers, Share Intent  |
|   lib/features/message_detector/           -> SMS/WhatsApp UI, SimHash Fingerprint|
|   lib/features/call_detector/              -> Call Transcript UI, Auto-Analyze    |
|   lib/features/qr_check/                   -> UPI QR Validator, Scanner UI        |
|   lib/features/report/                     -> Report Screen, ReportQueue, 1930 CTA|
+-----------------------------------------------------------------------------------+
| Radhika:                                                                          |
|   lib/engine/                              -> Models, Classifier, Analyzers       |
|   assets/models/                           -> scam_model.json                     |
|   assets/rules/                            -> call_rules.json                     |
|   assets/samples/                          -> Sample audio and transcripts        |
|   ml/                                      -> Dataset prep, training, held-out    |
+-----------------------------------------------------------------------------------+
| Aagam:                                                                            |
|   backend/                                 -> FastAPI, SQLite, faster-whisper     |
|   lib/features/lessons/                    -> 11 Lesson JSONs, Flashcard UI       |
|   lib/features/quiz/                       -> 7 Quiz Banks, DFL Literacy Score    |
|   lib/features/dashboard/                  -> Scam Trends, Summary, Alert Visuals |
|   assets/lessons/, assets/quiz/, assets/data/ -> Content & seed datasets           |
+-----------------------------------------------------------------------------------+
```

### 3.1 Locked Core Contracts

The following API signatures are permanently locked and cannot be broken:

```dart
// 1. Data Contracts (lib/engine/models.dart)
class Reason { String phrase; double weight; }
class ScamResult { String label /* 'scam'|'genuine' */; double score /* 0..1 */; List<Reason> reasons; }
class CallMatch { String phrase; String scriptType; }
class CallResult { String risk /* 'high'|'medium'|'low' */; List<CallMatch> matches; }

// 2. ML Classifier Contract (lib/engine/scam_classifier.dart)
static Future<ScamClassifier> ScamClassifier.load();
ScamResult classify(String text);

// 3. Call Analyzer Contract (lib/engine/call_analyzer.dart)
static Future<CallAnalyzer> CallAnalyzer.load();
CallResult analyze(String transcript);

// 4. Live Call Guard Contract (lib/engine/live_call_analyzer.dart)
class LiveCallState { String risk; double score; List<CallMatch> matches; List<CallMatch> newMatches; String transcript; }
class LiveCallAnalyzer { static Future<LiveCallAnalyzer> load(); LiveCallState add(String chunkText); void reset(); }

// 5. Backend Client Contract (lib/core/api_client.dart)
Future<Map> transcribe(File audio);
Future<Map> transcribeChunk(File audio, {String? lang});
Future<Map> transcribeRecording(File audio, {Duration timeout});
Future<bool> isReachable();
Future<void> postReport(String type, String district);
Future<void> postReportAt(String type, String district, String ts);
Future<List<Map>> getTrends();
Future<Map> getTrendSummary();
Future<List<Map>> getAlerts();
Future<void> postFingerprint(String fp, String category);
```

---

## 4. Complete Feature Breakdown & Implementation

### 4.1 Offline Message Scam Detector & SimHash Fingerprinting
- **Route:** `/message`
- **Source:** `lib/features/message_detector/message_detector_screen.dart`, `message_fingerprint.dart`
- **Functionality:**
  - Evaluates suspect SMS or WhatsApp messages locally against `assets/models/scam_model.json`.
  - Normalizes text (replaces URLs with ` urltoken `, strips punctuation, extracts unigrams and bigrams).
  - Computes probability score (0.0 to 1.0) and outputs a verdict (`SCAM` vs `GENUINE`).
  - Displays top 5 contributing phrase chips with positive or negative weights (e.g., `"account blocked"`, `"click link"`, `"apk"`).
  - Includes 8 quick-load sample presets (`message_examples.dart`) for testing.
  - **SimHash Message Fingerprinting:** Generates a 64-bit privacy-preserving SimHash (`16 hex digits`) using FNV-1a hashing on word 3-grams after masking numbers to `0` and URLs to `url`.
  - **Opt-in Threat Sharing:** If enabled by the user in settings, a detected scam transmits only the anonymous 16-hex hash and category to `POST /fingerprints` without sharing any personal message text.

### 4.2 Fake UPI QR Code Scanner & Detector
- **Route:** `/qr`
- **Source:** `lib/features/qr_check/qr_check_screen.dart`, `upi_qr.dart`, `qr_scanner_page.dart`
- **Functionality:**
  - Scans QR codes live via camera (`mobile_scanner`) or accepts pasted raw QR strings.
  - **Protocol Parsing:** Verifies `upi://pay` URI scheme and extracts parameters: `pa` (payee address), `pn` (payee name), `am` (amount), `tn` (transaction note), `cu` (currency).
  - **Reverse Payment Trap Detection:** Flags fraud triggers when transaction notes contain deceptive words like `"refund"`, `"cashback"`, `"prize"`, `"reward"`, `"lottery"`, `"kyc"`, `"रिफंड"`, `"इनाम"`, `"जीत"`. In UPI, scanning a QR code *only sends money*; it can never be used to receive funds.
  - **Handle Verification:** Matches the UPI domain (`@...`) against a curated whitelist of 90+ verified Indian banking and fintech handles (`@okhdfcbank`, `@oksbi`, `@paytm`, `@ybl`, etc.).
  - **Name Mismatch Heuristic:** Compares payee name tokens (`pn`) with the alphanumeric prefix of `pa`. Personal accounts claiming to be institutions or individuals with conflicting names are flagged.
  - **Risk Classification:**
    - `DANGER` (Red): Non-UPI deceptive links, invalid VPA formats, receive-words traps.
    - `CAUTION` (Amber): Unspecified payee name, name mismatch, pre-set debit amount, unrecognized banking handle, non-INR currency.
    - `OK` (Green): Clean, standard verified merchant or peer UPI QR.

### 4.3 Call Scam Transcript & Audio Analyzer
- **Route:** `/call`
- **Source:** `lib/features/call_detector/call_detector_screen.dart`, `call_highlight.dart`
- **Functionality:**
  - Accepts audio files (`.wav`, `.mp3`, `.m4a`, `.ogg`, `.amr`, `.aac`, `.3gp`, `.opus`, `.flac`) or pasted call transcripts.
  - **Audio Pathway:** Sends recording to `POST /transcribe`. If offline, displays an informative offline card and provides offline sample transcripts.
  - **Transcript Pathway:** Executes `CallAnalyzer.analyze(transcript)` synchronously on-device.
  - Evaluates patterns across 10 scam script categories loaded from `call_rules.json`.
  - Negation window algorithm ensures phrases like *"do not share your OTP"* are suppressed from triggering false alerts.
  - Dynamic visual highlighting color-codes suspect phrases directly in the transcript viewer.

### 4.4 Live Call Guard (Real-Time Audio Stream)
- **Route:** `/live`
- **Source:** `lib/features/live_call/live_call_screen.dart`, `lib/engine/live_call_analyzer.dart`
- **Functionality:**
  - Monitors live phone calls on speakerphone.
  - Records continuous 6-second audio chunks via `record`.
  - **Local Silence Filter:** Calculates peak dBFS; audio chunks below `-45 dBFS` are discarded locally to eliminate redundant network traffic and server computation.
  - Uploads active audio chunks to `POST /transcribe?lang=hi|en|auto`.
  - **Incremental Analysis:** Evaluates newly transcribed text against previous context using `LiveCallAnalyzer`.
  - **Phonetic ASR Tolerance:** Normalizes Devanagari ASR speech-to-text confusions (e.g., retroflex vs dental consonants, short vs long vowels, sibilant folding).
  - **Emergency Alert:** On `HIGH` risk detection, triggers continuous haptic vibration, flashes a prominent emergency alert banner, and presents a 1-tap "Hang Up & Report" button.
  - **Offline Demo Mode:** 5 bundled audio scenarios (`scam_digital_arrest`, `scam_fake_kyc_otp`, `scam_courier_customs`, `genuine_family_call`, `genuine_bank_service`) with line-by-line audio in `assets/samples/live/audio/`.

### 4.5 Automatic Background Call Recording Analyzer
- **Routes:** `/call/auto`, `/call/recording`, `/call/warning`, `/call/warning/demo`, `/call/report`, `/live/inbox`
- **Source:** `lib/features/call_detector/auto_analyze_service.dart`, `auto_analyze_screen.dart`, `recording_result_screen.dart`, `recording_warning_screen.dart`
- **Functionality:**
  - Android foreground service (`flutter_foreground_task`) monitors the device's call recording directory (`/Recordings/Call/`).
  - When a call recording completes, the service automatically initiates transcription and analysis.
  - **Full-Screen Lockscreen Alert:** If a call is rated `HIGH` or `MEDIUM` risk, launches a full-screen warning window using `USE_FULL_SCREEN_INTENT` and `setShowWhenLocked` in `MainActivity.kt`.
  - **Call Timeline Breakdown:** `call_timeline.dart` maps out an interactive playback timeline displaying the exact timestamps where suspicious phrases were spoken.
  - **Recording Inbox:** Stores history of analyzed recordings with risk badges and cached findings.

### 4.6 Android Share Intent Integration (Text & Audio)
- **Source:** `android/app/src/main/kotlin/.../MainActivity.kt`, `lib/core/share_intent.dart`
- **Functionality:**
  - Registers `ACTION_SEND` intent filters in `AndroidManifest.xml` for `text/plain` and `audio/*`.
  - **Text Share:** Sharing SMS or WhatsApp text directly from other apps automatically launches ScamRakshak, routes to `/message`, pre-fills the input, and runs the scam classifier immediately.
  - **Audio Share:** Sharing voice notes or call recordings copies the file into the app's cache directory (`cache/shared_audio`) to maintain private file permissions, routes to `/call`, and initiates transcription.
  - Supported on cold start (`getInitialShare`) and while running (`onNewIntent` / `onShare`).

### 4.7 Fraud Incident Reporting & Offline Report Queue
- **Route:** `/report`
- **Source:** `lib/features/report/report_screen.dart`, `report_data.dart`
- **Functionality:**
  - **National Cybercrime Helpline:** Primary CTA dials `1930` (`tel:1930`) directly.
  - **Official Portal Escalation:** Direct links to `cybercrime.gov.in` and Department of Telecommunications **Chakshu** portal (`sancharsaathi.gov.in/sfc/`).
  - **Incident Form:** Collects fraud type (`otp`, `fake_qr`, `loan_app`, `call`, `other`), district (strictly validated against 33 Chhattisgarh districts or "unknown"), and UTC timestamp.
  - **Offline Report Queue (`ReportQueue`):** If network is absent, reports are serialized to `shared_preferences` under key `'report_queue_v1'` (capped at 200 items). When connectivity is restored, `ReportQueue.flush()` transmits pending reports sequentially.
  - **Evidence Preservation Checklist:** Guides victims to secure transaction UTRs, bank statements, caller IDs, and screenshots before perpetrators delete them.

### 4.8 Digital Financial Literacy Score & Tracker
- **Source:** `lib/features/quiz/literacy_score.dart`, embedded in `home_screen.dart`
- **Functionality:**
  - Computes a unified Digital Financial Literacy (DFL) score from 0 to 100 displayed prominently on the home screen.
  - **Weighted Formulation:**
    $$\text{DFL Score} = 60 \times (\text{Average Quiz Accuracy across 11 topics}) + 40 \times (\text{Share of 11 Lessons Completed})$$
  - Untried topics contribute 0 towards accuracy, encouraging users to explore all modules.
  - **Personalized Recommendations:** Identifies the user's weakest topic and recommends the next best action (e.g., *"Take the Fake QR quiz"* or *"Read the Digital Arrest lesson"*).
  - Persisted locally in `shared_preferences` (`'dfl_topic_quiz_v1'`).

### 4.9 Interactive Safety Lessons (11 Scenarios)
- **Route:** `/lessons`
- **Source:** `lib/features/lessons/lesson_list_screen.dart`, `lesson_detail_screen.dart`, `assets/lessons/*.json`
- **Functionality:**
  - 11 comprehensive lesson modules:
    1. `otp` — OTP Confidentiality
    2. `upi_pin` — UPI PIN Safety (PIN is entered only to pay, never to receive)
    3. `qr` — Fake QR Code Traps
    4. `atm_pin` — ATM Card Security
    5. `digital_arrest` — Digital Arrest Coercion Tactics
    6. `fake_kyc` — Bank & SIM KYC Suspension Threats
    7. `loan_app` — Predatory Instant Loan Apps & Contact Blackmail
    8. `courier_customs` — Courier Narcotics Parcel Scams
    9. `lottery_prize` — Fake KBC / Lottery Winner Schemes
    10. `phishing` — Phishing URLs & Fake Electricity Disconnections
    11. `remote_access` — Screen-Sharing Apps (AnyDesk, TeamViewer risks)
  - Features trilingual Devanagari text, search filter, topic chips, and completion tracking.

### 4.10 Fraud Awareness Quiz System
- **Route:** `/quiz`
- **Source:** `lib/features/quiz/quiz_screen.dart`, `assets/quiz/*.json`
- **Functionality:**
  - 7 comprehensive question banks.
  - Three distinct modes: **Quick Quiz** (5 randomized questions), **Full Quiz** (complete question set), and **Topic Quiz** (targeted test for a specific lesson).
  - Animated visual feedback, trilingual answer explanations, and high-score tracking.

### 4.11 District Scam Trends, Summary & Emerging Alerts
- **Route:** `/dashboard`
- **Source:** `lib/features/dashboard/trends_screen.dart`, `backend/database.py`
- **Functionality:**
  - Combines local phone detection history with remote aggregated incident data.
  - Dynamic bar and pie charts (`fl_chart`) visualising fraud distribution across 33 Chhattisgarh districts.
  - **K-Anonymity Privacy:** Integrates `GET /trends/summary`, suppressing data cells with fewer than 5 reports (`min_count: 5`) to prevent deanonymization.
  - **Emerging Threat Alerts:** Visualizes data from `GET /alerts`:
    - **Spike Alerts:** Detects localized surges (last 7 days volume vs prior 4-week baseline) by district and fraud type.
    - **Cluster Alerts:** Groups near-identical SimHash fingerprints to warn of mass-SMS scam campaigns.

### 4.12 Trilingual Accessibility & Localization Engine
- **Source:** `lib/core/strings.dart`, `theme.dart`, `widgets/language_switcher.dart`
- **Functionality:**
  - Centralized dictionary class `S` supporting English (`en`), Hindi (`hi`), and Chhattisgarhi (`chh`).
  - Feature folders register local dictionaries via `S.register(Map)`.
  - Reactive switching with zero app restarts via Riverpod `localeProvider`.
  - Persisted in `shared_preferences` (`'scamrakshak_selected_locale'`).
  - High-contrast accessible theme (Deep Teal `#00796B`, Amber Warning `#F57C00`, Critical Red `#D32F2F`) tailored for first-time smartphone users.

---

## 5. End-to-End Data & Execution Flows

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as ScamRakshak Mobile App
    participant Engine as On-Device Dart Engine
    participant API as FastAPI Backend (:8000)
    participant Whisper as faster-whisper (CPU int8)
    participant DB as SQLite (backend/data.db)

    Note over User,Engine: Flow 1: Offline SMS / WhatsApp Detection
    User->>App: Paste message or Share via Android Intent
    App->>Engine: ScamClassifier.classify(text)
    Engine->>Engine: Tokenize -> TF-IDF dot product -> Sigmoid
    Engine-->>App: ScamResult (Verdict, Score, Top 5 Reasons)
    App->>User: Display Green/Red Alert, Advice Chips & CTA

    Note over User,Engine: Flow 2: Offline UPI QR Code Validation
    User->>App: Scan QR or paste upi://pay link
    App->>Engine: checkUpiQr(rawString)
    Engine->>Engine: Verify scheme, VPA regex, 90+ handles, check 'refund/prize' tokens
    Engine-->>App: UpiQrResult (Level: danger|caution|ok, risks)
    App->>User: Display Safety Card & Specific Threat Breakdown

    Note over User,DB: Flow 3: Live Call Guard Stream
    User->>App: Start Live Call Guard on Speakerphone
    loop Every 6 Seconds
        App->>App: Record mic chunk (audio.wav)
        App->>App: Check peak dBFS < -45 dBFS?
        alt Is Silence
            App->>App: Discard chunk locally (0 network)
        else Has Speech
            App->>API: POST /transcribe?lang=hi|en|auto
            API->>Whisper: transcribe(temp.wav, initial_prompt)
            Whisper-->>API: segments -> transcript text
            API-->>App: {"text": "...", "lang": "hi"}
            App->>Engine: LiveCallAnalyzer.add(chunkText)
            Engine->>Engine: Phonetic normalization + Rule regex matching
            alt High Risk Triggered
                Engine-->>App: LiveCallState(risk: 'high')
                App->>User: Trigger Haptic Vibration, Emergency UI & "Hang Up" CTA
            end
        end
    end

    Note over User,DB: Flow 4: Resilient Incident Reporting
    User->>App: Submit fraud report (Type, District)
    App->>App: Enqueue in ReportQueue (SharedPreferences)
    alt Network Available
        App->>API: POST /reports {"type": "otp", "district": "Raipur", "ts": "..."}
        API->>DB: INSERT INTO reports (type, district, source='user')
        DB-->>API: Success (id: 301)
        API-->>App: 201 Created
        App->>App: Dequeue from ReportQueue
    else Offline
        App-->>User: Report queued locally; auto-submits on reconnect
    end
```

---

## 6. Machine Learning Pipeline & Engine Implementation

### 6.1 TF-IDF + Logistic Regression Architecture
- **Classifier Type:** Linear Logistic Regression with balanced class weights ($C=100$) trained on extracted TF-IDF n-grams (unigrams and bigrams, `min_df=2`).
- **Feature Space:** 19,709 in-vocabulary n-grams spanning English, Hindi (Devanagari script), and Hinglish (Latin transliteration).
- **Training Set:** 7,673 augmented training samples (5,881 pre-augmentation) curated in `ml/data/train.csv` and `ml/data/extra_train.csv`.

### 6.2 Pure-Dart JSON Inference Engine
To avoid bundling heavy runtime dependencies (e.g., TensorFlow Lite, ONNX Runtime, Python), the model parameters are exported by `ml/export_model.py` into a single standalone JSON file: `assets/models/scam_model.json` (786 KB).

`ScamClassifier` (`lib/engine/scam_classifier.dart`) implements scikit-learn's inference formula directly in pure Dart:
$$\text{Score} = \sigma\left(\beta_0 + \sum_{j \in \text{vocab}} \frac{\text{tf}_j \cdot \text{idf}_j}{\|x\|_2} \cdot \beta_j\right), \quad \sigma(z) = \frac{1}{1 + e^{-z}}$$

**Mathematical Parity:**
`test/engine/parity_test.dart` verifies that inference output in Dart matches Python `scikit-learn` to within $< 10^{-6}$ error tolerance across 50 reference samples.

### 6.3 Empirical Performance & Held-Out 2026 Evaluation

The model was subjected to multiple evaluation regimes:
1. **Full Synthetic Test Set (`test.csv`, $n=1539$):** Stratified test hold-out.
2. **Hand-Written Subset (`handwritten_test.py`, $n=68$):** Realistic human-authored messages.
3. **Held-Out 2026 Benchmark (`ml/data/heldout_2026.csv`, $n=108$):** Clean, unseen benchmark created after model weights were frozen. Verified by `test/engine/heldout_eval_test.dart` ensuring zero duplicate or high-Jaccard overlap ($J < 0.8$) with any training or test data.

#### Benchmark Results Summary:

| Evaluation Slice | Sample Size ($n$) | Accuracy | Precision | Recall | $F_1$ Score |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Full Test Set (All)** | 1,539 | **98.64%** | **97.12%** | **97.38%** | **0.9725** |
| - English Subset | 1,139 | 98.16% | 94.02% | 94.54% | 0.9428 |
| - Hindi (Devanagari) | 200 | 100.00% | 100.00% | 100.00% | 1.0000 |
| - Hinglish Subset | 200 | 100.00% | 100.00% | 100.00% | 1.0000 |
| **Hand-Written Subset (All)**| 68 | **98.53%** | **100.00%**| **97.06%** | **0.9851** |
| - English Subset | 24 | 95.83% | 100.00% | 91.67% | 0.9565 |
| - Hindi (Devanagari) | 22 | 100.00% | 100.00% | 100.00% | 1.0000 |
| - Hinglish Subset | 22 | 100.00% | 100.00% | 100.00% | 1.0000 |
| **Held-Out 2026 (Unseen Clean)**| 108 | **89.81%** | **87.72%** | **92.59%** | **0.9009** |
| - English Slice | 36 | 77.78% | 77.78% | 77.78% | 0.7778 |
| - Hindi (Devanagari) | 36 | 91.67% | 85.71% | 100.00% | 0.9231 |
| - Hinglish Slice | 36 | 100.00% | 100.00% | 100.00% | 1.0000 |

> **Analysis of Edge Cases:** In the strict 2026 held-out test, Hinglish achieved 100% and Hindi achieved 92.3% F1. English (77.8% F1) represented the primary edge case source, missing atypical scams lacking conventional keywords (e.g., student accidental transfer refund pleas) and misclassifying genuine utility receipts containing urgency words.

### 6.4 Script-Rule Engine & Phonetic Devanagari Normalization
`assets/rules/call_rules.json` contains regex rules across 10 scam script categories:
1. `digital_arrest` (CBI, police, webcam detention, arrest warrant)
2. `fake_kyc` (Bank account suspended, KYC verification, Aadhaar update)
3. `courier_customs` (FedEx parcel, customs narcotics, contraband seizure)
4. `remote_access` (AnyDesk, TeamViewer, QuickSupport installation)
5. `otp_request` (Read OTP, verify code, 6-digit SMS)
6. `upi_collect` (Accept request, enter UPI PIN to receive money)
7. `loan_threat` (Instant loan, contact list hacking, extortion)
8. `lottery_prize` (KBC prize, lucky draw, processing fee deposit)
9. `telecom_threat` (SIM card disconnection within 2 hours)
10. `electricity_bill` (Power disconnection tonight due to unpaid bill)

**Devanagari Phonetic Normalization (`LiveCallAnalyzer`):**
Audio transcription often introduces phonetic spelling variations. `LiveCallAnalyzer.normalizeWord()` applies rule-based character folding before matching:
- **Vowel Folding:** Short and long vowels (`ि` $\leftrightarrow$ `ी`, `ु` $\leftrightarrow$ `ू`).
- **Consonant Confusion:** Dental vs retroflex consonants (`त` $\leftrightarrow$ `ट`, `द` $\leftrightarrow$ `ड`, `थ` $\leftrightarrow$ `ठ`).
- **Sibilant Normalization:** `श`, `ष`, `स` $\to$ `स`.
- **Nukta Stripping:** `क़` $\to$ `क`, `फ़` $\to$ `फ`, `ज़` $\to$ `ज`.

---

## 7. Backend Architecture & API Specifications

The backend service is located in `backend/` and implemented with **Python FastAPI**, **SQLite3**, and **faster-whisper**.

### 7.1 Server Runtime & faster-whisper Configuration
- **Entry Point:** `backend/main.py`
- **Default Port:** `0.0.0.0:8000` (CORS enabled for mobile clients, emulators, and LAN hosts).
- **Audio Decoding:** PyAV with monkey-patched `metadata_errors` fix ensuring compatibility with Python 3.13 and PyAV 14+/19+.
- **Speech-to-Text Model:** `faster-whisper` `small` model running on CPU with `int8` quantization (~2s per 6s audio chunk).
- **Devanagari Script Steering:** Initial prompt `HINDI_PROMPT` enforces output in Devanagari script, preventing smaller Whisper models from writing Hindi speech in Urdu or Latin transliteration.

### 7.2 REST API Endpoints Specification

#### 1. `GET /health`
Returns operational health, Whisper model state, and total database reports.
```json
{
  "status": "ok",
  "model_loaded": true,
  "reports_count": 300
}
```

#### 2. `POST /transcribe`
Transcribes audio recordings (`.wav`, `.mp3`, `.m4a`, `.ogg`, `.amr`, `.aac`, `.3gp`, `.opus`, `.flac`).
- **Query Parameter:** `?lang=hi|en|auto` (default: `auto`).
- **Multipart Form:** `file: Binary`
- **Response:**
  ```json
  {
    "text": "आपका बिजली का बिल बकाया है, तुरंत अपडेट करें।",
    "lang": "hi"
  }
  ```
- **Silent Audio Handling:** If VAD detects no audible speech, returns `{"text": "", "lang": "hi"}` with `200 OK` (no error).

#### 3. `POST /reports`
Records an anonymous fraud incident in SQLite.
- **Request Body:**
  ```json
  {
    "type": "otp",
    "district": "Raipur",
    "ts": "2026-11-23T14:00:00Z"
  }
  ```
- **Validation:** `district` must match one of the 33 Chhattisgarh districts or `"unknown"` (returns `422 Unprocessable Entity` otherwise). `type` must be one of `otp`, `fake_qr`, `loan_app`, `call`, `other`.
- **Response `201 Created`:** `{"status": "success", "id": 301}`

#### 4. `GET /trends`
Returns district-level aggregated incident counts.
```json
[
  {"district": "Raipur", "type": "otp", "count": 23},
  {"district": "Durg", "type": "fake_qr", "count": 15}
]
```

#### 5. `GET /trends/summary`
Returns comprehensive aggregated statistics with privacy preservation.
- **K-Anonymity:** Data cells with counts $< 5$ are suppressed (`"min_count": 5`).
- **Payload:** Separated into `synthetic` (pre-seeded) and `live` (user submitted), each containing `total`, `by_district_type`, `by_district`, `by_type`, `weekly` (12 weeks Monday-start), and `suppressed_cells`.

#### 6. `GET /alerts`
Detects emerging scam outbreaks.
- **Query Parameter:** `?include_synthetic=false`
- **Output:** Returns active `spike` alerts (last 7 days count vs prior 4-week baseline) and `cluster` alerts (clusters of $\ge 3$ matching SimHash message fingerprints).

#### 7. `POST /fingerprints`
Stores anonymous 64-bit SimHash (16 hex digits) of user-reported scam messages for cluster detection.
- **Request Body:** `{"fp": "a1b2c3d4e5f60718", "category": "electricity_bill"}`
- **Response `201 Created`:** `{"status": "success", "id": 12}`

### 7.3 SQLite Database Schema & Seeding
Database located at `backend/data.db`:
- **Table `reports`:** `id`, `type`, `district`, `ts`, `source` (`'seed'` vs `'user'`). Auto-seeded at startup with 300 realistic Chhattisgarh fraud incidents across 10 major districts.
- **Table `fingerprints`:** `id`, `fp` (16 hex chars), `category`, `ts`.

---

## 8. Complete Repository Directory & File Catalog

```
ScamRakshak/
├── AGENTS.md                                # Team folder ownership rules and locked contracts
├── pubspec.yaml                             # Dependencies, assets, and typography declarations
├── analysis_options.yaml                    # Dart analysis options and linter configurations
├── README.md                                # General project introduction
├── PROJECT_DOCUMENTATION.md                 # Complete system documentation (this document)
│
├── android/                                 # Native Android host configuration
│   ├── app/src/main/AndroidManifest.xml     # Permissions, Share intent filters, Foreground Service
│   └── app/src/main/kotlin/.../
│       └── MainActivity.kt                  # Share Intent receiver, Lockscreen Full-Screen Intent
│
├── assets/                                  # 100% Offline bundled application assets
│   ├── fonts/
│   │   └── NotoSansDevanagari-Regular.ttf   # Bundled Devanagari typography
│   ├── models/
│   │   └── scam_model.json                  # Exported TF-IDF + Logistic Regression JSON model (786 KB)
│   ├── rules/
│   │   └── call_rules.json                  # Script rules across 10 scam categories
│   ├── lessons/                             # 11 Trilingual Safety Lesson JSON definitions
│   ├── quiz/                                # 7 Trilingual Quiz Question Bank JSON definitions
│   ├── data/                                # District names and Chhattisgarh seeding data
│   └── samples/                             # Sample call recordings, transcripts, and live MP3s
│       └── live/audio/                      # 5 Spoken multi-chunk MP3 scenarios for Live Call Guard
│
├── lib/                                     # Flutter application codebase
│   ├── main.dart                            # App initialization, ProviderScope, GoRouter mount
│   │
│   ├── core/                                # Core shared architecture (Sayanthan)
│   │   ├── api_client.dart                  # Backend REST client, offline fallback, error typing
│   │   ├── providers.dart                   # Riverpod provider definitions
│   │   ├── router.dart                      # Declarative GoRouter configuration (15 routes)
│   │   ├── share_intent.dart                # Android ACTION_SEND text & audio bridge
│   │   ├── strings.dart                     # Trilingual localization dictionary (class S)
│   │   ├── theme.dart                       # AppTheme: Accessible high-contrast teal theme
│   │   ├── screens/
│   │   │   └── home_screen.dart             # Primary dashboard (DFL score, 8 action tiles)
│   │   └── widgets/
│   │       └── language_switcher.dart       # Reusable 3-chip language switcher (en, hi, chh)
│   │
│   ├── engine/                              # On-device AI & rule engines (Radhika)
│   │   ├── models.dart                      # Locked data contracts (ScamResult, CallResult, etc.)
│   │   ├── scam_classifier.dart             # Pure Dart TF-IDF + Logistic Regression evaluator
│   │   ├── call_analyzer.dart               # Transcript pattern matcher with negation windows
│   │   └── live_call_analyzer.dart          # Real-time incremental ASR-tolerant call analyzer
│   │
│   └── features/                            # Domain-specific feature modules
│       ├── message_detector/                # SMS/WhatsApp scam detector & SimHash generator
│       │   ├── message_detector_screen.dart # Message checking screen
│       │   ├── message_fingerprint.dart     # 64-bit SimHash (16 hex) anonymous fingerprinting
│       │   └── message_examples.dart        # 8 Preset sample messages
│       ├── qr_check/                        # Fake UPI QR Code Scanner & Validator
│       │   ├── qr_check_screen.dart         # QR check screen (paste & scan UI)
│       │   ├── qr_scanner_page.dart         # Live camera scanner (mobile_scanner)
│       │   ├── upi_qr.dart                  # UPI protocol parser & 90+ handle validator
│       │   └── qr_check_strings.dart        # Trilingual strings for QR checks
│       ├── call_detector/                   # Call transcript and audio checker
│       │   ├── call_detector_screen.dart    # Manual audio/transcript check screen
│       │   ├── auto_analyze_service.dart    # Android Foreground Service for call recording
│       │   ├── auto_analyze_screen.dart     # Auto-analyze settings & directory watcher
│       │   ├── call_timeline.dart           # Interactive visual threat timeline
│       │   ├── recording_result_screen.dart # Detailed recording report
│       │   └── recording_warning_screen.dart# Lockscreen full-screen warning window
│       ├── live_call/                       # Live Call Guard module
│       │   ├── live_call_screen.dart        # Live speakerphone monitoring screen
│       │   ├── live_call_io.dart            # Mic chunk recorder & audio player
│       │   └── recording_inbox.dart         # Historical recording result inbox
│       ├── report/                          # Fraud incident reporting module
│       │   ├── report_screen.dart           # 1930 dialer CTA, portal links, evidence checklist
│       │   └── report_data.dart             # ReportQueue offline FIFO queue in SharedPreferences
│       ├── lessons/                         # Educational safety lessons module
│       │   ├── lesson_list_screen.dart      # 11-lesson hub & category filter
│       │   ├── lesson_detail_screen.dart    # Interactive flashcard reader
│       │   └── lesson_models.dart           # Lesson data models & progress tracker
│       ├── quiz/                            # Interactive assessment & literacy score
│       │   ├── quiz_screen.dart             # Gamified quiz assessment
│       │   ├── quiz_models.dart             # Question schemas & scoring algorithms
│       │   └── literacy_score.dart          # Digital Financial Literacy Score (0-100)
│       └── dashboard/                       # Analytics and trends module
│           ├── trends_screen.dart           # Trends dashboard with fl_chart graphics
│           └── trends_models.dart           # District trends data structures
│
├── backend/                                 # FastAPI server & Whisper transcription (Aagam)
│   ├── main.py                              # REST API endpoints, lifespan events, PyAV patch
│   ├── database.py                          # SQLite database schema, seeding, K-anonymity logic
│   ├── models.py                            # Pydantic schemas for requests and responses
│   ├── requirements.txt                     # Python dependencies
│   ├── bench.py                             # Latency benchmarks for audio transcription
│   ├── test_all_endpoints.py                # REST API test suite
│   ├── test_live_transcribe.py              # Whisper transcription test suite
│   └── test_trends_alerts.py                # Spike and cluster alert test suite
│
├── ml/                                      # Machine learning training pipeline (Radhika)
│   ├── build_dataset.py                     # Dataset builder & multilingual augmentations
│   ├── preprocess.py                        # NLP tokenization, URL masking, Devanagari rules
│   ├── train.py                             # scikit-learn Logistic Regression training script
│   ├── export_model.py                      # Serializes model weights to pure JSON
│   ├── handwritten_test.py                  # Evaluation on realistic human test samples
│   ├── results.md                           # Empirical benchmark results and held-out scores
│   └── data/                                # Datasets (train, test, extra_train, heldout_2026.csv)
│
└── test/                                    # Automated Flutter test suites (322 tests passing)
    ├── detector_screens_test.dart           # SMS and Call detector screen widget tests
    ├── engine_test.dart                     # Core engine functionality tests
    ├── report_screen_test.dart              # Reporting screen, 1930 dialing, and checklist tests
    ├── share_intent_test.dart               # Share intent handler tests
    ├── strings_coverage_test.dart           # Trilingual string coverage tests
    ├── widget_test.dart                     # Widget mounting tests
    ├── engine/
    │   ├── call_analyzer_test.dart          # Call script rule matcher tests
    │   ├── call_intent_test.dart            # Intent analysis tests
    │   ├── heldout_eval_test.dart           # Benchmark test against heldout_2026.csv
    │   ├── live_call_analyzer_test.dart     # Phonetic normalization and chunk evaluation tests
    │   ├── live_whisper_fixtures_test.dart  # Whisper fixture integration tests
    │   ├── parity_test.dart                 # Dart vs Python mathematical parity tests (< 1e-6)
    │   ├── reported_calls_test.dart         # Realistic fraud call scenario tests
    │   ├── samples_test.dart                # Offline sample evaluation tests
    │   └── scam_classifier_test.dart        # SMS classifier unit tests
    └── features/
        ├── auto_analyze_test.dart           # Background recording auto-analyze tests
        ├── fingerprint_test.dart            # 64-bit SimHash fingerprinting tests
        ├── lessons_test.dart                # Lesson JSON parsing and progress tests
        ├── literacy_offline_test.dart       # Digital Financial Literacy scoring tests
        ├── live_call_test.dart              # Live call stream and demo scenario tests
        ├── phone_layout_test.dart           # Responsive layout and language switching tests
        ├── qr_check_test.dart               # UPI QR parsing, VPA validation, and risk tests
        ├── quiz_test.dart                   # Quiz engine, randomizer, and high score tests
        ├── recording_inbox_test.dart        # Call recording timeline and inbox tests
        └── trends_test.dart                 # District trends and chart rendering tests
```

---

## 9. Setup, Execution & Testing Guide

### 9.1 Mobile Application (Flutter)

#### Prerequisites
- Flutter SDK `^3.14.0` (Dart 3.5+)
- Android Studio / Android SDK (API 34 recommended)

#### Execution Commands
```bash
# 1. Fetch dependencies
flutter pub get

# 2. Run static code analysis (zero issues allowed)
flutter analyze

# 3. Execute the full test suite (322 tests)
flutter test

# 4. Run application on connected Android device or emulator
flutter run
```

### 9.2 Backend Server (Python FastAPI)

#### Prerequisites
- Python 3.10+
- FFmpeg installed on system path (required by faster-whisper / PyAV)

#### Execution Commands
```bash
# 1. Navigate to backend directory
cd backend

# 2. Set up virtual environment
python -m venv venv
.\venv\Scripts\Activate.ps1    # Windows PowerShell
source venv/bin/activate       # macOS / Linux

# 3. Install dependencies
pip install -r requirements.txt

# 4. Launch backend server (listens on 0.0.0.0:8000)
uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# 5. Run automated backend test suites
python test_all_endpoints.py
python test_live_transcribe.py
python test_trends_alerts.py
```

### 9.3 Machine Learning Pipeline (Retraining & Export)

```bash
cd ml
pip install -r requirements.txt

# 1. Generate augmented dataset
python build_dataset.py

# 2. Train model and evaluate
python train.py

# 3. Export weights to pure JSON
python export_model.py

# 4. Evaluate on realistic human samples
python handwritten_test.py
```

---

## 10. Feature Verification & Implementation Status Matrix

The matrix below explicitly classifies features as **Code-Implemented**, **Test-Verified** (automated test passing), and **Real-Device Verified**:

| Feature Component | Implementation Status | Automated Test Verification | Real-Device Verified | Technical Notes |
| :--- | :---: | :---: | :---: | :--- |
| **Offline Message Detector** | Complete | **Verified** (`scam_classifier_test.dart`, `detector_screens_test.dart`) | Code Verified | 100% on-device; classifies English, Hindi, Hinglish. |
| **SimHash Message Fingerprints** | Complete | **Verified** (`fingerprint_test.dart`) | Code Verified | 64-bit SimHash (16 hex); opt-in anonymous sharing. |
| **Fake UPI QR Checker** | Complete | **Verified** (`qr_check_test.dart`) | Code Verified | Offline UPI parsing, 90+ handles, reverse trap checks. |
| **Live Camera QR Scanning** | Complete | **Verified** (`qr_check_test.dart`) | Hardware Dependent | Uses `mobile_scanner` with fallback to text paste. |
| **Call Transcript Analyzer** | Complete | **Verified** (`call_analyzer_test.dart`) | Code Verified | 10 scam script categories; negation window checks. |
| **Live Call Guard (Demo Mode)**| Complete | **Verified** (`live_call_test.dart`) | Code Verified | 5 bundled multi-lingual spoken scenarios with playback. |
| **Live Call Guard (Mic Stream)**| Complete | **Verified** (`live_call_test.dart`) | Hardware Dependent | Records 6s chunks, drops silence, uploads to backend. |
| **Auto Call Recording Scanner** | Complete | **Verified** (`auto_analyze_test.dart`) | OS Dependent | Android 11+ requires `MANAGE_EXTERNAL_STORAGE`. |
| **Lockscreen Scam Warnings** | Complete | **Verified** (`auto_analyze_test.dart`) | OS Dependent | Utilizes `USE_FULL_SCREEN_INTENT` & `setShowWhenLocked`. |
| **Call Threat Timeline** | Complete | **Verified** (`recording_inbox_test.dart`)| Code Verified | Interactive visual timeline mapping spoken threat points. |
| **Android Share Intent Target** | Complete | **Verified** (`share_intent_test.dart`) | Code Verified | Handles `ACTION_SEND` text/plain and audio/*. |
| **1930 Helpline Direct Dialing**| Complete | **Verified** (`report_screen_test.dart`) | Code Verified | Launches `tel:1930` via `url_launcher`. |
| **Offline Report Queue** | Complete | **Verified** (`report_screen_test.dart`) | Code Verified | Queues reports in SharedPreferences (`report_queue_v1`). |
| **Digital Financial Literacy Score**| Complete | **Verified** (`literacy_offline_test.dart`)| Code Verified | Weighted 0-100 score combining lessons & quizzes. |
| **Safety Lessons (11 Scenarios)**| Complete | **Verified** (`lessons_test.dart`) | Code Verified | Full Devanagari translation in `en`, `hi`, `chh`. |
| **Interactive Safety Quizzes** | Complete | **Verified** (`quiz_test.dart`) | Code Verified | Quick, Full, and Topic quiz modes with explanations. |
| **District Scam Trends** | Complete | **Verified** (`trends_test.dart`) | Code Verified | Dynamic charts rendered via `fl_chart`. |
| **K-Anonymity Trend Summary** | Complete | **Verified** (`test_trends_alerts.py`) | Code Verified | Hides cells with count $< 5$ via `GET /trends/summary`. |
| **Emerging Spike & Cluster Alerts**| Complete | **Verified** (`test_trends_alerts.py`) | Code Verified | Spikes & SimHash clusters via `GET /alerts`. |
| **Trilingual Localization** | Complete | **Verified** (`strings_coverage_test.dart`, `phone_layout_test.dart`) | Code Verified | Instant language switching with zero restart required. |
| **FastAPI Backend Services** | Complete | **Verified** (`test_all_endpoints.py`)| Code Verified | Health, transcribe, reports, trends operational. |
| **faster-whisper STT Engine** | Complete | **Verified** (`test_live_transcribe.py`)| Code Verified | Tested with small CPU int8 model and Devanagari steering. |

---

## 11. Known Limitations, Constraints & Future Roadmap

### 11.1 Technical Constraints & Operating System Quirks
1. **Android Call Recording Restrictions (Android 10+):**
   - Modern Android versions restrict third-party background call recording APIs.
   - The *Automatic Call Recording Analyzer* reads files generated by the manufacturer's native dialer (e.g., Google Phone, Samsung, or Xiaomi call recorder directory).
   - On Android 11+, users must grant `MANAGE_EXTERNAL_STORAGE` ("All files access").
2. **Microphone Exclusivity During Active Calls:**
   - Android prevents secondary background apps from opening the microphone during an ongoing standard phone call. For *Live Call Guard*, the user must turn on **Speakerphone** so the ambient microphone can capture both sides of the conversation.
3. **Whisper Latency on Edge Hardware:**
   - The `small` Whisper model takes ~1.5 to 2.2 seconds to transcribe a 6-second audio chunk on a modern laptop CPU. On entry-level edge servers, latency may rise. The architecture mitigates this using local dBFS silence filtering and pre-transcribed demo scenarios.
4. **Offline Font Dependency:**
   - App-wide typography requires `assets/fonts/NotoSansDevanagari-Regular.ttf` to ensure proper Devanagari rendering without cloud font downloads.

### 11.2 Strategic Roadmap
- **On-Device Whisper (LiteRT / ONNX):** Port Whisper speech recognition directly to on-device NPU/CPU execution, eliminating local Wi-Fi backend dependencies for live call transcription.
- **Dialer Accessibility Assistant:** Optional Android Accessibility Service prompting the user with a subtle overlay to enable speakerphone whenever an unknown or flagged caller connects.
- **Regional Dialect Expansion:** Broaden the localization engine beyond Chhattisgarhi to Gondi, Halbi, Bhojpuri, and Maithili.
- **Automated Carrier SMS Whitelisting:** Real-time synchronization of recognized Indian telecom sender headers (e.g., `AD-HDFCBK`, `VK-SBIINB`) to reduce false-positive rates on legitimate transactional alerts.
