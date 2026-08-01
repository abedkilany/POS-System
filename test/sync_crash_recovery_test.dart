import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/sync_change.dart';
import 'package:ventio/models/sync_queue_item.dart';

const _identity = <String, dynamic>{
  'storeId': 'ST-CRASH-RECOVERY',
  'branchId': 'BR-MAIN',
  'deviceId': 'DV-CLIENT-1',
  'deviceName': 'Recovery Client',
  'platform': 'web',
  'deviceRole': 'client',
  'appRole': 'store',
  'syncMode': 'cloudConnected',
  'hostDeviceId': 'DV-HOST-1',
  'cloudTenantId': '',
  'deviceToken': 'device-token',
  'storeEpoch': 1,
  'recoveryKey': 'RECOVERY-KEY',
  'activeSyncTransport': 'cloud',
};

Future<AppStore> _openStore({
  required SyncQueueItem queueItem,
  required SyncChange change,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  await LocalDatabaseService.resetForTesting();
  LocalDatabaseService.useInMemoryStoreForTesting(<String, String>{
    'app_identity_v1': jsonEncode(_identity),
    'sync_sequence_v1': '0',
  });
  final store = AppStore();
  await store.initialize();
  await store.ensureSyncDataLoaded();
  // Seed the draft through AppStore so the test exercises the same local
  // change persistence path used by the running application. The in-memory
  // test backend has no SQLite sync table for refreshAfterDatabaseChange().
  await store.applyRemoteSyncChanges(<SyncChange>[change]);
  await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
    'sync_queue_v1',
    <Map<String, dynamic>>[queueItem.toJson()],
  );
  await store.refreshAfterDatabaseChange('sync_queue_v1');
  return store;
}

SyncChange _localDraft(DateTime createdAt) => SyncChange(
      id: 'draft-after-crash',
      entityType: 'product',
      entityId: 'product-after-crash',
      operation: 'create',
      deviceId: 'DV-CLIENT-1',
      createdAt: createdAt,
      payload: const <String, dynamic>{
        'id': 'product-after-crash',
        'name': 'Recovered product',
        'code': 'RECOVERED-1',
      },
    );

void main() {
  group('Sync crash and recovery', () {
    tearDown(() async {
      await LocalDatabaseService.flushPendingWrites();
      LocalDatabaseService.clearInMemoryStoreForTesting();
    });

    test('recovers an in-progress push after reopening the app', () async {
      final crashedAt = DateTime.now().subtract(const Duration(minutes: 2));
      final change = _localDraft(crashedAt);
      final storeBeforeCrash = await _openStore(
        change: change,
        queueItem: SyncQueueItem(
          id: 'draft-after-crash-cloud_host',
          changeId: change.id,
          target: 'cloud_host',
          status: 'inProgress',
          attempts: 1,
          createdAt: crashedAt,
          updatedAt: crashedAt,
        ),
      );

      expect(storeBeforeCrash.syncQueue.single.status, 'inProgress');
      expect(storeBeforeCrash.syncChanges.single.isSynced, isFalse);
      storeBeforeCrash.dispose();

      // A new AppStore instance represents the next process after a crash.
      final recovered = await _openStore(
        change: change,
        queueItem: SyncQueueItem(
          id: 'draft-after-crash-cloud_host',
          changeId: change.id,
          target: 'cloud_host',
          status: 'inProgress',
          attempts: 1,
          createdAt: crashedAt,
          updatedAt: crashedAt,
        ),
      );
      await recovered.recoverStaleInProgressSyncQueue(
        target: 'cloud_host',
        staleAfter: const Duration(seconds: 45),
      );

      expect(recovered.syncQueue.single.status, 'pending');
      expect(
          recovered.pendingSyncChangesForTarget('cloud_host', readyOnly: false),
          hasLength(1));
      expect(recovered.syncChanges.single.isSynced, isFalse);
      recovered.dispose();

      final reopened = await _openStore(
        change: change,
        queueItem: recovered.syncQueue.single,
      );
      expect(reopened.syncQueue.single.status, 'pending');
      expect(reopened.syncChanges.single.isSynced, isFalse);
      reopened.dispose();
    });

    test(
        'does not lose a submitted Client draft after a crash before Host confirmation',
        () async {
      final submittedAt = DateTime.now().subtract(const Duration(minutes: 1));
      final change = _localDraft(submittedAt);
      final storeBeforeCrash = await _openStore(
        change: change,
        queueItem: SyncQueueItem(
          id: 'draft-after-crash-cloud_host',
          changeId: change.id,
          target: 'cloud_host',
          status: 'submitted',
          attempts: 1,
          createdAt: submittedAt,
          updatedAt: submittedAt,
        ),
      );
      expect(storeBeforeCrash.syncQueue.single.status, 'submitted');
      storeBeforeCrash.dispose();

      final recovered = await _openStore(
        change: change,
        queueItem: SyncQueueItem(
          id: 'draft-after-crash-cloud_host',
          changeId: change.id,
          target: 'cloud_host',
          status: 'submitted',
          attempts: 1,
          createdAt: submittedAt,
          updatedAt: submittedAt,
        ),
      );
      expect(recovered.syncChanges.single.isSynced, isFalse);

      // Relay receipt is not Host confirmation. After restart, the draft must
      // be retried until the authoritative event is pulled and applied.
      await recovered.recoverSubmittedSyncQueue(target: 'cloud_host');
      expect(recovered.syncQueue.single.status, 'pending');
      expect(
          recovered.pendingSyncChangesForTarget('cloud_host', readyOnly: false),
          hasLength(1));
      expect(recovered.syncChanges.single.isSynced, isFalse);
      recovered.dispose();
    });
  });
}
