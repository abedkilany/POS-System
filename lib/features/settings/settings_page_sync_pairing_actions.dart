// ignore_for_file: invalid_use_of_protected_member
part of 'settings_page.dart';

extension _SyncPairingActions on _UnifiedSyncSettingsCardState {
  Future<void> _refreshHostIpAddresses() async {
    if (_detectingHostIp) return;
    if (mounted) setState(() => _detectingHostIp = true);
    try {
      final addresses = await LanSyncSettings.localIpv4Addresses();
      if (!mounted) return;
      setState(() {
        _hostIpAddresses = addresses;
        if (_deviceRole == DeviceRole.host && addresses.isNotEmpty) {
          _lanHostController.text = addresses.first;
        }
      });
    } finally {
      if (mounted) setState(() => _detectingHostIp = false);
    }
  }

  Future<void> _generateLanToken() async {
    widget.store.requirePermission(AppPermission.syncManage);
    final savedLan = LanSyncSettings.load();
    final identity = widget.store.appIdentity;
    final lanEnabled =
        identity.isHost && savedLan.setupComplete && savedLan.isHost;
    if (!_lanEnabledForHost || !lanEnabled) {
      throw StateError(tr.text('enable_lan_before_pairing_code'));
    }
    final current = savedLan.copyWith(
      host: _lanHostController.text.trim().isEmpty
          ? savedLan.host
          : _lanHostController.text.trim(),
      port: _lanPort,
    );
    final result = await _lanEngine(current)
        .createPairingCode(ttlMinutes: _pairingCodeLifetime.inMinutes);
    if (!result.ok) {
      throw StateError(localizeRuntimeMessage(result.message, tr));
    }
    final code = result.code;
    final expiresAt =
        result.expiresAt ?? DateTime.now().add(_pairingCodeLifetime);
    _lanTokenController.text = code;
    _latestLanPairingExpiresAt = expiresAt;
    _latestLanPairingConsumed = false;
    _showLanPairingCode = true;
    await LocalDatabaseService.setString(
        _lanPairingExpiryStorageKey, expiresAt.toIso8601String());
    if (mounted) setState(() => _status = tr.text('lan_pairing_code_created'));
  }

  void _loadActivePairingCodes() {
    final now = DateTime.now();
    final lanExpiry = DateTime.tryParse(
        LocalDatabaseService.getString(_lanPairingExpiryStorageKey) ?? '');
    if (_lanTokenController.text.trim().isNotEmpty &&
        lanExpiry != null &&
        lanExpiry.isAfter(now)) {
      _latestLanPairingExpiresAt = lanExpiry;
    } else if (lanExpiry != null && !lanExpiry.isAfter(now)) {
      _expireLanPairingCode();
    }
    final directCode =
        LocalDatabaseService.getString(_directPairingCodeStorageKey) ?? '';
    if (directCode.trim().isNotEmpty) {
      _latestDirectPairingCode = directCode.trim();
    }
    final directExpiry = DateTime.tryParse(
        LocalDatabaseService.getString(_directPairingExpiryStorageKey) ?? '');
    if (directCode.trim().isNotEmpty &&
        directExpiry != null &&
        directExpiry.isAfter(now)) {
      _latestDirectPairingExpiresAt = directExpiry;
      _latestDirectPairingInvalid = false;
    } else if (directExpiry != null && !directExpiry.isAfter(now)) {
      _latestDirectPairingExpiresAt = directExpiry;
      _expireDirectPairingCode();
    }
  }

  void _startPairingCountdownTimer() {
    _pairingCountdownTimer?.cancel();
    _pairingCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      if (_latestLanPairingExpiresAt != null &&
          !_latestLanPairingExpiresAt!.isAfter(now)) {
        _expireLanPairingCode();
      }
      _refreshLanPairingConsumedState();
      if (_latestDirectPairingExpiresAt != null &&
          !_latestDirectPairingExpiresAt!.isAfter(now)) {
        _expireDirectPairingCode();
      }
      if (_latestDirectPairingCode.trim().isNotEmpty &&
          (_latestDirectPairingExpiresAt?.isAfter(now) ?? false)) {
        final lastCheck = _lastDirectPairingStatusCheck;
        if (lastCheck == null || now.difference(lastCheck).inSeconds >= 5) {
          _lastDirectPairingStatusCheck = now;
          unawaited(_refreshDirectPairingStatus());
        }
      }
      setState(() {});
    });
  }

  void _refreshLanPairingConsumedState() {
    final activeCode = _lanTokenController.text.trim();
    if (activeCode.isEmpty || _latestLanPairingConsumed) return;
    final expiresAt = _latestLanPairingExpiresAt;
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) return;
    final savedSecret = LanSyncSettings.load().secret.trim();
    if (savedSecret.isEmpty || savedSecret != activeCode) {
      _latestLanPairingConsumed = true;
    }
  }

  void _expireLanPairingCode() {
    _latestLanPairingConsumed = false;
    unawaited(LocalDatabaseService.deleteString(_lanPairingExpiryStorageKey));
    unawaited(LanSyncSettings.load().copyWith(secret: '').save());
  }

  void _expireDirectPairingCode() {
    _latestDirectPairingConsumed = false;
    _latestDirectPairingInvalid = false;
    unawaited(LocalDatabaseService.deleteString(_directPairingCodeStorageKey));
    unawaited(
        LocalDatabaseService.deleteString(_directPairingExpiryStorageKey));
  }

  String _countdownText(DateTime? expiresAt) {
    if (expiresAt == null) return '00:00';
    final seconds = expiresAt
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 24 * 60 * 60)
        .toInt();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  bool get _hasActiveLanPairingCode =>
      _lanTokenController.text.trim().isNotEmpty &&
      _latestLanPairingExpiresAt != null &&
      _latestLanPairingExpiresAt!.isAfter(DateTime.now());

  bool get _hasActiveDirectPairingCode =>
      _latestDirectPairingCode.trim().isNotEmpty &&
      _latestDirectPairingExpiresAt != null &&
      _latestDirectPairingExpiresAt!.isAfter(DateTime.now());

  String get _lanPairingButtonLabel => _hasActiveLanPairingCode
      ? tr.text('regenerate_new_lan_code')
      : tr.text('generate_lan_code');

  String get _directPairingButtonLabel =>
      _hasActiveDirectPairingCode && _latestPairingTransport == 'direct'
          ? 'Regenerate Direct Code'
          : 'Direct pairing code';

  Future<void> _refreshDirectPairingStatus() async {
    final code = _latestDirectPairingCode.trim();
    if (code.isEmpty || !widget.store.appIdentity.isHost) return;
    final settings = _directSettings(enabled: true);
    if (!settings.isConfigured) return;
    final result =
        await _controlPlaneService().pairingCodeStatus(settings, code);
    if (!mounted || !result.ok) return;
    if (result.status == 'consumed') {
      await _adoptConsumedDirectPairingDevice(result);
      if (!mounted) return;
    }
    setState(() {
      if (result.status == 'consumed') {
        _latestDirectPairingConsumed = true;
        _latestDirectPairingInvalid = false;
      } else if (result.status == 'expired' || result.status == 'invalid') {
        _latestDirectPairingConsumed = false;
        _latestDirectPairingInvalid = result.status == 'invalid';
        _latestDirectPairingExpiresAt = result.status == 'expired'
            ? DateTime.now().subtract(const Duration(seconds: 1))
            : _latestDirectPairingExpiresAt;
      } else if (result.expiresAt != null) {
        _latestDirectPairingInvalid = false;
        _latestDirectPairingExpiresAt = result.expiresAt;
      }
    });
  }

  Future<void> _adoptConsumedDirectPairingDevice(
      DirectPairingStatusResult result) async {
    final clientDeviceId = result.claimedByDeviceId.trim();
    if (clientDeviceId.isEmpty || !widget.store.appIdentity.isHost) return;

    final hostDeviceId = widget.store.deviceId.trim();
    final current =
        LanSyncSettings.load().withMigratedHostRegistry(hostDeviceId);
    final updated = current.withDirectPairedHostRegistryDevice(
      hostDeviceId: hostDeviceId,
      clientDeviceId: clientDeviceId,
      deviceToken: result.claimedDeviceToken,
      deviceName: result.claimedByDeviceName,
      pairedAt: result.claimedAt ?? DateTime.now(),
    );
    await updated.save();
  }

  Future<void> _handleLanPairingButton() async {
    final identity = widget.store.appIdentity;
    final lan = LanSyncSettings.load();
    final lanEnabled = identity.isHost && lan.setupComplete && lan.isHost;
    if (!_lanEnabledForHost || !lanEnabled) {
      setState(() => _status = tr.text('enable_lan_before_pairing_code'));
      return;
    }
    final limit = _localClientDeviceLimitStatus(widget.store, lan);
    if (limit?.limitReached == true) {
      setState(() => _status = tr.text('device_limit_reached'));
      return;
    }
    if (_hasActiveLanPairingCode) _expireLanPairingCode();
    await _generateLanToken();
  }

  Future<void> _requestHostTransfer() => _run(() async {
        await widget.store.requestHostTransfer(
            reason: tr.text('user_requested_host_role_reason'));
        final direct = _directSettings(enabled: true);
        if (direct.apiBaseUrl.trim().isNotEmpty) {
          await _controlPlaneService().requestHostTransfer(direct,
              reason: tr.text('user_requested_host_role_reason'));
        }
        if (mounted) {
          setState(() => _status = tr.format('host_transfer_request_created',
              {'deviceId': widget.store.deviceId}));
        }
      });

  Future<void> _approveHostTransferFromUi() => _run(() async {
        widget.store.requirePermission(AppPermission.syncManage);
        final deviceId = _transferDeviceController.text.trim();
        if (deviceId.isEmpty) {
          throw StateError(tr.text('client_device_id_required'));
        }
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(
                AppLocalizations.of(context).text('approve_host_transfer')),
            content: Text(AppLocalizations.of(context)
                .text('approve_host_transfer_desc')
                .replaceAll('{deviceId}', deviceId)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(AppLocalizations.of(context).text('cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(AppLocalizations.of(context).text('approve'))),
            ],
          ),
        );
        if (confirmed != true) return;
        final direct = _directSettings(enabled: true);
        if (direct.isConfigured) {
          final directResult = await _controlPlaneService()
              .approveHostTransfer(direct, deviceId);
          if (!directResult.ok) {
            throw StateError(localizeRuntimeMessage(directResult.message, tr));
          }
        }
        await widget.store.approveHostTransfer(deviceId);
        if (mounted) {
          setState(() {
            _deviceRole = DeviceRole.host;
            _status = tr.text('host_transfer_approved_wait_activation');
          });
        }
      });

  Future<void> _activateApprovedHostTransferFromUi() => _run(() async {
        widget.store.requirePermission(AppPermission.syncManage);
        final direct = _directSettings(enabled: true);
        if (direct.apiBaseUrl.trim().isNotEmpty) {
          await _controlPlaneService().activateHostTransfer(direct);
        }
        await widget.store.activateApprovedHostTransfer();
        if (mounted) {
          setState(() {
            _deviceRole = DeviceRole.host;
            _status = tr.text('host_transfer_activated_now_host');
          });
        }
      });

  String _normalizedPairingId(String value) => value.trim().toUpperCase();

  void _clearExpectedPairingTarget() {
    _expectedPairingStoreId = '';
    _expectedPairingBranchId = '';
    _expectedPairingHostDeviceId = '';
    _expectedPairingControlPlaneId = '';
  }

  void _rememberExpectedPairingTarget(_ScannedPairingPayload payload) {
    _expectedPairingStoreId = payload.storeId.trim();
    _expectedPairingBranchId = payload.branchId.trim();
    _expectedPairingHostDeviceId = payload.hostDeviceId.trim();
    _expectedPairingControlPlaneId = payload.controlPlaneTenantId.trim();
  }

  _ScannedPairingPayload _parseScannedPairingPayload(String raw) {
    var code = raw.trim();
    var transport = '';
    var host = '';
    var port = '';
    var apiBaseUrl = '';
    var storeId = '';
    var branchId = '';
    var hostDeviceId = '';
    var controlPlaneTenantId = '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        transport = (decoded['transport'] ??
                decoded['syncType'] ??
                decoded['type'] ??
                '')
            .toString()
            .toLowerCase();
        host = (decoded['host'] ?? decoded['hostIp'] ?? decoded['ip'] ?? '')
            .toString()
            .trim();
        port = (decoded['port'] ?? '').toString().trim();
        apiBaseUrl = (decoded['apiBaseUrl'] ??
                decoded['apiUrl'] ??
                decoded['controlPlaneApiUrl'] ??
                '')
            .toString()
            .trim();
        code = (decoded['pairingCode'] ??
                decoded['pairing_code'] ??
                decoded['code'] ??
                decoded['token'] ??
                decoded['pairingToken'] ??
                raw)
            .toString()
            .trim();
        storeId =
            (decoded['storeId'] ?? decoded['store_id'] ?? '').toString().trim();
        branchId = (decoded['branchId'] ?? decoded['branch_id'] ?? '')
            .toString()
            .trim();
        hostDeviceId = (decoded['hostDeviceId'] ??
                decoded['hostId'] ??
                decoded['host_id'] ??
                decoded['host_device_id'] ??
                '')
            .toString()
            .trim();
        controlPlaneTenantId = (decoded['controlPlaneTenantId'] ??
                decoded['tenantId'] ??
                decoded['tenant_id'] ??
                '')
            .toString()
            .trim();
      }
    } catch (_) {
      // Plain pairing code.
    }
    return _ScannedPairingPayload(
      raw: raw,
      code: code,
      transport: transport,
      host: host,
      port: port,
      apiBaseUrl: apiBaseUrl,
      storeId: storeId,
      branchId: branchId,
      hostDeviceId: hostDeviceId,
      controlPlaneTenantId: controlPlaneTenantId,
    );
  }

  void _applyParsedPairingPayload(_ScannedPairingPayload payload,
      {void Function(VoidCallback fn)? dialogSetState,
      SyncMode? fallbackMode}) {
    void apply() {
      if (payload.transport.contains('lan')) {
        _clientSyncMode = SyncMode.lanOnly;
      } else if (payload.transport.contains('direct') ||
          payload.transport.contains('direct')) {
        _clientSyncMode = SyncMode.directConnected;
      } else if (fallbackMode != null) {
        _clientSyncMode = fallbackMode;
      }
      if (payload.host.isNotEmpty) _lanHostController.text = payload.host;
      if (payload.port.isNotEmpty) _lanPortController.text = payload.port;
      if (_clientSyncMode == SyncMode.lanOnly) {
        _lanTokenController.text = payload.code;
      } else {
        _directPairingCodeController.text = payload.code;
      }
      _rememberExpectedPairingTarget(payload);
      _status = tr.text('qr_detected_review_connect');
    }

    if (dialogSetState != null) {
      dialogSetState(apply);
    } else if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _validateExpectedPairingTarget(AppIdentity identity) {
    final mismatches = <String>[];
    final actualStore = _normalizedPairingId(identity.storeId);
    final actualBranch = _normalizedPairingId(identity.branchId);
    final actualHost = _normalizedPairingId(identity.hostDeviceId);
    final actualTenant = _normalizedPairingId(identity.controlPlaneTenantId);
    final expectedStore = _normalizedPairingId(_expectedPairingStoreId);
    final expectedBranch = _normalizedPairingId(_expectedPairingBranchId);
    final expectedHost = _normalizedPairingId(_expectedPairingHostDeviceId);
    final expectedTenant = _normalizedPairingId(_expectedPairingControlPlaneId);
    if (expectedStore.isNotEmpty && actualStore != expectedStore) {
      mismatches.add(tr.text('store_id_label'));
    }
    if (expectedBranch.isNotEmpty && actualBranch != expectedBranch) {
      mismatches.add(tr.text('branch_id_label'));
    }
    if (expectedHost.isNotEmpty && actualHost != expectedHost) {
      mismatches.add(tr.text('host_id_label'));
    }
    if (expectedTenant.isNotEmpty &&
        actualTenant.isNotEmpty &&
        actualTenant != expectedTenant) {
      mismatches.add(tr.text('tenant_id_label'));
    }
    if (mismatches.isNotEmpty) {
      throw Exception(
          tr.format('pairing_data_mismatch', {'items': mismatches.join(', ')}));
    }
  }

  void _validateAgainstExistingClientIdentity(
      AppIdentity before, AppIdentity after) {
    if (!before.isClient || before.hostDeviceId.trim().isEmpty) return;
    final mismatches = <String>[];
    if (_normalizedPairingId(before.storeId) !=
        _normalizedPairingId(after.storeId)) {
      mismatches.add(tr.text('store_id_label'));
    }
    if (_normalizedPairingId(before.branchId) !=
        _normalizedPairingId(after.branchId)) {
      mismatches.add(tr.text('branch_id_label'));
    }
    if (_normalizedPairingId(before.hostDeviceId) !=
        _normalizedPairingId(after.hostDeviceId)) {
      mismatches.add(tr.text('host_id_label'));
    }
    if (mismatches.isNotEmpty) {
      throw Exception(tr.format(
          'connection_different_store', {'items': mismatches.join(', ')}));
    }
  }

  Future<void> _scanConnectToStoreQr(
      void Function(VoidCallback fn) setDialogState,
      void Function(SyncMode mode) setDialogMode,
      SyncMode fallbackMode) async {
    widget.store.requirePermission(AppPermission.syncManage);
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PageTimingScope(
          key: const ValueKey('BarcodeScannerPage'),
          pageKey: 'BarcodeScannerPage',
          pageLabel: 'Barcode scanner',
          child: BarcodeScannerPage(
            title: AppLocalizations.of(context).text('scan_pairing_qr'),
            helpText: AppLocalizations.of(context).text('scan_pairing_qr_help'),
            formats: const [BarcodeFormat.qrCode],
          ),
        ),
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    final payload = _parseScannedPairingPayload(raw.trim());
    if (payload.transport.contains('lan')) {
      setDialogMode(SyncMode.lanOnly);
    } else if (payload.transport.contains('direct') ||
        payload.transport.contains('direct')) {
      setDialogMode(SyncMode.directConnected);
    }
    _applyParsedPairingPayload(payload,
        dialogSetState: setDialogState, fallbackMode: fallbackMode);
  }

  Future<void> _scanPairingQr() async {
    widget.store.requirePermission(AppPermission.syncManage);
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PageTimingScope(
          key: const ValueKey('BarcodeScannerPage'),
          pageKey: 'BarcodeScannerPage',
          pageLabel: 'Barcode scanner',
          child: BarcodeScannerPage(
            title: AppLocalizations.of(context).text('scan_pairing_qr'),
            helpText: AppLocalizations.of(context).text('scan_pairing_qr_help'),
            formats: const [BarcodeFormat.qrCode],
          ),
        ),
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    _applyScannedPairingPayload(raw.trim());
  }

  void _applyScannedPairingPayload(String raw) {
    final payload = _parseScannedPairingPayload(raw);
    _applyParsedPairingPayload(payload);
  }

  Future<void> _createDirectPairingCode() => _run(() async {
        var stage = 'validate';
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] directPairingCode:start device=${widget.store.deviceId}');
        try {
          widget.store.requirePermission(AppPermission.syncManage);
          final identity = widget.store.appIdentity;
          if (!_directEnabled ||
              !_effectiveDirectEnabled ||
              !identity.isDirectEnabled) {
            throw StateError(tr.text('enable_direct_before_pairing_code'));
          }
          final settings = VpsControlPlaneSettings.load();
          if (!identity.isHost || settings.apiBaseUrl.trim().isEmpty) {
            throw StateError('Direct pairing needs the Ventio server address.');
          }
          final existingDirect = DirectSyncSettings.load();
          stage = 'save_settings';
          await DirectSyncSettings(
            apiBaseUrl: settings.apiBaseUrl.trim(),
            peerDeviceId: identity.deviceId,
            setupComplete: true,
            autoSyncEnabled: existingDirect.autoSyncEnabled,
            stunServer: existingDirect.stunServer,
            stunServers: existingDirect.stunServers,
            turnServers: existingDirect.turnServers,
            iceTransportPolicy: existingDirect.iceTransportPolicy,
            iceCandidatePoolSize: existingDirect.iceCandidatePoolSize,
          ).save();
          stage = 'request_code';
          final result = await UnifiedSyncFactory.directEngine(widget.store)
              .createPairingCode(ttlMinutes: _pairingCodeLifetime.inMinutes);
          if (!result.ok) {
            throw StateError(result.message);
          }
          final expiresAt =
              result.expiresAt ?? DateTime.now().add(_pairingCodeLifetime);
          stage = 'save_code';
          await LocalDatabaseService.setString(
              _directPairingCodeStorageKey, result.code);
          await LocalDatabaseService.setString(
              _directPairingExpiryStorageKey, expiresAt.toIso8601String());
          if (!mounted) return;
          setState(() {
            _latestPairingTransport = 'direct';
            _latestDirectPairingCode = result.code;
            _latestDirectPairingExpiresAt = expiresAt;
            _latestDirectPairingConsumed = false;
            _latestDirectPairingInvalid = false;
            _showDirectPairingCode = true;
            _status = 'Direct pairing code created.';
          });
          SyncDiagnosticsLog.add(
              '[SYNC_TRACE] directPairingCode:success expiresAt=${expiresAt.toIso8601String()}');
        } catch (error) {
          SyncDiagnosticsLog.add(
              '[SYNC_TRACE] directPairingCode:failed stage=$stage error=$error');
          rethrow;
        }
      });

  Future<void> _clearInvalidPendingChanges() async {
    widget.store.requirePermission(AppPermission.syncManage);
    final pendingCount = widget.store.pendingSyncCount;
    if (pendingCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('clear_sync_settings_pending')),
        content: Text(tr.text('clear_sync_settings_pending_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(tr.text('clear')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final removed = await widget.store.clearLocalOnlyPendingSyncChanges();
      if (!mounted) return;
      setState(() {
        _status = removed > 0
            ? tr
                .text('sync_settings_pending_cleared')
                .replaceAll('{count}', removed.toString())
            : tr.text('no_sync_settings_pending_found');
      });
    });
  }
}
