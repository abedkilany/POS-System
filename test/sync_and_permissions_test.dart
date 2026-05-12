import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/sync_change.dart';
import 'package:ventio/models/sync_queue_item.dart';
import 'package:ventio/models/user_role.dart';

void main() {
  group('SyncQueueItem state machine', () {
    test('pending item is ready when no retry date exists', () {
      final item = SyncQueueItem(id: 'q1', changeId: 'c1', target: 'cloud', status: 'pending', attempts: 0, createdAt: DateTime.now(), updatedAt: DateTime.now());
      expect(item.isPending, isTrue);
      expect(item.isReadyToSend, isTrue);
    });

    test('failed item is pending but waits until retry date', () {
      final item = SyncQueueItem(id: 'q1', changeId: 'c1', target: 'cloud', status: 'failed', attempts: 1, createdAt: DateTime.now(), updatedAt: DateTime.now(), nextRetryAt: DateTime.now().add(const Duration(minutes: 5)));
      expect(item.isFailed, isTrue);
      expect(item.isPending, isTrue);
      expect(item.isReadyToSend, isFalse);
    });

    test('failed item becomes ready after retry date', () {
      final item = SyncQueueItem(id: 'q1', changeId: 'c1', target: 'cloud', status: 'failed', attempts: 1, createdAt: DateTime.now(), updatedAt: DateTime.now(), nextRetryAt: DateTime.now().subtract(const Duration(seconds: 1)));
      expect(item.isReadyToSend, isTrue);
    });

    test('fresh inProgress item is not pending', () {
      final item = SyncQueueItem(id: 'q1', changeId: 'c1', target: 'cloud', status: 'inProgress', attempts: 1, createdAt: DateTime.now(), updatedAt: DateTime.now());
      expect(item.isInProgress, isTrue);
      expect(item.isPending, isFalse);
    });

    test('stale inProgress item is recoverable as pending', () {
      final item = SyncQueueItem(id: 'q1', changeId: 'c1', target: 'cloud', status: 'inProgress', attempts: 1, createdAt: DateTime.now().subtract(const Duration(minutes: 2)), updatedAt: DateTime.now().subtract(const Duration(minutes: 2)));
      expect(item.isPending, isTrue);
      expect(item.isReadyToSend, isTrue);
    });

    test('synced item is not pending or ready', () {
      final item = SyncQueueItem(id: 'q1', changeId: 'c1', target: 'cloud', status: 'synced', attempts: 1, createdAt: DateTime.now(), updatedAt: DateTime.now());
      expect(item.isSynced, isTrue);
      expect(item.isPending, isFalse);
      expect(item.isReadyToSend, isFalse);
    });

    test('copyWith clears retry date when requested', () {
      final original = SyncQueueItem(id: 'q1', changeId: 'c1', target: 'cloud', status: 'failed', attempts: 1, createdAt: DateTime.now(), updatedAt: DateTime.now(), nextRetryAt: DateTime.now().add(const Duration(minutes: 1)));
      final copied = original.copyWith(status: 'pending', clearNextRetryAt: true);
      expect(copied.nextRetryAt, isNull);
      expect(copied.status, 'pending');
    });
  });

  group('SyncChange metadata', () {
    test('copyWith can mark a change as synced', () {
      final syncedAt = DateTime.utc(2026, 1, 1);
      final change = SyncChange(id: 'c1', entityType: 'sale', entityId: 's1', operation: 'create', deviceId: 'd1', createdAt: syncedAt, payload: {'id': 's1'});
      final synced = change.copyWith(isSynced: true, syncedAt: syncedAt, sequence: 9);

      expect(synced.isSynced, isTrue);
      expect(synced.syncedAt, syncedAt);
      expect(synced.sequence, 9);
    });

    test('fromJson tolerates missing payload', () {
      final change = SyncChange.fromJson({'id': 'c1', 'entityType': 'product', 'entityId': 'p1', 'operation': 'update'});
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

    test('admin role is identified by id', () {
      final role = UserRole(id: 'admin', name: 'Administrator', permissions: AppPermission.all.toSet());
      expect(role.isAdmin, isTrue);
      expect(role.copyWith(name: 'Owner').isAdmin, isTrue);
    });

    test('copyWith keeps user id stable while changing role and permissions', () {
      const user = AppUser(id: 'u1', fullName: 'Cashier', username: 'cashier', passwordHash: 'h', roleId: 'cashier');
      final updated = user.copyWith(roleId: 'manager', extraPermissions: {AppPermission.reportsView}, deniedPermissions: {AppPermission.productsDelete});

      expect(updated.id, 'u1');
      expect(updated.roleId, 'manager');
      expect(updated.extraPermissions, contains(AppPermission.reportsView));
      expect(updated.deniedPermissions, contains(AppPermission.productsDelete));
    });
  });

  group('AppIdentity defaults', () {
    test('windows default is host on LAN', () {
      final identity = AppIdentity.defaults(deviceId: 'win-1', platform: AppPlatformType.windows);
      expect(identity.isHost, isTrue);
      expect(identity.syncMode, SyncMode.lanOnly);
      expect(identity.storeId, 'store_win-1');
    });

    test('web default is cloud-connected client', () {
      final identity = AppIdentity.defaults(deviceId: 'web-1', platform: AppPlatformType.web);
      expect(identity.isClient, isTrue);
      expect(identity.isCloudEnabled, isTrue);
    });

    test('marketplace mode is both cloud enabled and marketplace enabled', () {
      final identity = AppIdentity.defaults(deviceId: 'web-1', platform: AppPlatformType.web).copyWith(syncMode: SyncMode.marketplaceEnabled);
      expect(identity.isCloudEnabled, isTrue);
      expect(identity.isMarketplaceEnabled, isTrue);
    });
  });
}
