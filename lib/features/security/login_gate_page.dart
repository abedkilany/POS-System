import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/account_auth_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/utils/responsive.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../data/app_store.dart';
import '../../models/user_role.dart';
import '../settings/sync_setup_page.dart';
import '../account/store_account_dashboard_page.dart';
import '../admin/admin_subscribers_page.dart';

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
  final TextEditingController _storeNameController =
      TextEditingController(text: 'my_store');

  bool _savingSetup = false;
  bool _loggingIn = false;
  bool _rememberLogin = false;
  bool _showRegister = false;
  bool _showPassword = false;
  bool _checkingSuspension = false;

  @override
  void initState() {
    super.initState();
    _rememberLogin = widget.store.rememberLogin;
    _storeNameController.text = widget.store.storeProfile.name.trim().isEmpty
        ? 'my_store'
        : _normalizeLoginPart(widget.store.storeProfile.name.trim());
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _storeNameController.dispose();
    super.dispose();
  }

  String _normalizeLoginPart(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  bool _isValidLoginPart(String value) {
    return RegExp(r'^[a-z0-9][a-z0-9_-]{2,31}$').hasMatch(value);
  }

  void _showAuthMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkSuspensionStatus() async {
    if (!widget.store.appIdentity.isClient) return;
    final tr = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checkingSuspension = true);
    try {
      final identity = widget.store.appIdentity;
      final active = identity.activeSyncTransportNormalized;
      final result = active == 'cloud'
          ? await UnifiedSyncFactory.cloudEngine(widget.store).syncNow()
          : await UnifiedSyncFactory.lanEngine(widget.store).syncNow();
      if (!mounted) return;
      if (result.ok && !widget.store.isSuspendedByHost) {
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('client_resume_detected'))));
        setState(() {});
      } else {
        messenger.showSnackBar(SnackBar(
            content: Text(result.message.isEmpty
                ? tr.text('client_still_suspended')
                : localizeRuntimeMessage(result.message, tr))));
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _checkingSuspension = false);
    }
  }

  Future<void> _recoverStoreIdentity(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final cache = AccountAuthCache.load();
    final cloud = CloudSyncSettings.load();
    final storeId = (cache?.storeId.trim().isNotEmpty == true
            ? cache!.storeId
            : widget.store.appIdentity.storeId)
        .trim()
        .toUpperCase();
    final branchId = (cache?.branchId.trim().isNotEmpty == true
            ? cache!.branchId
            : widget.store.appIdentity.branchId)
        .trim()
        .toUpperCase();

    if (cache == null || cache.accountToken.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Online account session is required. Please sign in again.')),
      );
      return;
    }
    if (!storeId.startsWith('ST-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A valid Store ID was not found for this account.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('recover_store_identity')),
        content: ResponsiveDialogBox(
          maxWidth: VentioResponsive.modalMaxWidth(context, 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('recover_store_identity_desc')),
              const SizedBox(height: 12),
              Text('Store ID: $storeId'),
              if (branchId.isNotEmpty) Text('Branch ID: $branchId'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr.text('recover')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final recoverySettings = cloud.copyWith(
        enabled: true,
        apiBaseUrl: cloud.apiBaseUrl.trim().isNotEmpty
            ? cloud.apiBaseUrl.trim()
            : CloudSyncSettings.bundledApiBaseUrl,
        clearLastPullCursor: true,
      );
      await recoverySettings.save();
      final result = await CloudSyncService(widget.store)
          .recoverExistingStoreIdentityFromCloud(
        recoverySettings,
        storeId: storeId,
        branchId: branchId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizeRuntimeMessage(result.message, tr))),
        );
        setState(() {});
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _recoverStoreData(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final cache = AccountAuthCache.load();
    final cloud = CloudSyncSettings.load();
    final storeId = (cache?.storeId.trim().isNotEmpty == true
            ? cache!.storeId
            : widget.store.appIdentity.storeId)
        .trim()
        .toUpperCase();
    final branchId = (cache?.branchId.trim().isNotEmpty == true
            ? cache!.branchId
            : widget.store.appIdentity.branchId)
        .trim()
        .toUpperCase();

    if (cache == null || cache.accountToken.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Online account session is required. Please sign in again.')),
      );
      return;
    }
    if (!storeId.startsWith('ST-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A valid Store ID was not found for this account.')),
      );
      return;
    }
    if (widget.store.appIdentity.hostDeviceId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('recover_store_identity_first'))),
      );
      return;
    }
    if (!widget.store.hasPermission(AppPermission.syncManage)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You do not have permission: sync.manage')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('recover_store_data')),
        content: ResponsiveDialogBox(
          maxWidth: VentioResponsive.modalMaxWidth(context, 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('recover_store_data_desc')),
              const SizedBox(height: 12),
              Text('Store ID: $storeId'),
              if (branchId.isNotEmpty) Text('Branch ID: $branchId'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr.text('recover')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final recoverySettings = cloud.copyWith(
        enabled: true,
        apiBaseUrl: cloud.apiBaseUrl.trim().isNotEmpty
            ? cloud.apiBaseUrl.trim()
            : CloudSyncSettings.bundledApiBaseUrl,
        clearLastPullCursor: true,
      );
      await recoverySettings.save();
      final result =
          await CloudSyncService(widget.store).recoverExistingStoreFromCloud(
        recoverySettings,
        storeId: storeId,
        branchId: branchId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizeRuntimeMessage(result.message, tr))),
        );
        setState(() {});
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _unlock() async {
    final invalidLoginMessage =
        AppLocalizations.of(context).text('invalid_login');
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _loggingIn = true);
    var localUsername = _usernameController.text.trim();

    final typedUsername = _usernameController.text.trim();
    final isOnlineLogin = typedUsername.contains('@');

    if (isOnlineLogin) {
      final onlineUsername = _normalizeLoginPart(typedUsername);
      final parts = onlineUsername.split('@');
      if (parts.length != 2 || parts.first.isEmpty || parts.last.isEmpty) {
        setState(() => _loggingIn = false);
        _showAuthMessage(
            'Online login must be username@store, for example user@store.');
        return;
      }
      try {
        final onlineResult = await AccountAuthService().login(
          username: onlineUsername,
          password: _passwordController.text,
        );
        if (!mounted) return;
        if (!onlineResult.ok) {
          setState(() => _loggingIn = false);
          messenger.showSnackBar(SnackBar(
            content: Text(onlineResult.message.isEmpty
                ? AppLocalizations.of(context).text('online_login_failed')
                : onlineResult.message),
          ));
          return;
        }
        await AccountAuthService.cacheOnlineResult(onlineResult, mode: 'login');
        await widget.store.logout();
        setState(() => _loggingIn = false);
        return;
      } catch (error) {
        if (!mounted) return;
        setState(() => _loggingIn = false);
        messenger.showSnackBar(SnackBar(
          content: Text(
              '${AppLocalizations.of(context).text('online_login_failed')}: $error'),
        ));
        return;
      }
    }

    final ok = await widget.store.login(
      localUsername,
      _passwordController.text,
      remember: _rememberLogin,
    );

    if (!mounted) return;

    setState(() => _loggingIn = false);

    if (ok) {
      setState(() {});
    } else {
      _passwordController.clear();
      messenger.showSnackBar(SnackBar(content: Text(invalidLoginMessage)));
    }
  }

  Future<void> _completeInitialSetup() async {
    final password = _passwordController.text.trim();
    final username = _normalizeLoginPart(_usernameController.text);
    final storeName = _normalizeLoginPart(_storeNameController.text);

    if (!_isValidLoginPart(username)) {
      _showAuthMessage(
          'Username must be 3-32 characters: letters, numbers, underscore, or hyphen. No spaces.');
      return;
    }
    if (username.contains('@')) {
      _showAuthMessage(
          'Register with username only. Online login will become username@store.');
      return;
    }
    if (!_isValidLoginPart(storeName)) {
      _showAuthMessage(
          'Store name must be 3-32 characters: letters, numbers, underscore, or hyphen. No spaces.');
      return;
    }
    if (storeName == 'ventio') {
      _showAuthMessage(
          'ventio is reserved for platform accounts. Choose another store name.');
      return;
    }

    if (password != _confirmPasswordController.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).text('passwords_do_not_match'))),
      );
      return;
    }

    final tr = AppLocalizations.of(context);
    setState(() => _savingSetup = true);

    try {
      final onlineResult = await AccountAuthService().register(
        username: username,
        password: password,
        fullName: 'Administrator',
        storeName: storeName,
      );
      if (!onlineResult.ok) {
        throw StateError(onlineResult.message.isEmpty
            ? tr.text('online_register_failed')
            : onlineResult.message);
      }
      await AccountAuthService.cacheOnlineResult(onlineResult,
          mode: 'registered_local');
      await widget.store.recoverOnlineStoreOwnerIdentity(
        storeId: onlineResult.storeId,
        branchId: onlineResult.branchId,
        storeName:
            onlineResult.storeName.isEmpty ? storeName : onlineResult.storeName,
        username: username,
        password: password,
      );

      await widget.store.logout();
      if (mounted) {
        setState(() {
          _showRegister = false;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
        final message = tr.format('trial_created_sign_in', {
          'days': '14',
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSetup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authCache = AccountAuthCache.load();
    final platformAdminUnlocked = authCache?.accountType == 'platform_admin';
    final storeAccountUnlocked = authCache?.accountType == 'store_owner' &&
        authCache?.mode == 'login' &&
        (authCache?.storeSlug ?? '').trim().isNotEmpty &&
        authCache?.storeSlug != 'ventio';
    if (platformAdminUnlocked && authCache != null) {
      return PlatformAdminDashboardPage(
        cache: authCache,
        onLogout: () async {
          await AccountAuthCache.clear();
          if (mounted) setState(() {});
        },
      );
    }
    if (storeAccountUnlocked && authCache != null) {
      return StoreAccountDashboardPage(
        store: widget.store,
        cache: authCache,
        hasStoreIdentity:
            widget.store.appIdentity.hostDeviceId.trim().isNotEmpty,
        canRecoverStoreData:
            widget.store.hasPermission(AppPermission.syncManage),
        onRecoverStoreIdentity: () => _recoverStoreIdentity(context),
        onRecoverStoreData: () => _recoverStoreData(context),
        onLogout: () async {
          await AccountAuthCache.clear();
          if (mounted) setState(() {});
        },
        onLocaleChanged: widget.onLocaleChanged,
      );
    }
    if (widget.store.activeUser != null) return widget.child;

    if (_showRegister && !kIsWeb && widget.store.needsInitialAdminSetup) {
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

    if (widget.store.isSuspendedByHost) {
      final reason = widget.store.suspendedByHostReason.trim().isEmpty
          ? tr.text('client_suspended_by_host_desc')
          : widget.store.suspendedByHostReason;
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
                          helperText: 'Offline: user  |  Online: user@store',
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
                          onPressed: _loggingIn
                              ? null
                              : () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(tr.text(
                                            'password_recovery_not_configured'))),
                                  );
                                },
                          child: Text(tr.text('forgot_password')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (widget.store.needsInitialAdminSetup)
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
                                            builder: (_) => SyncSetupPage(
                                              store: widget.store,
                                              onDone: () async {
                                                if (Navigator.of(context)
                                                    .canPop()) {
                                                  Navigator.of(context).pop();
                                                }
                                              },
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
                          helperText:
                              'Use letters/numbers only, no spaces. Example: oday',
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
                          helperText:
                              'Example: user. Online login becomes user@store.',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventio • Subscribers'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                cache.loginName.isEmpty ? 'Platform admin' : cache.loginName,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: const AdminSubscribersPage(),
    );
  }
}
