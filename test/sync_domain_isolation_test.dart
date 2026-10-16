import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/contracts/sync_domain_port.dart';
import 'package:ventio/core/contracts/sync_history_policy.dart';
import 'package:ventio/core/services/unified_sync_core_service.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/sync_change.dart';

// An intentionally small fake: accessing any undeclared capability fails.
// These tests never construct AppStore, open SQLite, or initialize Flutter UI.
class _SyncPort implements SyncDomainPort {
  @override
  final String deviceId = 'host';
  @override
  DateTime? latestResetAt;
  final List<String> applied = [];
  final List<String> verified = [];
  final List<String> acknowledged = [];
  bool failApply = false;
  int hostCompactions = 0;
  int clientCompactions = 0;
  @override
  Future<Map<String, int>> compactSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = SyncHistoryPolicy.keepRecentChanges,
    int minChangesBeforeCompact = SyncHistoryPolicy.minChangesBeforeCompact,
  }) async {
    hostCompactions++;
    return {};
  }

  @override
  Future<Map<String, int>> compactClientSyncedHistoryForMaintenance({
    int keepRecentSyncedChanges = SyncHistoryPolicy.keepRecentChanges,
  }) async {
    clientCompactions++;
    return {};
  }

  @override
  String? validateClientDraftForHostAcceptance(SyncChange change) =>
      change.id == 'invalid' ? 'Invalid draft' : null;
  @override
  Future<void> applyRemoteChanges(Iterable<SyncChange> changes,
      {bool markAppliedAsSynced = false, bool mirrorToDirect = false}) async {
    if (failApply) throw StateError('Persistence failed');
    expect(markAppliedAsSynced, isTrue);
    applied.addAll(changes.map((change) => change.id));
  }

  @override
  Future<void> assertRemoteChangesApplied(List<SyncChange> changes) async =>
      verified.addAll(changes.map((change) => change.id));
  @override
  Future<void> markAcknowledged(Iterable<String> ids) async =>
      acknowledged.addAll(ids);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

SyncChange _change(String id, {String device = 'client', DateTime? at}) =>
    SyncChange(
      id: id,
      entityId: id,
      entityType: 'sale',
      operation: 'create',
      deviceId: device,
      createdAt: at ?? DateTime.utc(2026, 1, 2),
      payload: const {},
    );

void main() {
  test('selects maintenance using the current device role', () async {
    final port = _SyncPort();
    final service = UnifiedSyncCoreService(port);
    await service.compactAfterSuccessfulSync(DeviceRole.standalone);
    expect(port.hostCompactions + port.clientCompactions, 0);
    await service.compactAfterSuccessfulSync(DeviceRole.host);
    expect(port.hostCompactions, 1);
    expect(port.clientCompactions, 0);
    await service.compactAfterSuccessfulSync(DeviceRole.client);
    expect(port.clientCompactions, 1);
  });

  test(
      'filters echoes and rejects stale or invalid drafts through a domain port',
      () async {
    final port = _SyncPort()..latestResetAt = DateTime.utc(2026, 1, 1);
    final service = UnifiedSyncCoreService(port);
    final result = await service.acceptClientChangesOnHost([
      _change('echo', device: 'host'),
      _change('old', at: DateTime.utc(2025, 12, 31)),
      _change('invalid'),
      _change('accepted'),
    ], mirrorToDirect: false, verifyApplied: true);
    expect(result.ackIds, ['accepted']);
    expect(result.rejected.keys, containsAll(['old', 'invalid']));
    expect(port.applied, ['accepted']);
    expect(port.verified, ['accepted']);
  });

  test('propagates persistence failure without reporting success', () async {
    final port = _SyncPort()..failApply = true;
    await expectLater(
        UnifiedSyncCoreService(port).acceptClientChangesOnHost(
            [_change('draft')],
            mirrorToDirect: false, verifyApplied: true),
        throwsStateError);
    expect(port.verified, isEmpty);
    expect(port.acknowledged, isEmpty);
  });

  test('acknowledges explicit server IDs or falls back to submitted IDs',
      () async {
    final port = _SyncPort();
    final service = UnifiedSyncCoreService(port);
    await service.markPushAcknowledged(['server'], fallbackIds: ['ignored']);
    await service.markPushAcknowledged([], fallbackIds: ['submitted']);
    expect(port.acknowledged, ['server', 'submitted']);
  });
}
