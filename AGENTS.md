# ScamRakshak: rules for every agent

Project: Flutter Android app (offline-first) that detects scam messages and scam calls,
teaches digital payment safety in English/Hindi/Chhattisgarhi, and helps report fraud.
Team of 3. Each person owns specific folders. ONLY edit files inside the folders named in
the user's prompt. Never edit pubspec.yaml, AGENTS.md, lib/core/ or another person's
folders unless the prompt says to. Never rename or change signatures listed below.

## Stack (fixed)
Flutter + Dart, flutter_riverpod, go_router, fl_chart, url_launcher, file_picker, http,
shared_preferences. Backend: Python FastAPI + SQLite + faster-whisper.
No google_fonts (must work offline). Bundled font: Noto Sans Devanagari.

## Folder ownership
lib/core/, lib/features/{message_detector,call_detector,report}/  -> Sayanthan
lib/engine/, assets/models/, assets/rules/, assets/samples/, ml/   -> Radhika
backend/, lib/features/{lessons,quiz,dashboard}/, assets/lessons/,
assets/quiz/, assets/data/                                         -> Aagam

## Languages
Codes: en, hi, chh. Use the S class in lib/core/strings.dart: S.of(context).t('key').
Each feature keeps its own keys in its own folder, e.g. lessons_strings.dart, and
registers them via S.register(map). Hindi and Chhattisgarhi use Devanagari.

## Contracts (LOCKED)
lib/engine/models.dart (Radhika):
  class Reason { String phrase; double weight; }
  class ScamResult { String label /* 'scam'|'genuine' */; double score /*0..1 scam prob*/; List<Reason> reasons; }
  class CallMatch { String phrase; String scriptType; }
  class CallResult { String risk /* 'high'|'medium'|'low' */; List<CallMatch> matches; }
lib/engine/scam_classifier.dart:
  static Future<ScamClassifier> ScamClassifier.load();   // loads assets/models/scam_model.json
  ScamResult classify(String text);                        // sync after load
lib/engine/call_analyzer.dart:
  static Future<CallAnalyzer> CallAnalyzer.load();         // loads assets/rules/call_rules.json
  CallResult analyze(String transcript);
Providers in lib/core/providers.dart (Sayanthan): scamClassifierProvider,
  callAnalyzerProvider, apiClientProvider, localeProvider.
ApiClient (lib/core/api_client.dart, Sayanthan):
  Future<Map> transcribe(File audio);  Future<void> postReport(String type, String district);
  Future<List<Map>> getTrends();  baseUrl is configurable and saved in shared_preferences.
Backend (Aagam):
  GET /health
  POST /transcribe (multipart 'file') -> {"text": "...", "lang": "hi"}
  POST /reports {"type": "otp|fake_qr|loan_app|call|other", "district": "...", "ts": "..."}
  GET /trends -> [{"district": "...", "type": "...", "count": 12}]
Lesson JSON: {"id","title":{en,hi,chh},"cards":[{"icon","text":{en,hi,chh}}]}
Quiz JSON: {"topic","questions":[{"q":{en,hi,chh},"options":{en:[...],hi:[...],chh:[...]},"answer":0}]}

## Working rules
- Small commits, branch per person, only Sayanthan merges to main.
- Everything except /transcribe and /reports and /trends must work with no internet.
- After finishing, summarize which files you created/changed. Do not refactor unrelated code.
## Live Call Guard (contract)
lib/engine/live_call_analyzer.dart (Radhika):
  class LiveCallState { String risk; double score; List<CallMatch> matches; List<CallMatch> newMatches; String transcript; }
  class LiveCallAnalyzer { static Future<LiveCallAnalyzer> load(); LiveCallState add(String chunkText); void reset(); }
Backend: POST /transcribe accepts optional ?lang=hi|en|auto (default auto); silent chunk -> {"text": "", "lang": ...}.
Screen: lib/features/live_call/ (LiveCallScreen), route /live. Demo scripts: assets/samples/live/*.txt (one chunk per line).