import 'package:drift/drift.dart';

import '../../models/inventory_batch.dart';
import '../../models/product.dart';
import '../localization/localized_domain_exception.dart';
import '../storage/sqlite/ventio_drift_database.dart';

/// Transactional batch inventory operations.
///
/// Phase 1 introduces a unified batch engine for every stock-tracked product.
/// The legacy expiry-only entry points remain temporarily for compatibility
/// until purchase/sale write paths cut over in Phase 2.
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
    double unitCost = 0,
    String sourceLineId = '',
    String costCurrency = 'USD',
    double exchangeRate = 1,
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
        unitCost: unitCost,
      );
      await db.customStatement('''
        INSERT INTO inventory_batches
          (id, product_id, product_name, supplier_batch_number,
           manufacturing_date, expiration_date, status, source_type,
           source_id, source_line_id, unit_cost, initial_quantity,
           cost_currency, exchange_rate, received_at, store_id, branch_id,
           created_at, updated_at, device_id,
           last_modified_by_device_id, sync_status, version)
        VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 1)
        ON CONFLICT(id) DO UPDATE SET
          product_name = excluded.product_name,
          supplier_batch_number = excluded.supplier_batch_number,
          manufacturing_date = excluded.manufacturing_date,
          expiration_date = excluded.expiration_date,
          source_line_id = CASE
            WHEN trim(inventory_batches.source_line_id) = '' THEN excluded.source_line_id
            ELSE inventory_batches.source_line_id
          END,
          unit_cost = CASE
            WHEN inventory_batches.unit_cost <= 0 THEN excluded.unit_cost
            ELSE inventory_batches.unit_cost
          END,
          initial_quantity = CASE
            WHEN inventory_batches.initial_quantity <= 0 THEN excluded.initial_quantity
            ELSE inventory_batches.initial_quantity
          END,
          cost_currency = CASE
            WHEN inventory_batches.unit_cost <= 0 THEN excluded.cost_currency
            ELSE inventory_batches.cost_currency
          END,
          exchange_rate = CASE
            WHEN inventory_batches.unit_cost <= 0 THEN excluded.exchange_rate
            ELSE inventory_batches.exchange_rate
          END,
          received_at = CASE
            WHEN trim(inventory_batches.received_at) = '' THEN excluded.received_at
            ELSE inventory_batches.received_at
          END,
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
        sourceLineId,
        unitCost,
        allocation.quantity,
        costCurrency.toUpperCase(),
        exchangeRate,
        nowText,
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
    double unitCost = 0,
    String sourceLineId = '',
    String costCurrency = 'USD',
    double exchangeRate = 1,
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
        unitCost: unitCost,
      );
      await db.customInsert(
        '''
        INSERT OR IGNORE INTO inventory_batches
          (id, product_id, product_name, supplier_batch_number,
           manufacturing_date, expiration_date, status, source_type,
           source_id, source_line_id, unit_cost, initial_quantity,
           cost_currency, exchange_rate, received_at, store_id, branch_id,
           created_at, updated_at, device_id,
           last_modified_by_device_id, sync_status, version)
        VALUES (?, ?, ?, ?, ?, ?, 'active', 'purchase', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 1)
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
          Variable<String>(sourceLineId),
          Variable<double>(unitCost),
          Variable<double>(allocation.quantity),
          Variable<String>(costCurrency.toUpperCase()),
          Variable<double>(exchangeRate),
          Variable<String>(nowText),
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
    bool allowNegativeStock = false,
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
             b.manufacturing_date, b.expiration_date, b.unit_cost,
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
        unitCost: row.read<double>('unit_cost'),
      ));
      remaining -= used;
    }
    if (remaining > 0.000001) {
      if (allowNegativeStock) {
        allocations.add(BatchAllocation(batchId: '', quantity: remaining));
        return allocations;
      }
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
      if (allocation.batchId.trim().isEmpty) continue;
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
    bool allowNegativeStock = false,
  }) async {
    final allocations = await allocateFefoInTransaction(
      product: product,
      warehouseId: fromWarehouseId,
      quantity: quantity,
      saleDate: transferredAt,
      storeId: storeId,
      deviceId: deviceId,
      allowNegativeStock: allowNegativeStock,
    );
    final nowText = transferredAt.toUtc().toIso8601String();
    for (final allocation in allocations) {
      if (allocation.batchId.trim().isEmpty) continue;
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

  /// Phase 1 unified batch entry point.
  ///
  /// Unlike the legacy expiry-only helpers above, this method is valid for
  /// every stock-tracked product. Expiry-tracked products must carry an expiry
  /// date; non-expiry products are forbidden from carrying one. A stable
  /// [sourceLineId] makes the operation idempotent at the document-line level.
  Future<BatchAllocation> addUnifiedBatchStockInTransaction({
    required Product product,
    required String warehouseId,
    required String batchId,
    required double quantity,
    required double unitCost,
    required String sourceType,
    required String sourceId,
    required String sourceLineId,
    required DateTime receivedAt,
    required String storeId,
    required String branchId,
    required String deviceId,
    String supplierBatchNumber = '',
    DateTime? manufacturingDate,
    DateTime? expirationDate,
    String costCurrency = 'USD',
    double exchangeRate = 1,
  }) async {
    if (!product.trackStock) {
      throw LocalizedDomainException(
        'error_batch_requires_stock_tracking',
        values: {'product': product.name},
        fallback: 'Batch inventory requires stock tracking for ${product.name}.',
      );
    }
    final normalizedBatchId = batchId.trim();
    final normalizedSourceType = sourceType.trim();
    final normalizedSourceId = sourceId.trim();
    final normalizedSourceLineId = sourceLineId.trim();
    if (normalizedBatchId.isEmpty ||
        normalizedSourceType.isEmpty ||
        normalizedSourceId.isEmpty ||
        normalizedSourceLineId.isEmpty) {
      throw const LocalizedDomainException(
        'error_batch_identity_required',
        fallback: 'Batch and source line identity are required.',
      );
    }
    if (quantity <= 0) {
      throw const LocalizedDomainException(
        'error_batch_quantity_positive',
        fallback: 'Batch quantity must be greater than zero.',
      );
    }
    if (unitCost < 0 || exchangeRate <= 0) {
      throw const LocalizedDomainException(
        'error_batch_cost_invalid',
        fallback: 'Batch unit cost and exchange rate must be valid.',
      );
    }
    _validateUnifiedExpiryContract(
      product: product,
      expirationDate: expirationDate,
      receivedAt: receivedAt,
    );

    final existing = await db.customSelect(
      '''
      SELECT id, product_id, unit_cost, initial_quantity, expiration_date
      FROM inventory_batches
      WHERE store_id = ? AND source_type = ? AND source_id = ?
        AND source_line_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(normalizedSourceType),
        Variable<String>(normalizedSourceId),
        Variable<String>(normalizedSourceLineId),
      ],
    ).getSingleOrNull();
    if (existing != null) {
      final existingId = existing.read<String>('id');
      final existingProductId = existing.read<String>('product_id');
      final existingCost = existing.read<double>('unit_cost');
      final existingInitialQuantity =
          existing.read<double>('initial_quantity');
      final existingExpiry =
          DateTime.tryParse(existing.read<String>('expiration_date'));
      if (existingId != normalizedBatchId ||
          existingProductId != product.id ||
          (existingCost - unitCost).abs() > 0.000001 ||
          (existingInitialQuantity - quantity).abs() > 0.000001 ||
          !_sameCalendarDate(existingExpiry, expirationDate)) {
        throw const LocalizedDomainException(
          'error_batch_source_line_conflict',
          fallback:
              'This document line is already linked to a different batch definition.',
        );
      }
      return BatchAllocation(
        batchId: existingId,
        quantity: quantity,
        supplierBatchNumber: supplierBatchNumber.trim(),
        manufacturingDate: manufacturingDate,
        expirationDate: expirationDate,
        unitCost: existingCost,
      );
    }

    final nowText = receivedAt.toUtc().toIso8601String();
    final normalizedCurrency = costCurrency.trim().isEmpty
        ? 'USD'
        : costCurrency.trim().toUpperCase();
    await db.customStatement(
      '''
      INSERT INTO inventory_batches
        (id, product_id, product_name, supplier_batch_number,
         manufacturing_date, expiration_date, status, source_type, source_id,
         source_line_id, unit_cost, initial_quantity, cost_currency,
         exchange_rate, received_at, store_id, branch_id, created_at,
         updated_at, device_id,
         last_modified_by_device_id, sync_status, version)
      VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 1)
      ''',
      <Object?>[
        normalizedBatchId,
        product.id,
        product.name,
        supplierBatchNumber.trim(),
        manufacturingDate?.toUtc().toIso8601String() ?? '',
        expirationDate == null ? '' : _calendarDateText(expirationDate),
        normalizedSourceType,
        normalizedSourceId,
        normalizedSourceLineId,
        unitCost,
        quantity,
        normalizedCurrency,
        exchangeRate,
        nowText,
        storeId,
        branchId,
        nowText,
        nowText,
        deviceId,
        deviceId,
      ],
    );

    final balanceId =
        '$storeId::$warehouseId::${product.id}::$normalizedBatchId';
    await db.customStatement(
      '''
      INSERT INTO inventory_batch_balances
        (id, batch_id, product_id, warehouse_id, store_id, branch_id,
         quantity, reserved_quantity, version, created_at, updated_at,
         device_id, last_modified_by_device_id, sync_status)
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, ?, 'pending')
      ''',
      <Object?>[
        balanceId,
        normalizedBatchId,
        product.id,
        warehouseId,
        storeId,
        branchId,
        quantity,
        nowText,
        nowText,
        deviceId,
        deviceId,
      ],
    );
    return BatchAllocation(
      batchId: normalizedBatchId,
      quantity: quantity,
      supplierBatchNumber: supplierBatchNumber.trim(),
      manufacturingDate: manufacturingDate,
      expirationDate: expirationDate,
      unitCost: unitCost,
    );
  }

  /// Idempotent Phase-2 cutover for one product/warehouse.
  ///
  /// Non-expiry legacy stock can be represented by one opening batch because
  /// no historical lot identity existed before Unified Batch. Expiry-tracked
  /// stock must already be fully represented by real expiry batches.
  Future<void> ensureUnifiedCutoverInTransaction({
    required Product product,
    required String warehouseId,
    required double openingUnitCost,
    required DateTime cutoverAt,
    required String storeId,
    required String branchId,
    required String deviceId,
  }) async {
    if (!product.trackStock) return;
    final markerId = '$storeId::$warehouseId::${product.id}';
    final existingMarker = await db.customSelect(
      '''
      SELECT id FROM unified_batch_cutovers
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingleOrNull();
    if (existingMarker != null) {
      final check = await checkWarehouseBatchBalanceInTransaction(
        productId: product.id,
        warehouseId: warehouseId,
        storeId: storeId,
      );
      if (!check.isConsistent) {
        throw LocalizedDomainException(
          'error_batch_cutover_mismatch',
          values: {'product': product.name},
          fallback:
              'Unified batch stock no longer matches warehouse stock for ${product.name}.',
        );
      }
      return;
    }

    // Legacy expiry batches predate unit-cost persistence. Before the first
    // Unified cutover, recover an exact purchase-line cost when that relation
    // exists; otherwise use the current documented carrying/opening cost as a
    // cutover snapshot. This prevents old expiry lots from producing zero COGS
    // merely because their batch rows were created before Phase 1.
    final safeOpeningCost = openingUnitCost < 0 ? 0.0 : openingUnitCost;
    await db.customStatement(
      '''
      UPDATE inventory_batches
      SET unit_cost = COALESCE((
            SELECT CASE
              WHEN pi.conversion_to_base > 0
                THEN pi.unit_cost / pi.conversion_to_base
              ELSE pi.unit_cost
            END
            FROM purchase_item_batch_allocations pba
            JOIN purchase_items pi ON pi.id = pba.purchase_item_id
            WHERE pba.batch_id = inventory_batches.id
              AND pi.product_id = inventory_batches.product_id
              AND pi.unit_cost > 0
            ORDER BY pba.line_no ASC
            LIMIT 1
          ), CASE WHEN ? > 0 THEN ? ELSE inventory_batches.unit_cost END),
          cost_currency = CASE
            WHEN unit_cost <= 0 AND ? > 0 THEN 'USD'
            ELSE cost_currency
          END,
          updated_at = ?,
          device_id = ?,
          last_modified_by_device_id = ?,
          sync_status = 'pending'
      WHERE store_id = ? AND product_id = ? AND unit_cost <= 0
      ''',
      <Object?>[
        safeOpeningCost,
        safeOpeningCost,
        safeOpeningCost,
        cutoverAt.toUtc().toIso8601String(),
        deviceId,
        deviceId,
        storeId,
        product.id,
      ],
    );

    final warehouseRow = await db.customSelect(
      '''
      SELECT COALESCE(quantity, 0) AS quantity
      FROM warehouse_inventory
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingleOrNull();
    final warehouseQuantity =
        (warehouseRow?.data['quantity'] as num?)?.toDouble() ?? 0.0;
    final batchRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(bb.quantity), 0) AS quantity
      FROM inventory_batch_balances bb
      JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingle();
    final batchQuantity =
        (batchRow.data['quantity'] as num?)?.toDouble() ?? 0.0;
    final difference = warehouseQuantity - batchQuantity;
    const tolerance = 0.000001;
    if (difference < -tolerance) {
      throw LocalizedDomainException(
        'error_batch_cutover_overstated',
        values: {'product': product.name},
        fallback:
            'Batch stock exceeds warehouse stock for ${product.name}; cutover was stopped.',
      );
    }

    String openingBatchId = '';
    double openingQuantity = 0;
    if (difference > tolerance) {
      if (product.expiryTrackingEnabled) {
        throw LocalizedDomainException(
          'error_batch_cutover_expiry_missing',
          values: {'product': product.name},
          fallback:
              'Expiry-tracked stock for ${product.name} is not fully represented by batches.',
        );
      }
      openingBatchId =
          'opening_${storeId}_${warehouseId}_${product.id}'.replaceAll(' ', '_');
      openingQuantity = difference;
      await addUnifiedBatchStockInTransaction(
        product: product,
        warehouseId: warehouseId,
        batchId: openingBatchId,
        quantity: difference,
        unitCost: openingUnitCost < 0 ? 0 : openingUnitCost,
        sourceType: 'unified_batch_opening',
        sourceId: warehouseId,
        sourceLineId: 'cutover:${product.id}:$warehouseId',
        receivedAt: cutoverAt,
        storeId: storeId,
        branchId: branchId,
        deviceId: deviceId,
        costCurrency: 'USD',
        exchangeRate: 1,
      );
    }

    final check = await checkWarehouseBatchBalanceInTransaction(
      productId: product.id,
      warehouseId: warehouseId,
      storeId: storeId,
    );
    if (!check.isConsistent) {
      throw LocalizedDomainException(
        'error_batch_cutover_mismatch',
        values: {'product': product.name},
        fallback:
            'Unified batch cutover did not reconcile for ${product.name}.',
      );
    }
    final nowText = cutoverAt.toUtc().toIso8601String();
    await db.customStatement(
      '''
      INSERT INTO unified_batch_cutovers
        (id, store_id, warehouse_id, product_id, cutover_at,
         opening_batch_id, opening_quantity, opening_unit_cost,
         created_at, device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        markerId,
        storeId,
        warehouseId,
        product.id,
        nowText,
        openingBatchId,
        openingQuantity,
        openingUnitCost < 0 ? 0 : openingUnitCost,
        nowText,
        deviceId,
      ],
    );
  }

  /// Unified allocation for all stock-tracked products.
  ///
  /// Expiry products use FEFO. Non-expiry products use oldest received batch
  /// first. This phase-1 API never creates anonymous negative-stock slices.
  Future<List<BatchAllocation>> allocateUnifiedInTransaction({
    required Product product,
    required String warehouseId,
    required double quantity,
    required DateTime movementDate,
    required String storeId,
    required String deviceId,
  }) async {
    if (!product.trackStock || quantity <= 0) {
      return const <BatchAllocation>[];
    }
    final startOfMovementDay = _calendarDateText(movementDate);
    final expiryPredicate = product.expiryTrackingEnabled
        ? "trim(b.expiration_date) <> '' AND substr(b.expiration_date, 1, 10) >= ?"
        : "trim(b.expiration_date) = ''";
    final ordering = product.expiryTrackingEnabled
        ? '''substr(b.expiration_date, 1, 10) ASC,
             CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END ASC,
             b.id ASC'''
        : '''CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END ASC,
             b.id ASC''';
    final variables = <Variable<Object>>[
      Variable<String>(storeId),
      Variable<String>(warehouseId),
      Variable<String>(product.id),
      if (product.expiryTrackingEnabled)
        Variable<String>(startOfMovementDay),
    ];
    final rows = await db.customSelect(
      '''
      SELECT b.id AS batch_id, b.supplier_batch_number,
             b.manufacturing_date, b.expiration_date, b.unit_cost,
             bb.quantity, bb.reserved_quantity
      FROM inventory_batch_balances bb
      JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
        AND b.status = 'active'
        AND (bb.quantity - bb.reserved_quantity) > 0.000001
        AND $expiryPredicate
      ORDER BY $ordering
      ''',
      variables: variables,
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
      final updated = await db.customUpdate(
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
          Variable<String>(movementDate.toUtc().toIso8601String()),
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
      if (updated != 1) {
        throw const LocalizedDomainException(
          'error_batch_concurrent_change',
          fallback: 'Batch stock changed while allocating inventory.',
        );
      }
      allocations.add(BatchAllocation(
        batchId: batchId,
        quantity: used,
        supplierBatchNumber: row.read<String>('supplier_batch_number'),
        manufacturingDate:
            DateTime.tryParse(row.read<String>('manufacturing_date')),
        expirationDate:
            DateTime.tryParse(row.read<String>('expiration_date')),
        unitCost: row.read<double>('unit_cost'),
      ));
      remaining -= used;
    }
    if (remaining > 0.000001) {
      throw LocalizedDomainException(
        'error_insufficient_batch_stock',
        values: {'product': product.name},
        fallback: 'Insufficient batch stock for ${product.name}.',
      );
    }
    return allocations;
  }

  Future<void> restoreUnifiedInTransaction({
    required Product product,
    required String warehouseId,
    required List<BatchAllocation> allocations,
    required DateTime restoredAt,
    required String storeId,
    required String deviceId,
  }) async {
    if (!product.trackStock || allocations.isEmpty) return;
    for (final allocation in allocations) {
      final batchId = allocation.batchId.trim();
      if (batchId.isEmpty || allocation.quantity <= 0) {
        throw const LocalizedDomainException(
          'error_batch_restore_invalid',
          fallback: 'A valid batch and positive quantity are required.',
        );
      }
      final updated = await db.customUpdate(
        '''
        UPDATE inventory_batch_balances
        SET quantity = quantity + ?, version = version + 1, updated_at = ?,
            device_id = ?, last_modified_by_device_id = ?, sync_status = 'pending'
        WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
          AND batch_id = ?
          AND EXISTS (
            SELECT 1 FROM inventory_batches b
            WHERE b.id = inventory_batch_balances.batch_id
              AND b.product_id = ? AND b.store_id = ?
          )
        ''',
        variables: <Variable<Object>>[
          Variable<double>(allocation.quantity),
          Variable<String>(restoredAt.toUtc().toIso8601String()),
          Variable<String>(deviceId),
          Variable<String>(deviceId),
          Variable<String>(storeId),
          Variable<String>(warehouseId),
          Variable<String>(product.id),
          Variable<String>(batchId),
          Variable<String>(product.id),
          Variable<String>(storeId),
        ],
        updates: const <TableInfo<Table, Object?>>{},
      );
      if (updated != 1) {
        throw LocalizedDomainException(
          'error_batch_no_longer_exists',
          values: {'batch': batchId},
          fallback: 'Batch $batchId no longer exists.',
        );
      }
      await db.customStatement(
        '''
        UPDATE inventory_batches
        SET status = CASE WHEN status = 'depleted' THEN 'active' ELSE status END,
            updated_at = ?, version = version + 1,
            last_modified_by_device_id = ?, sync_status = 'pending'
        WHERE id = ? AND store_id = ?
        ''',
        <Object?>[
          restoredAt.toUtc().toIso8601String(),
          deviceId,
          batchId,
          storeId,
        ],
      );
    }
  }

  Future<void> adjustUnifiedBatchInTransaction({
    required Product product,
    required String warehouseId,
    required String batchId,
    required double quantityDelta,
    required DateTime adjustedAt,
    required String storeId,
    required String deviceId,
  }) async {
    if (!product.trackStock || quantityDelta == 0) return;
    final updated = await db.customUpdate(
      '''
      UPDATE inventory_batch_balances
      SET quantity = quantity + ?, version = version + 1, updated_at = ?,
          device_id = ?, last_modified_by_device_id = ?, sync_status = 'pending'
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ? AND batch_id = ?
        AND quantity + ? >= 0
      ''',
      variables: <Variable<Object>>[
        Variable<double>(quantityDelta),
        Variable<String>(adjustedAt.toUtc().toIso8601String()),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
        Variable<String>(batchId.trim()),
        Variable<double>(quantityDelta),
      ],
      updates: const <TableInfo<Table, Object?>>{},
    );
    if (updated != 1) {
      throw const LocalizedDomainException(
        'error_batch_missing_or_insufficient',
        fallback: 'The batch does not exist or has insufficient stock.',
      );
    }
  }

  Future<List<BatchAllocation>> transferUnifiedInTransaction({
    required Product product,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    required DateTime transferredAt,
    required String storeId,
    required String branchId,
    required String deviceId,
  }) async {
    final allocations = await allocateUnifiedInTransaction(
      product: product,
      warehouseId: fromWarehouseId,
      quantity: quantity,
      movementDate: transferredAt,
      storeId: storeId,
      deviceId: deviceId,
    );
    final nowText = transferredAt.toUtc().toIso8601String();
    for (final allocation in allocations) {
      final id = '$storeId::$toWarehouseId::${product.id}::${allocation.batchId}';
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
        ],
      );
    }
    return allocations;
  }

  /// Compares the aggregate warehouse quantity with the sum of batch balances.
  /// Phase 1 exposes the invariant without enforcing it on legacy write paths;
  /// phase 2+ callers can assert it after each unified transaction.
  Future<BatchInventoryBalanceCheck> checkWarehouseBatchBalanceInTransaction({
    required String productId,
    required String warehouseId,
    required String storeId,
    double tolerance = 0.000001,
  }) async {
    final aggregateRow = await db.customSelect(
      '''
      SELECT COALESCE(quantity, 0) AS quantity
      FROM warehouse_inventory
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).getSingleOrNull();
    final batchRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(bb.quantity), 0) AS quantity,
             COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS carrying_value
      FROM inventory_batch_balances bb
      JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).getSingle();
    return BatchInventoryBalanceCheck(
      productId: productId,
      warehouseId: warehouseId,
      warehouseQuantity:
          (aggregateRow?.data['quantity'] as num? ?? 0).toDouble(),
      batchQuantity: (batchRow.data['quantity'] as num? ?? 0).toDouble(),
      batchCarryingValue:
          (batchRow.data['carrying_value'] as num? ?? 0).toDouble(),
      tolerance: tolerance,
    );
  }

  Future<void> assertWarehouseBatchBalanceInTransaction({
    required String productId,
    required String warehouseId,
    required String storeId,
    double tolerance = 0.000001,
  }) async {
    final check = await checkWarehouseBatchBalanceInTransaction(
      productId: productId,
      warehouseId: warehouseId,
      storeId: storeId,
      tolerance: tolerance,
    );
    if (!check.isConsistent) {
      throw LocalizedDomainException(
        'error_batch_warehouse_balance_mismatch',
        values: <String, Object?>{
          'warehouseQuantity': check.warehouseQuantity,
          'batchQuantity': check.batchQuantity,
        },
        fallback:
            'Warehouse inventory and batch balances do not match for $productId.',
      );
    }
  }

  void _validateUnifiedExpiryContract({
    required Product product,
    required DateTime? expirationDate,
    required DateTime receivedAt,
  }) {
    if (product.expiryTrackingEnabled) {
      if (expirationDate == null) {
        throw LocalizedDomainException(
          'error_expiration_date_required',
          values: {'product': product.name},
          fallback: 'Expiration date is required for ${product.name}.',
        );
      }
      final receiptDay = _calendarDate(receivedAt);
      final minimumExpiry = receiptDay.add(
        Duration(days: product.minimumReceiptShelfLifeDays),
      );
      if (_calendarDate(expirationDate).isBefore(minimumExpiry)) {
        throw LocalizedDomainException(
          'error_minimum_shelf_life',
          values: {'product': product.name},
          fallback:
              'The remaining shelf life for ${product.name} is below the allowed minimum.',
        );
      }
      return;
    }
    if (expirationDate != null) {
      throw LocalizedDomainException(
        'error_expiration_not_allowed',
        values: {'product': product.name},
        fallback: 'Expiration date is disabled for ${product.name}.',
      );
    }
  }

  DateTime _calendarDate(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  String _calendarDateText(DateTime value) =>
      _calendarDate(value).toIso8601String().substring(0, 10);

  bool _sameCalendarDate(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == null && right == null;
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
