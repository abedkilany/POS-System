import 'package:drift/drift.dart';

import '../../models/inventory_reconciliation.dart';
import '../../models/product.dart';
import '../../models/warehouse_inventory.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'warehouse_inventory_repository.dart';

class InventoryReconciliationRepository {
  InventoryReconciliationRepository._();

  static const String backfillMarkerKey = 'warehouse_inventory_backfill_v1';
  static const String backfillBatchId =
      'warehouse_inventory_backfill_adjustment_v1';

  static double _asDouble(Object? value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static int _asInt(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ??
        (double.tryParse(value.toString())?.toInt() ?? 0);
  }

  static Future<List<InventoryReconciliation>> listAll(
    VentioDriftDatabase db, {
    String storeId = '',
    String status = '',
  }) async {
    final conditions = <String>[];
    final variables = <Variable<Object>>[];
    if (storeId.trim().isNotEmpty) {
      conditions.add('store_id = ?');
      variables.add(Variable<String>(storeId.trim()));
    }
    if (status.trim().isNotEmpty) {
      conditions.add('status = ?');
      variables.add(Variable<String>(status.trim()));
    }
    final whereSql = conditions.isEmpty ? '1=1' : conditions.join(' AND ');
    final rows = await db.customSelect('''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             warehouse_id AS warehouseId, product_id AS productId,
             legacy_product_stock AS legacyProductStock,
             ledger_balance AS ledgerBalance,
             warehouse_balance AS warehouseBalance,
             difference, classification, status, created_at AS createdAt,
             resolved_at AS resolvedAt, resolution_note AS resolutionNote
      FROM inventory_reconciliations
      WHERE $whereSql
      ORDER BY created_at DESC, id ASC
    ''', variables: variables).get();
    return rows
        .map((row) => InventoryReconciliation.fromJson(
              Map<String, dynamic>.from(row.data),
            ))
        .toList(growable: false);
  }

  static Future<List<WarehouseInventory>> listInventoryBalances(
    VentioDriftDatabase db, {
    String storeId = '',
    String branchId = '',
    String warehouseId = '',
    String productId = '',
  }) {
    return WarehouseInventoryRepository.listBalances(
      db,
      storeId: storeId,
      branchId: branchId,
      warehouseId: warehouseId,
      productId: productId,
    );
  }

  static Future<List<WarehouseInventory>> listNegativeBalances(
    VentioDriftDatabase db, {
    String storeId = '',
    String warehouseId = '',
  }) async {
    final conditions = <String>['quantity < 0'];
    final variables = <Variable<Object>>[];
    if (storeId.trim().isNotEmpty) {
      conditions.add('store_id = ?');
      variables.add(Variable<String>(storeId.trim()));
    }
    if (warehouseId.trim().isNotEmpty) {
      conditions.add('warehouse_id = ?');
      variables.add(Variable<String>(warehouseId.trim()));
    }
    final whereSql = conditions.join(' AND ');
    final rows = await db.customSelect('''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             warehouse_id AS warehouseId, product_id AS productId,
             quantity, version, created_at AS createdAt,
             updated_at AS updatedAt, device_id AS deviceId,
             sync_status AS syncStatus,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM warehouse_inventory
      WHERE $whereSql
      ORDER BY store_id ASC, warehouse_id ASC, product_id ASC
    ''', variables: variables).get();
    return rows
        .map((row) => WarehouseInventory.fromJson(
              Map<String, dynamic>.from(row.data),
            ))
        .toList(growable: false);
  }

  static Future<List<Product>> listProductsWithoutInventoryRow(
    VentioDriftDatabase db, {
    String storeId = '',
  }) async {
    final conditions = <String>['wi.id IS NULL', 'p.deleted_at = \'\''];
    final variables = <Variable<Object>>[];
    if (storeId.trim().isNotEmpty) {
      conditions.add('p.store_id = ?');
      variables.add(Variable<String>(storeId.trim()));
    }
    final whereSql = conditions.join(' AND ');
    final rows = await db.customSelect('''
      SELECT p.id, p.name, p.code, p.name_en AS nameEn, p.name_ar AS nameAr,
             p.price, p.cost, p.original_cost AS originalCost,
             p.cost_currency AS costCurrency, p.usd_cost AS usdCost,
             p.cost_exchange_rate_at_entry AS costExchangeRateAtEntry,
             p.original_price AS originalPrice,
             p.original_currency AS originalCurrency,
             p.usd_price AS usdPrice,
             p.exchange_rate_at_entry AS exchangeRateAtEntry,
             p.stock, p.category, p.barcode, p.brand, p.supplier,
             p.description, p.unit, p.quantity_type AS quantityType,
             p.low_stock_threshold AS lowStockThreshold,
             CASE WHEN p.track_stock = 1 THEN 1 ELSE 0 END AS trackStock,
             CASE WHEN p.is_active = 1 THEN 1 ELSE 0 END AS isActive,
             p.image_path AS imagePath, p.created_at AS createdAt,
             p.updated_at AS updatedAt, p.deleted_at AS deletedAt,
             p.device_id AS deviceId, p.sync_status AS syncStatus,
             p.store_id AS storeId, p.branch_id AS branchId, p.version,
             p.last_modified_by_device_id AS lastModifiedByDeviceId
      FROM products p
      LEFT JOIN warehouse_inventory wi
        ON wi.product_id = p.id AND wi.store_id = p.store_id
      WHERE $whereSql
      GROUP BY p.id
      ORDER BY lower(p.name) ASC, p.id ASC
    ''', variables: variables).get();
    return rows
        .map((row) => Product.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  static Future<void> backfillFromLegacyData(
    VentioDriftDatabase db, {
    String? forceMarkerKey,
  }) async {
    final markerKey = forceMarkerKey ?? backfillMarkerKey;
    final marker = await _metaValue(db, markerKey);
    if (marker == 'done') return;

    await db.transaction(() async {
      final products = await db.customSelect('''
        SELECT id, name, store_id AS storeId, branch_id AS branchId, stock
        FROM products
        WHERE deleted_at = ''
      ''').get();
      final movementRows = await db.customSelect('''
        SELECT store_id AS storeId,
               COALESCE(NULLIF(branch_id, ''), 'main') AS branchId,
               COALESCE(NULLIF(warehouse_id, ''), 'main') AS warehouseId,
               product_id AS productId,
               COALESCE(SUM(quantity), 0) AS quantity,
               MAX(CASE WHEN trim(warehouse_id) = '' THEN 1 ELSE 0 END)
                 AS missingWarehouse
        FROM stock_movements
        WHERE deleted_at = ''
        GROUP BY store_id,
                 COALESCE(NULLIF(branch_id, ''), 'main'),
                 COALESCE(NULLIF(warehouse_id, ''), 'main'),
                 product_id
      ''').get();

      final groupedMovements = <String, List<QueryRow>>{};
      for (final row in movementRows) {
        final key =
            '${row.read<String>('storeId')}::${row.read<String>('productId')}';
        groupedMovements.putIfAbsent(key, () => <QueryRow>[]).add(row);
      }

      for (final productRow in products) {
        final storeId = productRow.read<String>('storeId');
        final branchId = productRow.read<String>('branchId');
        final productId = productRow.read<String>('id');
        final legacyStock = _asDouble(productRow.data['stock']);
        final productKey = '$storeId::$productId';
        final rowsForProduct = groupedMovements[productKey] ?? const <QueryRow>[];
        var ledgerBalance = 0.0;
        var hasMissingWarehouse = false;

        for (final row in rowsForProduct) {
          final warehouseId = row.read<String>('warehouseId');
          final quantity = _asDouble(row.data['quantity']);
          ledgerBalance += quantity;
          hasMissingWarehouse =
              hasMissingWarehouse || _asInt(row.data['missingWarehouse']) == 1;
          await WarehouseInventoryRepository.upsert(
            db,
            WarehouseInventory(
              id: ['wi', storeId, warehouseId, productId].join('_'),
              storeId: storeId,
              branchId: row.read<String>('branchId').trim().isEmpty
                  ? branchId
                  : row.read<String>('branchId'),
              warehouseId: warehouseId,
              productId: productId,
              quantity: quantity,
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
              deviceId: '',
              syncStatus: 'synced',
              lastModifiedByDeviceId: '',
            ),
          );
        }

        final diff = legacyStock - ledgerBalance;
        if (diff.abs() > 0.000001) {
          final adjustmentExists = await _hasBackfillAdjustment(
            db,
            batchId: backfillBatchId,
            storeId: storeId,
            warehouseId: 'main',
            productId: productId,
          );
          if (!adjustmentExists) {
            final mainIdentity =
                await WarehouseInventoryRepository.getByIdentity(
              db,
              storeId: storeId,
              warehouseId: 'main',
              productId: productId,
            );
            final base = mainIdentity?.quantity ?? 0;
            final now = DateTime.now().toUtc();
            await WarehouseInventoryRepository.upsert(
              db,
              WarehouseInventory(
                id: mainIdentity?.id ??
                    ['wi', storeId, 'main', productId].join('_'),
                storeId: storeId,
                branchId: branchId.isEmpty ? 'main' : branchId,
                warehouseId: 'main',
                productId: productId,
                quantity: base + diff,
                version: (mainIdentity?.version ?? 0) + 1,
                createdAt: mainIdentity?.createdAt ?? now,
                updatedAt: now,
                deviceId: '',
                syncStatus: 'synced',
                lastModifiedByDeviceId: '',
              ),
            );
            await _recordBackfillAdjustment(
              db,
              batchId: backfillBatchId,
              storeId: storeId,
              branchId: branchId.isEmpty ? 'main' : branchId,
              warehouseId: 'main',
              productId: productId,
              legacyProductStock: legacyStock,
              ledgerBalance: ledgerBalance,
              appliedDelta: diff,
            );
          }
        }

        final classification = legacyStock < 0
            ? 'negative_legacy_balance'
            : rowsForProduct.isEmpty && legacyStock != 0
                ? 'legacy_unassigned'
                : hasMissingWarehouse
                    ? 'missing_warehouse'
                    : (diff.abs() > 0.000001 ? 'ledger_mismatch' : '');
        if (classification.isNotEmpty) {
          await _upsertReconciliation(
            db,
            InventoryReconciliation(
              id: ['recon', storeId, productId].join('_'),
              storeId: storeId,
              branchId: branchId.isEmpty ? 'main' : branchId,
              warehouseId: rowsForProduct.isEmpty
                  ? 'main'
                  : rowsForProduct.first.read<String>('warehouseId'),
              productId: productId,
              legacyProductStock: legacyStock,
              ledgerBalance: ledgerBalance,
              warehouseBalance: ledgerBalance,
              difference: diff,
              classification: classification,
              status: 'open',
              createdAt: DateTime.now().toUtc(),
              resolutionNote: '',
            ),
          );
        }
      }

      final inventoryProducts = <String>{for (final row in products) row.read<String>('id')};
      final invalidRows = await db.customSelect('''
        SELECT store_id AS storeId,
               COALESCE(NULLIF(branch_id, ''), 'main') AS branchId,
               COALESCE(NULLIF(warehouse_id, ''), 'main') AS warehouseId,
               product_id AS productId,
               COALESCE(SUM(quantity), 0) AS quantity
        FROM stock_movements
        WHERE deleted_at = ''
          AND product_id NOT IN (${List.filled(inventoryProducts.isEmpty ? 1 : inventoryProducts.length, '?').join(', ')})
        GROUP BY store_id,
                 COALESCE(NULLIF(branch_id, ''), 'main'),
                 COALESCE(NULLIF(warehouse_id, ''), 'main'),
                 product_id
      ''', variables: inventoryProducts.isEmpty
          ? <Variable<Object>>[const Variable<String>('')]
          : inventoryProducts.map((id) => Variable<String>(id)).toList()).get();
      for (final row in invalidRows) {
        final productId = row.read<String>('productId');
        await _upsertReconciliation(
          db,
          InventoryReconciliation(
            id: 'recon_${row.read<String>('storeId')}_$productId',
            storeId: row.read<String>('storeId'),
            branchId: row.read<String>('branchId'),
            warehouseId: row.read<String>('warehouseId'),
            productId: productId,
            legacyProductStock: 0,
            ledgerBalance: _asDouble(row.data['quantity']),
            warehouseBalance: 0,
            difference: -_asDouble(row.data['quantity']),
            classification: 'invalid_product_reference',
            status: 'open',
            createdAt: DateTime.now().toUtc(),
            resolutionNote: '',
          ),
        );
      }

      await _setMetaValue(db, markerKey, 'done');
    });
  }

  static Future<bool> _hasBackfillAdjustment(
    VentioDriftDatabase db, {
    required String batchId,
    required String storeId,
    required String warehouseId,
    required String productId,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT id
      FROM inventory_migration_adjustments
      WHERE migration_batch_id = ?
        AND store_id = ?
        AND warehouse_id = ?
        AND product_id = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(batchId),
        Variable<String>(storeId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
      ],
    ).get();
    return rows.isNotEmpty;
  }

  static Future<void> _recordBackfillAdjustment(
    VentioDriftDatabase db, {
    required String batchId,
    required String storeId,
    required String branchId,
    required String warehouseId,
    required String productId,
    required double legacyProductStock,
    required double ledgerBalance,
    required double appliedDelta,
  }) async {
    final now = DateTime.now().toUtc();
    await db.customInsert(
      '''
      INSERT INTO inventory_migration_adjustments
        (id, migration_batch_id, store_id, branch_id, warehouse_id,
         product_id, legacy_product_stock, ledger_balance, applied_delta,
         created_at, updated_at, notes)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>('adj_${batchId}_${storeId}_${warehouseId}_$productId'),
        Variable<String>(batchId),
        Variable<String>(storeId),
        Variable<String>(branchId),
        Variable<String>(warehouseId),
        Variable<String>(productId),
        Variable<double>(legacyProductStock),
        Variable<double>(ledgerBalance),
        Variable<double>(appliedDelta),
        Variable<String>(now.toIso8601String()),
        Variable<String>(now.toIso8601String()),
        Variable<String>('backfill_adjustment'),
      ],
    );
  }

  static Future<void> _upsertReconciliation(
    VentioDriftDatabase db,
    InventoryReconciliation reconciliation,
  ) async {
    await db.customInsert(
      '''
      INSERT INTO inventory_reconciliations
        (id, store_id, branch_id, warehouse_id, product_id,
         legacy_product_stock, ledger_balance, warehouse_balance, difference,
         classification, status, created_at, resolved_at, resolution_note)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(store_id, warehouse_id, product_id) DO UPDATE SET
        branch_id = excluded.branch_id,
        legacy_product_stock = excluded.legacy_product_stock,
        ledger_balance = excluded.ledger_balance,
        warehouse_balance = excluded.warehouse_balance,
        difference = excluded.difference,
        classification = excluded.classification,
        status = excluded.status,
        created_at = excluded.created_at,
        resolved_at = excluded.resolved_at,
        resolution_note = excluded.resolution_note
      ''',
      variables: <Variable<Object>>[
        Variable<String>(reconciliation.id),
        Variable<String>(reconciliation.storeId),
        Variable<String>(reconciliation.branchId),
        Variable<String>(reconciliation.warehouseId),
        Variable<String>(reconciliation.productId),
        Variable<double>(reconciliation.legacyProductStock),
        Variable<double>(reconciliation.ledgerBalance),
        Variable<double>(reconciliation.warehouseBalance),
        Variable<double>(reconciliation.difference),
        Variable<String>(reconciliation.classification),
        Variable<String>(reconciliation.status),
        Variable<String>(reconciliation.createdAt.toIso8601String()),
        Variable<String>(reconciliation.resolvedAt?.toIso8601String() ?? ''),
        Variable<String>(reconciliation.resolutionNote),
      ],
    );
  }

  static Future<String?> _metaValue(
    VentioDriftDatabase db,
    String key,
  ) async {
    final rows = await db.customSelect(
      'SELECT value FROM migration_meta WHERE key = ?',
      variables: <Variable<Object>>[Variable<String>(key)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.read<String>('value');
  }

  static Future<void> _setMetaValue(
    VentioDriftDatabase db,
    String key,
    String value,
  ) async {
    await db.customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        Variable<String>(key),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }
}
