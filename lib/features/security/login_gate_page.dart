import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/account_auth_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/utils/responsive.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../data/app_store.dart';
import '../settings/sync_setup_page.dart';
import '../account/store_account_dashboard_page.dart';

class LoginGatePage extends StatefulWidget {
  const LoginGatePage({super.key, required this.store, required this.child});

  final AppStore store;
  final Widget child;

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

  Future<void> _loadRecoveryFileIntoFields(
    BuildContext context, {
    required TextEditingController apiUrlController,
    required TextEditingController storeIdController,
    required TextEditingController branchIdController,
    required TextEditingController recoveryKeyController,
    required VoidCallback onLoaded,
  }) async {
    final tr = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['json'],
          withData: true);
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception(tr.text('empty_recovery_file'));
      }
      final data = widget.store.parseRecoveryFileJson(utf8.decode(bytes));
      if ((data['cloudApiUrl'] ?? '').isNotEmpty) {
        apiUrlController.text = data['cloudApiUrl']!;
      }
      storeIdController.text = data['storeId'] ?? '';
      branchIdController.text = data['branchId'] ?? '';
      recoveryKeyController.text = data['recoveryKey'] ?? '';
      onLoaded();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('recovery_file_loaded'))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${tr.text('invalid_recovery_file')}: $error')));
      }
    }
  }

  Future<void> _recoverExistingStore(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final cloud = CloudSyncSettings.load();
    final apiUrlController = TextEditingController(text: cloud.apiBaseUrl);
    final storeIdController =
        TextEditingController(text: widget.store.appIdentity.storeId);
    final branchIdController = TextEditingController();
    final recoveryKeyController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var canRecover = false;
        void refresh(StateSetter setState) {
          setState(() => canRecover = apiUrlController.text.trim().isNotEmpty &&
              storeIdController.text.trim().isNotEmpty &&
              recoveryKeyController.text.trim().isNotEmpty);
        }

        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(
                AppLocalizations.of(context).text('recover_existing_store')),
            content: ResponsiveDialogBox(
              maxWidth: VentioResponsive.modalMaxWidth(context, 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)
                      .text('recover_existing_store_desc')),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _loadRecoveryFileIntoFields(
                        context,
                        apiUrlController: apiUrlController,
                        storeIdController: storeIdController,
                        branchIdController: branchIdController,
                        recoveryKeyController: recoveryKeyController,
                        onLoaded: () => refresh(setState),
                      ),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(AppLocalizations.of(context)
                          .text('upload_recovery_file')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiUrlController,
                    decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context).text('cloud_api_url'),
                      hintText: 'https://your-cloud-api.vercel.app',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => refresh(setState),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: storeIdController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).text('store_id'),
                      hintText: 'ST-XXXXXX',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => refresh(setState),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: branchIdController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)
                          .text('branch_id_optional'),
                      hintText: AppLocalizations.of(context)
                          .text('branch_id_recover_hint'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: recoveryKeyController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context).text('recovery_key'),
                      hintText: 'RK-XXXX-XXXX-XXXX',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => refresh(setState),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context).text('cancel')),
              ),
              FilledButton(
                onPressed: canRecover
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: Text(AppLocalizations.of(context).text('recover')),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;
    try {
      final recoverySettings = cloud.copyWith(
        enabled: true,
        apiBaseUrl: apiUrlController.text.trim(),
        clearLastPullCursor: true,
      );
      await recoverySettings.save();
      final result =
          await CloudSyncService(widget.store).recoverExistingStoreFromCloud(
        recoverySettings,
        storeId: storeIdController.text,
        branchId: branchIdController.text,
        recoveryKey: recoveryKeyController.text,
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
    } finally {
      apiUrlController.dispose();
      storeIdController.dispose();
      branchIdController.dispose();
      recoveryKeyController.dispose();
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
      localUsername = parts.first;
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
        if (onlineResult.accountType == 'store_owner' &&
            onlineResult.storeSlug != 'ventio') {
          await widget.store.recoverOnlineStoreOwnerIdentity(
            storeId: onlineResult.storeId,
            branchId: onlineResult.branchId,
            storeName: onlineResult.storeName,
            username: parts.first,
            password: _passwordController.text,
          );
          if (!mounted) return;
          setState(() => _loggingIn = false);
          return;
        }
        if (onlineResult.accountType == 'platform_admin' ||
            onlineResult.storeSlug == 'ventio') {
          setState(() => _loggingIn = false);
          return;
        }
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
      await AccountAuthService.cacheOnlineResult(onlineResult, mode: 'trial');

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
    final platformAdminUnlocked = authCache?.accountType == 'platform_admin' ||
        authCache?.storeSlug == 'ventio';
    final storeAccountUnlocked = authCache?.accountType == 'store_owner' &&
        (authCache?.storeSlug ?? '').trim().isNotEmpty &&
        authCache?.storeSlug != 'ventio';
    if (platformAdminUnlocked) return widget.child;
    if (widget.store.activeUser != null) return widget.child;
    if (storeAccountUnlocked && authCache != null) {
      return StoreAccountDashboardPage(
        cache: authCache,
        onRecoverExistingStore: () => _recoverExistingStore(context),
        onLogout: () async {
          await AccountAuthCache.clear();
          if (mounted) setState(() {});
        },
      );
    }

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
