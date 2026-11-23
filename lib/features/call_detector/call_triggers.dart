import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/models.dart';
import 'call_highlight.dart';

/// Background of a dangerous sentence; key words inside it are red and bold on pink.
const kDangerSentenceColor = Color(0xFFFFE0B2);

/// Transcript with dangerous sentences shaded and matched words highlighted.
TextSpan callTranscriptSpan(String transcript, List<CallMatch> matches) => TextSpan(children: [
      for (final p in splitCallHighlights(transcript, matches))
        TextSpan(
          text: p.text,
          style: p.highlighted
              ? const TextStyle(backgroundColor: Color(0xFFFFCDD2), color: AppTheme.errorRed, fontWeight: FontWeight.bold)
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
        Text(s.t('call_triggers'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        for (final m in result.matches)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.warningOrange),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '"${m.phrase}"', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: ' – ${s.t('script_${m.scriptType}')}'),
                ]), style: const TextStyle(fontSize: 15)),
              ),
            ]),
          ),
      ],
    );
  }
}
