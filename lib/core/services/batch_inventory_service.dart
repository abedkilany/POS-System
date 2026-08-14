import 'package:drift/drift.dart';

import '../../models/inventory_batch.dart';
import '../../models/product.dart';
import '../localization/localized_domain_exception.dart';
import '../storage/sqlite/ventio_drift_database.dart';

/// Transactional batch/expiry inventory operations.
///
/// Callers must execute these methods inside the same SQLite transaction used
/// for the corresponding stock movements so aggregate and batch balances can
/// never diverge.
class BatchInventoryService {
  const BatchInventoryService(this.db);

  final VentioDriftDatabase db;

  Future<List<BatchAllocation>> addStockInTransaction({
    required Product product,
    required String warehouseId,
    required String sourceType,
    required String sourceId,
    required double expectedQuantity,
    required List<BatchAllocation> allocations,
    required DateTime receivedAt,
    required String storeId,
    required String branchId,
    required String deviceId,
  }) async {
    if (!product.expiryTrackingEnabled) return const <BatchAllocation>[];
    if (allocations.isEmpty) {
      throw LocalizedDomainException('error_expiry_batches_required',
          values: {'product': product.name},
          fallback: 'Expiry batches are required for ${product.name}.');
    }
    final total = allocations.fold<double>(
      0,
      (sum, allocation) => sum + allocation.quantity,
    );
    if ((total - expectedQuantity).abs() > 0.000001) {
      throw LocalizedDomainException('error_batch_quantity_total',
          values: {'product': product.name, 'quantity': expectedQuantity},
          fallback:
              'Batch quantities for ${product.name} must equal $expectedQuantity.');
    }
    final minimumExpiry = DateTime.utc(
      receivedAt.year,
      receivedAt.month,
      receivedAt.day,
    ).add(Duration(days: product.minimumReceiptShelfLifeDays));
    final nowText = receivedAt.toUtc().toIso8601String();
    final resolved = <BatchAllocation>[];
    for (var index = 0; index < allocations.length; index += 1) {
      final allocation = allocations[index];
      if (allocation.quantity <= 0) {
        throw const LocalizedDomainException('error_batch_quantity_positive',
            fallback: 'Batch quantity must be greater than zero.');
      }
      final expiry = allocation.expirationDate;
      if (product.expiryEntryRequired && expiry == null) {
        throw LocalizedDomainException('error_expiration_date_required',
            values: {'product': product.name},
            fallback: 'Expiration date is required for ${product.name}.');
      }
      if (expiry != null && expiry.isBefore(minimumExpiry)) {
        throw LocalizedDomainException('error_minimum_shelf_life',
            values: {'product': product.name},
            fallback:
                'The remaining shelf life for ${product.name} is below the allowed minimum.');
      }
      final batchId = allocation.batchId.trim().isEmpty
          ? '$sourceId-batch-$index'
          : allocation.batchId.trim();
      final normalized = BatchAllocation(
        batchId: batchId,
        quantity: allocation.quantity,
        supplierBatchNumber: allocation.supplierBatchNumber.trim(),
        manufacturingDate: allocation.manufacturingDate,
        expirationDate: expiry,
      );
      await db.customStatement('''
        INSERT INTO inventory_batches
          (id, product_id, product_name, supplier_batch_number,
           manufacturing_date, expiration_date, status, source_type,
           source_id, store_id, branch_id, created_at, updated_at, device_id,
           last_modified_by_device_id, sync_status, version)
        VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 1)
        ON CONFLICT(id) DO UPDATE SET
          product_name = excluded.product_name,
          supplier_batch_number = excluded.supplier_batch_number,
          manufacturing_date = excluded.manufacturing_date,
          expiration_date = excluded.expiration_date,
          updated_at = excluded.updated_at,
          sync_status = 'pending'
      ''', <Object?>[
        batchId,
        product.id,
        product.name,
        normalized.supplierBatchNumber,
        normalized.manufacturingDate?.toUtc().toIso8601String() ?? '',
        expiry?.toUtc().toIso8601String() ?? '',
        sourceType,
        sourceId,
        storeId,
        branchId,
        nowText,
        nowText,
        deviceId,
        deviceId,
      ]);
      final balanceId = '$storeId::$warehouseId::${product.id}::$batchId';
      await db.customStatement('''
        INSERT INTO inventory_batch_balances
          (id, batch_id, product_id, warehouse_id, store_id, branch_id,
           quantity, reserved_quantity, version, created_at, updated_at,
           device_id, last_modified_by_device_id, sync_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, ?, 'pending')
        ON CONFLICT(store_id, warehouse_id, product_id, batch_id) DO UPDATE SET
          quantity = inventory_batch_balances.quantity + excluded.quantity,
          version = inventory_batch_balances.version + 1,
          updated_at = excluded.updated_at,
          device_id = excluded.device_id,
          last_modified_by_device_id = excluded.last_modified_by_device_id,
          sync_status = 'pending'
      ''', <Object?>[
        balanceId,
        batchId,
        product.id,
        warehouseId,
        storeId,
        branchId,
        allocation.quantity,
        nowText,
        nowText,
        deviceId,
        deviceId,
      ]);
      resolved.add(normalized);
    }
    return resolved;
  }

  Future<void> adjustSpecificBatchInTransaction({
    required Product product,
    required String warehouseId,
    required String batchId,
    required double quantityDelta,
    required DateTime adjustedAt,
    required String storeId,
    required String deviceId,
  }) async {
    if (!product.expiryTrackingEnabled || quantityDelta == 0) return;
    final updated = await db.customUpdate(
      '''
      UPDATE inventory_batch_balances
      SET quantity = quantity + ?, version = version + 1, updated_at = ?,
          device_id = ?, last_modified_by_device_id = ?, sync_status = 'pending'
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ? AND batch_id = ?
        AND quantity + ? >= -0.000001
      ''',
      variables: <Variable<Object>>[
        Variable<double>(quantityDelta),
        Variable<String>(adjustedAt.toUtc().toIso8601String()),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
        Variable<String>(batchId),
        Variable<double>(quantityDelta),
      ],
      updates: const <TableInfo<Table, Object?>>{},
    );
    if (updated != 1) {
      throw const LocalizedDomainException(
          'error_batch_missing_or_insufficient',
          fallback: 'The batch does not exist or has insufficient stock.');
    }
  }

  Future<void> setBatchStatusInTransaction({
    required String batchId,
    required String status,
    required DateTime updatedAt,
    required String storeId,
    required String deviceId,
  }) async {
    if (!const {'active', 'blocked', 'depleted', 'disposed'}.contains(status)) {
      throw const LocalizedDomainException('error_unsupported_batch_status',
          fallback: 'Unsupported batch status.');
    }
    final updated = await db.customUpdate(
      '''
      UPDATE inventory_batches
      SET status = ?, version = version + 1, updated_at = ?, device_id = ?,
          last_modified_by_device_id = ?, sync_status = 'pending'
      WHERE id = ? AND store_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(status),
        Variable<String>(updatedAt.toUtc().toIso8601String()),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(batchId),
        Variable<String>(storeId),
      ],
      updates: const <TableInfo<Table, Object?>>{},
    );
    if (updated != 1) {
      throw const LocalizedDomainException('error_batch_not_found',
          fallback: 'Batch not found.');
    }
  }

  Future<List<BatchAllocation>> receiveInTransaction({
    required Product product,
    required String warehouseId,
    required String purchaseId,
    required int purchaseLineIndex,
    required double expectedQuantity,
    required List<BatchAllocation> allocations,
    required DateTime receivedAt,
    required String storeId,
    required String branchId,
    required String deviceId,
  }) async {
    if (!product.expiryTrackingEnabled) return const <BatchAllocation>[];
    if (allocations.isEmpty) {
      throw LocalizedDomainException('error_expiry_batches_required',
          values: {'product': product.name},
          fallback: 'Expiry batches are required for ${product.name}.');
    }
    final allocatedQuantity = allocations.fold<double>(
      0,
      (sum, allocation) => sum + allocation.quantity,
    );
    if ((allocatedQuantity - expectedQuantity).abs() > 0.000001) {
      throw LocalizedDomainException('error_batch_quantity_total',
          values: {'product': product.name, 'quantity': expectedQuantity},
          fallback:
              'Batch quantities for ${product.name} must equal $expectedQuantity.');
    }

    final nowText = receivedAt.toUtc().toIso8601String();
    final startOfReceiptDay = DateTime.utc(
      receivedAt.year,
      receivedAt.month,
      receivedAt.day,
    );
    final minimumExpiry = startOfReceiptDay.add(
      Duration(days: product.minimumReceiptShelfLifeDays),
    );
    final resolved = <BatchAllocation>[];
    for (var index = 0; index < allocations.length; index += 1) {
      final allocation = allocations[index];
      if (allocation.quantity <= 0) {
        throw const LocalizedDomainException('error_batch_quantity_positive',
            fallback: 'Batch quantity must be greater than zero.');
      }
      final expiry = allocation.expirationDate;
      if (product.expiryEntryRequired && expiry == null) {
        throw LocalizedDomainException('error_expiration_date_required',
            values: {'product': product.name},
            fallback: 'Expiration date is required for ${product.name}.');
      }
      if (expiry != null && expiry.isBefore(minimumExpiry)) {
        throw LocalizedDomainException('error_minimum_shelf_life',
            values: {'product': product.name},
            fallback:
                'The remaining shelf life for ${product.name} is below the allowed minimum.');
      }
      final batchId = allocation.batchId.trim().isEmpty
          ? '$purchaseId-batch-$purchaseLineIndex-$index'
          : allocation.batchId.trim();
      final normalized = BatchAllocation(
        batchId: batchId,
        quantity: allocation.quantity,
        supplierBatchNumber: allocation.supplierBatchNumber.trim(),
        manufacturingDate: allocation.manufacturingDate,
        expirationDate: expiry,
      );
      await db.customInsert(
        '''
        INSERT OR IGNORE INTO inventory_batches
          (id, product_id, product_name, supplier_batch_number,
           manufacturing_date, expiration_date, status, source_type,
           source_id, store_id, branch_id, created_at, updated_at, device_id,
           last_modified_by_device_id, sync_status, version)
        VALUES (?, ?, ?, ?, ?, ?, 'active', 'purchase', ?, ?, ?, ?, ?, ?, ?, 'pending', 1)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(batchId),
          Variable<String>(product.id),
          Variable<String>(product.name),
          Variable<String>(normalized.supplierBatchNumber),
          Variable<String>(
              normalized.manufacturingDate?.toUtc().toIso8601String() ?? ''),
          Variable<String>(expiry?.toUtc().toIso8601String() ?? ''),
          Variable<String>(purchaseId),
          Variable<String>(storeId),
          Variable<String>(branchId),
          Variable<String>(nowText),
          Variable<String>(nowText),
          Variable<String>(deviceId),
          Variable<String>(deviceId),
        ],
      );
      final balanceId = '$storeId::$warehouseId::${product.id}::$batchId';
      await db.customStatement(
        '''
        INSERT INTO inventory_batch_balances
          (id, batch_id, product_id, warehouse_id, store_id, branch_id,
           quantity, reserved_quantity, version, created_at, updated_at,
           device_id, last_modified_by_device_id, sync_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, ?, 'pending')
        ON CONFLICT(store_id, warehouse_id, product_id, batch_id) DO UPDATE SET
          quantity = inventory_batch_balances.quantity + excluded.quantity,
          version = inventory_batch_balances.version + 1,
          updated_at = excluded.updated_at,
          device_id = excluded.device_id,
          last_modified_by_device_id = excluded.last_modified_by_device_id,
          sync_status = 'pending'
        ''',
        <Object?>[
          balanceId,
          batchId,
          product.id,
          warehouseId,
          storeId,
          branchId,
          allocation.quantity,
          nowText,
          nowText,
          deviceId,
          deviceId,
        ],
      );
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO purchase_item_batch_allocations
          (id, purchase_item_id, line_no, batch_id, quantity,
           supplier_batch_number, manufacturing_date, expiration_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>('$purchaseId:$purchaseLineIndex:batch:$index'),
          Variable<String>('$purchaseId:$purchaseLineIndex'),
          Variable<int>(index),
          Variable<String>(batchId),
          Variable<double>(allocation.quantity),
          Variable<String>(normalized.supplierBatchNumber),
          Variable<String>(
              normalized.manufacturingDate?.toUtc().toIso8601String() ?? ''),
          Variable<String>(expiry?.toUtc().toIso8601String() ?? ''),
        ],
      );
      resolved.add(normalized);
    }
    return resolved;
  }

  Future<List<BatchAllocation>> allocateFefoInTransaction({
    required Product product,
    required String warehouseId,
    required double quantity,
    required DateTime saleDate,
    required String storeId,
    required String deviceId,
  }) async {
    if (!product.expiryTrackingEnabled) return const <BatchAllocation>[];
    if (quantity <= 0) return const <BatchAllocation>[];
    final startOfSaleDay = DateTime.utc(
      saleDate.year,
      saleDate.month,
      saleDate.day,
    ).toIso8601String();
    final rows = await db.customSelect(
      '''
      SELECT b.id AS batch_id, b.supplier_batch_number,
             b.manufacturing_date, b.expiration_date,
             bb.quantity, bb.reserved_quantity
      FROM inventory_batch_balances bb
      JOIN inventory_batches b ON b.id = bb.batch_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
        AND b.status = 'active'
        AND (bb.quantity - bb.reserved_quantity) > 0.000001
        AND (trim(b.expiration_date) = '' OR b.expiration_date >= ?)
      ORDER BY CASE WHEN trim(b.expiration_date) = '' THEN 1 ELSE 0 END ASC,
               b.expiration_date ASC, b.created_at ASC, b.id ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
        Variable<String>(startOfSaleDay),
      ],
    ).get();
    var remaining = quantity;
    final allocations = <BatchAllocation>[];
    for (final row in rows) {
      if (remaining <= 0.000001) break;
      final available =
          row.read<double>('quantity') - row.read<double>('reserved_quantity');
      final used = available < remaining ? available : remaining;
      if (used <= 0) continue;
      final batchId = row.read<String>('batch_id');
      await db.customUpdate(
        '''
        UPDATE inventory_batch_balances
        SET quantity = quantity - ?, version = version + 1,
            updated_at = ?, device_id = ?, last_modified_by_device_id = ?,
            sync_status = 'pending'
        WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
          AND batch_id = ? AND (quantity - reserved_quantity) >= ?
        ''',
        variables: <Variable<Object>>[
          Variable<double>(used),
          Variable<String>(saleDate.toUtc().toIso8601String()),
          Variable<String>(deviceId),
          Variable<String>(deviceId),
          Variable<String>(storeId),
          Variable<String>(warehouseId),
          Variable<String>(product.id),
          Variable<String>(batchId),
          Variable<double>(used),
        ],
        updates: const <TableInfo<Table, Object?>>{},
      );
      allocations.add(BatchAllocation(
        batchId: batchId,
        quantity: used,
        supplierBatchNumber: row.read<String>('supplier_batch_number'),
        manufacturingDate:
            DateTime.tryParse(row.read<String>('manufacturing_date')),
        expirationDate: DateTime.tryParse(row.read<String>('expiration_date')),
      ));
      remaining -= used;
    }
    if (remaining > 0.000001) {
      throw LocalizedDomainException('error_insufficient_valid_batch_stock',
          values: {'product': product.name},
          fallback:
              'Insufficient non-expired batch stock for ${product.name}.');
    }
    return allocations;
  }

  Future<void> restoreInTransaction({
    required Product product,
    required String warehouseId,
    required List<BatchAllocation> allocations,
    required DateTime restoredAt,
    required String storeId,
    required String deviceId,
  }) async {
    if (!product.expiryTrackingEnabled || allocations.isEmpty) return;
    for (final allocation in allocations) {
      final updated = await db.customUpdate(
        '''
        UPDATE inventory_batch_balances
        SET quantity = quantity + ?, version = version + 1, updated_at = ?,
            device_id = ?, last_modified_by_device_id = ?, sync_status = 'pending'
        WHERE store_id = ? AND warehouse_id = ? AND product_id = ? AND batch_id = ?
        ''',
        variables: <Variable<Object>>[
          Variable<double>(allocation.quantity),
          Variable<String>(restoredAt.toUtc().toIso8601String()),
          Variable<String>(deviceId),
          Variable<String>(deviceId),
          Variable<String>(storeId),
          Variable<String>(warehouseId),
          Variable<String>(product.id),
          Variable<String>(allocation.batchId),
        ],
        updates: const <TableInfo<Table, Object?>>{},
      );
      if (updated != 1) {
        throw LocalizedDomainException('error_batch_no_longer_exists',
            values: {'batch': allocation.batchId},
            fallback: 'Batch ${allocation.batchId} no longer exists.');
      }
    }
  }

  Future<List<BatchAllocation>> transferFefoInTransaction({
    required Product product,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    required DateTime transferredAt,
    required String storeId,
    required String branchId,
    required String deviceId,
  }) async {
    final allocations = await allocateFefoInTransaction(
      product: product,
      warehouseId: fromWarehouseId,
      quantity: quantity,
      saleDate: transferredAt,
      storeId: storeId,
      deviceId: deviceId,
    );
    final nowText = transferredAt.toUtc().toIso8601String();
    for (final allocation in allocations) {
      final id =
          '$storeId::$toWarehouseId::${product.id}::${allocation.batchId}';
      await db.customStatement('''
        INSERT INTO inventory_batch_balances
          (id, batch_id, product_id, warehouse_id, store_id, branch_id,
           quantity, reserved_quantity, version, created_at, updated_at,
           device_id, last_modified_by_device_id, sync_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, ?, 'pending')
        ON CONFLICT(store_id, warehouse_id, product_id, batch_id) DO UPDATE SET
          quantity = inventory_batch_balances.quantity + excluded.quantity,
          version = inventory_batch_balances.version + 1,
          updated_at = excluded.updated_at,
          device_id = excluded.device_id,
          last_modified_by_device_id = excluded.last_modified_by_device_id,
          sync_status = 'pending'
      ''', <Object?>[
        id,
        allocation.batchId,
        product.id,
        toWarehouseId,
        storeId,
        branchId,
        allocation.quantity,
        nowText,
        nowText,
        deviceId,
        deviceId,
      ]);
    }
    return allocations;
  }
}
