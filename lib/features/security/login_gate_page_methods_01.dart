// ignore_for_file: invalid_use_of_protected_member
part of 'login_gate_page.dart';

extension _LoginGatePageStatePart1 on _LoginGatePageState {
  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
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

  void _setAuthCache(AccountAuthCache? cache) {
    if (!mounted) return;
    setState(() => _authCache = cache);
  }

  Future<void> _persistRecoveredStoreAuthCache({
    required String storeId,
    required String branchId,
  }) async {
    final cache = _authCache;
    if (cache == null) return;
    final updatedCache = cache.copyWith(
      mode: 'login',
      storeId: storeId.trim().toUpperCase(),
      branchId: branchId.trim().toUpperCase(),
      lastVerifiedAt: DateTime.now(),
    );
    await AccountAuthCache.save(updatedCache);
    _setAuthCache(updatedCache);
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
    DirectStoreRecoveryResult result,
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
    if (!widget.store.runtime.identity.isClient) return;
    final tr = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checkingSuspension = true);
    try {
      final result =
          await UnifiedSyncFactory.activeEngine(widget.store).syncNow();
      if (!mounted) return;
      if (result.ok && !widget.store.runtime.isSuspendedByHost) {
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
    final cache = _authCache ?? AccountAuthCache.load();
    final direct = VpsControlPlaneSettings.load();
    final previousIdentity = widget.store.runtime.identity;
    final storeId = (cache?.storeId.trim().isNotEmpty == true
            ? cache!.storeId
            : widget.store.runtime.identity.storeId)
        .trim()
        .toUpperCase();
    final branchId = (cache?.branchId.trim().isNotEmpty == true
            ? cache!.branchId
            : widget.store.runtime.identity.branchId)
        .trim()
        .toUpperCase();
    SyncDiagnosticsLog.add(
      '[RECOVER_IDENTITY] press '
      'hasLocalStoreData=${widget.store.recovery.hasLocalStoreData} '
      'hasStoreIdentity=${widget.store.runtime.identity.hostDeviceId.trim().isNotEmpty} '
      'hasCache=${cache != null} '
      'accountToken=${cache?.accountToken.trim().isNotEmpty == true} '
      'storeId=$storeId branchId=$branchId',
    );

    if (cache == null || cache.accountToken.trim().isEmpty) {
      SyncDiagnosticsLog.add(
        '[RECOVER_IDENTITY] blocked reason=missing_online_session',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('online_account_session_required'))),
      );
      return;
    }
    if (widget.store.security.hasLocalAdminUser) {
      SyncDiagnosticsLog.add(
        '[RECOVER_IDENTITY] blocked reason=local_store_data_exists',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr.text('local_store_identity_recovery_locked'))),
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
        SnackBar(content: Text(tr.text('store_id_not_found_for_account'))),
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
      final recoverySettings = direct.copyWith(
        enabled: true,
        apiBaseUrl: direct.apiBaseUrl.trim().isNotEmpty
            ? direct.apiBaseUrl.trim()
            : VpsControlPlaneSettings.bundledApiBaseUrl,
        clearLastPullCursor: true,
      );
      await recoverySettings.save();
      final recoveryClient = http.Client();
      late final DirectStoreRecoveryResult result;
      try {
        result = await DirectControlPlaneService(
          widget.store,
          client: recoveryClient,
        ).recoverExistingStoreIdentityFromDirect(
          recoverySettings,
          storeId: storeId,
          branchId: branchId,
        );
      } finally {
        recoveryClient.close();
      }
      SyncDiagnosticsLog.add(
        '[RECOVER_IDENTITY] result ok=${result.ok} '
        'storeId=${result.identity?.storeId ?? storeId} '
        'branchId=${result.identity?.branchId ?? branchId} '
        'loginName=${result.loginName} '
        'storeSlug=${result.storeSlug} '
        'directSyncEnabled=${result.directSyncEnabled} '
        'deviceLimit=${result.deviceLimit?.allowed ?? -1}',
      );
      if (result.ok) {
        final recoveryCache = _authCache ?? AccountAuthCache.load();
        final recoveryUsername = recoveryCache == null
            ? ''
            : _recoveryUsernameFromResult(result, recoveryCache);
        if (recoveryCache != null && recoveryUsername.isNotEmpty) {
          await widget.store.security.recoverOnlineStoreOwnerIdentity(
            storeId: result.identity?.storeId ?? storeId,
            branchId: result.identity?.branchId ?? branchId,
            storeName: result.storeName.trim().isNotEmpty
                ? result.storeName
                : recoveryCache.storeName.trim().isNotEmpty
                    ? recoveryCache.storeName
                    : widget.store.runtime.profile.name,
            username: recoveryUsername,
            password: _onlineSessionPassword,
            hostDeviceId:
                result.identity?.hostDeviceId.trim().isNotEmpty == true
                    ? result.identity!.hostDeviceId
                    : widget.store.sync.deviceId,
            deviceToken: result.identity?.deviceToken ?? '',
            controlPlaneTenantId: result.identity?.controlPlaneTenantId ?? '',
            deviceRole: DeviceRole.host,
            syncMode: previousIdentity.syncMode,
          );
          final updatedCache = recoveryCache.copyWith(
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
            // Keep the cached entitlement unchanged here. Store recovery may
            // rebuild the identity, but the subscription gate must still be
            // decided by the live plan check, not by the recovery response.
            directSyncEnabled: recoveryCache.directSyncEnabled,
            devicesLimit:
                result.deviceLimit?.allowed ?? recoveryCache.devicesLimit,
            lastVerifiedAt: DateTime.now(),
          );
          await AccountAuthCache.save(updatedCache);
          _setAuthCache(updatedCache);
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
    final cache = _authCache ?? AccountAuthCache.load();
    final direct = VpsControlPlaneSettings.load();
    SyncDiagnosticsLog.add(
      '[RECOVER_DATA] press '
      'hasLocalStoreData=${widget.store.recovery.hasLocalStoreData} '
      'hasStoreIdentity=${widget.store.runtime.identity.hostDeviceId.trim().isNotEmpty} '
      'hasCache=${cache != null} '
      'accountToken=${cache?.accountToken.trim().isNotEmpty == true}',
    );

    if (cache == null || cache.accountToken.trim().isEmpty) {
      SyncDiagnosticsLog.add(
        '[RECOVER_DATA] blocked reason=missing_online_session',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('online_account_session_required'))),
      );
      return;
    }
    if (widget.store.runtime.identity.hostDeviceId.trim().isEmpty) {
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
      latestCache = await AccountAuthService.cacheOnlineResult(sessionResult,
          mode: cache.mode.isEmpty ? 'login' : cache.mode);
      _setAuthCache(latestCache);
    }
    SyncDiagnosticsLog.add(
      '[RECOVER_DATA] refresh_session result ok=${sessionResult.ok} '
      'storeId=${sessionResult.storeId} branchId=${sessionResult.branchId} '
      'directSyncEnabled=${sessionResult.directSyncEnabled}',
    );
    if (!context.mounted) return;
    final storeId = (sessionResult.storeId.trim().isNotEmpty
            ? sessionResult.storeId
            : latestCache.storeId.trim().isNotEmpty
                ? latestCache.storeId
                : widget.store.runtime.identity.storeId)
        .trim()
        .toUpperCase();
    final branchId = (sessionResult.branchId.trim().isNotEmpty
            ? sessionResult.branchId
            : latestCache.branchId.trim().isNotEmpty
                ? latestCache.branchId
                : widget.store.runtime.identity.branchId)
        .trim()
        .toUpperCase();
    if (!storeId.startsWith('ST-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('store_id_not_found_for_account'))),
      );
      return;
    }
    // The live subscription response is authoritative. A stale local cache
    // must not keep Direct enabled after Admin disables it.
    final directAllowed = sessionResult.ok && sessionResult.directSyncEnabled;
    if (!directAllowed) {
      SyncDiagnosticsLog.add(
        '[RECOVER_DATA] blocked reason=direct_sync_not_enabled storeId=$storeId branchId=$branchId',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr.text('subscription_not_enrolled_direct_sync'))),
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
      final recoverySettings = direct.copyWith(
        enabled: true,
        apiBaseUrl: direct.apiBaseUrl.trim().isNotEmpty
            ? direct.apiBaseUrl.trim()
            : VpsControlPlaneSettings.bundledApiBaseUrl,
        clearLastPullCursor: true,
      );
      await recoverySettings.save();
      final recoveryClient = http.Client();
      late final DirectStoreRecoveryResult result;
      try {
        final recoveryService = DirectControlPlaneService(
          widget.store,
          client: recoveryClient,
        );
        final identityMismatch =
            widget.store.runtime.identity.storeId.trim().toUpperCase() != storeId;
        // When business data already exists and only a test/probe identity is
        // wrong, repair the identity without replacing local data by a remote
        // snapshot. Full recovery remains available for an empty matching
        // Store installation.
        result = identityMismatch && widget.store.recovery.hasLocalStoreData
            ? await recoveryService.recoverExistingStoreIdentityFromDirect(
                recoverySettings,
                storeId: storeId,
                branchId: branchId,
              )
            : await recoveryService.recoverExistingStoreFromDirect(
                recoverySettings,
                storeId: storeId,
                branchId: branchId,
              );
      } finally {
        recoveryClient.close();
      }
      SyncDiagnosticsLog.add(
        '[RECOVER_DATA] result ok=${result.ok} '
        'storeId=${result.identity?.storeId ?? storeId} '
        'branchId=${result.identity?.branchId ?? branchId} '
        'storeName=${result.storeName} '
        'pulled=${result.pulled} '
        'loginName=${result.loginName} '
        'storeSlug=${result.storeSlug} '
        'directSyncEnabled=${result.directSyncEnabled} '
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
        StartupTimingService.event(
          'login_success',
          category: 'auth',
          details: 'mode=online',
        );
        _onlineSessionPassword = _passwordController.text;
        final cached = await AccountAuthService.cacheOnlineResult(
          onlineResult,
          mode: 'login',
        );
        _setAuthCache(cached);
        // An online login opens the account-management surface. It must not
        // rewrite the local Store Owner, especially for platform_admin
        // accounts such as user@ventio. Local credentials are synchronized
        // only through an explicit password change on either side.
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

    final ok = await widget.store.security.login(
      localUsername,
      _passwordController.text,
      remember: _rememberLogin,
    );

    if (!mounted) return;

    setState(() => _loggingIn = false);

    if (ok) {
      StartupTimingService.event(
        'login_success',
        category: 'auth',
        details: 'mode=local',
      );
      setState(() {});
    } else {
      _passwordController.clear();
      messenger.showSnackBar(SnackBar(content: Text(invalidLoginMessage)));
    }
  }
}
