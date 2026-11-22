import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/strings.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: ScamRakshakApp(),
    ),
  );
}

/// Root widget of ScamRakshak.
/// Binds theme, localization, and go_router to Riverpod state.
class ScamRakshakApp extends ConsumerWidget {
  const ScamRakshakApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeLocale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'ScamRakshak',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      locale: Locale(activeLocale),
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('chh'),
      ],
      localizationsDelegates: [
        AppLocalizationsDelegate(activeLocale),
        // Fallback default material delegates if needed
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    );
  }
}
