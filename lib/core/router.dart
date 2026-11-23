import 'dart:io';

import 'package:go_router/go_router.dart';

import '../features/call_detector/auto_analyze_screen.dart';
import '../features/call_detector/call_detector_screen.dart';
import '../features/call_detector/call_timeline.dart';
import '../features/call_detector/recording_result_screen.dart';
import '../features/call_detector/recording_warning_screen.dart';
import '../features/dashboard/trends_screen.dart';
import '../features/lessons/lesson_list_screen.dart';
import '../features/live_call/live_call_screen.dart';
import '../features/live_call/recording_inbox.dart';
import '../features/message_detector/message_detector_screen.dart';
import '../features/qr_check/qr_check_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/report/report_screen.dart';
import 'screens/home_screen.dart';
import 'share_intent.dart';

/// App router configuration using GoRouter.
/// Routes correspond to core navigation specified in AGENTS.md and task specs.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      // AutoAnalyzeHost opens results from "auto-analyzed call recording" notifications.
      // ShareHost opens texts/recordings shared from other apps.
      builder: (context, state) => const ShareHost(child: AutoAnalyzeHost(child: HomeScreen())),
    ),
    GoRoute(
      path: '/message',
      // Optional extra: shared text, prefilled and checked at once.
      builder: (context, state) => MessageDetectorScreen(initialText: state.extra is String ? state.extra as String : null),
    ),
    GoRoute(
      path: '/call',
      // Optional extra: a shared recording (File, private cache copy) analysed at once.
      builder: (context, state) => CallDetectorScreen(initialAudio: state.extra is File ? state.extra as File : null),
    ),
    GoRoute(
      path: '/call/auto',
      builder: (context, state) => const AutoAnalyzeScreen(),
    ),
    GoRoute(
      path: '/call/recording',
      // extra: notification payload ({"result": id} or {"pending": path}).
      builder: (context, state) => RecordingResultScreen(payload: state.extra as String?),
    ),
    GoRoute(
      path: '/call/warning',
      // extra: saved result id. Full-screen warning for a HIGH/MEDIUM auto-analysed recording.
      builder: (context, state) => RecordingWarningScreen(resultId: state.extra as String),
    ),
    GoRoute(
      path: '/call/warning/demo',
      // extra: CallTimelineResult of the bundled sample call. DEMO only: nothing saved.
      builder: (context, state) => RecordingWarningScreen.demo(demo: state.extra as CallTimelineResult),
    ),
    GoRoute(
      path: '/call/report',
      // extra: saved result id. Reporting options with that recording as evidence.
      builder: (context, state) => RecordingReportScreen(resultId: state.extra as String),
    ),
    GoRoute(
      path: '/live',
      builder: (context, state) => const LiveCallScreen(),
    ),
    GoRoute(
      path: '/live/inbox',
      builder: (context, state) => const RecordingInboxScreen(),
    ),
    GoRoute(
      path: '/qr',
      builder: (context, state) => const QrCheckScreen(),
    ),
    GoRoute(
      path: '/report',
      // Optional extra: report type ('otp'|'fake_qr'|'loan_app'|'call'|'other') to preselect.
      builder: (context, state) => ReportScreen(initialType: state.extra as String?),
    ),
    GoRoute(
      path: '/lessons',
      builder: (context, state) => const LessonListScreen(),
    ),
    GoRoute(
      path: '/quiz',
      builder: (context, state) => const QuizScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const TrendsScreen(),
    ),
  ],
);
