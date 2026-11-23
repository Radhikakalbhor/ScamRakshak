import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../engine/models.dart';
import '../dashboard/detection_history.dart';
import '../report/report_nav.dart';
import 'message_examples.dart';
import 'message_fingerprint.dart';
import 'message_strings.dart';

/// Offline SMS / WhatsApp scam checker using [scamClassifierProvider].
class MessageDetectorScreen extends ConsumerStatefulWidget {
  /// Text shared from another app: prefilled and checked as soon as the model is ready.
  final String? initialText;

  const MessageDetectorScreen({super.key, this.initialText});

  @override
  ConsumerState<MessageDetectorScreen> createState() => _MessageDetectorScreenState();
}

class _MessageDetectorScreenState extends ConsumerState<MessageDetectorScreen> {
  final _controller = TextEditingController();
  ScamResult? _result;
  String _checkedText = '';
  bool _fpOptIn = false;

  @override
  void initState() {
    super.initState();
    MessageStrings.ensure();
    FingerprintOptIn.get().then((v) {
      if (mounted) setState(() => _fpOptIn = v);
    });
    final shared = widget.initialText?.trim() ?? '';
    if (shared.isNotEmpty) {
      _controller.text = shared;
      ref.read(scamClassifierProvider.future).then((_) {
        if (mounted && _controller.text.trim() == shared) _check();
      }, onError: (Object _) {});
    }
  }

  /// Opt-in only: sends the anonymous fingerprint + category of a real (non-example) scam message.
  void _shareFingerprint(String text, ScamResult r) {
    if (!_fpOptIn || r.label != 'scam' || kMessageExamples.values.contains(text)) return;
    final api = ref.read(apiClientProvider);
    final analyzer = ref.read(callAnalyzerProvider).valueOrNull;
    unawaited(api
        .postFingerprint(messageFingerprint(text), messageCategory(text, r, analyzer))
        .catchError((Object _) {}));
  }

  Future<void> _setOptIn(bool v) async {
    setState(() => _fpOptIn = v);
    await FingerprintOptIn.set(v);
    final r = _result;
    if (v && r != null) _shareFingerprint(_checkedText, r);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String key) => showDsToast(context, S.of(context).t(key));

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
    _shareFingerprint(text, result);
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
          padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section),
          children: [
            Text(s.t('msg_intro'), style: DsType.body),
            const SizedBox(height: DsSpace.l),
            AppTextField(
              key: const Key('msg_input'),
              controller: _controller,
              minLines: 5,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              hint: s.t('msg_hint'),
              onChanged: (_) {
                if (_result != null) setState(() => _result = null);
              },
            ),
            const SizedBox(height: DsSpace.m),
            // Wrap + full-width Check: on a 360dp phone (or large system font) a single Row pushed
            // the Check button off-screen, leaving only Paste visible.
            Wrap(spacing: DsSpace.s, runSpacing: DsSpace.s, children: [
              PillChip(
                key: const Key('msg_paste'),
                icon: Icons.content_paste_rounded,
                label: s.t('msg_paste'),
                onTap: _paste,
              ),
              PillChip(
                key: const Key('msg_clear'),
                icon: Icons.clear_rounded,
                label: s.t('msg_clear'),
                onTap: () => setState(() {
                  _controller.clear();
                  _result = null;
                }),
              ),
            ]),
            const SizedBox(height: DsSpace.m),
            PrimaryButton(
              key: const Key('msg_check'),
              label: s.t('msg_check'),
              icon: Icons.shield_outlined,
              onPressed: ready ? _check : null,
            ),
            if (model.isLoading)
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.s),
                child: Row(children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: DsSpace.s),
                  Expanded(child: Text(s.t('msg_loading_model'), style: DsType.small)),
                ]),
              ),
            if (model.hasError)
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.s),
                child: Text(s.t('msg_model_error'), style: DsType.body.copyWith(color: DsColors.alert)),
              ),
            const SizedBox(height: DsSpace.xl),
            Text(s.t('msg_examples'), style: DsType.greeting),
            const SizedBox(height: DsSpace.s),
            Wrap(spacing: DsSpace.s, runSpacing: DsSpace.s, children: [
              for (final e in kMessageExamples.entries)
                PillChip(
                  key: Key(e.key),
                  icon: e.key == 'msg_ex_genuine' ? Icons.account_balance_outlined : Icons.sms_failed_outlined,
                  label: s.t(e.key),
                  onTap: () => setState(() {
                    _controller.text = e.value;
                    _result = null;
                  }),
                ),
            ]),
            if (_result != null) ...[
              const SizedBox(height: DsSpace.xxl),
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
    final confidence = ((scam ? r.score : 1 - r.score) * 100).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      VerdictBanner(
        key: const Key('msg_verdict'),
        verdict: scam ? DsVerdict.danger : DsVerdict.safe,
        icon: scam ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
        title: scam ? s.t('msg_verdict_scam') : s.t('msg_verdict_genuine'),
        lines: ['${s.t('msg_confidence')}: $confidence%'],
      ),
      if (scam && r.reasons.isNotEmpty) ...[
        const SizedBox(height: DsSpace.l),
        Text(s.t('msg_reasons'), style: DsType.section),
        const SizedBox(height: DsSpace.s),
        Wrap(spacing: DsSpace.s, runSpacing: DsSpace.s, children: [
          for (final reason in r.reasons)
            Chip(
              avatar: const Icon(Icons.warning_amber_rounded, size: 18, color: DsColors.alert),
              label: Text(_phrase(s, reason.phrase), style: DsType.label),
              backgroundColor: DsColors.alertSoft,
              side: const BorderSide(color: DsColors.alert),
            ),
        ]),
      ],
      const SizedBox(height: DsSpace.l),
      if (scam)
        SurfacePanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('msg_advice_title'), style: DsType.section),
            const SizedBox(height: DsSpace.s),
            for (var i = 1; i <= 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DsSpace.xs),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_outline_rounded, color: DsColors.brand, size: 20),
                  const SizedBox(width: DsSpace.s),
                  Expanded(child: Text(s.t('msg_advice_$i'), style: DsType.body)),
                ]),
              ),
          ]),
        )
      else
        Text(s.t('msg_genuine_note'), style: DsType.body),
      if (scam) ...[
        const SizedBox(height: DsSpace.m),
        SurfacePanel(
          padding: const EdgeInsets.symmetric(vertical: DsSpace.xs, horizontal: DsSpace.xs),
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const Key('msg_fp_optin'),
              value: _fpOptIn,
              onChanged: _setOptIn,
              title: Text(s.t('msg_fp_title'), style: DsType.title),
              subtitle: Text(s.t('msg_fp_sub'), style: DsType.small),
            ),
          ),
        ),
      ],
      if (scam) ...[
        const SizedBox(height: DsSpace.m),
        PrimaryButton(
          key: const Key('msg_report'),
          label: s.t('msg_report'),
          icon: Icons.report_outlined,
          color: DsColors.alert,
          onPressed: () => openReport(context, type: guessReportType(_checkedText)),
        ),
      ],
    ]);
  }
}
