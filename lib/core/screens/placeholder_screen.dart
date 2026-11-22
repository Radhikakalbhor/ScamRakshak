import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../strings.dart';
import '../theme.dart';

/// Reusable placeholder scaffold for feature routes during scaffolding.
class PlaceholderFeatureScreen extends StatelessWidget {
  final String titleKey;
  final IconData icon;
  final String moduleOwner;

  const PlaceholderFeatureScreen({
    super.key,
    required this.titleKey,
    required this.icon,
    required this.moduleOwner,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(titleKey)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: s.t('btn_back'),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryLightTeal,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        size: 56,
                        color: AppTheme.primaryTeal,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      s.t(titleKey),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s.t('placeholder_body'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryLightBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Assigned Owner: $moduleOwner (per AGENTS.md)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.secondaryNavy,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/');
                        }
                      },
                      icon: const Icon(Icons.home, size: 22),
                      label: Text(s.t('btn_home')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
