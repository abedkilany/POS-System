import 'package:drift/drift.dart';

import '../../models/inventory_batch.dart';
import '../../models/product.dart';
import '../localization/localized_domain_exception.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';

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

    final settledDeficitQuantity = normalizedSourceType == 'inventory_deficit'
        ? 0.0
        : await _settleOpenDeficitsWithIncomingBatchInTransaction(
            productId: product.id,
            productName: product.name,
            warehouseId: warehouseId,
            incomingBatchId: normalizedBatchId,
            incomingQuantity: quantity,
            actualUnitCost: unitCost,
            settledAt: receivedAt,
            storeId: storeId,
            branchId: branchId,
            deviceId: deviceId,
            postAccountingAdjustments: true,
          );
    final balanceQuantity = (quantity - settledDeficitQuantity) < 0.000001
        ? 0.0
        : quantity - settledDeficitQuantity;
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
        balanceQuantity,
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
    final physicalBatchQuantity =
        (batchRow.data['quantity'] as num?)?.toDouble() ?? 0.0;
    final deficitRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(quantity_open), 0) AS quantity
      FROM inventory_stock_deficits
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        AND status = 'open' AND quantity_open > 0.000001
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingle();
    final deficitQuantity =
        (deficitRow.data['quantity'] as num?)?.toDouble() ?? 0.0;
    final batchQuantity = physicalBatchQuantity - deficitQuantity;
    final difference = warehouseQuantity - batchQuantity;
    const tolerance = 0.000001;

    String openingBatchId = '';
    double openingQuantity = 0;

    // Legacy warehouse stock may already be negative before Unified Batch is
    // activated. Preserve that valid historical state by converting the
    // missing quantity into a tracked deficit during cutover. Positive stock
    // with excess batch quantity remains a hard integrity error.
    if (difference < -tolerance) {
      if (warehouseQuantity < -tolerance) {
        final legacyDeficitQuantity = -difference;
        final legacyDeficitBatchId =
            'deficit:cutover:$storeId:$warehouseId:${product.id}'
                .replaceAll(' ', '_');
        final provisionalUnitCost =
            await _provisionalDeficitUnitCostInTransaction(
          product: product,
          warehouseId: warehouseId,
          storeId: storeId,
        );
        await _ensureDeficitBatchAndRecordInTransaction(
          productId: product.id,
          productName: product.name,
          warehouseId: warehouseId,
          deficitBatchId: legacyDeficitBatchId,
          quantity: legacyDeficitQuantity,
          provisionalUnitCost: provisionalUnitCost,
          createdAt: cutoverAt,
          storeId: storeId,
          branchId: branchId,
          deviceId: deviceId,
          expiryTracked: product.expiryTrackingEnabled,
          syncStatus: 'pending',
        );
      } else {
        throw LocalizedDomainException(
          'error_batch_cutover_overstated',
          values: {'product': product.name},
          fallback:
              'Batch stock exceeds warehouse stock for ${product.name}; cutover was stopped.',
        );
      }
    } else if (difference > tolerance) {
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

  static bool isDeficitBatchId(String batchId) =>
      batchId.trim().startsWith('deficit:');

  Future<double> _provisionalDeficitUnitCostInTransaction({
    required Product product,
    required String warehouseId,
    required String storeId,
  }) async {
    final row = await db.customSelect(
      '''
      SELECT b.unit_cost
      FROM inventory_batches b
      LEFT JOIN inventory_batch_balances bb ON bb.batch_id = b.id
        AND bb.store_id = b.store_id AND bb.product_id = b.product_id
        AND bb.warehouse_id = ?
      WHERE b.store_id = ? AND b.product_id = ?
        AND b.source_type <> 'inventory_deficit'
        AND b.unit_cost > 0
      ORDER BY CASE WHEN bb.batch_id IS NULL THEN 1 ELSE 0 END ASC,
               CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END DESC,
               b.id DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(warehouseId),
        Variable<String>(storeId),
        Variable<String>(product.id),
      ],
    ).getSingleOrNull();
    final batchCost = (row?.data['unit_cost'] as num?)?.toDouble() ?? 0.0;
    if (batchCost > 0) return batchCost;
    if (product.usdCost > 0) return product.usdCost;
    if (product.cost > 0) return product.cost;
    return 0.0;
  }

  Future<void> _ensureDeficitBatchAndRecordInTransaction({
    required String productId,
    required String productName,
    required String warehouseId,
    required String deficitBatchId,
    required double quantity,
    required double provisionalUnitCost,
    required DateTime createdAt,
    required String storeId,
    required String branchId,
    required String deviceId,
    required bool expiryTracked,
    required String syncStatus,
  }) async {
    if (quantity <= 0) return;
    final normalizedBatchId = deficitBatchId.trim();
    if (normalizedBatchId.isEmpty) {
      throw const LocalizedDomainException(
        'error_batch_identity_required',
        fallback: 'A deficit batch identity is required.',
      );
    }
    final nowText = createdAt.toUtc().toIso8601String();
    final expirationText = expiryTracked ? '9999-12-31' : '';
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO inventory_batches
        (id, product_id, product_name, supplier_batch_number,
         manufacturing_date, expiration_date, status, source_type, source_id,
         source_line_id, unit_cost, initial_quantity, cost_currency,
         exchange_rate, received_at, store_id, branch_id, created_at,
         updated_at, device_id, last_modified_by_device_id, sync_status, version)
      VALUES (?, ?, ?, 'NEGATIVE-STOCK-DEFICIT', '', ?, 'active',
              'inventory_deficit', ?, ?, ?, ?, 'USD', 1, ?, ?, ?, ?, ?, ?, ?, ?, 1)
      ''',
      <Object?>[
        normalizedBatchId,
        productId,
        productName,
        expirationText,
        normalizedBatchId,
        normalizedBatchId,
        provisionalUnitCost < 0 ? 0.0 : provisionalUnitCost,
        quantity,
        nowText,
        storeId,
        branchId.trim().isEmpty ? 'main' : branchId.trim(),
        nowText,
        nowText,
        deviceId,
        deviceId,
        syncStatus,
      ],
    );
    final deficitId = 'deficit_record:$normalizedBatchId';
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO inventory_stock_deficits
        (id, deficit_batch_id, product_id, warehouse_id, store_id, branch_id,
         quantity_original, quantity_open, provisional_unit_cost, status,
         created_at, updated_at, device_id, last_modified_by_device_id,
         sync_status, version)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?, ?, ?, 1)
      ''',
      <Object?>[
        deficitId,
        normalizedBatchId,
        productId,
        warehouseId,
        storeId,
        branchId.trim().isEmpty ? 'main' : branchId.trim(),
        quantity,
        quantity,
        provisionalUnitCost < 0 ? 0.0 : provisionalUnitCost,
        nowText,
        nowText,
        deviceId,
        deviceId,
        syncStatus,
      ],
    );
  }

  Future<double> _settleOpenDeficitsWithIncomingBatchInTransaction({
    required String productId,
    required String productName,
    required String warehouseId,
    required String incomingBatchId,
    required double incomingQuantity,
    required double actualUnitCost,
    required DateTime settledAt,
    required String storeId,
    required String branchId,
    required String deviceId,
    required bool postAccountingAdjustments,
  }) async {
    if (incomingQuantity <= 0) return 0.0;
    final deficits = await db.customSelect(
      '''
      SELECT id, deficit_batch_id, quantity_open, provisional_unit_cost
      FROM inventory_stock_deficits
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        AND status = 'open' AND quantity_open > 0.000001
      ORDER BY created_at ASC, id ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).get();
    var remainingIncoming = incomingQuantity;
    var totalSettled = 0.0;
    var settlementIndex = 0;
    final nowText = settledAt.toUtc().toIso8601String();
    for (final deficit in deficits) {
      if (remainingIncoming <= 0.000001) break;
      final open = (deficit.data['quantity_open'] as num? ?? 0).toDouble();
      if (open <= 0.000001) continue;
      final settled = open < remainingIncoming ? open : remainingIncoming;
      if (settled <= 0) continue;
      final deficitId = deficit.data['id']?.toString() ?? '';
      final deficitBatchId = deficit.data['deficit_batch_id']?.toString() ?? '';
      final provisionalUnitCost =
          (deficit.data['provisional_unit_cost'] as num? ?? 0).toDouble();
      final nextOpen = open - settled;
      await db.customStatement(
        '''
        UPDATE inventory_stock_deficits
        SET quantity_open = ?,
            status = CASE WHEN ? <= 0.000001 THEN 'resolved' ELSE 'open' END,
            updated_at = ?, version = version + 1,
            last_modified_by_device_id = ?, sync_status = ?
        WHERE id = ?
        ''',
        <Object?>[
          nextOpen < 0.000001 ? 0.0 : nextOpen,
          nextOpen,
          nowText,
          deviceId,
          postAccountingAdjustments ? 'pending' : 'synced',
          deficitId,
        ],
      );
      if (nextOpen <= 0.000001) {
        await db.customStatement(
          '''
          UPDATE inventory_batches
          SET status = 'depleted', updated_at = ?, version = version + 1,
              last_modified_by_device_id = ?, sync_status = ?
          WHERE id = ? AND store_id = ?
            AND NOT EXISTS (
              SELECT 1 FROM inventory_batch_balances bb
              WHERE bb.batch_id = inventory_batches.id
                AND bb.store_id = inventory_batches.store_id
                AND bb.quantity > 0.000001
            )
          ''',
          <Object?>[
            nowText,
            deviceId,
            postAccountingAdjustments ? 'pending' : 'synced',
            deficitBatchId,
            storeId,
          ],
        );
      }
      final settlementId =
          'deficit_settlement:$deficitId:$incomingBatchId:${settledAt.microsecondsSinceEpoch}:$settlementIndex';
      final costAdjustment = settled * (actualUnitCost - provisionalUnitCost);
      await db.customStatement(
        '''
        INSERT OR IGNORE INTO inventory_deficit_settlements
          (id, deficit_id, incoming_batch_id, quantity, reversed_quantity,
           provisional_unit_cost, actual_unit_cost, cost_adjustment,
           settled_at, updated_at, device_id, status)
        VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, 'active')
        ''',
        <Object?>[
          settlementId,
          deficitId,
          incomingBatchId,
          settled,
          provisionalUnitCost,
          actualUnitCost < 0 ? 0.0 : actualUnitCost,
          costAdjustment,
          nowText,
          nowText,
          deviceId,
        ],
      );

      if (postAccountingAdjustments && costAdjustment.abs() > 0.000001) {
        final source = await db.customSelect(
          '''
          SELECT movement_type, reference_id, reference_no, branch_id
          FROM stock_movements
          WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
            AND batch_id = ? AND quantity < 0 AND deleted_at = ''
          ORDER BY movement_date ASC, id ASC
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable<String>(storeId),
            Variable<String>(warehouseId),
            Variable<String>(productId),
            Variable<String>(deficitBatchId),
          ],
        ).getSingleOrNull();
        final sourceMovementType =
            source?.data['movement_type']?.toString() ?? '';
        final sourceBranchValue =
            source?.data['branch_id']?.toString().trim() ?? '';
        final sourceBranchId =
            sourceBranchValue.isEmpty ? branchId : sourceBranchValue;
        if (sourceMovementType == 'sale') {
          await AccountingService
              .recordInventoryDeficitCostReconciliationInTransaction(
            database: db,
            settlementId: settlementId,
            productId: productId,
            productName: productName,
            quantity: settled,
            provisionalUnitCost: provisionalUnitCost,
            actualUnitCost: actualUnitCost,
            entryDate: settledAt,
            sourceReferenceId: source?.data['reference_id']?.toString() ?? '',
            sourceReferenceNo: source?.data['reference_no']?.toString() ?? '',
            createdBy: deviceId,
            storeId: storeId,
            branchId: sourceBranchId,
          );
        } else if (source != null) {
          await AccountingService.recordInventoryDeficitCostVarianceInTransaction(
            database: db,
            settlementId: settlementId,
            productId: productId,
            productName: productName,
            quantity: settled,
            provisionalUnitCost: provisionalUnitCost,
            actualUnitCost: actualUnitCost,
            entryDate: settledAt,
            sourceReferenceId: source.data['reference_id']?.toString() ?? '',
            sourceReferenceNo: source.data['reference_no']?.toString() ?? '',
            sourceMovementType: sourceMovementType,
            createdBy: deviceId,
            storeId: storeId,
            branchId: sourceBranchId,
          );
        }
      }
      remainingIncoming -= settled;
      totalSettled += settled;
      settlementIndex += 1;
    }
    return totalSettled;
  }

  Future<void> _restoreDeficitAllocationInTransaction({
    required String deficitBatchId,
    required double quantity,
    required DateTime restoredAt,
    required String storeId,
    required String warehouseId,
    required String productId,
    required String productName,
    required String branchId,
    required String deviceId,
    required bool postAccountingAdjustments,
  }) async {
    if (quantity <= 0) return;
    final deficit = await db.customSelect(
      '''
      SELECT id, quantity_open, provisional_unit_cost
      FROM inventory_stock_deficits
      WHERE deficit_batch_id = ? AND store_id = ? AND warehouse_id = ?
        AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(deficitBatchId),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).getSingleOrNull();
    if (deficit == null) {
      throw const LocalizedDomainException(
        'error_batch_restore_invalid',
        fallback: 'Negative-stock deficit record was not found.',
      );
    }
    final deficitId = deficit.data['id']?.toString() ?? '';
    final provisionalUnitCost =
        (deficit.data['provisional_unit_cost'] as num? ?? 0).toDouble();
    var remaining = quantity;
    var open = (deficit.data['quantity_open'] as num? ?? 0).toDouble();
    final nowText = restoredAt.toUtc().toIso8601String();
    if (open > 0.000001) {
      final directRestore = open < remaining ? open : remaining;
      open -= directRestore;
      remaining -= directRestore;
      await db.customStatement(
        '''
        UPDATE inventory_stock_deficits
        SET quantity_open = ?, updated_at = ?, version = version + 1,
            last_modified_by_device_id = ?, sync_status = ?
        WHERE id = ?
        ''',
        <Object?>[
          open < 0.000001 ? 0.0 : open,
          nowText,
          deviceId,
          postAccountingAdjustments ? 'pending' : 'synced',
          deficitId,
        ],
      );
    }

    if (remaining > 0.000001) {
      final settlements = await db.customSelect(
        '''
        SELECT id, incoming_batch_id, quantity, reversed_quantity,
               actual_unit_cost
        FROM inventory_deficit_settlements
        WHERE deficit_id = ? AND reversed_quantity < quantity - 0.000001
        ORDER BY settled_at DESC, id DESC
        ''',
        variables: <Variable<Object>>[
          Variable<String>(deficitId),
        ],
      ).get();
      var restoreIndex = 0;
      for (final settlement in settlements) {
        if (remaining <= 0.000001) break;
        final settledQuantity =
            (settlement.data['quantity'] as num? ?? 0).toDouble();
        final reversedQuantity =
            (settlement.data['reversed_quantity'] as num? ?? 0).toDouble();
        final availableToRestore = settledQuantity - reversedQuantity;
        if (availableToRestore <= 0.000001) continue;
        final restored =
            availableToRestore < remaining ? availableToRestore : remaining;
        final incomingBatchId =
            settlement.data['incoming_batch_id']?.toString() ?? '';
        final updated = await db.customUpdate(
          '''
          UPDATE inventory_batch_balances
          SET quantity = quantity + ?, version = version + 1,
              updated_at = ?, device_id = ?, last_modified_by_device_id = ?,
              sync_status = ?
          WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
            AND batch_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<double>(restored),
            Variable<String>(nowText),
            Variable<String>(deviceId),
            Variable<String>(deviceId),
            Variable<String>(
                postAccountingAdjustments ? 'pending' : 'synced'),
            Variable<String>(storeId),
            Variable<String>(warehouseId),
            Variable<String>(productId),
            Variable<String>(incomingBatchId),
          ],
          updates: const <TableInfo<Table, Object?>>{},
        );
        if (updated != 1) {
          throw LocalizedDomainException(
            'error_batch_no_longer_exists',
            values: {'batch': incomingBatchId},
            fallback: 'Batch $incomingBatchId no longer exists.',
          );
        }
        await db.customStatement(
          '''
          UPDATE inventory_batches
          SET status = 'active', updated_at = ?, version = version + 1,
              last_modified_by_device_id = ?, sync_status = ?
          WHERE id = ? AND store_id = ?
          ''',
          <Object?>[
            nowText,
            deviceId,
            postAccountingAdjustments ? 'pending' : 'synced',
            incomingBatchId,
            storeId,
          ],
        );
        final nextReversed = reversedQuantity + restored;
        final settlementId = settlement.data['id']?.toString() ?? '';
        await db.customStatement(
          '''
          UPDATE inventory_deficit_settlements
          SET reversed_quantity = ?,
              status = CASE
                WHEN ? >= quantity - 0.000001 THEN 'reversed'
                ELSE 'partial_reversal'
              END,
              updated_at = ?
          WHERE id = ?
          ''',
          <Object?>[
            nextReversed,
            nextReversed,
            nowText,
            settlementId,
          ],
        );
        if (postAccountingAdjustments) {
          final source = await db.customSelect(
            '''
            SELECT movement_type, reference_id, reference_no, branch_id
            FROM stock_movements
            WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
              AND batch_id = ? AND quantity < 0 AND deleted_at = ''
            ORDER BY movement_date ASC, id ASC
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(storeId),
              Variable<String>(warehouseId),
              Variable<String>(productId),
              Variable<String>(deficitBatchId),
            ],
          ).getSingleOrNull();
          if (source != null) {
            final actualUnitCost =
                (settlement.data['actual_unit_cost'] as num? ?? 0).toDouble();
            final sourceMovementType =
                source.data['movement_type']?.toString() ?? '';
            final sourceBranchId =
                source.data['branch_id']?.toString().trim().isNotEmpty == true
                    ? source.data['branch_id'].toString()
                    : branchId;
            final reversalSettlementId =
                '$settlementId:restore:${restoredAt.microsecondsSinceEpoch}:$restoreIndex';
            if (sourceMovementType == 'sale') {
              await AccountingService
                  .recordInventoryDeficitCostReconciliationInTransaction(
                database: db,
                settlementId: reversalSettlementId,
                productId: productId,
                productName: productName,
                quantity: restored,
                provisionalUnitCost: actualUnitCost,
                actualUnitCost: provisionalUnitCost,
                entryDate: restoredAt,
                sourceReferenceId:
                    source.data['reference_id']?.toString() ?? '',
                sourceReferenceNo:
                    source.data['reference_no']?.toString() ?? '',
                createdBy: deviceId,
                storeId: storeId,
                branchId: sourceBranchId,
              );
            } else {
              await AccountingService
                  .recordInventoryDeficitCostVarianceInTransaction(
                database: db,
                settlementId: reversalSettlementId,
                productId: productId,
                productName: productName,
                quantity: restored,
                provisionalUnitCost: actualUnitCost,
                actualUnitCost: provisionalUnitCost,
                entryDate: restoredAt,
                sourceReferenceId:
                    source.data['reference_id']?.toString() ?? '',
                sourceReferenceNo:
                    source.data['reference_no']?.toString() ?? '',
                sourceMovementType: sourceMovementType,
                createdBy: deviceId,
                storeId: storeId,
                branchId: sourceBranchId,
              );
            }
          }
        }
        remaining -= restored;
        restoreIndex += 1;
      }
    }

    if (remaining > 0.000001) {
      throw const LocalizedDomainException(
        'error_batch_restore_invalid',
        fallback: 'Negative-stock deficit cannot be restored completely.',
      );
    }
    final activeSettlementRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(quantity - reversed_quantity), 0) AS active_qty
      FROM inventory_deficit_settlements
      WHERE deficit_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(deficitId),
      ],
    ).getSingle();
    final activeSettled =
        (activeSettlementRow.data['active_qty'] as num? ?? 0).toDouble();
    final refreshedDeficit = await db.customSelect(
      'SELECT quantity_open FROM inventory_stock_deficits WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(deficitId)],
    ).getSingle();
    final refreshedOpen =
        (refreshedDeficit.data['quantity_open'] as num? ?? 0).toDouble();
    if (refreshedOpen <= 0.000001 && activeSettled <= 0.000001) {
      await db.customStatement(
        '''
        UPDATE inventory_stock_deficits
        SET status = 'reversed', updated_at = ?, version = version + 1,
            last_modified_by_device_id = ?, sync_status = ?
        WHERE id = ?
        ''',
        <Object?>[
          nowText,
          deviceId,
          postAccountingAdjustments ? 'pending' : 'synced',
          deficitId,
        ],
      );
    }
  }

  Future<void> applySyncedBatchMovementInTransaction({
    required String productId,
    required String productName,
    required String warehouseId,
    required String batchId,
    required double quantity,
    required double unitCost,
    required DateTime movementDate,
    required String storeId,
    required String branchId,
    required String deviceId,
  }) async {
    if (batchId.trim().isEmpty || quantity.abs() <= 0.000001) return;
    final normalizedBatchId = batchId.trim();
    final nowText = movementDate.toUtc().toIso8601String();
    if (isDeficitBatchId(normalizedBatchId)) {
      if (quantity < 0) {
        final productRow = await db.customSelect(
          'SELECT expiry_tracking_enabled FROM products WHERE id = ? LIMIT 1',
          variables: <Variable<Object>>[Variable<String>(productId)],
        ).getSingleOrNull();
        final expiryTracked =
            (productRow?.data['expiry_tracking_enabled'] as num? ?? 0).toInt() == 1;
        await _ensureDeficitBatchAndRecordInTransaction(
          productId: productId,
          productName: productName,
          warehouseId: warehouseId,
          deficitBatchId: normalizedBatchId,
          quantity: quantity.abs(),
          provisionalUnitCost: unitCost,
          createdAt: movementDate,
          storeId: storeId,
          branchId: branchId,
          deviceId: deviceId,
          expiryTracked: expiryTracked,
          syncStatus: 'synced',
        );
        return;
      }
      final localDeficit = await db.customSelect(
        '''
        SELECT id FROM inventory_stock_deficits
        WHERE deficit_batch_id = ? AND store_id = ? AND warehouse_id = ?
          AND product_id = ?
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(normalizedBatchId),
          Variable<String>(storeId),
          Variable<String>(warehouseId),
          Variable<String>(productId),
        ],
      ).getSingleOrNull();
      if (localDeficit != null) {
        await _restoreDeficitAllocationInTransaction(
          deficitBatchId: normalizedBatchId,
          quantity: quantity,
          restoredAt: movementDate,
          storeId: storeId,
          warehouseId: warehouseId,
          productId: productId,
          productName: productName,
          branchId: branchId,
          deviceId: deviceId,
          postAccountingAdjustments: false,
        );
        return;
      }
    }

    final batchExists = await db.customSelect(
      'SELECT id FROM inventory_batches WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(normalizedBatchId)],
    ).getSingleOrNull();
    if (batchExists == null) {
      await db.customStatement(
        '''
        INSERT INTO inventory_batches
          (id, product_id, product_name, supplier_batch_number,
           manufacturing_date, expiration_date, status, source_type,
           source_id, source_line_id, unit_cost, initial_quantity,
           cost_currency, exchange_rate, received_at, store_id, branch_id,
           created_at, updated_at, device_id, last_modified_by_device_id,
           sync_status, version)
        VALUES (?, ?, ?, '', '', '', 'active', 'sync_movement', ?, '', ?, ?,
                'USD', 1, ?, ?, ?, ?, ?, ?, ?, 'synced', 1)
        ''',
        <Object?>[
          normalizedBatchId,
          productId,
          productName,
          normalizedBatchId,
          unitCost < 0 ? 0.0 : unitCost,
          quantity > 0 ? quantity : 0.0,
          nowText,
          storeId,
          branchId.trim().isEmpty ? 'main' : branchId.trim(),
          nowText,
          nowText,
          deviceId,
          deviceId,
        ],
      );
    }

    var balanceDelta = quantity;
    if (quantity > 0 && !isDeficitBatchId(normalizedBatchId)) {
      final settled = await _settleOpenDeficitsWithIncomingBatchInTransaction(
        productId: productId,
        productName: productName,
        warehouseId: warehouseId,
        incomingBatchId: normalizedBatchId,
        incomingQuantity: quantity,
        actualUnitCost: unitCost,
        settledAt: movementDate,
        storeId: storeId,
        branchId: branchId,
        deviceId: deviceId,
        postAccountingAdjustments: false,
      );
      balanceDelta = quantity - settled;
    }
    final balanceId = '$storeId::$warehouseId::$productId::$normalizedBatchId';
    if (quantity > 0) {
      final persistedBalanceDelta =
          balanceDelta <= 0.000001 ? 0.0 : balanceDelta;
      await db.customStatement(
        '''
        INSERT INTO inventory_batch_balances
          (id, batch_id, product_id, warehouse_id, store_id, branch_id,
           quantity, reserved_quantity, version, created_at, updated_at,
           device_id, last_modified_by_device_id, sync_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, ?, 'synced')
        ON CONFLICT(store_id, warehouse_id, product_id, batch_id) DO UPDATE SET
          quantity = inventory_batch_balances.quantity + excluded.quantity,
          version = inventory_batch_balances.version + 1,
          updated_at = excluded.updated_at,
          device_id = excluded.device_id,
          last_modified_by_device_id = excluded.last_modified_by_device_id,
          sync_status = 'synced'
        ''',
        <Object?>[
          balanceId,
          normalizedBatchId,
          productId,
          warehouseId,
          storeId,
          branchId.trim().isEmpty ? 'main' : branchId.trim(),
          persistedBalanceDelta,
          nowText,
          nowText,
          deviceId,
          deviceId,
        ],
      );
      await _refreshBatchLifecycleStatusInTransaction(
        batchId: normalizedBatchId,
        storeId: storeId,
        updatedAt: movementDate,
        deviceId: deviceId,
        syncStatus: 'synced',
      );
      return;
    }
    if (balanceDelta.abs() <= 0.000001) return;
    final updated = await db.customUpdate(
      '''
      UPDATE inventory_batch_balances
      SET quantity = quantity + ?, version = version + 1,
          updated_at = ?, device_id = ?, last_modified_by_device_id = ?,
          sync_status = 'synced'
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        AND batch_id = ? AND quantity + ? >= -0.000001
      ''',
      variables: <Variable<Object>>[
        Variable<double>(balanceDelta),
        Variable<String>(nowText),
        Variable<String>(deviceId),
        Variable<String>(deviceId),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
        Variable<String>(normalizedBatchId),
        Variable<double>(balanceDelta),
      ],
      updates: const <TableInfo<Table, Object?>>{},
    );
    if (updated != 1) {
      throw const LocalizedDomainException(
        'error_batch_missing_or_insufficient',
        fallback: 'The batch does not exist or has insufficient stock.',
      );
    }
    await _refreshBatchLifecycleStatusInTransaction(
      batchId: normalizedBatchId,
      storeId: storeId,
      updatedAt: movementDate,
      deviceId: deviceId,
      syncStatus: 'synced',
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
    String branchId = 'main',
    bool allowNegativeStock = false,
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
      await _refreshBatchLifecycleStatusInTransaction(
        batchId: batchId,
        storeId: storeId,
        updatedAt: movementDate,
        deviceId: deviceId,
      );
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
      if (!allowNegativeStock) {
        throw LocalizedDomainException(
          'error_insufficient_batch_stock',
          values: {'product': product.name},
          fallback: 'Insufficient batch stock for ${product.name}.',
        );
      }
      final provisionalUnitCost =
          await _provisionalDeficitUnitCostInTransaction(
        product: product,
        warehouseId: warehouseId,
        storeId: storeId,
      );
      final counterRow = await db.customSelect(
        '''
        SELECT COUNT(*) AS c
        FROM inventory_stock_deficits
        WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        ''',
        variables: <Variable<Object>>[
          Variable<String>(storeId),
          Variable<String>(warehouseId),
          Variable<String>(product.id),
        ],
      ).getSingle();
      final deficitSequence =
          ((counterRow.data['c'] as num?)?.toInt() ?? 0) + 1;
      final deficitBatchId =
          'deficit:$storeId:$warehouseId:${product.id}:${movementDate.microsecondsSinceEpoch}:$deficitSequence';
      await _ensureDeficitBatchAndRecordInTransaction(
        productId: product.id,
        productName: product.name,
        warehouseId: warehouseId,
        deficitBatchId: deficitBatchId,
        quantity: remaining,
        provisionalUnitCost: provisionalUnitCost,
        createdAt: movementDate,
        storeId: storeId,
        branchId: branchId,
        deviceId: deviceId,
        expiryTracked: product.expiryTrackingEnabled,
        syncStatus: 'pending',
      );
      allocations.add(BatchAllocation(
        batchId: deficitBatchId,
        quantity: remaining,
        supplierBatchNumber: 'NEGATIVE-STOCK-DEFICIT',
        expirationDate: product.expiryTrackingEnabled
            ? DateTime.utc(9999, 12, 31)
            : null,
        unitCost: provisionalUnitCost,
      ));
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
    String branchId = 'main',
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
      if (isDeficitBatchId(batchId)) {
        await _restoreDeficitAllocationInTransaction(
          deficitBatchId: batchId,
          quantity: allocation.quantity,
          restoredAt: restoredAt,
          storeId: storeId,
          warehouseId: warehouseId,
          productId: product.id,
          productName: product.name,
          branchId: branchId,
          deviceId: deviceId,
          postAccountingAdjustments: true,
        );
        continue;
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
      await _refreshBatchLifecycleStatusInTransaction(
        batchId: batchId,
        storeId: storeId,
        updatedAt: restoredAt,
        deviceId: deviceId,
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
    await _refreshBatchLifecycleStatusInTransaction(
      batchId: batchId.trim(),
      storeId: storeId,
      updatedAt: adjustedAt,
      deviceId: deviceId,
    );
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
    bool allowNegativeStock = false,
  }) async {
    final allocations = await allocateUnifiedInTransaction(
      product: product,
      warehouseId: fromWarehouseId,
      quantity: quantity,
      movementDate: transferredAt,
      storeId: storeId,
      deviceId: deviceId,
      branchId: branchId,
      allowNegativeStock: allowNegativeStock,
    );
    final nowText = transferredAt.toUtc().toIso8601String();
    for (final allocation in allocations) {
      final settledAtDestination =
          await _settleOpenDeficitsWithIncomingBatchInTransaction(
        productId: product.id,
        productName: product.name,
        warehouseId: toWarehouseId,
        incomingBatchId: allocation.batchId,
        incomingQuantity: allocation.quantity,
        actualUnitCost: allocation.unitCost,
        settledAt: transferredAt,
        storeId: storeId,
        branchId: branchId,
        deviceId: deviceId,
        postAccountingAdjustments: true,
      );
      final destinationBalanceQuantity =
          allocation.quantity - settledAtDestination;
      final persistedDestinationBalance = destinationBalanceQuantity <= 0.000001
          ? 0.0
          : destinationBalanceQuantity;
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
          persistedDestinationBalance,
          nowText,
          nowText,
          deviceId,
          deviceId,
        ],
      );
      await _refreshBatchLifecycleStatusInTransaction(
        batchId: allocation.batchId,
        storeId: storeId,
        updatedAt: transferredAt,
        deviceId: deviceId,
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
    final deficitRow = await db.customSelect(
      '''
      SELECT COALESCE(SUM(quantity_open), 0) AS quantity,
             COALESCE(SUM(quantity_open * provisional_unit_cost), 0) AS carrying_value
      FROM inventory_stock_deficits
      WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        AND status = 'open' AND quantity_open > 0.000001
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).getSingle();
    final physicalQuantity =
        (batchRow.data['quantity'] as num? ?? 0).toDouble();
    final physicalValue =
        (batchRow.data['carrying_value'] as num? ?? 0).toDouble();
    final deficitQuantity =
        (deficitRow.data['quantity'] as num? ?? 0).toDouble();
    final deficitValue =
        (deficitRow.data['carrying_value'] as num? ?? 0).toDouble();
    return BatchInventoryBalanceCheck(
      productId: productId,
      warehouseId: warehouseId,
      warehouseQuantity:
          (aggregateRow?.data['quantity'] as num? ?? 0).toDouble(),
      batchQuantity: physicalQuantity - deficitQuantity,
      batchCarryingValue: physicalValue - deficitValue,
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

  Future<void> _refreshBatchLifecycleStatusInTransaction({
    required String batchId,
    required String storeId,
    required DateTime updatedAt,
    required String deviceId,
    String syncStatus = 'pending',
  }) async {
    // Negative-stock deficit batches have their own lifecycle/status contract.
    if (isDeficitBatchId(batchId)) return;
    final hasPositiveBalance = await db.customSelect(
      '''
      SELECT 1
      FROM inventory_batch_balances
      WHERE store_id = ? AND batch_id = ? AND quantity > 0.000001
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(batchId),
      ],
    ).getSingleOrNull();
    final nextStatus = hasPositiveBalance == null ? 'depleted' : 'active';
    final currentOpposite = nextStatus == 'depleted' ? 'active' : 'depleted';
    await db.customStatement(
      '''
      UPDATE inventory_batches
      SET status = ?, updated_at = ?, version = version + 1,
          last_modified_by_device_id = ?, sync_status = ?
      WHERE id = ? AND store_id = ? AND status = ?
      ''',
      <Object?>[
        nextStatus,
        updatedAt.toUtc().toIso8601String(),
        deviceId,
        syncStatus,
        batchId,
        storeId,
        currentOpposite,
      ],
    );
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
