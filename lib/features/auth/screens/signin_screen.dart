import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/tokens.dart';
import '../../../core/providers.dart';
import '../../../core/strings.dart';
import '../auth_strings.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    AuthStrings.ensure();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onSendOtp() {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final phoneDigits = _phoneController.text.trim();
    final username = _nameController.text.trim();
    final locale = ref.read(localeProvider);

    ref
        .read(authNotifierProvider.notifier)
        .sendOtp(
          phone: '+91$phoneDigits',
          username: username,
          locale: locale,
          onCodeSent: () {
            if (!mounted) return;
            setState(() => _isLoading = false);
            context.push('/otp');
          },
          onError: (err) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _errorMessage = err;
            });
          },
        );
  }

  Future<void> _editServer() async {
    final s = S(ref.read(localeProvider));
    final currentUrl = await ref.read(apiClientProvider).getBaseUrl();
    if (!mounted) return;
    final ctrl = TextEditingController(text: currentUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          s.t('live_server_title'),
          style: DsType.titleLarge.copyWith(color: DsColors.ink),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t('live_server_help'),
              style: DsType.body.copyWith(color: DsColors.ink),
            ),
            const SizedBox(height: DsSpace.m),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: DsType.body.copyWith(color: DsColors.ink),
              decoration: InputDecoration(
                hintText: 'http://192.168.1.5:8000',
                hintStyle: DsType.body.copyWith(color: DsColors.muted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DsRadius.tile),
                  borderSide: const BorderSide(color: DsColors.line),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              s.t('btn_cancel'),
              style: DsType.label.copyWith(color: DsColors.muted),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            style: FilledButton.styleFrom(
              backgroundColor: DsColors.brand,
              foregroundColor: DsColors.onDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DsRadius.tile),
              ),
            ),
            child: Text(
              s.t('live_server_save'),
              style: DsType.label.copyWith(color: DsColors.onDark),
            ),
          ),
        ],
      ),
    );
    if (url == null || !mounted) return;
    var clean = url.trim();
    if (clean.isEmpty) return;
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (Uri.tryParse(clean)?.host.isEmpty ?? true) return;
    await ref.read(apiClientProvider).setBaseUrl(clean);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Server updated: $clean',
          style: DsType.body.copyWith(color: DsColors.onDark),
        ),
        backgroundColor: DsColors.brand,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final s = S(locale);

    return Scaffold(
      backgroundColor: DsColors.page,
      appBar: AppBar(
        title: Text(
          s.t('auth_signin_title'),
          style: DsType.titleLarge.copyWith(color: DsColors.ink),
        ),
        backgroundColor: DsColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.settings_ethernet_rounded,
              color: DsColors.brand,
            ),
            tooltip: s.t('live_server_title'),
            onPressed: _editServer,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpace.xl,
              vertical: DsSpace.l,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Security Icon & Title
                  const Center(
                    child: CircleAvatar(
                      radius: DsSpace.section,
                      backgroundColor: DsColors.powder,
                      child: Icon(
                        Icons.shield_outlined,
                        size: 48,
                        color: DsColors.brand,
                      ),
                    ),
                  ),
                  const SizedBox(height: DsSpace.l),
                  Text(
                    s.t('auth_signin_title'),
                    textAlign: TextAlign.center,
                    style: DsType.cardTitle.copyWith(color: DsColors.ink),
                  ),
                  const SizedBox(height: DsSpace.s),
                  Text(
                    s.t('auth_signin_sub'),
                    textAlign: TextAlign.center,
                    style: DsType.small.copyWith(color: DsColors.muted),
                  ),
                  const SizedBox(height: DsSpace.xxl),

                  // Name Field
                  Text(
                    s.t('auth_username_label'),
                    style: DsType.label.copyWith(color: DsColors.ink),
                  ),
                  const SizedBox(height: DsSpace.s),
                  TextFormField(
                    key: const Key('signin_name_field'),
                    controller: _nameController,
                    style: DsType.body.copyWith(color: DsColors.ink),
                    decoration: InputDecoration(
                      hintText: s.t('auth_username_hint'),
                      hintStyle: DsType.body.copyWith(color: DsColors.muted),
                      prefixIcon: const Icon(
                        Icons.person_outline,
                        color: DsColors.brand,
                      ),
                      filled: true,
                      fillColor: DsColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: DsSpace.l,
                        vertical: DsSpace.m,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DsRadius.tile),
                        borderSide: const BorderSide(color: DsColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DsRadius.tile),
                        borderSide: const BorderSide(color: DsColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DsRadius.tile),
                        borderSide: const BorderSide(
                          color: DsColors.brand,
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (val) {
                      if (val == null ||
                          val.trim().isEmpty ||
                          val.trim().length > 50) {
                        return s.t('auth_username_error');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: DsSpace.l),

                  // Phone Number Field (+91 fixed prefix, 10 digits)
                  Text(
                    s.t('auth_phone_label'),
                    style: DsType.label.copyWith(color: DsColors.ink),
                  ),
                  const SizedBox(height: DsSpace.s),
                  TextFormField(
                    key: const Key('signin_phone_field'),
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: DsType.body.copyWith(color: DsColors.ink),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      hintText: s.t('auth_phone_hint'),
                      hintStyle: DsType.body.copyWith(color: DsColors.muted),
                      prefixIcon: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DsSpace.m,
                        ),
                        alignment: Alignment.centerLeft,
                        width: 70,
                        child: Text(
                          s.t('auth_phone_prefix'),
                          style: DsType.title.copyWith(
                            color: DsColors.brand,
                            fontWeight: DsWeight.bold,
                          ),
                        ),
                      ),
                      filled: true,
                      fillColor: DsColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: DsSpace.l,
                        vertical: DsSpace.m,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DsRadius.tile),
                        borderSide: const BorderSide(color: DsColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DsRadius.tile),
                        borderSide: const BorderSide(color: DsColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DsRadius.tile),
                        borderSide: const BorderSide(
                          color: DsColors.brand,
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().length != 10) {
                        return s.t('auth_phone_error');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: DsSpace.xl),

                  // Error Display
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
                              style: DsType.small.copyWith(
                                color: DsColors.alert,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Send OTP Button
                  ElevatedButton(
                    key: const Key('signin_submit_btn'),
                    onPressed: _isLoading ? null : _onSendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DsColors.brand,
                      foregroundColor: DsColors.onDark,
                      padding: const EdgeInsets.symmetric(vertical: DsSpace.l),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DsRadius.tile),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    DsColors.onDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: DsSpace.m),
                              Text(
                                s.t('auth_sending_otp'),
                                style: DsType.label.copyWith(
                                  color: DsColors.onDark,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            s.t('auth_send_otp'),
                            style: DsType.label.copyWith(
                              color: DsColors.onDark,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
