import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/call_detector/call_detector_screen.dart';
import '../features/message_detector/message_detector_screen.dart';
import '../features/report/report_screen.dart';
import 'screens/home_screen.dart';
import 'screens/placeholder_screen.dart';

/// App router configuration using GoRouter.
/// Routes correspond to core navigation specified in AGENTS.md and task specs.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
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
      path: '/report',
      // Optional extra: report type ('otp'|'fake_qr'|'loan_app'|'call'|'other') to preselect.
      builder: (context, state) => ReportScreen(initialType: state.extra as String?),
    ),
    GoRoute(
      path: '/lessons',
      builder: (context, state) => const PlaceholderFeatureScreen(
        titleKey: 'learn',
        icon: Icons.school_rounded,
        moduleOwner: 'Aagam (lib/features/lessons)',
      ),
    ),
    GoRoute(
      path: '/quiz',
      builder: (context, state) => const PlaceholderFeatureScreen(
        titleKey: 'quiz',
        icon: Icons.psychology_rounded,
        moduleOwner: 'Aagam (lib/features/quiz)',
      ),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const PlaceholderFeatureScreen(
        titleKey: 'scam_trends',
        icon: Icons.insights_rounded,
        moduleOwner: 'Aagam (lib/features/dashboard)',
      ),
    ),
  ],
);
