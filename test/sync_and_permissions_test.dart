import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';

import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/sync_change.dart';
import 'package:ventio/models/sync_queue_item.dart';
import 'package:ventio/models/user_role.dart';

void main() {
  group('AppStore sync queue recovery', () {
    test(
        'recovers submitted cloud_host rows to pending without duplicating work',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final now = DateTime.utc(2026, 1, 1, 12);
      LocalDatabaseService.useInMemoryStoreForTesting(<String, String>{
        'app_identity_v1': jsonEncode(<String, dynamic>{
          'storeId': 'ST-REC',
          'branchId': 'BR-REC',
          'deviceId': 'DV-REC',
          'deviceName': 'Recovery Client',
          'platform': 'web',
          'deviceRole': 'client',
          'appRole': 'store',
          'syncMode': 'cloudConnected',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'hostDeviceId': 'HOST-REC',
          'cloudTenantId': '',
          'deviceToken': 'device_rec',
          'storeEpoch': 1,
          'recoveryKey': 'RK-REC',
          'activeSyncTransport': 'cloud',
        }),
        'sync_changes_v1': jsonEncode(<Map<String, dynamic>>[
          SyncChange(
            id: 'cmd-1',
            entityType: 'product',
            entityId: 'p1',
            operation: 'create',
            deviceId: 'DV-REC',
            createdAt: now,
            payload: const <String, dynamic>{
              'id': 'p1',
              'code': 'REC-1',
            },
          ).toJson(),
        ]),
        'sync_queue_v1': '[]',
        'sync_sequence_v1': '0',
      });

      final store = AppStore();
      await store.initialize();
      await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
        'sync_queue_v1',
        <Map<String, dynamic>>[
          SyncQueueItem(
            id: 'cmd-1-cloud_host',
            changeId: 'cmd-1',
            target: 'cloud_host',
            status: 'submitted',
            attempts: 1,
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        ],
      );
      await store.refreshAfterDatabaseChange('sync_queue_v1');
      expect(store.syncQueue.single.status, 'submitted');
      expect(store.hasOutstandingSyncWorkForTarget('cloud_host'), isTrue);

      await store.recoverSubmittedSyncQueue(target: 'cloud_host');
      expect(store.syncQueue.single.status, 'pending');
      expect(store.hasOutstandingSyncWorkForTarget('cloud_host'), isTrue);
      expect(
          store.pendingSyncQueueForTarget('cloud_host', readyOnly: false),
          hasLength(1));

      await store.recoverSubmittedSyncQueue(target: 'cloud_host');
      expect(store.syncQueue, hasLength(1));
      expect(store.syncQueue.single.status, 'pending');
    });
  });

  group('SyncQueueItem state machine', () {
    test('pending item is ready when no retry date exists', () {
      final item = SyncQueueItem(
          id: 'q1',
          changeId: 'c1',
          target: 'cloud',
          status: 'pending',
          attempts: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());
      expect(item.isPending, isTrue);
      expect(item.isReadyToSend, isTrue);
    });

    test('failed item is pending but waits until retry date', () {
      final item = SyncQueueItem(
          id: 'q1',
          changeId: 'c1',
          target: 'cloud',
          status: 'failed',
          attempts: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          nextRetryAt: DateTime.now().add(const Duration(minutes: 5)));
      expect(item.isFailed, isTrue);
      expect(item.isPending, isTrue);
      expect(item.isReadyToSend, isFalse);
    });

    test('failed item becomes ready after retry date', () {
      final item = SyncQueueItem(
          id: 'q1',
          changeId: 'c1',
          target: 'cloud',
          status: 'failed',
          attempts: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          nextRetryAt: DateTime.now().subtract(const Duration(seconds: 1)));
      expect(item.isReadyToSend, isTrue);
    });

    test('fresh inProgress item is not pending', () {
      final item = SyncQueueItem(
          id: 'q1',
          changeId: 'c1',
          target: 'cloud',
          status: 'inProgress',
          attempts: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());
      expect(item.isInProgress, isTrue);
      expect(item.isPending, isFalse);
    });

    test('stale inProgress item is recoverable as pending', () {
      final item = SyncQueueItem(
          id: 'q1',
          changeId: 'c1',
          target: 'cloud',
          status: 'inProgress',
          attempts: 1,
          createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 2)));
      expect(item.isPending, isTrue);
      expect(item.isReadyToSend, isTrue);
    });

    test('synced item is not pending or ready', () {
      final item = SyncQueueItem(
          id: 'q1',
          changeId: 'c1',
          target: 'cloud',
          status: 'synced',
          attempts: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());
      expect(item.isSynced, isTrue);
      expect(item.isPending, isFalse);
      expect(item.isReadyToSend, isFalse);
    });

    test('copyWith clears retry date when requested', () {
      final original = SyncQueueItem(
          id: 'q1',
          changeId: 'c1',
          target: 'cloud',
          status: 'failed',
          attempts: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          nextRetryAt: DateTime.now().add(const Duration(minutes: 1)));
      final copied =
          original.copyWith(status: 'pending', clearNextRetryAt: true);
      expect(copied.nextRetryAt, isNull);
      expect(copied.status, 'pending');
    });
  });

  group('SyncChange metadata', () {
    test('copyWith can mark a change as synced', () {
      final syncedAt = DateTime.utc(2026, 1, 1);
      final change = SyncChange(
          id: 'c1',
          entityType: 'sale',
          entityId: 's1',
          operation: 'create',
          deviceId: 'd1',
          createdAt: syncedAt,
          payload: {'id': 's1'});
      final synced =
          change.copyWith(isSynced: true, syncedAt: syncedAt, sequence: 9);

      expect(synced.isSynced, isTrue);
      expect(synced.syncedAt, syncedAt);
      expect(synced.sequence, 9);
    });

    test('fromJson tolerates missing payload', () {
      final change = SyncChange.fromJson({
        'id': 'c1',
        'entityType': 'product',
        'entityId': 'p1',
        'operation': 'update'
      });
      expect(change.payload, isEmpty);
      expect(change.storeEpoch, 1);
      expect(change.sequence, 0);
    });
  });

  group('Roles and users', () {
    test('permission registry has labels for every permission', () {
      for (final permission in AppPermission.all) {
        expect(AppPermission.labels, contains(permission));
        expect(AppPermission.labels[permission], isNotEmpty);
      }
    });

    test('permission catalog maps every permission to a page', () {
      for (final permission in AppPermission.all) {
        expect(AppPermission.pageForPermission(permission), isNotNull);
      }
    });

    test('page catalog covers all permissions exactly once', () {
      final catalogPermissions =
          AppPermission.pages.expand((page) => page.permissions).toList();

      expect(catalogPermissions.toSet(), equals(AppPermission.all.toSet()));
      expect(catalogPermissions.length, AppPermission.all.length);
    });

    test('page catalog exposes explicit page ids and titles', () {
      for (final page in AppPermission.pages) {
        expect(page.id, isNotEmpty);
        expect(page.title, isNotEmpty);
        expect(page.accessPermission, isNotEmpty);
        expect(page.permissions, contains(page.accessPermission));
        if (page.navigationPermissions.isNotEmpty) {
          for (final permission in page.navigationPermissions) {
            expect(AppPermission.all, contains(permission));
          }
        }
        expect(page.permissions, isNotEmpty);
        expect(AppPermission.pageById(page.id), same(page));
      }
    });

    test('page catalog ids and titles are unique', () {
      final ids = AppPermission.pages.map((page) => page.id).toList();
      final titles = AppPermission.pages.map((page) => page.title).toList();
      final accessPermissions =
          AppPermission.pages.map((page) => page.accessPermission).toList();
      final navigationPermissions = AppPermission.pages
          .expand((page) => page.navigationPermissions)
          .toList();

      expect(ids.toSet().length, ids.length);
      expect(titles.toSet().length, titles.length);
      expect(accessPermissions.toSet().length, accessPermissions.length);
      expect(
          navigationPermissions.toSet().length, navigationPermissions.length);
    });

    test('admin role is identified by id', () {
      final role = UserRole(
          id: 'admin',
          name: 'Administrator',
          permissions: AppPermission.all.toSet());
      expect(role.isAdmin, isTrue);
      expect(role.copyWith(name: 'Owner').isAdmin, isTrue);
    });

    test('copyWith keeps user id stable while changing role and permissions',
        () {
      const user = AppUser(
          id: 'u1',
          fullName: 'Cashier',
          username: 'cashier',
          passwordHash: 'h',
          roleId: 'cashier');
      final updated = user.copyWith(
          roleId: 'manager',
          extraPermissions: {AppPermission.reportsView},
          deniedPermissions: {AppPermission.productsDelete});

      expect(updated.id, 'u1');
      expect(updated.roleId, 'manager');
      expect(updated.extraPermissions, contains(AppPermission.reportsView));
      expect(updated.deniedPermissions, contains(AppPermission.productsDelete));
    });
  });

  group('AppIdentity defaults', () {
    test('windows default is standalone and local-only before setup', () {
      final identity = AppIdentity.defaults(
        deviceId: 'win-1',
        platform: AppPlatformType.windows,
      );

      expect(identity.deviceRole, DeviceRole.standalone);
      expect(identity.isHost, isFalse);
      expect(identity.isClient, isFalse);
      expect(identity.syncMode, SyncMode.localOnly);
      expect(identity.isCloudEnabled, isFalse);
      expect(identity.storeId, startsWith('ST-'));
      expect(identity.storeId.length, greaterThan('ST-'.length));
    });

    test('android default is standalone and local-only before setup', () {
      final identity = AppIdentity.defaults(
        deviceId: 'android-1',
        platform: AppPlatformType.android,
      );

      expect(identity.deviceRole, DeviceRole.standalone);
      expect(identity.isHost, isFalse);
      expect(identity.isClient, isFalse);
      expect(identity.syncMode, SyncMode.localOnly);
      expect(identity.isCloudEnabled, isFalse);
      expect(identity.storeId, startsWith('ST-'));
      expect(identity.storeId.length, greaterThan('ST-'.length));
    });

    test('web default is cloud-connected client', () {
      final identity = AppIdentity.defaults(
        deviceId: 'web-1',
        platform: AppPlatformType.web,
      );

      expect(identity.deviceRole, DeviceRole.client);
      expect(identity.isClient, isTrue);
      expect(identity.isHost, isFalse);
      expect(identity.syncMode, SyncMode.cloudConnected);
      expect(identity.isCloudEnabled, isTrue);
    });

    test('register setup can turn a native standalone device into a host', () {
      final identity = AppIdentity.defaults(
        deviceId: 'win-1',
        platform: AppPlatformType.windows,
      ).copyWith(
        deviceRole: DeviceRole.host,
        syncMode: SyncMode.lanOnly,
      );

      expect(identity.deviceRole, DeviceRole.host);
      expect(identity.isHost, isTrue);
      expect(identity.isClient, isFalse);
      expect(identity.syncMode, SyncMode.lanOnly);
    });

    test('connect to store can turn a native standalone device into a client',
        () {
      final identity = AppIdentity.defaults(
        deviceId: 'win-1',
        platform: AppPlatformType.windows,
      ).copyWith(
        deviceRole: DeviceRole.client,
        syncMode: SyncMode.lanOnly,
        hostDeviceId: 'host-1',
      );

      expect(identity.deviceRole, DeviceRole.client);
      expect(identity.isClient, isTrue);
      expect(identity.isHost, isFalse);
      expect(identity.syncMode, SyncMode.lanOnly);
      expect(identity.hostDeviceId, 'host-1');
    });

    test('marketplace mode is both cloud enabled and marketplace enabled', () {
      final identity = AppIdentity.defaults(
        deviceId: 'web-1',
        platform: AppPlatformType.web,
      ).copyWith(syncMode: SyncMode.marketplaceEnabled);

      expect(identity.isCloudEnabled, isTrue);
      expect(identity.isMarketplaceEnabled, isTrue);
    });
  });
}
