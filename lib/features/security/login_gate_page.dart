import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/account_auth_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/sync_diagnostics_log.dart';
import '../../core/services/windows_release_catalog.dart';
import '../../core/utils/responsive.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../data/app_store.dart';
import '../../models/app_identity.dart';
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
  String _onlineSessionPassword = '';

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

  Future<void> _persistRecoveredStoreAuthCache({
    required String storeId,
    required String branchId,
  }) async {
    final cache = AccountAuthCache.load();
    if (cache == null) return;
    await AccountAuthCache.save(
      cache.copyWith(
        mode: 'login',
        storeId: storeId.trim().toUpperCase(),
        branchId: branchId.trim().toUpperCase(),
        lastVerifiedAt: DateTime.now(),
      ),
    );
  }

  String _recoveryUsernameFromCache(AccountAuthCache cache) {
    final cachedUsername = cache.username.trim().toLowerCase();
    if (cachedUsername.isNotEmpty) return cachedUsername;
    final loginName = cache.loginName.trim().toLowerCase();
    if (loginName.contains('@')) {
      return loginName.split('@').first.trim();
    }
    return 'admin';
  }

  String _recoveryUsernameFromResult(
    CloudStoreRecoveryResult result,
    AccountAuthCache cache,
  ) {
    final resultUsername = result.username.trim().toLowerCase();
    if (resultUsername.isNotEmpty) return resultUsername;
    final resultLoginName = result.loginName.trim().toLowerCase();
    if (resultLoginName.contains('@')) {
      return resultLoginName.split('@').first.trim();
    }
    return _recoveryUsernameFromCache(cache);
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
    SyncDiagnosticsLog.add(
      '[RECOVER_IDENTITY] press '
      'hasLocalStoreData=${widget.store.hasLocalStoreData} '
      'hasStoreIdentity=${widget.store.appIdentity.hostDeviceId.trim().isNotEmpty} '
      'hasCache=${cache != null} '
      'accountToken=${cache?.accountToken.trim().isNotEmpty == true} '
      'storeId=$storeId branchId=$branchId',
    );

    if (cache == null || cache.accountToken.trim().isEmpty) {
      SyncDiagnosticsLog.add(
        '[RECOVER_IDENTITY] blocked reason=missing_online_session',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr.text('online_account_session_required'))),
      );
      return;
    }
    if (widget.store.hasLocalAdminUser) {
      SyncDiagnosticsLog.add(
        '[RECOVER_IDENTITY] blocked reason=local_store_data_exists',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(tr.text('local_store_identity_recovery_locked'))),
      );
      return;
    }
    if (_onlineSessionPassword.trim().length < 6) {
      SyncDiagnosticsLog.add(
        '[RECOVER_IDENTITY] blocked reason=missing_online_password',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                tr.text('sign_in_online_before_recovering_store_identity'))),
      );
      return;
    }
    if (!storeId.startsWith('ST-')) {
      SyncDiagnosticsLog.add(
        '[RECOVER_IDENTITY] blocked reason=invalid_store_id storeId=$storeId',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr.text('store_id_not_found_for_account'))),
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
              Text('${tr.text('store_id_label')}: $storeId'),
              if (branchId.isNotEmpty)
                Text('${tr.text('branch_id_label')}: $branchId'),
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
      SyncDiagnosticsLog.add(
        '[RECOVER_IDENTITY] start storeId=$storeId branchId=$branchId',
      );
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
      SyncDiagnosticsLog.add(
        '[RECOVER_IDENTITY] result ok=${result.ok} '
        'storeId=${result.identity?.storeId ?? storeId} '
        'branchId=${result.identity?.branchId ?? branchId} '
        'loginName=${result.loginName} '
        'storeSlug=${result.storeSlug} '
        'cloudSyncEnabled=${result.cloudSyncEnabled} '
        'deviceLimit=${result.deviceLimit?.allowed ?? -1}',
      );
      if (result.ok) {
        final recoveryCache = AccountAuthCache.load();
        final recoveryUsername = recoveryCache == null
            ? ''
            : _recoveryUsernameFromResult(result, recoveryCache);
        if (recoveryCache != null && recoveryUsername.isNotEmpty) {
          await widget.store.recoverOnlineStoreOwnerIdentity(
            storeId: result.identity?.storeId ?? storeId,
            branchId: result.identity?.branchId ?? branchId,
            storeName: result.storeName.trim().isNotEmpty
                ? result.storeName
                : recoveryCache.storeName.trim().isNotEmpty
                    ? recoveryCache.storeName
                    : widget.store.storeProfile.name,
            username: recoveryUsername,
            password: _onlineSessionPassword,
            hostDeviceId:
                result.identity?.hostDeviceId.trim().isNotEmpty == true
                    ? result.identity!.hostDeviceId
                    : widget.store.deviceId,
            deviceToken: result.identity?.deviceToken ?? '',
            cloudTenantId: result.identity?.cloudTenantId ?? '',
            deviceRole: DeviceRole.host,
            syncMode: SyncMode.cloudConnected,
          );
          await AccountAuthCache.save(
            recoveryCache.copyWith(
              mode: 'login',
              storeId: result.identity?.storeId ?? storeId,
              branchId: result.identity?.branchId ?? branchId,
              username: recoveryUsername,
              storeSlug: result.storeSlug.trim().isNotEmpty
                  ? result.storeSlug
                  : recoveryCache.storeSlug,
              storeName: result.storeName.trim().isNotEmpty
                  ? result.storeName
                  : recoveryCache.storeName,
              loginName: result.loginName.trim().isNotEmpty
                  ? result.loginName
                  : recoveryCache.loginName,
              cloudSyncEnabled: result.cloudSyncEnabled,
              devicesLimit:
                  result.deviceLimit?.allowed ?? recoveryCache.devicesLimit,
              lastVerifiedAt: DateTime.now(),
            ),
          );
        } else {
          await _persistRecoveredStoreAuthCache(
            storeId: result.identity?.storeId ?? storeId,
            branchId: result.identity?.branchId ?? branchId,
          );
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizeRuntimeMessage(result.message, tr))),
        );
        setState(() {});
      }
    } catch (error) {
      SyncDiagnosticsLog.add('[RECOVER_IDENTITY] error=$error');
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
    SyncDiagnosticsLog.add(
      '[RECOVER_DATA] press '
      'hasLocalStoreData=${widget.store.hasLocalStoreData} '
      'hasStoreIdentity=${widget.store.appIdentity.hostDeviceId.trim().isNotEmpty} '
      'hasCache=${cache != null} '
      'accountToken=${cache?.accountToken.trim().isNotEmpty == true}',
    );

    if (cache == null || cache.accountToken.trim().isEmpty) {
      SyncDiagnosticsLog.add(
        '[RECOVER_DATA] blocked reason=missing_online_session',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr.text('online_account_session_required'))),
      );
      return;
    }
    if (widget.store.appIdentity.hostDeviceId.trim().isEmpty) {
      SyncDiagnosticsLog.add(
        '[RECOVER_DATA] blocked reason=missing_store_identity',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('recover_store_identity_first'))),
      );
      return;
    }
    SyncDiagnosticsLog.add(
      '[RECOVER_DATA] refresh_session start storeId=${cache.storeId} branchId=${cache.branchId}',
    );
    var latestCache = cache;
    final sessionResult = await AccountAuthService()
        .refreshSession(accountToken: cache.accountToken.trim());
    if (sessionResult.ok) {
      await AccountAuthService.cacheOnlineResult(sessionResult,
          mode: cache.mode.isEmpty ? 'login' : cache.mode);
      latestCache = AccountAuthCache.load() ?? cache;
    }
    SyncDiagnosticsLog.add(
      '[RECOVER_DATA] refresh_session result ok=${sessionResult.ok} '
      'storeId=${sessionResult.storeId} branchId=${sessionResult.branchId} '
      'cloudSyncEnabled=${sessionResult.cloudSyncEnabled}',
    );
    if (!context.mounted) return;
    final storeId = (sessionResult.storeId.trim().isNotEmpty
            ? sessionResult.storeId
            : latestCache.storeId.trim().isNotEmpty
                ? latestCache.storeId
                : widget.store.appIdentity.storeId)
        .trim()
        .toUpperCase();
    final branchId = (sessionResult.branchId.trim().isNotEmpty
            ? sessionResult.branchId
            : latestCache.branchId.trim().isNotEmpty
                ? latestCache.branchId
                : widget.store.appIdentity.branchId)
        .trim()
        .toUpperCase();
    if (!storeId.startsWith('ST-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr.text('store_id_not_found_for_account'))),
      );
      return;
    }
    final cloudAllowed =
        latestCache.cloudSyncEnabled || sessionResult.cloudSyncEnabled;
    if (!cloudAllowed) {
      SyncDiagnosticsLog.add(
        '[RECOVER_DATA] blocked reason=cloud_sync_not_enabled storeId=$storeId branchId=$branchId',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(tr.text('subscription_not_enrolled_cloud_sync'))),
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
              Text('${tr.text('store_id_label')}: $storeId'),
              if (branchId.isNotEmpty)
                Text('${tr.text('branch_id_label')}: $branchId'),
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
      SyncDiagnosticsLog.add(
        '[RECOVER_DATA] start storeId=$storeId branchId=$branchId',
      );
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
      SyncDiagnosticsLog.add(
        '[RECOVER_DATA] result ok=${result.ok} '
        'storeId=${result.identity?.storeId ?? storeId} '
        'branchId=${result.identity?.branchId ?? branchId} '
        'storeName=${result.storeName} '
        'pulled=${result.pulled} '
        'loginName=${result.loginName} '
        'storeSlug=${result.storeSlug} '
        'cloudSyncEnabled=${result.cloudSyncEnabled} '
        'deviceLimit=${result.deviceLimit?.allowed ?? -1}',
      );
      if (result.ok) {
        await _persistRecoveredStoreAuthCache(
          storeId: result.identity?.storeId ?? storeId,
          branchId: result.identity?.branchId ?? branchId,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizeRuntimeMessage(result.message, tr))),
        );
        setState(() {});
      }
    } catch (error) {
      SyncDiagnosticsLog.add('[RECOVER_DATA] error=$error');
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
        _onlineSessionPassword = _passwordController.text;
        await AccountAuthService.cacheOnlineResult(onlineResult, mode: 'login');
        await widget.store.applyCloudStoreOwnerCredentials(
          username: onlineResult.username.isNotEmpty
              ? onlineResult.username
              : parts.first,
          fullName: null,
          password: _passwordController.text,
        );
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


  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    return '${size.toStringAsFixed(size >= 10 || unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
  }

  String _releaseSubtitle(AppLocalizations tr, WindowsReleaseItem item) {
    final parts = <String>[];
    if (item.version != null && item.version!.isNotEmpty) {
      final build = item.build == null ? '' : ' build ${item.build}';
      parts.add('${tr.text('version')}: ${item.version}$build');
    }
    final sizeBytes = item.sizeBytes;
    if (sizeBytes != null && sizeBytes > 0) parts.add(_formatBytes(sizeBytes));
    if (item.publishedAt != null) parts.add(_formatDateTime(item.publishedAt!));
    return parts.isEmpty ? item.name : parts.join(' • ');
  }

  Future<void> _showWindowsInstallerReleases() async {
    final tr = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(tr.text('windows_installer_versions')),
        content: const SizedBox(
          width: 360,
          child: Center(
            heightFactor: 1.5,
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    List<WindowsReleaseItem> releases;
    Object? error;
    try {
      releases = await WindowsReleaseCatalogService().fetchReleases();
    } catch (e) {
      releases = const <WindowsReleaseItem>[];
      error = e;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('windows_installer_versions')),
        content: SizedBox(
          width: 520,
          child: releases.isEmpty
              ? Text(error == null
                  ? tr.text('no_windows_installers_found')
                  : tr.text('could_not_load_windows_installers'))
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: releases.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = releases[index];
                      return ListTile(
                        leading: const Icon(Icons.download_for_offline_outlined),
                        title: Text(item.name),
                        subtitle: Text(_releaseSubtitle(tr, item)),
                        trailing: FilledButton.icon(
                          onPressed: () {
                            WindowsReleaseCatalogService().download(item);
                          },
                          icon: const Icon(Icons.download_outlined),
                          label: Text(tr.text('download')),
                        ),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr.text('close')),
          ),
        ],
      ),
    );
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
        hasLocalStoreData: widget.store.hasLocalAdminUser,
        canRecoverStoreData: authCache.cloudSyncEnabled,
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

    if (_showRegister && !kIsWeb && !widget.store.hasLocalAdminUser) {
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
                      if (!widget.store.hasLocalAdminUser)
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
