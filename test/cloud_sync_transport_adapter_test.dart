import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/cloud_sync_service.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/sync_unified/cloud_sync_transport_adapter.dart';
import 'package:ventio/core/sync_unified/sync_contracts.dart';
import 'package:ventio/core/sync_unified/sync_device_state.dart';
import 'package:ventio/core/sync_unified/sync_transport_adapter.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/sync_change.dart';
import 'package:ventio/models/sync_queue_item.dart';

class _FakeCloudSyncService extends CloudSyncService {
  _FakeCloudSyncService(super.store);

  static final DateTime _appliedAt = DateTime.utc(2026, 1, 1, 12);
  static const int _appliedSequence = 42;
  DateTime? lastPullCursorSeen;

  Future<CloudSyncResult> _writeCloudBaseline(CloudSyncSettings settings,
      {bool restoredSnapshot = false}) async {
    await settings.copyWith(lastPullCursor: _appliedAt).save();
    await SyncDeviceStateStore.recordSyncResult(
      store.appIdentity,
      transport: 'cloud',
      appliedCursor: _appliedAt,
      ackCursor: _appliedAt,
      appliedSequence: _appliedSequence,
      ackSequence: _appliedSequence,
    );
    return CloudSyncResult(
      ok: true,
      message: 'ok',
      pulled: 1,
      restoredSnapshot: restoredSnapshot,
    );
  }

  @override
  Future<CloudSyncResult> pullAuthoritativeChangesForUnifiedEngine(
    CloudSyncSettings settings, {
    DateTime? minSnapshotUpdatedAt,
    CloudSyncProgressCallback? onProgress,
  }) {
    lastPullCursorSeen = settings.lastPullCursor;
    return _writeCloudBaseline(settings);
  }

  @override
  Future<CloudSyncResult> rebuildFromCloudHostSnapshot(
    CloudSyncSettings settings, {
    CloudSyncProgressCallback? onProgress,
    bool requestFreshSnapshot = true,
    String expectedSnapshotGeneration = '',
    String expectedRestoreCommandId = '',
  }) {
    return _writeCloudBaseline(settings, restoredSnapshot: true);
  }

  @override
  Future<CloudSyncResult> pushPendingForUnifiedEngine(
    CloudSyncSettings settings, {
    CloudSyncProgressCallback? onProgress,
  }) async {
    return const CloudSyncResult(ok: true, message: 'ok', pushed: 0);
  }
}

class _SpyCloudSyncService extends CloudSyncService {
  _SpyCloudSyncService(super.store);

  int pushCallCount = 0;
  int pullCallCount = 0;
  int rebuildCallCount = 0;

  @override
  Future<CloudSyncResult> pushPendingForUnifiedEngine(
    CloudSyncSettings settings, {
    CloudSyncProgressCallback? onProgress,
  }) async {
    pushCallCount += 1;
    return const CloudSyncResult(ok: true, message: 'ok', pushed: 1);
  }

  @override
  Future<CloudSyncResult> pullAuthoritativeChangesForUnifiedEngine(
    CloudSyncSettings settings, {
    DateTime? minSnapshotUpdatedAt,
    CloudSyncProgressCallback? onProgress,
  }) async {
    pullCallCount += 1;
    return super.pullAuthoritativeChangesForUnifiedEngine(
      settings,
      minSnapshotUpdatedAt: minSnapshotUpdatedAt,
      onProgress: onProgress,
    );
  }

  @override
  Future<CloudSyncResult> rebuildFromCloudHostSnapshot(
    CloudSyncSettings settings, {
    CloudSyncProgressCallback? onProgress,
    bool requestFreshSnapshot = true,
    String expectedSnapshotGeneration = '',
    String expectedRestoreCommandId = '',
  }) async {
    rebuildCallCount += 1;
    return super.rebuildFromCloudHostSnapshot(
      settings,
      onProgress: onProgress,
      requestFreshSnapshot: requestFreshSnapshot,
      expectedSnapshotGeneration: expectedSnapshotGeneration,
      expectedRestoreCommandId: expectedRestoreCommandId,
    );
  }
}

class _OfflineCloudSyncService extends CloudSyncService {
  _OfflineCloudSyncService(super.store);

  int pushCallCount = 0;
  int pullCallCount = 0;
  int rebuildCallCount = 0;

  @override
  Future<CloudSyncResult> pushPendingForUnifiedEngine(
    CloudSyncSettings settings, {
    CloudSyncProgressCallback? onProgress,
  }) async {
    pushCallCount += 1;
    return const CloudSyncResult(ok: true, message: 'ok', pushed: 1);
  }

  @override
  Future<CloudSyncResult> pullAuthoritativeChangesForUnifiedEngine(
    CloudSyncSettings settings, {
    DateTime? minSnapshotUpdatedAt,
    CloudSyncProgressCallback? onProgress,
  }) async {
    pullCallCount += 1;
    return const CloudSyncResult(
      ok: false,
      message: 'Cloud pull failed: Host Offline. SocketException: offline',
    );
  }

  @override
  Future<CloudSyncResult> rebuildFromCloudHostSnapshot(
    CloudSyncSettings settings, {
    CloudSyncProgressCallback? onProgress,
    bool requestFreshSnapshot = true,
    String expectedSnapshotGeneration = '',
    String expectedRestoreCommandId = '',
  }) async {
    rebuildCallCount += 1;
    return const CloudSyncResult(
      ok: true,
      message: 'rebuild should not have been called',
      restoredSnapshot: true,
    );
  }
}

Future<AppStore> _buildClientStoreWithPendingCloudHostWork() async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final identity = AppIdentity.defaults(
    deviceId: 'DV-TEST',
    platform: AppPlatformType.web,
  ).copyWith(
    deviceRole: DeviceRole.client,
    syncMode: SyncMode.cloudConnected,
    hostDeviceId: 'HOST-TEST',
    activeSyncTransport: 'cloud',
  );
  final now = DateTime.utc(2026, 1, 1, 12);
  final queueItem = SyncQueueItem(
    id: 'cmd-1-cloud_host',
    changeId: 'cmd-1',
    target: 'cloud_host',
    status: 'pending',
    attempts: 0,
    createdAt: now,
    updatedAt: now,
  );
  final change = SyncChange(
    id: 'cmd-1',
    entityType: 'product',
    entityId: 'p1',
    operation: 'create',
    deviceId: identity.deviceId,
    createdAt: now,
    payload: const <String, dynamic>{
      'id': 'p1',
      'code': 'P-1',
    },
  );
  LocalDatabaseService.useInMemoryStoreForTesting(<String, String>{
    'app_identity_v1': jsonEncode(identity.toJson()),
    'sync_changes_v1': jsonEncode(<Map<String, dynamic>>[change.toJson()]),
    'sync_queue_v1': '[]',
    'sync_sequence_v1': '0',
  });

  final store = AppStore();
  await store.initialize();
  await LocalDatabaseService.setString(
    'sync_queue_v1',
    jsonEncode(<Map<String, dynamic>>[queueItem.toJson()]),
  );
  await store.refreshAfterDatabaseChange('sync_queue_v1');
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudSyncTransportAdapter', () {
    late AppStore store;
    late CloudSyncTransportAdapter adapter;

    setUp(() async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final identity = AppIdentity.defaults(
        deviceId: 'DV-TEST',
        platform: AppPlatformType.web,
      );
      LocalDatabaseService.useInMemoryStoreForTesting(<String, String>{
        'app_identity_v1': jsonEncode(identity.toJson()),
        'sync_changes_v1': '[]',
        'sync_queue_v1': '[]',
        'sync_sequence_v1': '0',
      });

      store = AppStore();
      await store.initialize();
      adapter = CloudSyncTransportAdapter(
        service: _FakeCloudSyncService(store),
        settings: const CloudSyncSettings(
          enabled: true,
          apiBaseUrl: 'https://sync.test',
        ),
      );
    });

    tearDown(() {
      LocalDatabaseService.clearInMemoryStoreForTesting();
    });

    test('preserves the cloud sequence after a pull', () async {
      final result = await adapter.pullChanges(
        UnifiedSyncPullRequest(
          deviceId: store.deviceId,
          deviceToken: store.appIdentity.deviceToken,
        ),
      );

      expect(result.ok, isTrue);
      expect(
        SyncDeviceStateStore.lastAppliedSequenceForTransport(
          store.appIdentity,
          'cloud',
        ),
        42,
      );
      expect(
        SyncDeviceStateStore.lastAckSequenceForTransport(
          store.appIdentity,
          'cloud',
        ),
        42,
      );
    });

    test('preserves the cloud sequence after a rebuild', () async {
      final result = await adapter.rebuildFromHostSnapshot();

      expect(result.ok, isTrue);
      expect(
        SyncDeviceStateStore.lastAppliedSequenceForTransport(
          store.appIdentity,
          'cloud',
        ),
        42,
      );
      expect(
        SyncDeviceStateStore.lastAckSequenceForTransport(
          store.appIdentity,
          'cloud',
        ),
        42,
      );
    });

    test('blocks rebuild while the client still has cloud_host work queued',
        () async {
      final pendingStore = await _buildClientStoreWithPendingCloudHostWork();
      final service = CloudSyncService(pendingStore);

      final result = await service.rebuildFromCloudHostSnapshot(
        const CloudSyncSettings(
          enabled: true,
          apiBaseUrl: 'https://sync.test',
        ),
      );

      expect(result.ok, isFalse);
      expect(result.syncDeferred, isTrue);
      expect(result.message, contains('paused'));
      expect(
        pendingStore.hasOutstandingSyncWorkForTarget('cloud_host'),
        isTrue,
      );
      expect(pendingStore.syncQueue.single.status, 'pending');
    });

    test(
        'defers cloud sync before pull or rebuild while the client still has cloud_host work queued',
        () async {
      final pendingStore = await _buildClientStoreWithPendingCloudHostWork();
      final service = _SpyCloudSyncService(pendingStore);
      final pendingAdapter = CloudSyncTransportAdapter(
        service: service,
        settings: const CloudSyncSettings(
          enabled: true,
          apiBaseUrl: 'https://sync.test',
        ),
      );

      final result = await pendingAdapter.syncNow();

      expect(result.ok, isTrue);
      expect(result.data['syncDeferred'], isTrue);
      expect(result.message, contains('paused'));
      expect(service.pushCallCount, 1);
      expect(service.pullCallCount, 1);
      expect(service.rebuildCallCount, 0);
      expect(
          pendingStore.hasOutstandingSyncWorkForTarget('cloud_host'), isTrue);
      expect(pendingStore.syncQueue.single.status, 'pending');
    });

    test('does not rebuild when Cloud Host is offline', () async {
      final offlineService = _OfflineCloudSyncService(store);
      final offlineAdapter = CloudSyncTransportAdapter(
        service: offlineService,
        settings: const CloudSyncSettings(
          enabled: true,
          apiBaseUrl: 'https://sync.test',
        ),
      );

      final result = await offlineAdapter.syncNow();

      expect(result.ok, isFalse);
      expect(result.message, contains('Host Offline'));
      expect(result.error.code, UnifiedSyncErrorCode.networkUnavailable);
      expect(offlineService.pushCallCount, 1);
      expect(offlineService.pullCallCount, 1);
      expect(offlineService.rebuildCallCount, 0);
    });

    test(
        'clears legacy cloud cursor before pulling when the client has no sequence baseline',
        () async {
      final legacyCursor = DateTime.utc(2026, 1, 1, 9);
      final fakeService = _FakeCloudSyncService(store);
      final legacyAdapter = CloudSyncTransportAdapter(
        service: fakeService,
        settings: CloudSyncSettings(
          enabled: true,
          apiBaseUrl: 'https://sync.test',
          lastPullCursor: legacyCursor,
        ),
      );

      final result = await legacyAdapter.pullChanges(
        UnifiedSyncPullRequest(
          deviceId: store.deviceId,
          deviceToken: store.appIdentity.deviceToken,
        ),
      );

      expect(result.ok, isTrue);
      expect(fakeService.lastPullCursorSeen, isNull);
    });

    test(
        'keeps an already-established cloud cursor even when the sequence baseline is still zero',
        () async {
      final baselineCursor = DateTime.utc(2026, 1, 2, 12);
      await SyncDeviceStateStore.recordSyncResult(
        store.appIdentity,
        transport: 'cloud',
        appliedCursor: baselineCursor,
        ackCursor: baselineCursor,
        appliedSequence: 0,
        ackSequence: 0,
      );

      final fakeService = _FakeCloudSyncService(store);
      final result = await CloudSyncTransportAdapter(
        service: fakeService,
        settings: const CloudSyncSettings(
          enabled: true,
          apiBaseUrl: 'https://sync.test',
        ),
      ).pullChanges(
        UnifiedSyncPullRequest(
          deviceId: store.deviceId,
          deviceToken: store.appIdentity.deviceToken,
        ),
      );

      expect(result.ok, isTrue);
      expect(fakeService.lastPullCursorSeen, baselineCursor);
    });
  });
}
