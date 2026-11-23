// Same Material library as lib/core/ (its ThemeData type is not interchangeable with material_ui's).
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/strings.dart';
import 'core/theme.dart';

void main() {
  runApp(const ProviderScope(child: ScamRakshakApp()));
}

/// Root widget: theme, go_router navigation and the S localization delegate
/// driven by [localeProvider] ('en' | 'hi' | 'chh').
class ScamRakshakApp extends ConsumerWidget {
  const ScamRakshakApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'ScamRakshak',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      localizationsDelegates: [AppLocalizationsDelegate(locale)],
    );
  }
}
