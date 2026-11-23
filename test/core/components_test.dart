import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/core/design/components.dart';
import 'package:scam_rakshak/core/design/tokens.dart';
import 'package:scam_rakshak/core/theme.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(DsSpace.xl), child: child)),
    );

void main() {
  test('type scale weights: medium body/display, semibold titles/labels, bold only for numbers', () {
    expect(DsType.display.fontWeight, DsWeight.medium);
    expect(DsType.headline.fontWeight, DsWeight.medium);
    expect(DsType.body.fontWeight, DsWeight.medium);
    expect(DsType.small.fontWeight, DsWeight.medium);
    for (final s in [DsType.cardTitle, DsType.section, DsType.title, DsType.label, DsType.greeting, DsType.caption]) {
      expect(s.fontWeight, DsWeight.semibold);
    }
    expect(DsType.number.fontWeight, DsWeight.bold);
    for (final s in [DsType.display, DsType.body, DsType.label, DsType.number]) {
      expect(s.fontFamily, DsFont.family);
      expect(s.fontFamilyFallback, DsFont.fallback);
    }
    final theme = AppTheme.lightTheme.textTheme;
    expect(theme.bodyLarge!.fontWeight, DsWeight.medium);
    expect(theme.titleLarge!.fontWeight, DsWeight.semibold);
    expect(theme.labelLarge!.fontWeight, DsWeight.semibold);
  });

  testWidgets('new components render with 48 dp targets and labels', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    var tab = 0;
    var tapped = 0;
    await tester.pumpWidget(_app(StatefulBuilder(
      builder: (context, setState) => Column(children: [
        AppTextField(key: const Key('field'), hint: 'Type here'),
        const SizedBox(height: DsSpace.m),
        DsListTile(
          key: const Key('tile'),
          leading: const IconBadge(Icons.call_outlined),
          title: 'Title',
          subtitle: 'Subtitle',
          onTap: () => tapped++,
        ),
        const SizedBox(height: DsSpace.m),
        DsTabs(key: const Key('tabs'), labels: const ['One', 'Two'], selected: tab, onSelect: (i) => setState(() => tab = i)),
        const SizedBox(height: DsSpace.m),
        const VerdictBanner(verdict: DsVerdict.danger, icon: Icons.gpp_bad_outlined, title: 'Scam', lines: ['Score 90%']),
        const EmptyState(icon: Icons.inbox_outlined, title: 'Nothing yet', message: 'New items appear here.'),
        const SizedBox(height: 120, child: LoadingState(message: 'Loading…')),
        PrimaryButton(key: const Key('busy'), label: 'Wait', busy: true, onPressed: () {}),
        PrimaryButton(key: const Key('report'), label: 'Report', color: DsColors.alert, onPressed: () => tapped++),
      ]),
    )));
    await tester.pump();
    for (final k in ['tile', 'busy', 'report']) {
      expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(kDsTouch), reason: k);
    }
    await tester.tap(find.text('Two'));
    await tester.pump();
    expect(tab, 1);
    await tester.tap(find.byKey(const Key('tile')));
    await tester.tap(find.byKey(const Key('busy'))); // busy: disabled
    await tester.tap(find.byKey(const Key('report')));
    expect(tapped, 2);
    await tester.pump(const Duration(milliseconds: 400)); // chip color animation finished
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('showDsDialog and showDsToast', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final result = showDsDialog<bool>(ctx,
        title: 'Delete?',
        content: Text('This cannot be undone.', style: DsType.body),
        actions: (d) => [
              PrimaryButton(label: 'Yes', onPressed: () => Navigator.pop(d, true)),
              PrimaryButton(label: 'No', filled: false, onPressed: () => Navigator.pop(d, false)),
            ]);
    await tester.pumpAndSettle();
    expect(find.text('Delete?'), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    showDsToast(ctx, 'Saved');
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
  });
}
