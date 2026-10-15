// ignore_for_file: invalid_use_of_protected_member
part of 'sync_setup_page.dart';

extension _SyncSetupPairing on _SyncSetupPageState {
  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
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
    if (code == null || code.trim().isEmpty) return;
    _applyScannedPayload(code.trim());
  }

  void _applyScannedPayload(String raw) {
    String code = raw;
    String apiBaseUrl = '';
    String peerDeviceId = '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final transport = (decoded['transport'] ??
                decoded['syncType'] ??
                decoded['type'] ??
                '')
            .toString()
            .toLowerCase();
        if (transport.contains('lan')) {
          _mode = _ConnectMode.lan;
        } else if (transport.contains('direct') ||
            transport.contains('direct')) {
          _mode = _ConnectMode.direct;
        }

        final host =
            (decoded['host'] ?? decoded['hostIp'] ?? decoded['ip'] ?? '')
                .toString();
        final port = (decoded['port'] ?? '').toString();
        final token = (decoded['pairingCode'] ??
                decoded['pairing_code'] ??
                decoded['code'] ??
                decoded['token'] ??
                decoded['pairingToken'] ??
                '')
            .toString();
        apiBaseUrl = (decoded['apiBaseUrl'] ?? decoded['apiUrl'] ?? '')
            .toString()
            .trim();
        peerDeviceId = (decoded['hostDeviceId'] ?? '').toString().trim();
        final expiresAtRaw =
            (decoded['expiresAt'] ?? decoded['expires_at'] ?? '').toString();
        _qrExpiresAt = DateTime.tryParse(expiresAtRaw);

        if (host.trim().isNotEmpty) _hostController.text = host.trim();
        if (port.trim().isNotEmpty) _portController.text = port.trim();

        code = token.trim().isNotEmpty ? token.trim() : raw;
      }
    } catch (_) {
      // Plain pairing code. Keep it as-is.
    }

    if (_mode == _ConnectMode.direct && apiBaseUrl.isNotEmpty) {
      final existingDirect = DirectSyncSettings.load();
      unawaited(DirectSyncSettings(
        apiBaseUrl: apiBaseUrl,
        peerDeviceId: peerDeviceId,
        // QR metadata may contain the Host device id, but it is not proof that
        // the Store Snapshot was imported successfully.
        setupComplete: false,
        autoSyncEnabled: existingDirect.autoSyncEnabled,
        stunServer: existingDirect.stunServer,
        stunServers: existingDirect.stunServers,
        turnServers: existingDirect.turnServers,
        iceTransportPolicy: existingDirect.iceTransportPolicy,
        iceCandidatePoolSize: existingDirect.iceCandidatePoolSize,
      ).save());
    }

    setState(() {
      if (_mode == _ConnectMode.lan) {
        _lanTokenController.text = code;
      } else {
        _directPairingCodeController.text = code;
      }
      _status = AppLocalizations.of(context).text('qr_detected_connecting');
      _statusType = _SetupStatus.info;
      _syncQrStatusFromInput();
    });
    Future.microtask(() async {
      if (!mounted || _busy) return;
      if (_mode == _ConnectMode.lan &&
          _lanTokenController.text.trim().isNotEmpty) {
        await _connectLan();
      } else if (_mode == _ConnectMode.direct &&
          _directPairingCodeController.text.trim().isNotEmpty) {
        await _connectDirect();
      }
    });
  }

  Future<void> _connectLan() async {
    final tr = AppLocalizations.of(context);
    final connectLanStart = tr.text('connect_lan_start');
    final hostIpRequiredLan = tr.text('host_ip_required_lan');
    final lanPairingCodeRequired = tr.text('lan_pairing_code_required');
    final claimingLanPairing = tr.text('claiming_lan_pairing');
    final connectedLanSignIn = tr.text('connected_lan_sign_in');
    final lanConnectionFailed = tr.text('lan_connection_failed');

    _beginConnectionAttempt(connectLanStart);
    try {
      final secret = _lanTokenController.text.trim();
      final host = _hostController.text.trim();
      if (host.isEmpty) {
        setState(() => _qrStatus = _ClientPairingState.noCode);
        _setStatus(hostIpRequiredLan, type: _SetupStatus.warning);
        return;
      }
      if (secret.isEmpty) {
        setState(() => _qrStatus = _ClientPairingState.noCode);
        _setStatus(lanPairingCodeRequired, type: _SetupStatus.warning);
        return;
      }

      _setStatus(claimingLanPairing);
      final result = await _lanEngine().claimPairingCode(secret,
          onProgress: (value, label) {
        _addConnectionLog('LAN progress ${(value * 100).round()}%: $label');
        _setSnapshotProgress(value, label);
      });
      if (!result.ok) {
        _addConnectionLog('FAILED: ${result.message}');
        _markQrFailed(result.message);
        _setStatus(result.message, type: _SetupStatus.error);
        return;
      }

      await _finishSuccessfulConnection(connectedLanSignIn);
      _addConnectionLog('SUCCESS: LAN pairing completed');
    } catch (error) {
      _addConnectionLog('EXCEPTION: $error');
      _markQrFailed(error.toString());
      _setStatus(_friendlyErrorMessage(error, fallback: lanConnectionFailed),
          type: _SetupStatus.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectDirect() async {
    _beginConnectionAttempt('Connecting directly to Host...');
    final previousIdentity = widget.store.runtime.identity;
    final previousDirectSettings = DirectSyncSettings.load();
    var provisionalPairingCreated = false;

    Future<void> rollbackProvisionalPairing() async {
      if (!provisionalPairingCreated) return;
      try {
        // Snapshot import is atomic. If bootstrap never reaches its successful
        // ACK/setupComplete point, restore the local role/settings that existed
        // before claiming the one-time code. This prevents a failed Direct
        // attempt from turning Connect to Store into the permanent login gate.
        final restoreSettings = previousIdentity.isClient &&
                previousIdentity.activeSyncTransportNormalized == 'direct'
            ? previousDirectSettings
            : previousDirectSettings.copyWith(
                peerDeviceId: '',
                setupComplete: false,
              );
        await restoreSettings.save();
        await widget.store.runtime.updateIdentityDuringSetup(previousIdentity);
        SyncDiagnosticsLog.add(
            '[DIRECT_PAIRING] provisional bootstrap rolled back after failed snapshot');
      } catch (rollbackError) {
        SyncDiagnosticsLog.add(
            '[DIRECT_PAIRING] provisional bootstrap rollback failed=$rollbackError');
      }
    }

    try {
      final code = _directPairingCodeController.text.trim();
      if (code.isEmpty) {
        setState(() => _qrStatus = _ClientPairingState.noCode);
        _setStatus('Direct pairing code is required.',
            type: _SetupStatus.warning);
        return;
      }
      final pairingEngine = UnifiedSyncFactory.directEngine(widget.store);
      final claim = await pairingEngine.claimPairingCode(code,
          onProgress: (value, label) {
        _addConnectionLog('DIRECT ${(value * 100).round()}%: $label');
        _setSnapshotProgress(value, label);
      });
      if (!claim.ok) {
        _markQrFailed(claim.message);
        _setStatus(claim.message, type: _SetupStatus.error);
        return;
      }
      provisionalPairingCreated = true;
      final syncEngine = UnifiedSyncFactory.directEngine(widget.store);
      final snapshot = await syncEngine.rebuildFromHostSnapshot(
        onProgress: (value, label) {
          _addConnectionLog(
              'DIRECT SNAPSHOT ${(value * 100).round()}%: $label');
          _setSnapshotProgress(value, label);
        },
      );
      if (!snapshot.ok) {
        await rollbackProvisionalPairing();
        provisionalPairingCreated = false;
        _markQrFailed(snapshot.message);
        _setStatus(snapshot.message, type: _SetupStatus.error);
        return;
      }
      provisionalPairingCreated = false;
      await _finishSuccessfulConnection('Direct connection completed.');
    } catch (error) {
      await rollbackProvisionalPairing();
      provisionalPairingCreated = false;
      _markQrFailed(error.toString());
      _setStatus('Direct connection failed: $error', type: _SetupStatus.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() {
    if (_mode == _ConnectMode.lan) return _connectLan();
    return _connectDirect();
  }
}
