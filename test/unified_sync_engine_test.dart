import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/sync_unified/sync_contracts.dart';
import 'package:ventio/core/sync_unified/sync_transport_adapter.dart';
import 'package:ventio/core/sync_unified/unified_sync_engine.dart';

class _FakeTransport implements SyncTransportAdapter {
  _FakeTransport({
    required this.pullResult,
    required this.rebuildResult,
  });

  final UnifiedSyncResult pullResult;
  final UnifiedSyncResult rebuildResult;

  int pushCalls = 0;
  int pullCalls = 0;
  int rebuildCalls = 0;
  int compactCalls = 0;

  final UnifiedCursorEnvelope _pushCursor = UnifiedCursorEnvelope(
    value: 'push-cursor',
    generatedAt: DateTime.utc(2026, 1, 1, 12),
    source: 'device',
  );

  @override
  UnifiedSyncTransportKind get kind => UnifiedSyncTransportKind.cloud;

  @override
  String get label => 'Cloud';

  @override
  String get deviceId => 'DV-TEST';

  @override
  String get deviceToken => 'token';

  @override
  Future<UnifiedSyncResult> testConnection() async =>
      const UnifiedSyncResult(ok: true, message: 'ok');

  @override
  Future<UnifiedHostStatus> getHostStatus() async => const UnifiedHostStatus(
        cloudReachable: false,
        hostReachable: false,
        message: 'ok',
      );

  @override
  Future<UnifiedSyncResult> registerCurrentHost(
          {String transport = ''}) async =>
      const UnifiedSyncResult(ok: true, message: 'ok');

  @override
  Future<UnifiedSyncResult> createInitialHostSnapshot({
    DateTime? minSnapshotUpdatedAt,
    void Function(double value, String label)? onProgress,
  }) async =>
      const UnifiedSyncResult(ok: true, message: 'ok');

  @override
  Future<UnifiedPairingCodeResult> createPairingCode(
          {int ttlMinutes = 5}) async =>
      const UnifiedPairingCodeResult(ok: true, message: 'ok');

  @override
  Future<UnifiedPairingClaimResult> claimPairingCode(String code,
          {void Function(double value, String label)? onProgress}) async =>
      const UnifiedPairingClaimResult(ok: true, message: 'ok');

  @override
  Future<UnifiedSyncResult> pushPending(UnifiedSyncPushRequest request) async {
    pushCalls += 1;
    return UnifiedSyncResult(
      ok: true,
      message: 'push ok',
      pushed: 1,
      cursor: _pushCursor,
    );
  }

  @override
  Future<UnifiedSyncResult> pullChanges(UnifiedSyncPullRequest request) async {
    pullCalls += 1;
    return pullResult;
  }

  @override
  Future<UnifiedSyncResult> rebuildFromHostSnapshot({
    void Function(double value, String label)? onProgress,
  }) async {
    rebuildCalls += 1;
    return rebuildResult;
  }

  @override
  Future<void> compactAfterSuccessfulSync() async {
    compactCalls += 1;
  }

  @override
  Future<UnifiedSyncResult> syncNow({
    void Function(double value, String label)? onProgress,
  }) {
    throw UnimplementedError('Use UnifiedSyncEngine.syncNow in this test.');
  }
}

UnifiedSyncResult _networkFailurePull() => UnifiedSyncResult(
      ok: false,
      message: 'Cloud pull failed: Host Offline. SocketException: offline',
      error: const UnifiedSyncError(
        code: UnifiedSyncErrorCode.networkUnavailable,
        userMessage:
            'Cloud pull failed: Host Offline. SocketException: offline',
        debugMessage:
            'Cloud pull failed: Host Offline. SocketException: offline',
      ),
      cursor: UnifiedCursorEnvelope(
        value: 'pull-cursor',
        generatedAt: DateTime.utc(2026, 1, 1, 12),
        source: 'device',
      ),
    );

UnifiedSyncResult _snapshotFailurePull() => UnifiedSyncResult(
      ok: false,
      message: 'Cloud pull failed: Host snapshot is unavailable.',
      error: const UnifiedSyncError(
        code: UnifiedSyncErrorCode.snapshotUnavailable,
        userMessage: 'Cloud pull failed: Host snapshot is unavailable.',
        debugMessage: 'Cloud pull failed: Host snapshot is unavailable.',
      ),
      cursor: UnifiedCursorEnvelope(
        value: 'pull-cursor',
        generatedAt: DateTime.utc(2026, 1, 1, 12),
        source: 'device',
      ),
    );

void main() {
  group('UnifiedSyncEngine', () {
    test('does not rebuild when pull fails because the Host is offline',
        () async {
      final transport = _FakeTransport(
        pullResult: _networkFailurePull(),
        rebuildResult: const UnifiedSyncResult(
          ok: true,
          message: 'rebuild should not have been called',
        ),
      );

      final engine = UnifiedSyncEngine(transport);
      final result = await engine.syncNow();

      expect(result.ok, isFalse);
      expect(result.message, contains('Host Offline'));
      expect(transport.pushCalls, 1);
      expect(transport.pullCalls, 1);
      expect(transport.rebuildCalls, 0);
      expect(transport.compactCalls, 0);
    });

    test('still rebuilds when the pull reports a missing snapshot', () async {
      final transport = _FakeTransport(
        pullResult: _snapshotFailurePull(),
        rebuildResult: const UnifiedSyncResult(
          ok: true,
          message: 'rebuild ok',
          restoredSnapshot: true,
          pulled: 1,
        ),
      );

      final engine = UnifiedSyncEngine(transport);
      final result = await engine.syncNow();

      expect(result.ok, isTrue);
      expect(result.restoredSnapshot, isTrue);
      expect(transport.pushCalls, 1);
      expect(transport.pullCalls, 1);
      expect(transport.rebuildCalls, 1);
      expect(transport.compactCalls, 1);
    });
  });
}
