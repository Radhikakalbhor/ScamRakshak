import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../strings.dart';
import '../theme.dart';
import '../widgets/language_switcher.dart';

/// ScamRakshak Home Screen.
/// Designed for maximum accessibility, clarity, and ease of use for rural
/// and first-time smartphone users.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    const navigationTiles = [
      _HomeTileData(
        titleKey: 'check_message',
        subtitleKey: 'check_message_sub',
        icon: Icons.mark_chat_unread_rounded,
        iconColor: Color(0xFF00796B),
        iconBgColor: Color(0xFFE0F2F1),
        route: '/message',
      ),
      _HomeTileData(
        titleKey: 'check_call',
        subtitleKey: 'check_call_sub',
        icon: Icons.phone_in_talk_rounded,
        iconColor: Color(0xFF0D47A1),
        iconBgColor: Color(0xFFE3F2FD),
        route: '/call',
      ),
      _HomeTileData(
        titleKey: 'report_fraud',
        subtitleKey: 'report_fraud_sub',
        icon: Icons.report_problem_rounded,
        iconColor: Color(0xFFD32F2F),
        iconBgColor: Color(0xFFFFEBEE),
        route: '/report',
      ),
      _HomeTileData(
        titleKey: 'learn',
        subtitleKey: 'learn_sub',
        icon: Icons.school_rounded,
        iconColor: Color(0xFF2E7D32),
        iconBgColor: Color(0xFFE8F5E9),
        route: '/lessons',
      ),
      _HomeTileData(
        titleKey: 'quiz',
        subtitleKey: 'quiz_sub',
        icon: Icons.psychology_rounded,
        iconColor: Color(0xFF6A1B9A),
        iconBgColor: Color(0xFFF3E5F5),
        route: '/quiz',
      ),
      _HomeTileData(
        titleKey: 'scam_trends',
        subtitleKey: 'scam_trends_sub',
        icon: Icons.insights_rounded,
        iconColor: Color(0xFFE65100),
        iconBgColor: Color(0xFFFFF3E0),
        route: '/dashboard',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.security, size: 26),
            const SizedBox(width: 10),
            Text(s.t('app_name')),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Offline Protection Banner
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLightTeal,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user, color: AppTheme.primaryTeal, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.t('offline_badge'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDarkTeal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Prominent Language Switcher Card
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.translate, size: 20, color: AppTheme.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            s.t('select_language'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const LanguageSwitcher(),
                    ],
                  ),
                ),
              ),

              // Six Navigation Tiles
              ...navigationTiles.map(
                (tile) => _buildLargeNavTile(
                  context: context,
                  data: tile,
                  s: s,
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLargeNavTile({
    required BuildContext context,
    required _HomeTileData data,
    required S s,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(data.route),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: data.iconBgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  data.icon,
                  size: 32,
                  color: data.iconColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t(data.titleKey),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.t(data.subtitleKey),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 20,
                color: Color(0xFF90A4AE),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTileData {
  final String titleKey;
  final String subtitleKey;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String route;

  const _HomeTileData({
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.route,
  });
}


