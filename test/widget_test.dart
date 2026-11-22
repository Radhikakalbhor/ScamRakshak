import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamrakshak/main.dart';

void main() {
  testWidgets('ScamRakshak home screen renders all required elements',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ScamRakshakApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Teal header containing shield icon and ScamRakshak
    expect(find.text('ScamRakshak'), findsOneWidget);
    expect(find.byIcon(Icons.security), findsOneWidget);

    // 2. Offline Protected status banner
    expect(find.text('Offline Protected'), findsOneWidget);
    expect(find.byIcon(Icons.verified_user), findsOneWidget);

    // 3. Language selector
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('हिन्दी'), findsOneWidget);
    expect(find.text('छत्तीसगढ़ी'), findsOneWidget);

    // 4. Six navigation cards
    expect(find.text('Check Message'), findsOneWidget);
    expect(find.text('Detect SMS & WhatsApp fraud'), findsOneWidget);

    expect(find.text('Check Call'), findsOneWidget);
    expect(find.text('Analyze suspicious call transcripts'), findsOneWidget);

    expect(find.text('Report Fraud'), findsOneWidget);
    expect(find.text('Register incident & alert community'), findsOneWidget);

    expect(find.text('Learn'), findsOneWidget);
    expect(find.text('Digital payment safety cards'), findsOneWidget);

    expect(find.text('Quiz'), findsOneWidget);
    expect(find.text('Test your fraud defense skills'), findsOneWidget);

    expect(find.text('Scam Trends'), findsOneWidget);
    expect(find.text('District-level cybercrime data'), findsOneWidget);
  });

  testWidgets('Language switching updates UI strings',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ScamRakshakApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Hindi
    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();

    // Verify Hindi text appears
    expect(find.text('संदेश जांचें'), findsOneWidget);
    expect(find.text('बिना इंटरनेट सुरक्षित'), findsOneWidget);

    // Tap Chhattisgarhi
    await tester.tap(find.text('छत्तीसगढ़ी'));
    await tester.pumpAndSettle();

    // Verify Chhattisgarhi text appears
    expect(find.text('संदेश जांचव'), findsOneWidget);
    expect(find.text('बिना इंटरनेट चलहि'), findsOneWidget);

    // Tap English back
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();

    expect(find.text('Check Message'), findsOneWidget);
    expect(find.text('Offline Protected'), findsOneWidget);
  });

  testWidgets('Navigation to feature placeholders and back works',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ScamRakshakApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Check Message
    await tester.tap(find.text('Check Message'));
    await tester.pumpAndSettle();

    // Verify on Placeholder screen
    expect(
        find.text('This feature module is being connected by the team.'),
        findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    // Tap Home button to navigate back
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    // Back on Home
    expect(find.text('Offline Protected'), findsOneWidget);
  });
}


