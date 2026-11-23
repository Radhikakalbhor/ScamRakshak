import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../engine/models.dart';
import 'call_highlight.dart';

/// Background of a dangerous sentence; key words inside it are alert-red on a soft red tint.
const kDangerSentenceColor = DsColors.highlight;

/// Weight of highlighted key words in a transcript.
const kKeyWordWeight = DsWeight.semibold;

/// 'high' | 'medium' | 'low' -> verdict colors.
DsVerdict riskVerdict(String risk) => switch (risk) {
      'high' => DsVerdict.danger,
      'medium' => DsVerdict.caution,
      _ => DsVerdict.safe,
    };

/// Transcript with dangerous sentences shaded and matched words highlighted.
TextSpan callTranscriptSpan(String transcript, List<CallMatch> matches) => TextSpan(children: [
      for (final p in splitCallHighlights(transcript, matches))
        TextSpan(
          text: p.text,
          style: p.highlighted
              ? const TextStyle(backgroundColor: DsColors.alertSoft, color: DsColors.ink, fontWeight: kKeyWordWeight,
                  decoration: TextDecoration.underline, decorationColor: DsColors.alert, decorationThickness: 2)
              : (p.sentence ? const TextStyle(backgroundColor: kDangerSentenceColor) : null),
        ),
    ]);

/// Advice under the verdict: "No strong scam signs found" ONLY when nothing matched at all.
String callNoteKey(CallResult r) {
  if (r.risk != 'low') return 'call_advice_high';
  return r.matches.isEmpty ? 'call_low_note' : 'call_low_with_signs';
}

/// "Why: words that matched" – every trigger phrase with its plain reason (scam-type label).
class CallTriggerList extends StatelessWidget {
  final CallResult result;
  const CallTriggerList({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.matches.isEmpty) return const SizedBox.shrink();
    final s = S.of(context);
    return Column(
      key: const Key('call_triggers'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.t('call_triggers'), style: DsType.section),
        const SizedBox(height: DsSpace.xs),
        for (final m in result.matches)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: DsSpace.xxs),
                child: Icon(Icons.warning_amber_rounded, size: 18, color: DsColors.caution),
              ),
              const SizedBox(width: DsSpace.s),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '"${m.phrase}"', style: const TextStyle(fontWeight: DsWeight.semibold)),
                  TextSpan(text: ' – ${s.t('script_${m.scriptType}')}'),
                ]), style: DsType.body),
              ),
            ]),
          ),
      ],
    );
  }
}

/// Transcript card used by call results: dangerous sentences shaded, key words marked.
class CallTranscriptCard extends StatelessWidget {
  final String transcript;
  final List<CallMatch> matches;
  final Key textKey;
  const CallTranscriptCard({super.key, required this.transcript, required this.matches, required this.textKey});

  @override
  Widget build(BuildContext context) => SurfacePanel(
        padding: const EdgeInsets.all(DsSpace.l),
        child: Text.rich(key: textKey, callTranscriptSpan(transcript, matches), style: DsType.reading),
      );
}
