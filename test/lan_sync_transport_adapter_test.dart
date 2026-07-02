import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/lan_sync_service.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/sync_unified/lan_sync_transport_adapter.dart';
import 'package:ventio/core/sync_unified/sync_contracts.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';

class _FakeLanSyncService extends LanSyncService {
  _FakeLanSyncService(super.store);

  int pushCalls = 0;
  int pullCalls = 0;
  int repairCalls = 0;

  @override
  Future<LanSyncResult> pushPendingOnly(
    String host, {
    int port = 8787,
    String token = '',
    LanSyncProgressCallback? onProgress,
  }) async {
    pushCalls += 1;
    return const LanSyncResult(ok: true, message: 'LAN push completed.');
  }

  @override
  Future<LanSyncResult> pullChangesOnly(
    String host, {
    int port = 8787,
    String token = '',
    LanSyncProgressCallback? onProgress,
  }) async {
    pullCalls += 1;
    return const LanSyncResult(
      ok: false,
      message: 'LAN pull failed: Host Offline. SocketException: offline',
    );
  }

  @override
  Future<LanSyncResult> repairFromHostSnapshot(
    String host, {
    int port = 8787,
    String token = '',
    LanSyncProgressCallback? onProgress,
  }) async {
    repairCalls += 1;
    return const LanSyncResult(
      ok: true,
      message: 'repair should not have been called',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanSyncTransportAdapter', () {
    late AppStore store;
    late _FakeLanSyncService service;
    late LanSyncTransportAdapter adapter;

    setUp(() async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final identity = AppIdentity.defaults(
        deviceId: 'DV-TEST',
        platform: AppPlatformType.web,
      ).copyWith(
        storeId: 'ST-TEST',
        branchId: 'BR-TEST',
        deviceId: 'DV-CLIENT',
        deviceName: 'Client',
        deviceRole: DeviceRole.client,
        syncMode: SyncMode.lanOnly,
        activeSyncTransport: 'lan',
        deviceToken: 'device-token',
      );

      LocalDatabaseService.useInMemoryStoreForTesting(<String, String>{
        'app_identity_v1': jsonEncode(identity.toJson()),
        'sync_changes_v1': '[]',
        'sync_queue_v1': '[]',
        'sync_sequence_v1': '0',
      });

      store = AppStore();
      await store.initialize();
      service = _FakeLanSyncService(store);
      adapter = LanSyncTransportAdapter(
        service: service,
        settings: const LanSyncSettings(
          host: '127.0.0.1',
          port: 8787,
          autoSyncEnabled: true,
          hostModeEnabled: false,
          setupComplete: true,
          mode: LanSyncDeviceMode.client,
          secret: 'token',
        ),
      );
    });

    tearDown(LocalDatabaseService.clearInMemoryStoreForTesting);

    test('does not rebuild when the Host is offline', () async {
      final result = await adapter.syncNow();

      expect(result.ok, isFalse);
      expect(result.message, contains('Host Offline'));
      expect(result.error.code, UnifiedSyncErrorCode.networkUnavailable);
      expect(service.pushCalls, 1);
      expect(service.pullCalls, 1);
      expect(service.repairCalls, 0);
    });
  });
}
