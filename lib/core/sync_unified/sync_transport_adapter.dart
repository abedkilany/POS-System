import '../../models/app_identity.dart';
import 'sync_contracts.dart';

/// Transport-independent sync endpoint type.
///
/// Fix 10A intentionally introduces this contract without replacing the
/// existing LAN/Cloud services yet. Later phases can move each service behind
/// this adapter without changing UI flows again.
enum UnifiedSyncTransportKind { lan, cloud }

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

  UnifiedSyncEnvelope<UnifiedSyncBatchContract> toEnvelope({String transport = ''}) =>
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
    this.initialDataReady = true,
    super.data = const <String, dynamic>{},
    super.error = UnifiedSyncError.none,
  });

  final AppIdentity? identity;
  final UnifiedPairingClaimContract? contract;

  /// True only after the Client has downloaded/imported the first Store data.
  /// Pairing-code claim alone is not enough to send the user to Login.
  final bool initialDataReady;
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
  const UnifiedSyncCursor({super.value = '', super.generatedAt, super.source = ''});
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

  Future<UnifiedPairingClaimResult> claimPairingCode(String code);

  Future<UnifiedSyncResult> pushPending(UnifiedSyncPushRequest request);

  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request);

  Future<UnifiedSyncResult> rebuildFromHostSnapshot({
    void Function(double value, String label)? onProgress,
  });

  /// Runs local post-sync maintenance after a successful sync orchestration.
  /// Implementations should keep this best-effort and non-fatal.
  Future<void> compactAfterSuccessfulSync() async {}

  Future<UnifiedSyncResult> syncNow({
    void Function(double value, String label)? onProgress,
  });
}
