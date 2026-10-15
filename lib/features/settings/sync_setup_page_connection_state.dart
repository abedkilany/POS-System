// ignore_for_file: invalid_use_of_protected_member
part of 'sync_setup_page.dart';

extension _SyncSetupConnectionState on _SyncSetupPageState {
  void _startQrCountdownTimer() {
    _qrCountdownTimer?.cancel();
    _qrCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_qrStatus == _ClientPairingState.ready &&
          _qrExpiresAt != null &&
          !_qrExpiresAt!.isAfter(DateTime.now())) {
        setState(() => _qrStatus = _ClientPairingState.expired);
        return;
      }
      if (_qrStatus == _ClientPairingState.ready) setState(() {});
    });
  }

  void _syncQrStatusFromInput() {
    final code = _activePairingCode;
    if (code.isEmpty) {
      _qrStatus = _ClientPairingState.noCode;
      _qrExpiresAt = null;
      return;
    }
    if (_qrStatus == _ClientPairingState.connected ||
        _qrStatus == _ClientPairingState.connecting) {
      return;
    }
    if (_qrExpiresAt != null && !_qrExpiresAt!.isAfter(DateTime.now())) {
      _qrStatus = _ClientPairingState.expired;
      return;
    }
    _qrStatus = _ClientPairingState.ready;
    if (_statusType == _SetupStatus.error) {
      _status = '';
      _statusType = _SetupStatus.idle;
    }
  }

  void _markQrFailed(String message) {
    final lower = message.toLowerCase();
    final expiredOrUsed = lower.contains('expired') ||
        lower.contains('already used') ||
        lower.contains('410') ||
        lower.contains('409');
    if (!mounted) return;
    setState(() => _qrStatus = expiredOrUsed
        ? _ClientPairingState.expired
        : _ClientPairingState.failed);
  }

  void _setStatus(String message, {_SetupStatus type = _SetupStatus.info}) {
    if (!mounted) return;
    if (message.trim().isNotEmpty &&
        (_connectionLog.isEmpty || !_connectionLog.last.endsWith(message))) {
      _connectionLog
          .add('[${DateTime.now().toIso8601String()}] STATUS: $message');
    }
    setState(() {
      _status = message;
      _statusType = message.trim().isEmpty ? _SetupStatus.idle : type;
    });
  }

  void _setSnapshotProgress(double value, String label) {
    if (!mounted) return;
    setState(() {
      _snapshotProgressValue = value.clamp(0.0, 1.0).toDouble();
      _snapshotProgressLabel = label;
      _status = label;
      _statusType = _SetupStatus.info;
    });
  }

  void _clearStatus() {
    if (!mounted) return;
    setState(() {
      _status = '';
      _statusType = _SetupStatus.idle;
    });
  }

  void _beginConnectionAttempt(String message) {
    SyncDiagnosticsLog.clear();
    _connectionLog
      ..clear()
      ..add('[${DateTime.now().toIso8601String()}] START $message');
    setState(() {
      _busy = true;
      _qrStatus = _ClientPairingState.connecting;
      _status = message;
      _statusType = _SetupStatus.info;
      _snapshotProgressValue = 0.02;
      _snapshotProgressLabel = message;
    });
  }

  void _addConnectionLog(String message) {
    if (!mounted) return;
    setState(() =>
        _connectionLog.add('[${DateTime.now().toIso8601String()}] $message'));
  }

  String get _fullConnectionLogText {
    final directLines = SyncDiagnosticsLog.lines.value
        .where((line) => line.contains('[DIRECT_'));
    return <String>[..._connectionLog, ...directLines].join('\n');
  }

  Future<void> _finishSuccessfulConnection(String message) async {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _qrStatus = _ClientPairingState.connected;
      _status = message;
      _statusType = _SetupStatus.success;
    });
    try {
      await widget.onDone();
    } catch (_) {
      // Pairing has already succeeded. Navigation cleanup must never turn a
      // successful connection into an error message for the user.
    }
    if (!mounted) return;
    try {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    } catch (_) {
      // Best-effort fallback only. The login gate will refresh after onDone.
    }
  }

  String _friendlyErrorMessage(Object error, {required String fallback}) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('pairing code expired') ||
        lower.contains('already used') ||
        lower.contains('410') ||
        lower.contains('409')) {
      return AppLocalizations.of(context).text('pairing_code_expired_or_used');
    }
    if (lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('failed host lookup')) {
      return fallback;
    }
    if (lower.contains('null check operator used on a null value')) {
      return AppLocalizations.of(context).text('pairing_state_refresh_failed');
    }
    return fallback;
  }
}
