import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/tokens.dart';
import '../../../core/providers.dart';
import '../../../core/strings.dart';
import '../auth_strings.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const int _codeLength = 6;
  final List<TextEditingController> _controllers = List.generate(
    _codeLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _codeLength,
    (_) => FocusNode(),
  );

  Timer? _resendTimer;
  int _secondsRemaining = 60;
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    AuthStrings.ensure();
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _secondsRemaining = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String _getSmsCode() => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Handle paste of whole 6-digit code
      final cleanDigits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _codeLength && i < cleanDigits.length; i++) {
        _controllers[i].text = cleanDigits[i];
      }
      if (cleanDigits.length >= _codeLength) {
        _focusNodes[_codeLength - 1].unfocus();
        _verifyCode();
      } else {
        _focusNodes[cleanDigits.length].requestFocus();
      }
      return;
    }

    if (value.isNotEmpty) {
      if (index + 1 < _codeLength) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _verifyCode();
      }
    }
  }

  void _onKeyDown(int index, RawKeyEvent event) {
    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  String _mapErrorMessage(String error, S s) {
    final lower = error.toLowerCase();
    if (lower.contains('invalid') ||
        lower.contains('wrong') ||
        lower.contains('bad') ||
        lower.contains('code-mismatch')) {
      return s.t('auth_err_invalid_otp');
    }
    if (lower.contains('expired') || lower.contains('timeout')) {
      return s.t('auth_err_expired_otp');
    }
    if (lower.contains('quota') ||
        lower.contains('too-many') ||
        lower.contains('blocked') ||
        lower.contains('attempts')) {
      return s.t('auth_err_quota_exceeded');
    }
    if (lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('unreachable') ||
        lower.contains('offline')) {
      return s.t('auth_err_network');
    }
    return error;
  }

  void _verifyCode() {
    final code = _getSmsCode();
    if (code.length != _codeLength) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final s = S(ref.read(localeProvider));

    ref.read(authNotifierProvider.notifier).verifyOtp(
          smsCode: code,
          onSuccess: () {
            if (!mounted) return;
            setState(() => _isVerifying = false);
            // User is now authenticated; GoRouter redirect handles moving to original location or '/'
            context.go('/');
          },
          onError: (err) {
            if (!mounted) return;
            setState(() {
              _isVerifying = false;
              _errorMessage = _mapErrorMessage(err, s);
            });
          },
        );
  }

  void _resendCode() {
    if (_secondsRemaining > 0) return;
    setState(() {
      _errorMessage = null;
    });

    final s = S(ref.read(localeProvider));

    ref.read(authNotifierProvider.notifier).resendOtp(
          onCodeSent: () {
            if (!mounted) return;
            _startResendTimer();
          },
          onError: (err) {
            if (!mounted) return;
            setState(() {
              _errorMessage = _mapErrorMessage(err, s);
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final s = S(locale);
    final authNotifier = ref.watch(authNotifierProvider.notifier);
    final phone = authNotifier.pendingPhone ?? '';

    return Scaffold(
      backgroundColor: DsColors.page,
      appBar: AppBar(
        title: Text(
          s.t('auth_otp_title'),
          style: DsType.titleLarge.copyWith(color: DsColors.ink),
        ),
        backgroundColor: DsColors.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpace.xl,
              vertical: DsSpace.l,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Icon
                const Center(
                  child: CircleAvatar(
                    radius: DsSpace.section,
                    backgroundColor: DsColors.powder,
                    child: Icon(
                      Icons.sms_outlined,
                      size: 40,
                      color: DsColors.brand,
                    ),
                  ),
                ),
                const SizedBox(height: DsSpace.l),
                Text(
                  s.t('auth_otp_title'),
                  textAlign: TextAlign.center,
                  style: DsType.cardTitle.copyWith(color: DsColors.ink),
                ),
                const SizedBox(height: DsSpace.s),
                Text(
                  s
                      .t('auth_otp_sub')
                      .replaceAll('{phone}', phone.replaceAll('+91', '')),
                  textAlign: TextAlign.center,
                  style: DsType.small.copyWith(color: DsColors.muted),
                ),
                const SizedBox(height: DsSpace.section),

                // 6 OTP Digit Boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(_codeLength, (index) {
                    return SizedBox(
                      width: kDsTouch,
                      height: 56,
                      child: RawKeyboardListener(
                        focusNode: FocusNode(),
                        onKey: (event) => _onKeyDown(index, event),
                        child: TextFormField(
                          key: Key('otp_box_$index'),
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: DsType.cardTitle.copyWith(
                            color: DsColors.brand,
                            fontWeight: DsWeight.bold,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: DsColors.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: DsSpace.m,
                            ),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(DsRadius.small),
                              borderSide: const BorderSide(
                                color: DsColors.line,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(DsRadius.small),
                              borderSide: const BorderSide(
                                color: DsColors.line,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(DsRadius.small),
                              borderSide: const BorderSide(
                                color: DsColors.brand,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: (val) => _onDigitChanged(index, val),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: DsSpace.xxl),

                // Error Message Display
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(DsSpace.m),
                    margin: const EdgeInsets.only(bottom: DsSpace.l),
                    decoration: BoxDecoration(
                      color: DsColors.alert.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(DsRadius.small),
                      border: Border.all(
                        color: DsColors.alert.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: DsColors.alert,
                          size: 20,
                        ),
                        const SizedBox(width: DsSpace.s),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: DsType.small.copyWith(color: DsColors.alert),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Verify Button
                ElevatedButton(
                  key: const Key('otp_verify_btn'),
                  onPressed: _isVerifying || _getSmsCode().length != _codeLength
                      ? null
                      : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DsColors.brand,
                    foregroundColor: DsColors.onDark,
                    padding: const EdgeInsets.symmetric(vertical: DsSpace.l),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DsRadius.tile),
                    ),
                    elevation: 0,
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              DsColors.onDark,
                            ),
                          ),
                        )
                      : Text(
                          s.t('auth_otp_verify'),
                          style: DsType.label.copyWith(color: DsColors.onDark),
                        ),
                ),
                const SizedBox(height: DsSpace.xl),

                // Resend Timer & Button
                Center(
                  child: _secondsRemaining > 0
                      ? Text(
                          s
                              .t('auth_otp_resend_in')
                              .replaceAll('{seconds}', '$_secondsRemaining'),
                          style: DsType.small.copyWith(
                            color: DsColors.muted,
                            fontWeight: DsWeight.medium,
                          ),
                        )
                      : TextButton.icon(
                          key: const Key('otp_resend_btn'),
                          onPressed: _resendCode,
                          icon: const Icon(
                            Icons.refresh,
                            color: DsColors.brand,
                          ),
                          label: Text(
                            s.t('auth_otp_resend'),
                            style: DsType.label.copyWith(
                              color: DsColors.brand,
                              fontWeight: DsWeight.bold,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
