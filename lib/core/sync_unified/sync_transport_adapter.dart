import '../../models/app_identity.dart';
import 'sync_contracts.dart';

/// Transport-independent sync endpoint type.
///
/// Fix 10A intentionally introduces this contract without replacing the
/// existing LAN/Cloud services yet. Later phases can move each service behind
/// this adapter without changing UI flows again.
enum UnifiedSyncTransportKind { lan, cloud, direct }

/// Normalized result envelope used by the unified sync layer.
class UnifiedSyncResult {
  const UnifiedSyncResult({
    required this.ok,
    required this.message,
    this.pushed = 0,
    this.pulled = 0,
    this.restoredSnapshot = false,
    this.data = const <String, dynamic>{},
    this.error = UnifiedSyncError.none,
    this.cursor = const UnifiedCursorEnvelope(),
  });

  final bool ok;
  final String message;
  final int pushed;
  final int pulled;
  final bool restoredSnapshot;
  final Map<String, dynamic> data;
  final UnifiedSyncError error;
  final UnifiedCursorEnvelope cursor;

  UnifiedSyncEnvelope<UnifiedSyncBatchContract> toEnvelope(
          {String transport = ''}) =>
      UnifiedSyncEnvelope<UnifiedSyncBatchContract>(
        ok: ok,
        message: message,
        transport: transport,
        error: error,
        payload: UnifiedSyncBatchContract(
          cursor: cursor,
          pushed: pushed,
          pulled: pulled,
          restoredSnapshot: restoredSnapshot,
        ),
      );

  static const notImplemented = UnifiedSyncResult(
    ok: false,
    message: 'This unified sync operation is not connected to a transport yet.',
  );
}

extension UnifiedSyncResultSemantics on UnifiedSyncResult {
  bool get isDeferred => data['syncDeferred'] == true;
  String get deferredReason => data['deferredReason']?.toString() ?? '';
}

extension UnifiedSyncResultRepairDecision on UnifiedSyncResult {
  bool shouldRepairAfterPullFailure() {
    return error.code == UnifiedSyncErrorCode.snapshotUnavailable;
  }
}

class UnifiedSyncResultFactory {
  const UnifiedSyncResultFactory._();

  static UnifiedSyncResult success({
    required String label,
    required int pushed,
    required int pulled,
    required UnifiedCursorEnvelope cursor,
    bool restoredSnapshot = false,
    Map<String, dynamic> data = const <String, dynamic>{},
    String? message,
  }) {
    final deferred = data['syncDeferred'] == true;
    return UnifiedSyncResult(
      ok: true,
      message: message ??
          (deferred
              ? '$label sync deferred.'
              : '$label sync completed. Pushed $pushed change(s), pulled $pulled change(s).'),
      pushed: pushed,
      pulled: deferred ? 0 : pulled,
      restoredSnapshot: restoredSnapshot,
      data: data,
      cursor: cursor,
    );
  }

  static UnifiedSyncResult deferred({
    required String label,
    required int pushed,
    required int pulled,
    required UnifiedCursorEnvelope cursor,
    String reason = '',
  }) {
    return UnifiedSyncResult(
      ok: true,
      message: '$label sync deferred.',
      pushed: pushed,
      pulled: 0,
      data: <String, dynamic>{
        'syncDeferred': true,
        if (reason.trim().isNotEmpty) 'deferredReason': reason,
      },
      cursor: cursor,
    );
  }

  static UnifiedSyncResult failure({
    required String message,
    required int pushed,
    required int pulled,
    required UnifiedCursorEnvelope cursor,
    required UnifiedSyncError error,
  }) {
    return UnifiedSyncResult(
      ok: false,
      message: message,
      pushed: pushed,
      pulled: pulled,
      error: error,
      cursor: cursor,
    );
  }
}

class UnifiedPairingCodeResult extends UnifiedSyncResult {
  const UnifiedPairingCodeResult({
    required super.ok,
    required super.message,
    this.code = '',
    this.expiresAt,
    this.contract,
    super.data = const <String, dynamic>{},
    super.error = UnifiedSyncError.none,
  });

  final String code;
  final DateTime? expiresAt;
  final UnifiedPairingContract? contract;
}

class UnifiedPairingClaimResult extends UnifiedSyncResult {
  const UnifiedPairingClaimResult({
    required super.ok,
    required super.message,
    this.identity,
    this.contract,
    super.data = const <String, dynamic>{},
    super.error = UnifiedSyncError.none,
  });

  final AppIdentity? identity;
  final UnifiedPairingClaimContract? contract;
}

class UnifiedHostStatus {
  const UnifiedHostStatus({
    required this.cloudReachable,
    required this.hostReachable,
    required this.message,
    this.lastSeenAt,
  });

  final bool cloudReachable;
  final bool hostReachable;
  final String message;
  final DateTime? lastSeenAt;
}

class UnifiedSyncCursor extends UnifiedCursorEnvelope {
  const UnifiedSyncCursor(
      {super.value = '', super.generatedAt, super.source = ''});
}

class UnifiedSyncPushRequest {
  const UnifiedSyncPushRequest({
    required this.deviceId,
    required this.deviceToken,
    this.cursor = const UnifiedSyncCursor(),
  });

  final String deviceId;
  final String deviceToken;
  final UnifiedSyncCursor cursor;
}

class UnifiedSyncPullRequest {
  const UnifiedSyncPullRequest({
    required this.deviceId,
    required this.deviceToken,
    this.cursor = const UnifiedSyncCursor(),
  });

  final String deviceId;
  final String deviceToken;
  final UnifiedSyncCursor cursor;
}

/// Common transport adapter contract for LAN and Cloud.
///
/// Phase 10A does not force the app to use this adapter yet. It provides the
/// shared surface that 10B/10C will use to normalize pairing, push, pull,
/// snapshot and repair behavior.
abstract class SyncTransportAdapter {
  UnifiedSyncTransportKind get kind;
  String get label;
  String get deviceId;
  String get deviceToken;

  Future<UnifiedSyncResult> testConnection();

  Future<UnifiedHostStatus> getHostStatus();

  /// Registers/prepares the current device as Host for this transport.
  Future<UnifiedSyncResult> registerCurrentHost({String transport = ''});

  /// Creates, uploads, and verifies the first Host snapshot through this transport.
  Future<UnifiedSyncResult> createInitialHostSnapshot({
    DateTime? minSnapshotUpdatedAt,
    void Function(double value, String label)? onProgress,
  });

  Future<UnifiedPairingCodeResult> createPairingCode({int ttlMinutes = 5});

  Future<UnifiedPairingClaimResult> claimPairingCode(String code,
      {void Function(double value, String label)? onProgress});

  Future<UnifiedSyncResult> pushPending(UnifiedSyncPushRequest request);

  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request);

  Future<UnifiedSyncResult> rebuildFromHostSnapshot({
    void Function(double value, String label)? onProgress,
  });

  /// Runs local post-sync maintenance after a successful sync orchestration.
  /// Implementations should keep this best-effort and non-fatal.
  Future<void> compactAfterSuccessfulSync() async {}

  /// Waits for a transport-specific realtime wakeup signal.
  ///
  /// Returns `true` when new remote activity should trigger a sync tick.
  Future<bool> waitForRealtimeSignal() async => false;

  /// Best-effort host shutdown for transports that expose a local Host server.
  Future<void> stopHostIfSupported() async {}

  /// Requests a fresh Host snapshot when the transport supports explicit
  /// provisioning/bootstrap refresh.
  Future<void> requestFreshHostSnapshotIfSupported({
    DateTime? requestedAt,
  }) async {}

  Future<UnifiedSyncResult> syncNow({
    void Function(double value, String label)? onProgress,
  });
}
