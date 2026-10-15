// ignore_for_file: invalid_use_of_protected_member
part of 'settings_page.dart';

extension _SyncConfiguration on _UnifiedSyncSettingsCardState {
  String _runtimeClientTransport() {
    final identity = widget.store.appIdentity;
    final state = SyncDeviceStateStore.load(identity);
    final active = state.activeTransport.trim().toLowerCase();
    if (active == 'lan' || active == 'direct') return active;
    final last = state.lastSyncTransport.trim().toLowerCase();
    if (last == 'lan' || last == 'direct') return last;
    return identity.activeSyncTransportNormalized;
  }

  Future<void> _refreshDirectSyncPlanAccess() async {
    final cache = AccountAuthCache.load();
    // Do not treat the local cache as an entitlement. The Admin subscription
    // response must positively authorize Direct on every verification.
    bool? planAllowed;
    final identityAtStart = widget.store.appIdentity;
    final directAtStart = VpsControlPlaneSettings.load();

    String boolLabel(bool? value) {
      if (value == null) return 'unknown';
      return value ? 'true' : 'false';
    }

    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] directPlanAccess:start '
      'device=${identityAtStart.deviceId} '
      'role=${identityAtStart.deviceRole.name} '
      'store=${identityAtStart.storeId} '
      'branch=${identityAtStart.branchId} '
      'syncMode=${identityAtStart.syncMode.name} '
      'activeTransport=${identityAtStart.activeSyncTransportNormalized} '
      'apiBase=${directAtStart.apiBaseUrl} '
      'directConfigured=${directAtStart.isConfigured} '
      'hasDeviceToken=${identityAtStart.deviceToken.trim().isNotEmpty} '
      'cacheExists=${cache != null} '
      'cacheMode=${cache?.mode ?? ''} '
      'cacheStore=${cache?.storeId ?? ''} '
      'cacheBranch=${cache?.branchId ?? ''} '
      'hasAccountToken=${cache?.accountToken.trim().isNotEmpty == true} '
      'cacheAllowed=${boolLabel(planAllowed)}',
    );

    try {
      final token = cache?.accountToken.trim() ?? '';
      if (token.isNotEmpty) {
        // Access tokens are intentionally short-lived. The Direct entitlement
        // check must use the refresh token as well, otherwise an otherwise
        // valid subscription is displayed as "Locked by plan" after the
        // 15-minute access-token lifetime expires.
        final result = await AccountAuthService().refreshSession(
          accountToken: token,
          refreshToken: cache?.refreshToken.trim() ?? '',
        );
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] directPlanAccess:session '
          'ok=${result.ok} '
          'store=${result.storeId} '
          'branch=${result.branchId} '
          'status=${result.subscriptionStatus} '
          'allowed=${result.directSyncEnabled} '
          'message=${result.message}',
        );
        if (result.ok) {
          await AccountAuthService.cacheOnlineResult(result,
              mode: cache?.mode ?? 'login');
          planAllowed = result.directSyncEnabled;
        }
      } else {
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] directPlanAccess:session skipped=noAccountToken');
      }

      // Fallback for local Host sessions. After the user signs in locally as
      // admin, account_auth_cache_v1 may be missing or stale, while the device
      // still has valid store/device credentials. Ask the server directly for
      // this store's Direct Sync entitlement using device auth.
      if (planAllowed != true) {
        // The account session may be expired or concurrently refreshing in
        // another screen. Retry the store entitlement endpoint before
        // deciding that Direct is unavailable.
        for (var attempt = 1; attempt <= 3 && planAllowed != true; attempt++) {
          final fallbackAllowed = await _controlPlaneService()
              .checkDirectSyncPlanAccess(VpsControlPlaneSettings.load());
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] directPlanAccess:fallback '
            'attempt=$attempt allowed=$fallbackAllowed '
            'previous=${boolLabel(planAllowed)}',
          );
          if (fallbackAllowed != null) {
            planAllowed = fallbackAllowed;
            break;
          }
          if (attempt < 3) {
            await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
          }
        }
      }

      if (!mounted) return;
      final identity = widget.store.appIdentity;
      setState(() {
        _directSyncPlanAllowed = planAllowed;
        _directEnabled = identity.isDirectEnabled;
      });
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] directPlanAccess:final '
        'allowed=${boolLabel(planAllowed)} '
        'denied=${planAllowed == false} '
        'uiAllows=${planAllowed != false} '
        'identityDirect=${identity.isDirectEnabled} '
        'switchValue=$_directEnabled',
      );
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] directPlanAccess:refreshFailed $error');
      if (mounted && _directSyncPlanAllowed != true) {
        setState(() {
          _status = 'Could not verify Direct Sync access.';
        });
      }
      // Fail closed if the subscription authority cannot be reached.
    }
  }

  int get _lanPort => int.tryParse(_lanPortController.text.trim()) ?? 8787;
  int get _lanInterval => LanSyncSettings.defaultIntervalSeconds;
  int get _directInterval => LanSyncSettings.defaultIntervalSeconds;

  void _onSyncDraftChanged() {
    if (mounted) setState(() {});
    if (_deviceRole == DeviceRole.host) {
      _scheduleHostSyncAutoSave();
    }
  }

  void _scheduleHostSyncAutoSave() {
    _syncAutoSaveTimer?.cancel();
    _syncAutoSaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || _deviceRole != DeviceRole.host) return;
      unawaited(_saveSyncSettings());
    });
  }

  bool get _hasUnsavedSyncChanges {
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final role = identity.isClient ? DeviceRole.client : DeviceRole.host;
    final lanEnabled = identity.isHost && lan.setupComplete && lan.isHost;
    final directEnabled =
        identity.isDirectEnabled && _directSyncPlanAllowed == true;
    return _deviceRole != role ||
        _clientSyncModeDirty ||
        _lanEnabledForHost != lanEnabled ||
        _directEnabled != directEnabled ||
        _lanHostController.text.trim() != lan.host.trim() ||
        _lanPortController.text.trim() != lan.port.toString();
  }

  void _resetSyncDraft({String? status}) {
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final direct = DirectSyncSettings.load();
    setState(() {
      _deviceRole = identity.isClient ? DeviceRole.client : DeviceRole.host;
      _clientSyncMode = _runtimeClientTransport() == 'direct'
          ? SyncMode.directConnected
          : SyncMode.lanOnly;
      _clientSyncModeDirty = false;
      _lanEnabledForHost = identity.isHost && lan.setupComplete && lan.isHost;
      _directEnabled =
          identity.isDirectEnabled && _directSyncPlanAllowed == true;
      _lanHostController.text = lan.host;
      _lanPortController.text = lan.port.toString();
      _lanIntervalController.text = lan.intervalSeconds.toString();
      _directApiController.text = direct.apiBaseUrl;
      _directIntervalController.text =
          LanSyncSettings.defaultIntervalSeconds.toString();
      _status = status ?? AppLocalizations.of(context).text('cancelled');
    });
  }

  Future<void> _testCurrentConnection() async {
    final identity = widget.store.appIdentity;
    if (identity.isHost || _deviceRole == DeviceRole.host) {
      await _testPairedClientConnections();
      return;
    }
    final shouldTestDirect = _runtimeClientTransport() == 'direct';
    if (shouldTestDirect) {
      await _testDirectConnection();
    } else {
      await _testHostConnection();
    }
  }

  String _simpleSyncError(Object error, {required String fallback}) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('pairing code expired') ||
        lower.contains('already used')) {
      return tr.text('pairing_code_expired_or_used');
    }
    if (lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('failed host lookup')) {
      return fallback;
    }
    if (lower.contains('null check operator used on a null value')) {
      return tr.text('pairing_state_refresh_failed');
    }
    final readable = raw
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    // Keep the actual Direct/LAN failure visible. The old fallback hid relay
    // errors behind a generic message, making it impossible to distinguish a
    // missing Host, rejected request, or failed pull from the UI.
    return readable.isEmpty ? fallback : localizeRuntimeMessage(readable, tr);
  }

  Future<void> _saveSyncSettings() => _run(() async {
        widget.store.requirePermission(AppPermission.syncManage);
        final identity = widget.store.appIdentity;
        final tr = AppLocalizations.of(context);
        if (_deviceRole == DeviceRole.host) {
          if (_directEnabled && _directSyncPlanDenied) {
            throw Exception(tr.text('direct_sync_plan_required'));
          }
          final effectiveDirectEnabled = _effectiveDirectEnabled;
          await widget.store.updateAppIdentityLocalOnly(
            identity.copyWith(
              deviceRole: DeviceRole.host,
              syncMode: effectiveDirectEnabled
                  ? SyncMode.directConnected
                  : (_lanEnabledForHost
                      ? SyncMode.lanOnly
                      : SyncMode.localOnly),
              activeSyncTransport: effectiveDirectEnabled
                  ? 'direct'
                  : (_lanEnabledForHost ? 'lan' : 'local'),
            ),
            source: 'sync settings save',
          );
          final existingLan = LanSyncSettings.load();
          final migratedLan =
              existingLan.withMigratedHostRegistry(widget.store.deviceId);
          await LanSyncSettings(
            host: _lanHostController.text.trim().isEmpty
                ? migratedLan.host
                : _lanHostController.text.trim(),
            port: _lanPort,
            intervalSeconds: _lanInterval,
            autoSyncEnabled: _lanEnabledForHost,
            hostModeEnabled: _lanEnabledForHost,
            setupComplete: _lanEnabledForHost,
            mode: _lanEnabledForHost
                ? LanSyncDeviceMode.host
                : LanSyncDeviceMode.unconfigured,
            secret: migratedLan.secret,
            pairedDevices: migratedLan.pairedDevices,
            hostRegistry: migratedLan.hostRegistry,
          ).save();
          final directSettings = DirectSyncSettings.load();
          await directSettings
              .copyWith(
                apiBaseUrl: _directApiController.text.trim(),
                peerDeviceId: identity.deviceId,
                setupComplete: effectiveDirectEnabled,
                autoSyncEnabled: effectiveDirectEnabled,
              )
              .save();
          if (!effectiveDirectEnabled) {
            await LocalDatabaseService.deleteString(_initialDirectHostReadyKey);
          }
        } else {
          final activeTransport =
              _clientSyncMode == SyncMode.directConnected ? 'direct' : 'lan';
          final lanSettings = LanSyncSettings.load();
          final directSettings = DirectSyncSettings.load();
          final lanConfigured = _isLanClientConfigured(lanSettings);
          final directConfigured = _isDirectClientConfigured(directSettings);
          if (activeTransport == 'lan' && !lanConfigured) {
            throw Exception(tr.text('lan_not_configured_cannot_switch'));
          }
          if (activeTransport == 'direct' && !directConfigured) {
            throw Exception('Direct is not configured on this device.');
          }
          await widget.store.updateAppIdentityLocalOnly(
            identity.copyWith(
              deviceRole: DeviceRole.client,
              syncMode: _clientSyncMode,
              activeSyncTransport: activeTransport,
            ),
            source: 'sync settings save',
          );
          await lanSettings
              .copyWith(
                host: _lanHostController.text.trim().isEmpty
                    ? lanSettings.host
                    : _lanHostController.text.trim(),
                port: _lanPort,
                autoSyncEnabled: activeTransport == 'lan',
                hostModeEnabled: false,
                intervalSeconds: _lanInterval,
              )
              .save();
          await directSettings
              .copyWith(autoSyncEnabled: activeTransport == 'direct')
              .save();
          await widget.store.setActiveSyncTransport(activeTransport);
        }
        if (mounted) {
          _resetSyncDraft(
              status: AppLocalizations.of(context).text('sync_settings_saved'));
        }
      });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final tr = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = tr.text('working');
      _statusProgress = null;
    });
    try {
      await action();
      await widget.onSyncSettingsChanged?.call();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = _simpleSyncError(error,
              fallback: tr.text('sync_failed_check_info'));
          _statusProgress = null;
        });
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusProgress = null;
        });
      }
    }
  }

  VpsControlPlaneSettings _directSettings(
      {bool enabled = true, bool? autoSyncEnabled}) {
    final current = VpsControlPlaneSettings.load();
    final normalizedUrl = current.apiBaseUrl.trim().isNotEmpty
        ? current.apiBaseUrl
        : VpsControlPlaneSettings.normalizeApiBaseUrl(
            VpsControlPlaneSettings.bundledApiBaseUrl,
            fallback: kIsWeb ? Uri.base.origin : '',
          );
    return current.copyWith(
      enabled: enabled,
      apiBaseUrl: normalizedUrl,
      autoSyncEnabled: autoSyncEnabled ?? enabled,
      intervalSeconds: _directInterval,
    );
  }

  UnifiedSyncEngine _directEngine({bool enabled = true}) =>
      UnifiedSyncFactory.directEngine(
        widget.store,
        settings: _directSettings(enabled: enabled),
        enabled: enabled,
      );

  UnifiedSyncEngine _lanEngine([LanSyncSettings? settings]) =>
      UnifiedSyncFactory.lanEngine(
        widget.store,
        settings: settings ?? LanSyncSettings.load(),
      );

  DirectControlPlaneService _controlPlaneService() =>
      DirectControlPlaneService(widget.store);
}
