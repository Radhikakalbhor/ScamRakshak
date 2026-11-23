import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../strings.dart';

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
    void back() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(titleKey)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: s.t('btn_back'),
          onPressed: back,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DsSpace.xl),
            child: PastelCard(
              color: DsColors.powder,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.xl, vertical: DsSpace.section),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconBadge(icon, size: 96),
                  const SizedBox(height: DsSpace.xl),
                  Text(s.t(titleKey), textAlign: TextAlign.center, style: DsType.cardTitle),
                  const SizedBox(height: DsSpace.m),
                  Text(s.t('placeholder_body'), textAlign: TextAlign.center, style: DsType.body),
                  const SizedBox(height: DsSpace.l),
                  PillChip(label: 'Assigned Owner: $moduleOwner (per AGENTS.md)', background: DsColors.surface),
                  const SizedBox(height: DsSpace.xxl),
                  PrimaryButton(label: s.t('btn_home'), icon: Icons.home_rounded, onPressed: back),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
