import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/localization/app_localizations.dart';
import '../../core/app_brand.dart';
import '../../core/services/account_auth_service.dart';
import '../../core/services/direct_control_plane_service.dart';
import '../../core/services/direct_sync_settings.dart';
import '../../core/services/sync_diagnostics_log.dart';
import '../../core/services/page_timing_scope.dart';
import '../../core/services/startup_timing_service.dart';
import '../../core/services/windows_release_catalog.dart';
import '../../core/utils/responsive.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../settings/sync_setup_page.dart';
import '../account/store_account_dashboard_page.dart';
import '../admin/admin_subscribers_page.dart';
part 'login_gate_page_methods_01.dart';
part 'login_gate_page_methods_02.dart';

class LoginGatePage extends StatefulWidget {
  const LoginGatePage({
    super.key,
    required this.store,
    required this.child,
    required this.onLocaleChanged,
  });

  final AppStore store;
  final Widget child;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<LoginGatePage> createState() => _LoginGatePageState();
}

class _LoginGatePageState extends State<LoginGatePage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _storeNameController = TextEditingController();
  AccountAuthCache? _authCache;

  bool _savingSetup = false;
  bool _loggingIn = false;
  bool _rememberLogin = false;
  bool _showRegister = false;
  bool _showPassword = false;
  bool _checkingSuspension = false;
  bool _firstBuildMarked = false;
  bool _firstReadyMarked = false;
  String _onlineSessionPassword = '';
  late final VoidCallback _storeListener;

  @override
  void initState() {
    super.initState();
    StartupTimingService.markPageEntered(
      'LoginGatePage',
      pageLabel: 'Login gate',
    );
    _storeListener = _handleStoreChanged;
    widget.store.addListener(_storeListener);
    _authCache = AccountAuthCache.load();
    _rememberLogin = widget.store.security.rememberLogin;
  }

  @override
  void didUpdateWidget(covariant LoginGatePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_storeListener);
      widget.store.addListener(_storeListener);
    }
  }

  @override
  void dispose() {
    StartupTimingService.markPageExited(
      'LoginGatePage',
      pageLabel: 'Login gate',
    );
    widget.store.removeListener(_storeListener);
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _storeNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_firstBuildMarked) {
      _firstBuildMarked = true;
      StartupTimingService.markPageBuilt(
        'LoginGatePage',
        pageLabel: 'Login gate',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _firstReadyMarked) return;
        _firstReadyMarked = true;
        StartupTimingService.markPageReady(
          'LoginGatePage',
          pageLabel: 'Login gate',
        );
      });
    }
    final authCache = _authCache;
    final platformAdminUnlocked = authCache?.accountType == 'platform_admin';
    final storeAccountUnlocked = authCache?.accountType == 'store_owner' &&
        authCache?.mode == 'login' &&
        (authCache?.storeSlug ?? '').trim().isNotEmpty &&
        authCache?.storeSlug != 'ventio';
    if (platformAdminUnlocked && authCache != null) {
      return PageTimingScope(
        key: const ValueKey('PlatformAdminDashboardPage'),
        pageKey: 'PlatformAdminDashboardPage',
        pageLabel: 'Platform admin dashboard',
        child: PlatformAdminDashboardPage(
          cache: authCache,
          onLogout: () async {
            await AccountAuthCache.clear();
            if (mounted) setState(() => _authCache = null);
          },
        ),
      );
    }
    if (storeAccountUnlocked && authCache != null) {
      return PageTimingScope(
        key: const ValueKey('StoreAccountDashboardPage'),
        pageKey: 'StoreAccountDashboardPage',
        pageLabel: 'Store account dashboard',
        child: StoreAccountDashboardPage(
          store: widget.store,
          cache: authCache,
          hasStoreIdentity:
              widget.store.runtime.identity.hostDeviceId.trim().isNotEmpty,
          hasLocalStoreData: widget.store.security.hasLocalAdminUser,
          canRecoverStoreData: authCache.directSyncEnabled,
          onRecoverStoreIdentity: () => _recoverStoreIdentity(context),
          onRecoverStoreData: () => _recoverStoreData(context),
          onLogout: () async {
            await AccountAuthCache.clear();
            if (mounted) setState(() => _authCache = null);
          },
          onLocaleChanged: widget.onLocaleChanged,
        ),
      );
    }
    final identity = widget.store.runtime.identity;
    final directSettings = DirectSyncSettings.load();
    final directBootstrapIncomplete = identity.isClient &&
        identity.activeSyncTransportNormalized == 'direct' &&
        directSettings.hasBootstrapConfiguration &&
        !directSettings.setupComplete;
    if (directBootstrapIncomplete) {
      return PageTimingScope(
        key: const ValueKey('IncompleteDirectBootstrapPage'),
        pageKey: 'SyncSetupPage',
        pageLabel: 'Complete Store connection',
        child: SyncSetupPage(
          store: widget.store,
          onDone: () async {
            if (mounted) setState(() {});
          },
        ),
      );
    }

    if (widget.store.security.activeUser != null) return widget.child;

    if (_showRegister && !kIsWeb && !widget.store.security.hasLocalAdminUser) {
      return _InitialAdminSetupCard(
        storeNameController: _storeNameController,
        usernameController: _usernameController,
        passwordController: _passwordController,
        confirmPasswordController: _confirmPasswordController,
        saving: _savingSetup,
        onSubmit: _completeInitialSetup,
        onCancel:
            _savingSetup ? null : () => setState(() => _showRegister = false),
      );
    }

    final tr = AppLocalizations.of(context);

    if (widget.store.runtime.isSuspendedByHost) {
      final reason = widget.store.runtime.suspendedByHostReason.trim().isEmpty
          ? tr.text('client_suspended_by_host_desc')
          : widget.store.runtime.suspendedByHostReason;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: VentioResponsive.pageInsets(context),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: VentioResponsive.clampToScreen(context, 460,
                        min: 280, horizontalPadding: 32)),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: VentioResponsive.pageInsets(context),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                            radius: 34,
                            child: Icon(Icons.pause_circle_outline, size: 34)),
                        const SizedBox(height: 16),
                        Text(tr.text('client_suspended_by_host'),
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(reason, textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _checkingSuspension
                                ? null
                                : _checkSuspensionStatus,
                            icon: _checkingSuspension
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.refresh),
                            label: Text(tr.text('check_resume_status')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      bottomNavigationBar: kIsWeb
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(
                  heightFactor: 1,
                  child: TextButton.icon(
                    onPressed: _showWindowsInstallerReleases,
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(tr.text('windows_installer_versions')),
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: VentioResponsive.pageInsets(context),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: VentioResponsive.clampToScreen(context, 420,
                      min: 280, horizontalPadding: 32)),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 32,
                        child: Icon(Icons.lock_outline, size: 32),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr.text('ventio_login'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(tr.text('signin_hint'), textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _usernameController,
                        enabled: !_loggingIn,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: tr.text('username'),
                          helperText: tr.text('login_username_helper'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        enabled: !_loggingIn,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: tr.text('password'),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? tr.text('hide_password')
                                : tr.text('show_password'),
                            onPressed: _loggingIn
                                ? null
                                : () => setState(
                                    () => _showPassword = !_showPassword),
                            icon: Icon(_showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                        onSubmitted: (_) {
                          if (!_loggingIn) _unlock();
                        },
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _rememberLogin,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(tr.text('remember_me')),
                        subtitle: Text(tr.text('remember_me_desc')),
                        onChanged: _loggingIn
                            ? null
                            : (value) =>
                                setState(() => _rememberLogin = value ?? false),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loggingIn ? null : _unlock,
                          icon: _loggingIn
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.login),
                          label: Text(tr.text('login')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed:
                              _loggingIn ? null : _openSupportPasswordReset,
                          child: Text(tr.text('forgot_password')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!widget.store.security.hasLocalAdminUser)
                        Builder(
                          builder: (context) {
                            final canRegisterHere = !kIsWeb;
                            final actions = <Widget>[
                              if (canRegisterHere)
                                OutlinedButton.icon(
                                  onPressed: _loggingIn
                                      ? null
                                      : () =>
                                          setState(() => _showRegister = true),
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: Text(tr.text('register')),
                                ),
                              OutlinedButton.icon(
                                onPressed: _loggingIn
                                    ? null
                                    : () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => PageTimingScope(
                                              key: const ValueKey(
                                                  'SyncSetupPage'),
                                              pageKey: 'SyncSetupPage',
                                              pageLabel: 'Sync setup',
                                              child: SyncSetupPage(
                                                store: widget.store,
                                                onDone: () async {
                                                  if (Navigator.of(context)
                                                      .canPop()) {
                                                    Navigator.of(context).pop();
                                                  }
                                                },
                                              ),
                                            ),
                                          ),
                                        );
                                        if (mounted) setState(() {});
                                      },
                                icon: const Icon(Icons.link),
                                label: Text(tr.text('connect_to_store')),
                              ),
                            ];
                            return Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                children: actions,
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 20),
                      Text(
                        tr.format('version_build', {
                          'version': AppBrand.versionName,
                          'build': AppBrand.buildNumber,
                        }),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordResetDraft {
  const _PasswordResetDraft({
    required this.loginName,
    required this.code,
    required this.password,
  });

  final String loginName;
  final String code;
  final String password;
}

class _InitialAdminSetupCard extends StatefulWidget {
  const _InitialAdminSetupCard({
    required this.usernameController,
    required this.storeNameController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.saving,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController usernameController;
  final TextEditingController storeNameController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool saving;
  final VoidCallback onSubmit;
  final VoidCallback? onCancel;

  @override
  State<_InitialAdminSetupCard> createState() => _InitialAdminSetupCardState();
}

class _InitialAdminSetupCardState extends State<_InitialAdminSetupCard> {
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: VentioResponsive.pageInsets(context),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: VentioResponsive.clampToScreen(context, 460,
                      min: 280, horizontalPadding: 32)),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 34,
                        child: Icon(Icons.verified_user_outlined, size: 34),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr.text('welcome_to_ventio'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr.text('create_admin_desc'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: widget.storeNameController,
                        enabled: !widget.saving,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: tr.text('store_name'),
                          helperText: tr.text('store_slug_helper'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: widget.usernameController,
                        enabled: !widget.saving,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: tr.text('new_username'),
                          helperText: tr.text('username_online_helper'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: widget.passwordController,
                        enabled: !widget.saving,
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: tr.text('new_password'),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? tr.text('hide_password')
                                : tr.text('show_password'),
                            onPressed: widget.saving
                                ? null
                                : () => setState(
                                    () => _showPassword = !_showPassword),
                            icon: Icon(_showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: widget.confirmPasswordController,
                        enabled: !widget.saving,
                        obscureText: !_showConfirmPassword,
                        onSubmitted: (_) {
                          if (!widget.saving) widget.onSubmit();
                        },
                        decoration: InputDecoration(
                          labelText: tr.text('confirm_password'),
                          suffixIcon: IconButton(
                            tooltip: _showConfirmPassword
                                ? tr.text('hide_password')
                                : tr.text('show_password'),
                            onPressed: widget.saving
                                ? null
                                : () => setState(() => _showConfirmPassword =
                                    !_showConfirmPassword),
                            icon: Icon(_showConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: widget.saving ? null : widget.onCancel,
                              child: Text(tr.text('back_to_login')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: widget.saving ? null : widget.onSubmit,
                              icon: widget.saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                              label: Text(tr.text('register_admin')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlatformAdminDashboardPage extends StatelessWidget {
  const PlatformAdminDashboardPage({
    super.key,
    required this.cache,
    required this.onLogout,
  });

  final AccountAuthCache cache;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Ventio - ${tr.text('subscribers')}'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                cache.loginName.isEmpty
                    ? tr.text('platform_admin')
                    : cache.loginName,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          IconButton(
            tooltip: tr.text('logout'),
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: const PageTimingScope(
        pageKey: 'AdminSubscribersPage',
        pageLabel: 'Admin subscribers',
        child: AdminSubscribersPage(),
      ),
    );
  }
}
