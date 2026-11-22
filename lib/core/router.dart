import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
      builder: (context, state) => const PlaceholderFeatureScreen(
        titleKey: 'check_message',
        icon: Icons.mark_chat_unread_rounded,
        moduleOwner: 'Sayanthan (lib/features/message_detector)',
      ),
    ),
    GoRoute(
      path: '/call',
      builder: (context, state) => const PlaceholderFeatureScreen(
        titleKey: 'check_call',
        icon: Icons.phone_in_talk_rounded,
        moduleOwner: 'Sayanthan (lib/features/call_detector)',
      ),
    ),
    GoRoute(
      path: '/report',
      builder: (context, state) => const PlaceholderFeatureScreen(
        titleKey: 'report_fraud',
        icon: Icons.report_problem_rounded,
        moduleOwner: 'Sayanthan (lib/features/report)',
      ),
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
