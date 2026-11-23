# ScamRakshak audit (Phase 1, read-only)

Checked against the code at commit `3173186` (2026-11-23). Statuses: **Complete**, **Partial**, **Missing**, **Broken**, **Platform-limited**. "needs device test" = cannot be proven on an emulator or in unit tests.

Baseline: `flutter analyze` 29 issues, all `info` (deprecated `material.dart` import), 0 errors and 0 warnings. `flutter test`: 218 passed, 0 failed.

## 1. Message detector

| requirement | status | evidence | remaining work |
|---|---|---|---|
| Real Dart TF-IDF + LR inference loaded from assets | Complete | `lib/engine/scam_classifier.dart:59-62` loads `assets/models/scam_model.json`; `:97-142` runs n-grams → tf·idf → l2 → dot+intercept → sigmoid; `test/engine/parity_test.dart` checks against sklearn | none |
| URL handling | Complete | URLs → `urltoken` `scam_classifier.dart:93`; shown as "link" reason `message_detector_screen.dart:171-172` | none |
| Share input (share a message into the app) | Missing | no `ACTION_SEND` intent-filter in `android/app/src/main/AndroidManifest.xml:41-44`; no handler in `MainActivity.kt` | native intent handling (outside the P0-P2 list) |
| Offline | Complete | screen never calls `apiClientProvider` (`grep` of `lib/features/message_detector`) | zero-network test (P0) |
| en / hi / Hinglish | Complete | `ml/results.md:35-55` per-language blocks | none |
| No train/test leakage | Partial | exact-text dedup `ml/train.py:109-112`; Jaccard ≥ 0.8 filter `:44-65`; but extra train rows were added after looking at hand-written test errors (`ml/results.md:2`), and templated test rows share templates with train (`ml/results.md:57`) | clean, never-seen held-out set of ≥ 100 messages (P0) |

## 2. Call detector

| requirement | status | evidence | remaining work |
|---|---|---|---|
| Audio formats m4a, mp3, wav, amr, ogg | Broken (amr) | backend accepts only `.wav .mp3 .m4a .ogg` (`backend/main.py:85-90`), so `.amr` returns 400; the auto-analyze watcher sends `amr/aac/3gp` (`auto_analyze_core.dart:12`) | accept amr/aac/3gp (P1) |
| Whisper runs on the backend, so it needs network | Platform-limited (by design) | `api_client.dart:68-123`; offline message `call_detector_screen.dart:98-99` | state this in the UI (P1) |
| Clear errors when backend down | Partial | offline vs failed keys `call_detector_screen.dart:98-102`; an HTTP 400 (bad format) shows the same generic "could not be converted" | name the format error (P1) |
| Offline sample calls | Complete | `call_detector_screen.dart:27-34`, `:111-118` | none |

## 3. Reporting

| requirement | status | evidence | remaining work |
|---|---|---|---|
| 1930 for money lost | Partial | single list of actions, `report_screen.dart:110-133` | split "I lost money" path (P0) |
| Chakshu for suspected fraud before loss | Partial | same list, not separated `report_screen.dart:126-133` | "suspicious, no loss" path (P0) |
| cybercrime.gov.in | Complete | `report_data.dart:22` | none |
| Evidence checklist | Complete | `report_data.dart:17-44`, persisted; `test/report_screen_test.dart:86` | none |
| Offline queue, persistence and retry | Missing | fire-and-forget, errors swallowed `report_screen.dart:47-51` | persistent queue + retry (P0) |
| Report sent without telling the user | Partial (privacy) | posts on every action tap, district `'unknown'` `report_screen.dart:50` | explicit "send anonymous count" step |

## 4. Lessons

| requirement | status | evidence | remaining work |
|---|---|---|---|
| Count | Complete | 11 lessons, 48 cards `lesson_models.dart:8-20`, `assets/lessons/*.json` | none |
| en / hi / chh completeness | Complete | every `{en,hi,chh}` map non-empty in all 11 files (script scan) | none |
| Offline | Complete | `rootBundle` only `lesson_models.dart:89-95` | zero-network test (P0) |
| Progress persistence | Complete | `LessonProgress` `lesson_models.dart:98-116` | feed the literacy score (P0) |

## 5. Quiz and Digital Financial Literacy Score

| requirement | status | evidence | remaining work |
|---|---|---|---|
| Quiz content | Partial | 41 questions; 7 topics have only 3 (`assets/quiz/*.json`) | at least 5 per topic (P1) |
| Quiz score persisted | Partial | only the latest run's score `quiz_models.dart:164-184` | per-topic best accuracy |
| ONE overall persistent DFL score, shown to user, with recommendation | Missing | score only from the last quiz, quiz-only (`quiz_models.dart:126-153`); not on home (`home_screen.dart`) | unified quiz + lessons 0-100 score, level, weakest topic, on home (P0) |

## 6. Dashboard

| requirement | status | evidence | remaining work |
|---|---|---|---|
| Seeded vs real data labelled | Missing | `reports` table has no source column `backend/database.py:134-141`; 300 seeded rows mixed with user rows `:163-191`; UI shows one total `trends_screen.dart:630-645` | `source` column + labels (P0) |
| Aggregation per district / type | Complete | `database.py:211-231`, `trends_stats.dart:112-137` | none |
| Trends over time | Partial | local 7-day chart `trends_stats.dart:82-95`; no server time series | weekly server trend (P0) |
| Anonymisation | Partial | only type/district/ts stored `models.py:12-34`; no small-cell suppression | suppress counts < 5 (P0) |
| Local history stores no text | Complete | `detection_history.dart:12`, test `trends_test.dart:180` | none |

## 7. Live call

| requirement | status | evidence | remaining work |
|---|---|---|---|
| Mic + speakerphone only | Platform-limited | Android 10+ gives ordinary apps silence during calls; `record` config `live_call_io.dart`; hint `live_call_strings.dart` `live_silent_hint` | UI wording must say "mic + speakerphone, may not work on all phones" (P2) |
| Chunk upload, transcription, alerts, cleanup | Complete | `live_call_screen.dart:290-411` (files deleted `:350,:354,:401`) | needs device test |
| Consent | Complete | `live_call_screen.dart:58,121,129` | none |
| Needs backend | Platform-limited | `isReachable` check before listening | none |

## 8. Fake QR checker — Missing

No screen, route or `upi://` parser exists (`grep -r "upi://" lib` finds nothing). Remaining: paste or scan, parse `pa`/`pn`, flag risks (P2).

## 9. Emerging-scam alerts — Missing

No spike detection in `backend/` and no alert card in `trends_screen.dart`. Remaining: spike detection against a trailing baseline, opt-in fingerprints, dashboard card (P2).

## Offline vs backend

| feature | offline | needs backend |
|---|---|---|
| Message detector, lessons, quiz, evidence checklist, Live Call demo mode, sample calls, local Scam Trends | yes | no |
| Call recording analysis, Live Call mic mode, auto-analyze, server trends, report counts | no | `/transcribe`, `/reports`, `/trends` |
| 1930 dial / portals | dialer works offline; portals need internet | no |

## Strings

Script scan of every `en/hi/chh` map in `lib/**`: 355 keys in each language; 0 missing in hi or chh. Only `report_cybercrime` is identical to English, and that is a URL (intended). Every `t('key')` literal is defined. Dynamic keys (`risk_*`, `script_*`, `lessons_cat_*`) were spot-checked.

## Privacy

| item | status | evidence |
|---|---|---|
| Live audio chunks deleted after upload | Complete | `live_call_screen.dart:350,354,401`; server temp file removed `backend/main.py:250-256` |
| Auto-analyze transcripts kept on the phone (up to 500) | Partial | `auto_analyze_core.dart` `saveResult`; disclosed in the consent text (`auto_consent_more`) |
| Consent for mic and recordings | Complete | `live_call_consent_v1`; `auto_rec_consent_v1` |
| Report fields | Complete | type, district, ts only (`backend/models.py:12-34`) |
| Report sent silently | Partial | `report_screen.dart:47-51` |

## Test coverage

| area | covered | evidence |
|---|---|---|
| Offline / backend failure | yes | `detector_screens_test.dart` (offline), `report_screen_test.dart:60`, `trends_test.dart:279`, `live_call_test.dart` (offline, HTTP errors) |
| Permissions | yes (fakes) | `live_call_test.dart` (mic denied), `auto_analyze_test.dart` (setup) — needs device test |
| Persistence | yes | evidence `report_screen_test.dart:86`, history `trends_test.dart:147`, quiz `quiz_test.dart`, auto-analyze store |
| Zero network calls for offline features | no | — (P0) |

## Needs device test

Mic chunk capture and transcription on Samsung/Vivo; speakerphone during a real call; auto-analyze foreground service, notifications and All-files access; notification taps; QR camera scan (P2); 1930 dialer intent.

## Phase 2 status (after the fixes)

| item | now |
|---|---|
| Held-out accuracy (108 new messages, shipped Dart model) | 0.898 overall; English 0.778, Hindi 0.917, Hinglish 1.000 (`ml/results.md`) |
| Zero network in message / lessons / quiz, bundled font | tested (`test/features/literacy_offline_test.dart`) |
| Digital Financial Literacy Score (quiz 60 + lessons 40, level, weakest topic, on home) | Complete |
| Reporting: "I lost money" vs "suspicious, no loss"; persistent offline queue with retry | Complete |
| Dashboard: synthetic vs live labels, per district/type, weekly trend, counts < 5 hidden, districts validated | Complete |
| Call formats amr/aac/3gp accepted; format and server-starting errors named; "needs server" stated | Complete (decoding real AMR files: needs device test) |
| Quiz: every topic has at least 5 questions | Complete (55 questions, 5 per topic) |
| Fake-QR checker | Partial: paste works; camera scan needs a QR plugin (`pubspec.yaml` change was not allowed) |
| Emerging-scam alerts (spikes + opt-in fingerprint clusters, dashboard card) | Complete |
| Live call wording (mic + speakerphone, may not work on all phones) | Complete |
| Share input | Missing (not in the P0-P2 list) |
