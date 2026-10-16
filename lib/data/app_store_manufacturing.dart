part of 'app_store.dart';

bool _bomChangesInventoryClassification(
  BillOfMaterials previous,
  BillOfMaterials next,
) {
  if (previous.outputProductId != next.outputProductId) return true;

  final previousComponents = previous.components
      .map((component) => component.productId.trim())
      .where((productId) => productId.isNotEmpty)
      .toSet();
  final nextComponents = next.components
      .map((component) => component.productId.trim())
      .where((productId) => productId.isNotEmpty)
      .toSet();
  if (previousComponents.length != nextComponents.length) return true;
  return !previousComponents.containsAll(nextComponents);
}

extension _AppStoreSplitManufacturing on AppStore {
  Future<double> estimatedUnifiedBatchUnitCostForProduct(
    Product product, {
    String warehouseId = '',
    double requiredQuantity = 0,
  }) =>
      _estimatedUnifiedBatchUnitCostForProduct(
        product,
        warehouseId: warehouseId,
        requiredQuantity: requiredQuantity,
      );

  Future<double> _estimatedUnifiedBatchUnitCostForProduct(
    Product product, {
    String warehouseId = '',
    double requiredQuantity = 0,
  }) async {
    double fallback() {
      final cost = _productCostFor(product.id);
      if (cost.averageCost > 0) return cost.averageCost;
      if (cost.lastCost > 0) return cost.lastCost;
      if (product.usdCost > 0) return product.usdCost;
      if (product.cost > 0) return product.cost;
      return 0;
    }

    if (!product.trackStock ||
        !LocalDatabaseService.isSqliteAuthoritative ||
        SqliteMigrationManager.database == null) {
      return fallback();
    }
    final db = SqliteMigrationManager.database!;
    final normalizedWarehouse = warehouseId.trim();
    if (normalizedWarehouse.isNotEmpty && requiredQuantity > 0.000001) {
      final preview =
          await BatchInventoryService(db).previewUnifiedAllocationInTransaction(
        product: product,
        warehouseId: normalizedWarehouse,
        quantity: requiredQuantity,
        movementDate: DateTime.now(),
        storeId: appIdentity.storeId,
        includeProvisionalShortage: _storeProfile.allowNegativeStock,
      );
      if ((!preview.hasShortage && preview.physicalQuantity > 0.000001) ||
          (_storeProfile.allowNegativeStock &&
              preview.usesProvisionalCost &&
              preview.provisionalUnitCost > 0.000001)) {
        return preview.unitCost;
      }
    }
    final today = DateTime.now().toUtc();
    final todayText =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final expiryPredicate = product.expiryTrackingEnabled
        ? "trim(b.expiration_date) <> '' AND substr(b.expiration_date, 1, 10) >= ?"
        : "trim(b.expiration_date) = ''";
    final warehousePredicate =
        normalizedWarehouse.isEmpty ? '' : 'AND bb.warehouse_id = ?';
    final row = await db.customSelect(
      '''
      SELECT
        COALESCE(SUM((bb.quantity - bb.reserved_quantity) * b.unit_cost), 0)
          AS carrying_value,
        COALESCE(SUM(bb.quantity - bb.reserved_quantity), 0) AS quantity
      FROM inventory_batch_balances bb
      INNER JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.store_id = bb.store_id AND b.product_id = bb.product_id
      WHERE bb.store_id = ? AND bb.product_id = ?
        $warehousePredicate
        AND b.status = 'active'
        AND b.source_type <> 'inventory_deficit'
        AND b.id NOT LIKE 'deficit:%'
        AND (bb.quantity - bb.reserved_quantity) > 0.000001
        AND $expiryPredicate
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(product.id),
        if (normalizedWarehouse.isNotEmpty)
          Variable<String>(normalizedWarehouse),
        if (product.expiryTrackingEnabled) Variable<String>(todayText),
      ],
    ).getSingle();
    final quantity = (row.data['quantity'] as num? ?? 0).toDouble();
    final value = (row.data['carrying_value'] as num? ?? 0).toDouble();
    if (quantity > 0.000001 && value >= 0) return value / quantity;
    return fallback();
  }

  Future<void> _repairZeroCostManufacturingInputBatchesInTransaction(
    VentioDriftDatabase sqliteDb, {
    required BatchInventoryService batchService,
    required Product product,
    required String warehouseId,
    required double requiredQuantity,
    required DateTime repairedAt,
    required String referenceId,
    required String referenceNo,
  }) async {
    if (!product.trackStock || requiredQuantity <= 0.000001) return;
    final startOfMovementDay =
        '${repairedAt.year.toString().padLeft(4, '0')}-${repairedAt.month.toString().padLeft(2, '0')}-${repairedAt.day.toString().padLeft(2, '0')}';
    final expiryPredicate = product.expiryTrackingEnabled
        ? "trim(b.expiration_date) <> '' AND substr(b.expiration_date, 1, 10) >= ?"
        : "trim(b.expiration_date) = ''";
    final ordering = product.expiryTrackingEnabled
        ? '''substr(b.expiration_date, 1, 10) ASC,
             CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END ASC,
             b.id ASC'''
        : '''CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END ASC,
             b.id ASC''';
    final rows = await sqliteDb.customSelect(
      '''
      SELECT b.id AS batch_id, b.source_type, b.source_id, b.unit_cost,
             bb.quantity, bb.reserved_quantity
      FROM inventory_batch_balances bb
      JOIN inventory_batches b ON b.id = bb.batch_id
        AND b.product_id = bb.product_id AND b.store_id = bb.store_id
      WHERE bb.store_id = ? AND bb.warehouse_id = ? AND bb.product_id = ?
        AND b.status = 'active'
        AND b.source_type <> 'inventory_deficit'
        AND b.id NOT LIKE 'deficit:%'
        AND (bb.quantity - bb.reserved_quantity) > 0.000001
        AND $expiryPredicate
      ORDER BY $ordering
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
        if (product.expiryTrackingEnabled) Variable<String>(startOfMovementDay),
      ],
    ).get();

    var remaining = requiredQuantity;
    for (final row in rows) {
      if (remaining <= 0.000001) break;
      final available =
          row.read<double>('quantity') - row.read<double>('reserved_quantity');
      final used = available < remaining ? available : remaining;
      if (used <= 0) continue;
      remaining -= used;
      final existingUnitCost = row.read<double>('unit_cost');
      if (existingUnitCost > 0.000001) continue;

      final batchId = row.read<String>('batch_id');
      final sourceType = row.read<String>('source_type').trim().toLowerCase();
      if (sourceType != 'inventory_count') {
        throw LocalizedDomainException(
          'error_manufacturing_zero_cost_physical_batch',
          values: <String, Object?>{
            'product': product.name,
            'batch': batchId,
          },
          fallback:
              'Manufacturing cannot consume zero-cost physical batch $batchId for ${product.name}. Revalue or correct that batch first.',
        );
      }

      // Automatic repair is safe only while no historical outbound movement
      // has already consumed this zero-cost count batch. Otherwise a repair of
      // the remaining stock alone would leave past COGS/manufacturing history
      // at zero and silently rewrite only part of the lineage.
      final priorOutbound = await sqliteDb.customSelect(
        '''
        SELECT COUNT(*) AS c
        FROM stock_movements
        WHERE store_id = ? AND product_id = ? AND warehouse_id = ?
          AND batch_id = ? AND deleted_at = '' AND quantity < -0.000001
        ''',
        variables: <Variable<Object>>[
          Variable<String>(appIdentity.storeId),
          Variable<String>(product.id),
          Variable<String>(warehouseId),
          Variable<String>(batchId),
        ],
      ).getSingle();
      final outboundCount = (priorOutbound.data['c'] as num? ?? 0).toInt();
      if (outboundCount > 0) {
        throw LocalizedDomainException(
          'error_manufacturing_zero_cost_batch_already_consumed',
          values: <String, Object?>{
            'product': product.name,
            'batch': batchId,
          },
          fallback:
              'Zero-cost batch $batchId for ${product.name} has already been consumed by another movement. Run an explicit stock-cost repair before manufacturing.',
        );
      }

      // If the count movement itself carried a positive cost, GL already
      // contains that value and only the Batch row is stale/corrupt. In that
      // case restore the Batch cost without posting another gain. Otherwise
      // this was a true zero-value count overage and the repair must add both
      // Batch carrying value and the matching inventory revaluation journal.
      final sourceValueRow = await sqliteDb.customSelect(
        '''
        SELECT COALESCE(SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END), 0)
                 AS source_quantity,
               COALESCE(SUM(CASE WHEN quantity > 0
                                 THEN quantity * unit_cost ELSE 0 END), 0)
                 AS source_value
        FROM stock_movements
        WHERE store_id = ? AND product_id = ? AND warehouse_id = ?
          AND batch_id = ? AND deleted_at = ''
        ''',
        variables: <Variable<Object>>[
          Variable<String>(appIdentity.storeId),
          Variable<String>(product.id),
          Variable<String>(warehouseId),
          Variable<String>(batchId),
        ],
      ).getSingle();
      final sourceQuantity =
          (sourceValueRow.data['source_quantity'] as num? ?? 0).toDouble();
      final sourceValue =
          (sourceValueRow.data['source_value'] as num? ?? 0).toDouble();
      final sourceUnitCost =
          sourceQuantity <= 0.000001 ? 0.0 : sourceValue / sourceQuantity;
      final referenceUnitCost = sourceUnitCost > 0.000001
          ? sourceUnitCost
          : await batchService.resolveReferenceUnitCostInTransaction(
              product: product,
              warehouseId: warehouseId,
              storeId: appIdentity.storeId,
            );
      if (referenceUnitCost <= 0.000001) {
        throw LocalizedDomainException(
          'error_manufacturing_material_cost_missing',
          values: <String, Object?>{'product': product.name},
          fallback:
              'Manufacturing cost is missing for ${product.name}. Set a valid reference cost or receive a costed batch first.',
        );
      }

      final currentBatchQuantity = row.read<double>('quantity');
      final revaluationValue = sourceUnitCost > 0.000001
          ? 0.0
          : currentBatchQuantity * referenceUnitCost;
      final updated = await sqliteDb.customUpdate(
        '''
        UPDATE inventory_batches
        SET unit_cost = ?, cost_currency = 'USD', exchange_rate = 1,
            updated_at = ?, device_id = ?, last_modified_by_device_id = ?,
            sync_status = 'pending', version = version + 1
        WHERE id = ? AND store_id = ? AND product_id = ?
          AND unit_cost <= 0.000001
        ''',
        variables: <Variable<Object>>[
          Variable<double>(referenceUnitCost),
          Variable<String>(repairedAt.toUtc().toIso8601String()),
          Variable<String>(_deviceId),
          Variable<String>(_deviceId),
          Variable<String>(batchId),
          Variable<String>(appIdentity.storeId),
          Variable<String>(product.id),
        ],
        updates: const {},
      );
      if (updated != 1) {
        throw const LocalizedDomainException(
          'error_batch_concurrent_change',
          fallback: 'Batch cost changed while repairing manufacturing input.',
        );
      }

      if (revaluationValue > 0.000001) {
        final journalId = await AccountingService
            .recordInventoryBatchRevaluationInTransaction(
          database: sqliteDb,
          entryDate: repairedAt,
          referenceId: '$referenceId:batch-cost-repair:$batchId',
          referenceNo: referenceNo,
          productId: product.id,
          productName: product.name,
          batchId: batchId,
          valueDelta: revaluationValue,
          createdBy: _activeUser?.fullName ?? _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          reason:
              'Automatic repair of zero-cost inventory-count batch before manufacturing.',
        );
        if (journalId.trim().isEmpty) {
          throw StateError(
            'Zero-cost Batch repair requires a posted inventory revaluation journal.',
          );
        }
      }
    }
  }

  Future<BillOfMaterials> estimateBillOfMaterialsSnapshot(
    BillOfMaterials bom, {
    String warehouseId = '',
  }) async {
    final components = <BillOfMaterialsLine>[];
    for (final component in bom.components) {
      final product = _findProductById(component.productId);
      if (product == null) {
        components.add(component);
        continue;
      }
      final estimatedUnitCost = await _estimatedUnifiedBatchUnitCostForProduct(
        product,
        warehouseId: warehouseId,
        requiredQuantity: component.quantity,
      );
      components.add(component.copyWith(
        productName: product.name,
        unitCost: estimatedUnitCost,
      ));
    }
    return bom.copyWith(components: components);
  }

  Future<double> estimateBillOfMaterialsUnitCost(
    BillOfMaterials bom, {
    String warehouseId = '',
  }) async {
    final estimated = await estimateBillOfMaterialsSnapshot(
      bom,
      warehouseId: warehouseId,
    );
    return estimated.unitCost;
  }

  Future<BillOfMaterials> createBillOfMaterials({
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    if (name.trim().isEmpty) throw ArgumentError('BOM name is required.');
    if (outputQuantity <= 0) {
      throw ArgumentError('Output quantity must be greater than zero.');
    }
    if (components.isEmpty) {
      throw ArgumentError('BOM must contain at least one component.');
    }
    final output = _findProductById(outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final cleanedComponents = <BillOfMaterialsLine>[];
    for (final component in components) {
      if (component.quantity <= 0) {
        throw ArgumentError('Component quantity must be greater than zero.');
      }
      if (component.productId == outputProductId) {
        throw ArgumentError(
          'Output product cannot be used as a component in the same BOM.',
        );
      }
      final product = _findProductById(component.productId);
      if (product == null) {
        throw ArgumentError('Component product was not found.');
      }
      cleanedComponents.add(
        component.copyWith(
          productName: product.name,
          unitCost: await _estimatedUnifiedBatchUnitCostForProduct(product),
        ),
      );
    }
    final now = DateTime.now();
    final bom = _withSyncMeta<BillOfMaterials>(
      BillOfMaterials(
        id: '${now.microsecondsSinceEpoch}-bom',
        name: name.trim(),
        outputProductId: output.id,
        outputProductName: output.name,
        outputQuantity: outputQuantity,
        components: cleanedComponents,
        notes: notes.trim(),
      ),
      now,
      isCreate: true,
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      try {
        await sqliteDb.transaction(() async {
          await BusinessSqliteStore.upsertBillOfMaterialsPayloadInTransaction(
            sqliteDb,
            bom.toJson(),
            id: bom.id,
            payloadJson: jsonEncode(bom.toJson()),
            createdAt: bom.createdAt.toIso8601String(),
            updatedAt: bom.updatedAt.toIso8601String(),
            deletedAt: bom.deletedAt?.toIso8601String() ?? '',
            sortIndex: _billsOfMaterials.length,
          );
          await _reconcileInventoryAccountsAfterBomChange(
            bom,
            database: sqliteDb,
            withinExistingTransaction: true,
          );
        });
      } catch (_) {
        _forgetSqliteDirtyBusinessRow(AppStore._billsOfMaterialsKey, bom.id);
        rethrow;
      }
      _forgetSqliteDirtyBusinessRow(AppStore._billsOfMaterialsKey, bom.id);
      _billsOfMaterials.add(bom);
      _recordSyncChange(
        entityType: 'bill_of_materials',
        entityId: bom.id,
        operation: 'create',
        payload: bom.toJson(),
      );
      await _saveDirty(sync: true);
    } else {
      _billsOfMaterials.add(bom);
      _recordSyncChange(
        entityType: 'bill_of_materials',
        entityId: bom.id,
        operation: 'create',
        payload: bom.toJson(),
      );
      await _saveDirty(billsOfMaterials: true, sync: true);
    }
    _invalidateDerivedDataCaches();
    notifyListeners();
    return bom;
  }

  Future<BillOfMaterials> updateBillOfMaterials({
    required String id,
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    final index = _billsOfMaterials.indexWhere((item) => item.id == id);
    if (index == -1 || _billsOfMaterials[index].isDeleted) {
      throw ArgumentError('BOM was not found.');
    }
    if (name.trim().isEmpty) throw ArgumentError('BOM name is required.');
    if (outputQuantity <= 0) {
      throw ArgumentError('Output quantity must be greater than zero.');
    }
    if (components.isEmpty) {
      throw ArgumentError('BOM must contain at least one component.');
    }
    final output = _findProductById(outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final cleanedComponents = <BillOfMaterialsLine>[];
    for (final component in components) {
      if (component.quantity <= 0) {
        throw ArgumentError('Component quantity must be greater than zero.');
      }
      if (component.productId == outputProductId) {
        throw ArgumentError(
          'Output product cannot be used as a component in the same BOM.',
        );
      }
      final product = _findProductById(component.productId);
      if (product == null) {
        throw ArgumentError('Component product was not found.');
      }
      cleanedComponents.add(component.copyWith(
        productName: product.name,
        unitCost: await _estimatedUnifiedBatchUnitCostForProduct(product),
      ));
    }
    final now = DateTime.now();
    final previous = _billsOfMaterials[index];
    final updated = _withSyncMeta<BillOfMaterials>(
      previous.copyWith(
        name: name.trim(),
        outputProductId: output.id,
        outputProductName: output.name,
        outputQuantity: outputQuantity,
        components: cleanedComponents,
        notes: notes.trim(),
        updatedAt: now,
      ),
      now,
      isCreate: false,
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      try {
        await sqliteDb.transaction(() async {
          await BusinessSqliteStore.upsertBillOfMaterialsPayloadInTransaction(
            sqliteDb,
            updated.toJson(),
            id: updated.id,
            payloadJson: jsonEncode(updated.toJson()),
            createdAt: updated.createdAt.toIso8601String(),
            updatedAt: updated.updatedAt.toIso8601String(),
            deletedAt: updated.deletedAt?.toIso8601String() ?? '',
            sortIndex: index,
          );
          // A name, note, quantity, or component-cost edit does not change
          // the semantic inventory account of any product. Do not block
          // harmless metadata edits because of an unrelated old GL drift.
          if (_bomChangesInventoryClassification(previous, updated)) {
            await _reconcileInventoryAccountsAfterBomChange(
              updated,
              database: sqliteDb,
              withinExistingTransaction: true,
            );
          }
        });
      } catch (_) {
        _forgetSqliteDirtyBusinessRow(
            AppStore._billsOfMaterialsKey, updated.id);
        rethrow;
      }
      _forgetSqliteDirtyBusinessRow(AppStore._billsOfMaterialsKey, updated.id);
      _billsOfMaterials[index] = updated;
      _recordSyncChange(
        entityType: 'bill_of_materials',
        entityId: updated.id,
        operation: 'update',
        payload: updated.toJson(),
      );
      await _saveDirty(sync: true);
    } else {
      _billsOfMaterials[index] = updated;
      _recordSyncChange(
        entityType: 'bill_of_materials',
        entityId: updated.id,
        operation: 'update',
        payload: updated.toJson(),
      );
      await _saveDirty(billsOfMaterials: true, sync: true);
    }
    _invalidateDerivedDataCaches();
    notifyListeners();
    return updated;
  }

  Future<void> deleteBillOfMaterials(String id) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    final index = _billsOfMaterials.indexWhere((item) => item.id == id);
    if (index == -1 || _billsOfMaterials[index].isDeleted) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<BillOfMaterials>(
      _billsOfMaterials[index].copyWith(
        isActive: false,
        deletedAt: now,
        updatedAt: now,
      ),
      now,
      isCreate: false,
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      try {
        await sqliteDb.transaction(() async {
          await BusinessSqliteStore.upsertBillOfMaterialsPayloadInTransaction(
            sqliteDb,
            deleted.toJson(),
            id: deleted.id,
            payloadJson: jsonEncode(deleted.toJson()),
            createdAt: deleted.createdAt.toIso8601String(),
            updatedAt: deleted.updatedAt.toIso8601String(),
            deletedAt: deleted.deletedAt?.toIso8601String() ?? '',
            sortIndex: index,
          );
          await _reconcileInventoryAccountsAfterBomChange(
            deleted,
            database: sqliteDb,
            withinExistingTransaction: true,
          );
        });
      } catch (_) {
        _forgetSqliteDirtyBusinessRow(
            AppStore._billsOfMaterialsKey, deleted.id);
        rethrow;
      }
      _forgetSqliteDirtyBusinessRow(AppStore._billsOfMaterialsKey, deleted.id);
      _billsOfMaterials[index] = deleted;
      _recordSyncChange(
        entityType: 'bill_of_materials',
        entityId: deleted.id,
        operation: 'delete',
        payload: deleted.toJson(),
      );
      await _saveDirty(sync: true);
    } else {
      _billsOfMaterials[index] = deleted;
      _recordSyncChange(
        entityType: 'bill_of_materials',
        entityId: deleted.id,
        operation: 'delete',
        payload: deleted.toJson(),
      );
      await _saveDirty(billsOfMaterials: true, sync: true);
    }
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  Future<void> deleteManufacturingOrder(String id) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    final index = _manufacturingOrders.indexWhere((item) => item.id == id);
    if (index == -1 || _manufacturingOrders[index].isDeleted) return;

    final existing = _manufacturingOrders[index];
    final status = existing.status.trim().toLowerCase();
    if (<String>{'completed', 'complete', 'reversed'}.contains(status) ||
        status == 'posted') {
      throw StateError(
        'Posted or reversed manufacturing orders are retained for audit and cannot be deleted.',
      );
    }

    final now = DateTime.now();
    final deleted = _withSyncMeta<ManufacturingOrder>(
      existing.copyWith(
        deletedAt: now,
        updatedAt: now,
      ),
      now,
      isCreate: false,
      clearDeletedAt: false,
    );

    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      await sqliteDb.transaction(() async {
        await BusinessSqliteStore.upsertManufacturingOrderPayloadInTransaction(
          sqliteDb,
          deleted.toJson(),
          id: deleted.id,
          payloadJson: jsonEncode(deleted.toJson()),
          createdAt: deleted.createdAt.toIso8601String(),
          updatedAt: deleted.updatedAt.toIso8601String(),
          deletedAt: deleted.deletedAt?.toIso8601String() ?? '',
          sortIndex: 0,
        );
      });
      _manufacturingOrders[index] = deleted;
      _recordSyncChange(
        entityType: 'manufacturing_order',
        entityId: deleted.id,
        operation: 'delete',
        payload: deleted.toJson(),
      );
      _invalidateDerivedDataCaches();
      notifyListeners();
      return;
    }

    _manufacturingOrders[index] = deleted;
    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: deleted.id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(manufacturingOrders: true, sync: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }
}
