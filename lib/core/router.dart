import 'package:go_router/go_router.dart';

import '../features/call_detector/auto_analyze_screen.dart';
import '../features/call_detector/call_detector_screen.dart';
import '../features/call_detector/recording_result_screen.dart';
import '../features/dashboard/trends_screen.dart';
import '../features/lessons/lesson_list_screen.dart';
import '../features/live_call/live_call_screen.dart';
import '../features/live_call/recording_inbox.dart';
import '../features/message_detector/message_detector_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/report/report_screen.dart';
import 'screens/home_screen.dart';

/// App router configuration using GoRouter.
/// Routes correspond to core navigation specified in AGENTS.md and task specs.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      // AutoAnalyzeHost opens results from "auto-analyzed call recording" notifications.
      builder: (context, state) => const AutoAnalyzeHost(child: HomeScreen()),
    ),
    GoRoute(
      path: '/message',
      builder: (context, state) => const MessageDetectorScreen(),
    ),
    GoRoute(
      path: '/call',
      builder: (context, state) => const CallDetectorScreen(),
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
      path: '/live',
      builder: (context, state) => const LiveCallScreen(),
    ),
    GoRoute(
      path: '/live/inbox',
      builder: (context, state) => const RecordingInboxScreen(),
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
