import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/models.dart';
import '../dashboard/detection_history.dart';
import '../report/report_nav.dart';
import 'message_examples.dart';
import 'message_strings.dart';

/// Offline SMS / WhatsApp scam checker using [scamClassifierProvider].
class MessageDetectorScreen extends ConsumerStatefulWidget {
  const MessageDetectorScreen({super.key});

  @override
  ConsumerState<MessageDetectorScreen> createState() => _MessageDetectorScreenState();
}

class _MessageDetectorScreenState extends ConsumerState<MessageDetectorScreen> {
  final _controller = TextEditingController();
  ScamResult? _result;
  String _checkedText = '';

  @override
  void initState() {
    super.initState();
    MessageStrings.ensure();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String key) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).t(key))));

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _snack('msg_clipboard_empty');
      return;
    }
    setState(() {
      _controller.text = text;
      _result = null;
    });
    // Pasting is the whole job for most users: show the verdict straight away.
    if (ref.read(scamClassifierProvider).hasValue) _check();
  }

  void _check() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _snack('msg_empty');
      return;
    }
    final classifier = ref.read(scamClassifierProvider).valueOrNull;
    if (classifier == null) return;
    FocusScope.of(context).unfocus();
    final result = classifier.classify(text);
    setState(() {
      _result = result;
      _checkedText = text;
    });
    // Feeds Scam Trends (verdict + category only, never the text).
    recordMessageCheck(ref, text, result, sample: kMessageExamples.values.contains(text));
  }

  @override
  Widget build(BuildContext context) {
    MessageStrings.ensure();
    final s = S.of(context);
    final model = ref.watch(scamClassifierProvider);
    final ready = model.hasValue;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('msg_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.t('msg_intro'), style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('msg_input'),
              controller: _controller,
              minLines: 5,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 17),
              onChanged: (_) {
                if (_result != null) setState(() => _result = null);
              },
              decoration: InputDecoration(
                hintText: s.t('msg_hint'),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            // Wrap + full-width Check: on a 360dp phone (or large system font) a single Row pushed
            // the Check button off-screen, leaving only Paste visible.
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                key: const Key('msg_paste'),
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_rounded),
                label: Text(s.t('msg_paste')),
              ),
              TextButton.icon(
                key: const Key('msg_clear'),
                onPressed: () => setState(() {
                  _controller.clear();
                  _result = null;
                }),
                icon: const Icon(Icons.clear_rounded),
                label: Text(s.t('msg_clear')),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('msg_check'),
              onPressed: ready ? _check : null,
              icon: const Icon(Icons.shield_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(s.t('msg_check'), style: const TextStyle(fontSize: 18)),
              ),
            ),
            if (model.isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.t('msg_loading_model'))),
                ]),
              ),
            if (model.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(s.t('msg_model_error'), style: const TextStyle(color: AppTheme.errorRed)),
              ),
            const SizedBox(height: 16),
            Text(s.t('msg_examples'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final e in kMessageExamples.entries)
                ActionChip(
                  key: Key(e.key),
                  avatar: Icon(e.key == 'msg_ex_genuine' ? Icons.account_balance_rounded : Icons.sms_failed_rounded,
                      size: 18),
                  label: Text(s.t(e.key)),
                  onPressed: () => setState(() {
                    _controller.text = e.value;
                    _result = null;
                  }),
                ),
            ]),
            if (_result != null) ...[
              const SizedBox(height: 20),
              _resultView(s, _result!),
            ],
          ],
        ),
      ),
    );
  }

  String _phrase(S s, String p) =>
      p.split(' ').map((w) => w == 'urltoken' ? s.t('msg_reason_link') : w).join(' ');

  Widget _resultView(S s, ScamResult r) {
    final scam = r.label == 'scam';
    final color = scam ? AppTheme.errorRed : AppTheme.successGreen;
    final confidence = ((scam ? r.score : 1 - r.score) * 100).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        key: const Key('msg_verdict'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(scam ? Icons.gpp_bad_rounded : Icons.verified_user_rounded, color: Colors.white, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(scam ? s.t('msg_verdict_scam') : s.t('msg_verdict_genuine'),
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              Text('${s.t('msg_confidence')}: $confidence%',
                  style: const TextStyle(color: Colors.white, fontSize: 17)),
            ]),
          ),
        ]),
      ),
      if (scam && r.reasons.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(s.t('msg_reasons'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final reason in r.reasons)
            Chip(
              avatar: const Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.errorRed),
              label: Text(_phrase(s, reason.phrase),
                  style: const TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFFFFEBEE),
              side: const BorderSide(color: AppTheme.errorRed),
            ),
        ]),
      ],
      const SizedBox(height: 14),
      if (scam)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('msg_advice_title'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              for (var i = 1; i <= 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check_circle_rounded, color: AppTheme.primaryTeal, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.t('msg_advice_$i'), style: const TextStyle(fontSize: 16))),
                  ]),
                ),
            ]),
          ),
        )
      else
        Text(s.t('msg_genuine_note'), style: const TextStyle(fontSize: 16)),
      if (scam) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('msg_report'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
          onPressed: () => openReport(context, type: guessReportType(_checkedText)),
          icon: const Icon(Icons.report_rounded),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(s.t('msg_report'), style: const TextStyle(fontSize: 18)),
          ),
        ),
      ],
    ]);
  }
}
