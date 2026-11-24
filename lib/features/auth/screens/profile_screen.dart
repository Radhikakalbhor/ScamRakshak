import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/tokens.dart';
import '../../../core/providers.dart';
import '../../../core/strings.dart';
import '../../report/report_data.dart';
import '../auth_strings.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String? _selectedDistrict;
  String? _selectedLanguage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    AuthStrings.ensure();
    final profile = ref.read(authNotifierProvider).userProfile;
    if (profile != null) {
      _selectedDistrict = profile.district;
      _selectedLanguage = profile.language;
    }
  }

  void _onSaveProfile() async {
    setState(() => _isSaving = true);
    final s = S(ref.read(localeProvider));

    await ref
        .read(authNotifierProvider.notifier)
        .updateProfile(
          district: _selectedDistrict,
          language: _selectedLanguage,
        );

    // If language was updated, update global app locale as well
    if (_selectedLanguage != null &&
        _selectedLanguage != ref.read(localeProvider)) {
      await ref.read(localeProvider.notifier).setLocale(_selectedLanguage!);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          s.t('auth_profile_saved'),
          style: DsType.body.copyWith(color: DsColors.onDark),
        ),
        backgroundColor: DsColors.safe,
      ),
    );
  }

  void _onLogout() async {
    await ref.read(authNotifierProvider.notifier).signOut();
    if (!mounted) return;
    context.go('/signin');
  }

  void _onDeleteAccount() {
    final s = S(ref.read(localeProvider));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: DsColors.alert,
              size: 28,
            ),
            const SizedBox(width: DsSpace.s),
            Expanded(
              child: Text(
                s.t('auth_delete_confirm_title'),
                style: DsType.titleLarge.copyWith(color: DsColors.ink),
              ),
            ),
          ],
        ),
        content: Text(
          s.t('auth_delete_confirm_body'),
          style: DsType.body.copyWith(color: DsColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              s.t('btn_cancel'),
              style: DsType.label.copyWith(color: DsColors.muted),
            ),
          ),
          ElevatedButton(
            key: const Key('confirm_delete_account_btn'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(authNotifierProvider.notifier).deleteAccount();
              if (!mounted) return;
              context.go('/signin');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DsColors.alert,
              foregroundColor: DsColors.onDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DsRadius.tile),
              ),
            ),
            child: Text(
              s.t('auth_delete_confirm_btn'),
              style: DsType.label.copyWith(color: DsColors.onDark),
            ),
          ),
        ],
      ),
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
    final authState = ref.watch(authNotifierProvider);
    final profile = authState.userProfile;
    final locale = ref.watch(localeProvider);
    final s = S(locale);

    final districtList = ['unknown', ...kChhattisgarhDistricts];

    return Scaffold(
      backgroundColor: DsColors.page,
      appBar: AppBar(
        title: Text(
          s.t('auth_profile_title'),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpace.xl,
            vertical: DsSpace.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Header Card
              Card(
                color: DsColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DsRadius.tile),
                  side: const BorderSide(color: DsColors.line),
                ),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(DsSpace.xl),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: DsSpace.section,
                        backgroundColor: DsColors.powder,
                        child: Text(
                          (profile?.username.isNotEmpty == true)
                              ? profile!.username[0].toUpperCase()
                              : 'U',
                          style: DsType.headlineSmall.copyWith(
                            color: DsColors.brand,
                            fontWeight: DsWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: DsSpace.l),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.username ?? 'User',
                              style: DsType.featureTitle.copyWith(
                                color: DsColors.ink,
                              ),
                            ),
                            const SizedBox(height: DsSpace.xs),
                            // Immutable phone indicator with lock icon
                            Row(
                              children: [
                                const Icon(
                                  Icons.lock_outline,
                                  size: 16,
                                  color: DsColors.muted,
                                ),
                                const SizedBox(width: DsSpace.xs),
                                Text(
                                  profile?.phone.isNotEmpty == true
                                      ? profile!.phone
                                      : '+91XXXXXXXXXX',
                                  style: DsType.small.copyWith(
                                    color: DsColors.muted,
                                    fontWeight: DsWeight.medium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: DsSpace.s),
                            // Sync status indicator
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: DsSpace.s,
                                vertical: DsSpace.xs,
                              ),
                              decoration: BoxDecoration(
                                color: authState.isSynced
                                    ? DsColors.safe.withValues(alpha: 0.1)
                                    : DsColors.caution.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  DsRadius.small,
                                ),
                                border: Border.all(
                                  color: authState.isSynced
                                      ? DsColors.safe.withValues(alpha: 0.3)
                                      : DsColors.caution.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    authState.isSynced
                                        ? Icons.check_circle_outline
                                        : Icons.sync_problem_rounded,
                                    size: 14,
                                    color: authState.isSynced
                                        ? DsColors.safe
                                        : DsColors.caution,
                                  ),
                                  const SizedBox(width: DsSpace.xs),
                                  Text(
                                    authState.isSynced
                                        ? s.t('auth_sync_synced')
                                        : s.t('auth_sync_not_synced'),
                                    style: DsType.caption.copyWith(
                                      color: authState.isSynced
                                          ? DsColors.safe
                                          : DsColors.caution,
                                      fontWeight: DsWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: DsSpace.xxl),

              // District Selector
              Text(
                s.t('auth_profile_district'),
                style: DsType.label.copyWith(color: DsColors.ink),
              ),
              const SizedBox(height: DsSpace.s),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: DsSpace.l),
                decoration: BoxDecoration(
                  color: DsColors.surface,
                  borderRadius: BorderRadius.circular(DsRadius.tile),
                  border: Border.all(color: DsColors.line),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: DsColors.surface,
                    value: _selectedDistrict ?? profile?.district ?? 'unknown',
                    items: districtList.map((d) {
                      return DropdownMenuItem<String>(
                        value: d,
                        child: Text(
                          d,
                          style: DsType.body.copyWith(color: DsColors.ink),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedDistrict = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: DsSpace.xl),

              // Language Selector
              Text(
                s.t('auth_profile_language'),
                style: DsType.label.copyWith(color: DsColors.ink),
              ),
              const SizedBox(height: DsSpace.s),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: DsSpace.l),
                decoration: BoxDecoration(
                  color: DsColors.surface,
                  borderRadius: BorderRadius.circular(DsRadius.tile),
                  border: Border.all(color: DsColors.line),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: DsColors.surface,
                    value: _selectedLanguage ?? profile?.language ?? 'en',
                    items: [
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(
                          'English',
                          style: DsType.body.copyWith(color: DsColors.ink),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'hi',
                        child: Text(
                          'हिन्दी (Hindi)',
                          style: DsType.body.copyWith(color: DsColors.ink),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'chh',
                        child: Text(
                          'छत्तीसगढ़ी (Chhattisgarhi)',
                          style: DsType.body.copyWith(color: DsColors.ink),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedLanguage = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: DsSpace.xxl),

              // Save Changes Button
              ElevatedButton.icon(
                key: const Key('profile_save_btn'),
                onPressed: _isSaving ? null : _onSaveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DsColors.brand,
                  foregroundColor: DsColors.onDark,
                  padding: const EdgeInsets.symmetric(vertical: DsSpace.l),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DsRadius.tile),
                  ),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DsColors.onDark,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _isSaving
                      ? s.t('auth_profile_saving')
                      : s.t('auth_profile_save'),
                  style: DsType.label.copyWith(color: DsColors.onDark),
                ),
              ),
              const SizedBox(height: DsSpace.l),

              // Sync Now Button (if not synced or manual trigger)
              if (!authState.isSynced)
                OutlinedButton.icon(
                  key: const Key('profile_sync_now_btn'),
                  onPressed: authState.isSyncing
                      ? null
                      : () => ref.read(authNotifierProvider.notifier).syncNow(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DsColors.brand,
                    side: const BorderSide(color: DsColors.brand),
                    padding: const EdgeInsets.symmetric(vertical: DsSpace.l),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DsRadius.tile),
                    ),
                  ),
                  icon: const Icon(Icons.sync),
                  label: Text(
                    authState.isSyncing
                        ? s.t('auth_syncing')
                        : s.t('auth_sync_now'),
                    style: DsType.label.copyWith(color: DsColors.brand),
                  ),
                ),
              const SizedBox(height: DsSpace.section),
              const Divider(color: DsColors.line),
              const SizedBox(height: DsSpace.l),

              // Log Out Button
              OutlinedButton.icon(
                key: const Key('profile_logout_btn'),
                onPressed: _onLogout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: DsColors.muted,
                  side: const BorderSide(color: DsColors.line),
                  padding: const EdgeInsets.symmetric(vertical: DsSpace.l),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DsRadius.tile),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: Text(
                  s.t('auth_profile_logout'),
                  style: DsType.label.copyWith(color: DsColors.muted),
                ),
              ),
              const SizedBox(height: DsSpace.m),

              // Delete Account Button
              TextButton.icon(
                key: const Key('profile_delete_btn'),
                onPressed: _onDeleteAccount,
                style: TextButton.styleFrom(
                  foregroundColor: DsColors.alert,
                  padding: const EdgeInsets.symmetric(vertical: DsSpace.m),
                ),
                icon: const Icon(
                  Icons.delete_forever_rounded,
                  color: DsColors.alert,
                ),
                label: Text(
                  s.t('auth_profile_delete_account'),
                  style: DsType.label.copyWith(color: DsColors.alert),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
