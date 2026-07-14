import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/stock_transaction_service.dart';
import 'package:ventio/core/snapshot/unified_snapshot.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/stock_movement.dart';

Future<AppStore> _readySqliteStore() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final secureStorageChannel =
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStorage = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async {
    switch (call.method) {
      case 'read':
        return secureStorage[call.arguments['key'] as String];
      case 'write':
        secureStorage[call.arguments['key'] as String] =
            call.arguments['value'] as String? ?? '';
        return null;
      case 'delete':
        secureStorage.remove(call.arguments['key'] as String);
        return null;
      case 'containsKey':
        return secureStorage.containsKey(call.arguments['key'] as String);
      case 'readAll':
        return secureStorage;
      case 'deleteAll':
        secureStorage.clear();
        return null;
      default:
        return null;
    }
  });
  LocalDatabaseService.clearInMemoryStoreForTesting();
  await SqliteMigrationManager.initializeFreshSqlite();
  await LocalDatabaseService.initialize();
  final store = AppStore();
  await store.initialize();
  await store.factoryResetLocalDevice(enforcePermission: false);
  await store.recoverOnlineStoreOwnerIdentity(
    storeId: 'ST-SNAP01',
    branchId: 'BR-SNAP01',
    storeName: 'Snapshot Store',
    username: 'admin',
    password: 'AdminPass123',
    deviceRole: DeviceRole.client,
    syncMode: SyncMode.localOnly,
  );
  return store;
}

Future<void> _clearAuthoritativeTables() async {
  final db = SqliteMigrationManager.database;
  expect(db != null, isTrue);
  await db!.transaction(() async {
    await db.customStatement('DELETE FROM warehouse_inventory');
    await db.customStatement('DELETE FROM stock_operations');
    await db.customStatement('DELETE FROM inventory_reconciliations');
    await db.customStatement('DELETE FROM inventory_migration_adjustments');
    await db.customStatement('DELETE FROM stock_movements');
    await db.customStatement('DELETE FROM sync_events');
    await db.customStatement('DELETE FROM pending_sync_changes');
    await db.customStatement('DELETE FROM sync_queue');
    await db.customStatement('DELETE FROM products');
  });
}

void main() {
  group('Phase 2 snapshot behavior', () {
    test(
      'imports authoritative snapshots without double applying inventory',
      () async {
      final store = await _readySqliteStore();
      addTearDown(LocalDatabaseService.clearInMemoryStoreForTesting);
      await _clearAuthoritativeTables();

      await store.addOrUpdateProduct(
        Product(
          id: 'p-snap-1',
          code: 'PSNAP-1',
          name: 'Snapshot Product',
          price: 10,
          cost: 5,
          stock: 10,
          category: 'Test',
        ),
      );

      final db = SqliteMigrationManager.database!;
      final service = StockTransactionService(
        db,
        defaultStoreId: store.appIdentity.storeId,
        defaultBranchId: store.appIdentity.branchId,
        deviceId: store.appIdentity.deviceId,
      );
      await service.recordMovementsAtomically(
        operationType: 'purchase_receive',
        documentType: 'purchase',
        documentId: 'pur-1',
        movementGroupId: 'group-snap-1',
        idempotencyKey: 'op-snap-1',
        movements: <StockMovement>[
          StockMovement(
            id: 'sm-snap-1',
            productId: 'p-snap-1',
            productName: 'Snapshot Product',
            type: 'purchase_receive',
            quantity: 10,
            date: DateTime.utc(2026, 1, 1, 12),
            warehouseId: 'wh-1',
            warehouseName: 'Main Warehouse',
            movementGroupId: 'group-snap-1',
            documentLineId: 'line-1',
            sourceMovementId: '',
            reversalOfMovementId: '',
            idempotencyKey: 'mov-snap-1',
            storeId: store.appIdentity.storeId,
            branchId: store.appIdentity.branchId,
            syncStatus: 'pending',
          ),
        ],
      );

      final sourceChunks = await store.exportUnifiedSnapshotChunks(
        sectionIds: {UnifiedSnapshotCatalog.inventoryMovements.id},
      );
      final sourceJson = jsonEncode(<String, dynamic>{
        'snapshotChunks': sourceChunks,
      });
      final sourceBackup = jsonDecode(await store.exportBackupJson())
          as Map<String, dynamic>;

      expect(sourceBackup['warehouseInventory'], isNotEmpty);
      expect(sourceBackup['stockOperations'], isNotEmpty);
      expect(sourceBackup['stockMovements'], isNotEmpty);
      expect(
        (sourceBackup['stockMovements'] as List<dynamic>).first,
        allOf(
          containsPair('warehouseId', 'wh-1'),
          containsPair('warehouseName', 'Main Warehouse'),
          containsPair('movementGroupId', 'group-snap-1'),
          containsPair('documentLineId', 'line-1'),
          containsPair('idempotencyKey', 'mov-snap-1'),
        ),
      );

      await _clearAuthoritativeTables();
      await store.importSyncSnapshotJson(sourceJson);

      final afterFirstImport =
          jsonDecode(await store.exportBackupJson()) as Map<String, dynamic>;
      expect(afterFirstImport['warehouseInventory'],
          equals(sourceBackup['warehouseInventory']));
      expect(afterFirstImport['stockOperations'],
          equals(sourceBackup['stockOperations']));
      expect(afterFirstImport['stockMovements'],
          equals(sourceBackup['stockMovements']));

      await store.importSyncSnapshotJson(sourceJson);
      final afterSecondImport =
          jsonDecode(await store.exportBackupJson()) as Map<String, dynamic>;
      expect(afterSecondImport['warehouseInventory'],
          equals(afterFirstImport['warehouseInventory']));
      expect(afterSecondImport['stockOperations'],
          equals(afterFirstImport['stockOperations']));
      expect(afterSecondImport['stockMovements'],
          equals(afterFirstImport['stockMovements']));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'legacy snapshots remain compatible without warehouse-aware tables',
      () async {
      final store = await _readySqliteStore();
      addTearDown(LocalDatabaseService.clearInMemoryStoreForTesting);
      await _clearAuthoritativeTables();

      await store.addOrUpdateProduct(
        Product(
          id: 'p-legacy-1',
          code: 'PLEG-1',
          name: 'Legacy Product',
          price: 8,
          cost: 4,
          stock: 6,
          category: 'Test',
        ),
      );

      final db = SqliteMigrationManager.database!;
      await db.transaction(() async {
        await db.customInsert(
          '''
          INSERT INTO stock_movements
            (id, entity_type, created_at, updated_at, deleted_at, device_id,
             sync_status, store_id, branch_id, version, sort_index, product_id,
             product_name, movement_type, quantity, movement_date, reference_id,
             reference_no, reason, adjustment_category, notes, evidence_ref,
             warehouse_id, warehouse_name, movement_group_id, document_line_id,
             source_movement_id, reversal_of_movement_id, idempotency_key, unit_cost,
             last_modified_by_device_id)
          VALUES (?, 'stock_movement', ?, ?, '', '', 'synced', ?, 'main', 1,
                  0, ?, ?, 'sale', -4, ?, '', '', '', '', '', '', 'main',
                  'Main warehouse', '', '', '', '', '', 0, '')
          ''',
          variables: <Variable<Object>>[
            const Variable<String>('legacy-sm-1'),
            const Variable<String>('2026-01-01T10:00:00.000Z'),
            const Variable<String>('2026-01-01T10:00:00.000Z'),
            Variable<String>(store.appIdentity.storeId),
            const Variable<String>('p-legacy-1'),
            const Variable<String>('Legacy Product'),
            const Variable<String>('2026-01-01T10:00:00.000Z'),
          ],
        );
      });

      final sourceChunks = await store.exportUnifiedSnapshotChunks(
        sectionIds: {UnifiedSnapshotCatalog.inventoryMovements.id},
      );
      final legacyPayload = Map<String, dynamic>.from(
        store.unifiedSnapshotPayloadFromChunks(
          sourceChunks
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false),
        ),
      );
      legacyPayload.remove('warehouseInventory');
      legacyPayload.remove('stockOperations');
      legacyPayload.remove('inventoryReconciliations');
      legacyPayload.remove('inventoryMigrationAdjustments');
      legacyPayload.remove('warehouse_inventory');
      legacyPayload.remove('stock_operations');
      legacyPayload.remove('inventory_reconciliations');
      legacyPayload.remove('inventory_migration_adjustments');

      await _clearAuthoritativeTables();
      await store.importSyncSnapshotJson(jsonEncode(legacyPayload));

      final afterLegacyImport =
          jsonDecode(await store.exportBackupJson()) as Map<String, dynamic>;
      expect(afterLegacyImport['warehouseInventory'], isEmpty);
      expect(afterLegacyImport['stockOperations'], isEmpty);
      expect(afterLegacyImport.containsKey('stockMovements'), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
