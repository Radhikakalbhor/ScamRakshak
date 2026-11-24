import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/lessons/lesson_models.dart';
import '../../features/qr_check/qr_check_strings.dart';
import '../../features/quiz/literacy_score.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../strings.dart';
import '../widgets/language_switcher.dart';
import '../widgets/server_settings.dart';

/// ScamRakshak home (design/SPEC.md, styled by design/DESIGN_SYSTEM.md):
/// 1 header (logo + ScamRakshak, 3 bell) -> 2 Language / भाषा -> 4 Report Fraud (1930)
/// -> 5-7 + Live Call Guard feature grid -> 8 Digital Financial Literacy Score -> Scam Trends.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static final Uri _helpline1930 = Uri.parse('tel:1930');

  Future<void> _dial1930() async {
    try {
      await launchUrl(_helpline1930);
    } catch (_) {}
  }

  void _go(BuildContext context, String route) {
    final r = GoRouter.maybeOf(context);
    if (r != null) r.push(route);
  }

  @override
  Widget build(BuildContext context) {
    QrCheckStrings.ensure();
    LiteracyStrings.ensure();
    final s = S.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const Key('home_list'),
          padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.m, DsSpace.xl, DsSpace.section),
          children: [
            // 1 + 3: header with brand and language/notification actions
            ScreenHeader(
              leading: Semantics(
                label: s.t('app_name'),
                image: true,
                child: const ExcludeSemantics(
                  child: IconBadge(Icons.shield_rounded, background: DsColors.brand),
                ),
              ),
              brand: s.t('app_name'),
              actions: [
                const LanguageButton(),
                ArrowButton(
                  key: const Key('home_notifications'),
                  icon: Icons.notifications_none_rounded,
                  semanticLabel: s.t('notifications'),
                  onTap: () => _go(context, '/live/inbox'),
                ),
              ],
              title: s.t('home_title'),
            ),
            const SizedBox(height: DsSpace.m),
            const Align(alignment: Alignment.centerLeft, child: ServerStatusChip()),
            const SizedBox(height: DsSpace.l),

            // 4: Report Fraud (the one alert-colored card)
            _ReportFraudCard(
              title: s.t('report_fraud'),
              subtitle: s.t('report_fraud_sub'),
              callLabel: s.t('call_1930'),
              onOpen: () => _go(context, '/report'),
              onCall: _dial1930,
            ),
            const SizedBox(height: DsSpace.l),

            // 5, 6, 7 + Live Call Guard: feature grid
            PairRow(
              left: FeatureCard(
                key: const Key('home_tile_message'),
                color: DsColors.peach,
                icon: Icons.chat_bubble_outline_rounded,
                title: s.t('check_message'),
                subtitle: s.t('check_message_sub'),
                onTap: () => _go(context, '/message'),
              ),
              right: FeatureCard(
                key: const Key('home_tile_qr'),
                color: DsColors.powder,
                icon: Icons.qr_code_2_rounded,
                title: s.t('check_qr'),
                subtitle: s.t('check_qr_sub'),
                onTap: () => _go(context, '/qr'),
              ),
            ),
            const SizedBox(height: DsSpace.m),
            PairRow(
              left: FeatureCard(
                key: const Key('home_tile_call'),
                color: DsColors.mint,
                icon: Icons.call_outlined,
                title: s.t('check_call'),
                subtitle: s.t('check_call_sub'),
                onTap: () => _go(context, '/call'),
              ),
              right: FeatureCard(
                key: const Key('home_tile_live'),
                color: DsColors.lavender,
                icon: Icons.graphic_eq_rounded,
                title: s.t('live_call'),
                subtitle: s.t('live_call_sub'),
                onTap: () => _go(context, '/live'),
              ),
            ),
            const SizedBox(height: DsSpace.l),

            // 8: Digital Financial Literacy Score
            _LiteracyPanel(onLessons: () => _go(context, '/lessons'), onQuiz: () => _go(context, '/quiz')),
            const SizedBox(height: DsSpace.l),

            // Existing feature kept below the spec'd sections: Scam Trends.
            SurfacePanel(
              key: const Key('home_trends'),
              onTap: () => _go(context, '/dashboard'),
              semanticLabel: '${s.t('scam_trends')}. ${s.t('scam_trends_sub')}',
              child: Row(children: [
                const IconBadge(Icons.insights_rounded),
                const SizedBox(width: DsSpace.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.t('scam_trends'), style: DsType.title),
                    Text(s.t('scam_trends_sub'), style: DsType.small),
                  ]),
                ),
                const ArrowButton(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportFraudCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String callLabel;
  final VoidCallback onOpen;
  final VoidCallback onCall;
  const _ReportFraudCard({
    required this.title,
    required this.subtitle,
    required this.callLabel,
    required this.onOpen,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    const onAlert = DsColors.alertInk;
    return Stack(children: [
      PastelCard(
        key: const Key('home_report_btn'),
        color: DsColors.alert,
        onTap: onOpen,
        semanticLabel: '$title. $subtitle',
        child: ExcludeSemantics(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              IconBadge(Icons.report_gmailerrorred_rounded, background: onAlert, foreground: DsColors.alert),
              Spacer(),
              ArrowButton(color: onAlert),
            ]),
            const SizedBox(height: DsSpace.xl),
            Text(title, style: DsType.headline.copyWith(color: onAlert)),
            const SizedBox(height: DsSpace.xs),
            Text(subtitle, style: DsType.body.copyWith(color: onAlert)),
            const SizedBox(height: DsSpace.l),
            // Space reserved for the 1930 pill, which sits on top as its own button.
            const SizedBox(height: kDsTouch),
          ]),
        ),
      ),
      Positioned(
        left: DsSpace.xl,
        bottom: DsSpace.xl,
        child: PillChip(
          key: const Key('home_call_1930'),
          label: '1930',
          icon: Icons.call_rounded,
          background: onAlert,
          foreground: DsColors.alert,
          semanticLabel: callLabel,
          onTap: onCall,
        ),
      ),
    ]);
  }
}

/// Digital Financial Literacy Score: score at the upper right, progress bar, guidance, next step,
/// and two stacked actions. Data: LiteracyStore (quiz feature), refreshed on learning progress.
class _LiteracyPanel extends StatefulWidget {
  final VoidCallback onLessons;
  final VoidCallback onQuiz;
  const _LiteracyPanel({required this.onLessons, required this.onQuiz});

  @override
  State<_LiteracyPanel> createState() => _LiteracyPanelState();
}

class _LiteracyPanelState extends State<_LiteracyPanel> {
  LiteracyScore? _score;
  Map<String, Map<String, String>> _titles = const {};

  @override
  void initState() {
    super.initState();
    learningProgressChanged.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    learningProgressChanged.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    LiteracyScore d;
    try {
      d = await LiteracyStore.load();
    } catch (_) {
      d = const LiteracyScore({}, {});
    }
    var titles = _titles;
    final t = d.weakestTopic;
    if (t != null && !titles.containsKey(t)) {
      try {
        titles = {...titles, t: (await LessonRepository.load(t)).title};
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _score = d;
        _titles = titles;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final d = _score ?? const LiteracyScore({}, {});
    final score = d.score;
    final topic = d.weakestTopic;
    final topicName = topic == null ? '' : pickLang(_titles[topic] ?? const {}, s.locale);
    final name = topicName.isEmpty ? (topic ?? '') : topicName;
    final next = switch (d.recommendation) {
      'lesson' => s.t('dfl_rec_lesson').replaceAll('{topic}', name),
      'quiz' => s.t('dfl_rec_quiz').replaceAll('{topic}', name),
      _ => s.t('dfl_all_good'),
    };
    final n = kLessonIds.length;
    return SurfacePanel(
      key: const Key('home_literacy'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(s.t('quiz_score_title'), style: DsType.cardTitle)),
          const SizedBox(width: DsSpace.m),
          Semantics(
            label: '$score / 100',
            child: ExcludeSemantics(
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('$score', key: const Key('home_dfl_score'), style: DsType.number),
                Text(' /100', style: DsType.small),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: DsSpace.s),
        Text(s.t('dfl_sub'), style: DsType.small),
        const SizedBox(height: DsSpace.l),
        ProgressBar(value: score / 100, color: DsColors.brand, semanticLabel: s.t('quiz_score_title')),
        const SizedBox(height: DsSpace.l),
        if (!d.hasData)
          Text(s.t('dfl_empty'), key: const Key('home_dfl_empty'), style: DsType.body)
        else
          Text(
            s
                .t('dfl_parts')
                .replaceAll('{q}', '${(d.quizAccuracy * 100).round()}')
                .replaceAll('{t}', '${d.topicsTried}')
                .replaceAll('{l}', '${d.lessonCount}')
                .replaceAll('{n}', '$n'),
            style: DsType.body,
          ),
        const SizedBox(height: DsSpace.s),
        Text(next, key: const Key('home_dfl_next'), style: DsType.body.copyWith(fontWeight: DsWeight.semibold)),
        const SizedBox(height: DsSpace.xl),
        PrimaryButton(
          key: const Key('home_open_lessons'),
          label: s.t('dfl_learn'),
          icon: Icons.menu_book_rounded,
          onPressed: widget.onLessons,
        ),
        const SizedBox(height: DsSpace.s),
        PrimaryButton(
          key: const Key('home_take_quiz'),
          label: s.t('dfl_quiz'),
          icon: Icons.quiz_outlined,
          filled: false,
          onPressed: widget.onQuiz,
        ),
      ]),
    );
  }
}
