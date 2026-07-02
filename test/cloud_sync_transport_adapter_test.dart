import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/cloud_sync_service.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/sync_unified/cloud_sync_transport_adapter.dart';
import 'package:ventio/core/sync_unified/sync_device_state.dart';
import 'package:ventio/core/sync_unified/sync_transport_adapter.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';

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
  });
}
