part of 'app_store.dart';

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
      final cost = productCostFor(product.id);
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
      final preview = await BatchInventoryService(db)
          .previewUnifiedAllocationInTransaction(
        product: product,
        warehouseId: normalizedWarehouse,
        quantity: requiredQuantity,
        movementDate: DateTime.now(),
        storeId: appIdentity.storeId,
      );
      if (!preview.hasShortage && preview.physicalQuantity > 0.000001) {
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
    final updated = _withSyncMeta<BillOfMaterials>(
      _billsOfMaterials[index].copyWith(
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
          await _reconcileInventoryAccountsAfterBomChange(
            updated,
            database: sqliteDb,
            withinExistingTransaction: true,
          );
        });
      } catch (_) {
        _forgetSqliteDirtyBusinessRow(AppStore._billsOfMaterialsKey, updated.id);
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
        _forgetSqliteDirtyBusinessRow(AppStore._billsOfMaterialsKey, deleted.id);
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

Future<ManufacturingOrder> updateManufacturingOrder({
    required String id,
    required String bomId,
    required double quantity,
    required String rawMaterialsWarehouseId,
    required String rawMaterialsWarehouseName,
    required String finishedGoodsWarehouseId,
    required String finishedGoodsWarehouseName,
    String notes = '',
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    final index = _manufacturingOrders.indexWhere((item) => item.id == id);
    if (index == -1 || _manufacturingOrders[index].isDeleted) {
      throw ArgumentError('Manufacturing order was not found.');
    }
    final existing = _manufacturingOrders[index];
    final status = existing.status.trim().toLowerCase();
    if (<String>{'completed', 'complete', 'reversed'}.contains(status) ||
        status == 'posted') {
      throw StateError(
        'Completed manufacturing orders cannot be edited because inventory movements have already been posted.',
      );
    }
    if (quantity <= 0) {
      throw ArgumentError('Manufacturing quantity must be greater than zero.');
    }
    final bom = _billsOfMaterials.firstWhere(
      (item) => item.id == bomId && !item.isDeleted && item.isActive,
      orElse: () => throw ArgumentError('BOM was not found.'),
    );
    final output = _findProductById(bom.outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final rawWarehouse =
        resolveWarehouseForPurchase(warehouseId: rawMaterialsWarehouseId);
    final finishedWarehouse =
        resolveWarehouseForSale(warehouseId: finishedGoodsWarehouseId);
    final now = DateTime.now();
    final updated = _withSyncMeta<ManufacturingOrder>(
      existing.copyWith(
        bomId: bom.id,
        bomName: bom.name,
        outputProductId: output.id,
        outputProductName: output.name,
        quantity: quantity,
        rawMaterialsWarehouseId: rawWarehouse.id,
        rawMaterialsWarehouseName: rawMaterialsWarehouseName.trim().isEmpty
            ? rawWarehouse.name
            : rawMaterialsWarehouseName.trim(),
        finishedGoodsWarehouseId: finishedWarehouse.id,
        finishedGoodsWarehouseName: finishedGoodsWarehouseName.trim().isEmpty
            ? finishedWarehouse.name
            : finishedGoodsWarehouseName.trim(),
        notes: notes.trim(),
        updatedAt: now,
      ),
      now,
      isCreate: false,
    );
    _manufacturingOrders[index] = updated;
    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: updated.id,
      operation: 'update',
      payload: updated.toJson(),
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      await sqliteDb.transaction(() async {
        await BusinessSqliteStore.upsertManufacturingOrderPayloadInTransaction(
          sqliteDb,
          updated.toJson(),
          id: updated.id,
          payloadJson: jsonEncode(updated.toJson()),
          createdAt: updated.createdAt.toIso8601String(),
          updatedAt: updated.updatedAt.toIso8601String(),
          deletedAt: '',
          sortIndex: 0,
        );
      });
    } else {
      await _saveDirty(manufacturingOrders: true, sync: true);
    }
    _invalidateDerivedDataCaches();
    notifyListeners();
    return updated;
  }

Future<ManufacturingOrder> startManufacturingOrder({
    required String bomId,
    required double quantity,
    String rawMaterialsWarehouseId = '',
    String rawMaterialsWarehouseName = '',
    String finishedGoodsWarehouseId = '',
    String finishedGoodsWarehouseName = '',
    String notes = '',
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    if (quantity <= 0) {
      throw ArgumentError('Manufacturing quantity must be greater than zero.');
    }
    final bom = _billsOfMaterials.firstWhere(
      (item) => item.id == bomId && !item.isDeleted && item.isActive,
      orElse: () => throw ArgumentError('BOM was not found.'),
    );
    final output = _findProductById(bom.outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    final now = DateTime.now();
    final rawWarehouse = resolveWarehouseForPurchase(
      warehouseId: rawMaterialsWarehouseId,
    );
    final finishedWarehouse = resolveWarehouseForSale(
      warehouseId: finishedGoodsWarehouseId,
    );
    final order = _withSyncMeta<ManufacturingOrder>(
      ManufacturingOrder(
        id: '${now.microsecondsSinceEpoch}-mfg',
        orderNo: 'MFG-${now.microsecondsSinceEpoch.toString().substring(6)}',
        bomId: bom.id,
        bomName: bom.name,
        outputProductId: output.id,
        outputProductName: output.name,
        quantity: quantity,
        rawMaterialsWarehouseId: rawWarehouse.id,
        rawMaterialsWarehouseName: rawMaterialsWarehouseName.trim().isEmpty
            ? rawWarehouse.name
            : rawMaterialsWarehouseName.trim(),
        finishedGoodsWarehouseId: finishedWarehouse.id,
        finishedGoodsWarehouseName: finishedGoodsWarehouseName.trim().isEmpty
            ? finishedWarehouse.name
            : finishedGoodsWarehouseName.trim(),
        notes: notes.trim(),
        date: now,
        status: 'in_progress',
      ),
      now,
      isCreate: true,
    );

    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      await sqliteDb.transaction(() async {
        await BusinessSqliteStore.upsertManufacturingOrderPayloadInTransaction(
          sqliteDb,
          order.toJson(),
          id: order.id,
          payloadJson: jsonEncode(order.toJson()),
          createdAt: order.createdAt.toIso8601String(),
          updatedAt: order.updatedAt.toIso8601String(),
          deletedAt: '',
          sortIndex: 0,
        );
      });
      _manufacturingOrders.add(order);
      _recordSyncChange(
        entityType: 'manufacturing_order',
        entityId: order.id,
        operation: 'create',
        payload: order.toJson(),
      );
      notifyListeners();
      return order;
    }

    _manufacturingOrders.add(order);
    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: order.id,
      operation: 'create',
      payload: order.toJson(),
    );
    await _saveDirty(manufacturingOrders: true, sync: true);
    notifyListeners();
    return order;
  }

Future<ManufacturingOrder> finishManufacturingOrder({
    required String orderId,
    required double actualQuantity,
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    final existing = _manufacturingOrders.firstWhere(
      (item) => item.id == orderId && !item.isDeleted,
      orElse: () => throw ArgumentError('Manufacturing order was not found.'),
    );
    if (<String>{'completed', 'reversed'}
        .contains(existing.status.toLowerCase())) {
      // Database/business idempotency: a retry returns the already persisted
      // result and never consumes or produces stock a second time.
      return existing;
    }
    return completeManufacturingOrder(
      bomId: existing.bomId,
      quantity: actualQuantity,
      rawMaterialsWarehouseId: existing.rawMaterialsWarehouseId,
      rawMaterialsWarehouseName: existing.rawMaterialsWarehouseName,
      finishedGoodsWarehouseId: existing.finishedGoodsWarehouseId,
      finishedGoodsWarehouseName: existing.finishedGoodsWarehouseName,
      notes: existing.notes,
      outputBatchAllocations: outputBatchAllocations,
      actualConsumedQuantities: actualConsumedQuantities,
      wasteQuantities: wasteQuantities,
      wasteReasons: wasteReasons,
      existingOrderId: existing.id,
    );
  }

Future<ManufacturingOrder> completeManufacturingOrder({
    required String bomId,
    required double quantity,
    String rawMaterialsWarehouseId = '',
    String rawMaterialsWarehouseName = '',
    String finishedGoodsWarehouseId = '',
    String finishedGoodsWarehouseName = '',
    String notes = '',
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
    String existingOrderId = '',
    bool allowCompletedRepostInternal = false,
    bool withinExistingTransactionInternal = false,
    bool suppressPostCommitInternal = false,
    String technicalReferenceIdOverride = '',
    String operationReferenceIdOverride = '',
    ManufacturingOrder? existingOrderOverride,
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    if (!LocalDatabaseService.isSqliteAuthoritative ||
        SqliteMigrationManager.database == null) {
      throw StateError(
          'Manufacturing completion requires the authoritative SQLite store.');
    }
    // Prevent a stale debounced ProductCost snapshot from racing the finished
    // goods cost written atomically by the manufacturing transaction.
    if (!withinExistingTransactionInternal) {
      await _flushProductDerivedData();
    }
    if (quantity <= 0) {
      throw ArgumentError('Manufacturing quantity must be greater than zero.');
    }
    final existingOrderIndex = existingOrderId.trim().isEmpty
        ? -1
        : _manufacturingOrders.indexWhere(
            (item) => item.id == existingOrderId && !item.isDeleted,
          );
    if (existingOrderId.trim().isNotEmpty &&
        existingOrderIndex == -1 &&
        existingOrderOverride == null) {
      throw ArgumentError('Manufacturing order was not found.');
    }
    final existingOrder = existingOrderOverride ??
        (existingOrderIndex == -1 ? null : _manufacturingOrders[existingOrderIndex]);
    if (existingOrder != null &&
        <String>{'completed', 'reversed'}
            .contains(existingOrder.status.trim().toLowerCase()) &&
        !allowCompletedRepostInternal) {
      return existingOrder;
    }
    final bom = _billsOfMaterials.firstWhere(
      (item) => item.id == bomId && !item.isDeleted && item.isActive,
      orElse: () => throw ArgumentError('BOM was not found.'),
    );
    final output = _findProductById(bom.outputProductId);
    if (output == null) throw ArgumentError('Output product was not found.');
    if (!output.trackStock) {
      throw StateError('Manufacturing output must be a stock-tracked product.');
    }
    final factor = quantity / bom.outputQuantity;
    final now = DateTime.now();
    final rawWarehouse = resolveWarehouseForPurchase(
      warehouseId: rawMaterialsWarehouseId,
    );
    final finishedWarehouse = resolveWarehouseForSale(
      warehouseId: finishedGoodsWarehouseId,
    );
    final orderPreview = ManufacturingOrder(
        id: existingOrder?.id ?? '${now.microsecondsSinceEpoch}-mfg',
        orderNo: existingOrder?.orderNo ??
            'MFG-${now.microsecondsSinceEpoch.toString().substring(6)}',
        bomId: bom.id,
        bomName: bom.name,
        outputProductId: output.id,
        outputProductName: output.name,
        quantity: quantity,
        rawMaterialsWarehouseId: rawWarehouse.id,
        rawMaterialsWarehouseName: rawMaterialsWarehouseName.trim().isEmpty
            ? rawWarehouse.name
            : rawMaterialsWarehouseName.trim(),
        finishedGoodsWarehouseId: finishedWarehouse.id,
        finishedGoodsWarehouseName: finishedGoodsWarehouseName.trim().isEmpty
            ? finishedWarehouse.name
            : finishedGoodsWarehouseName.trim(),
        notes: notes.trim(),
        date: existingOrder?.date ?? now,
        createdAt: existingOrder?.createdAt,
        status: 'completed',
      );
    var order = suppressPostCommitInternal && existingOrder != null
        ? orderPreview.copyWith(
            updatedAt: now,
            deviceId: _deviceId,
            syncStatus: 'pending',
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            version: existingOrder.version + 1,
            lastModifiedByDeviceId: _deviceId,
          )
        : _withSyncMeta<ManufacturingOrder>(
            orderPreview,
            now,
            isCreate: existingOrder == null,
          );
    final operationReferenceId = operationReferenceIdOverride.trim().isEmpty
        ? order.id
        : operationReferenceIdOverride.trim();
    final technicalReferenceId = technicalReferenceIdOverride.trim().isEmpty
        ? order.id
        : technicalReferenceIdOverride.trim();
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final batchService = BatchInventoryService(sqliteDb);
      final movements = <StockMovement>[];
      var producedBatchAllocations = const <BatchAllocation>[];
      Product? persistedOutputProduct;
      ProductCost? persistedOutputCost;
      double consumedCost = 0;
      double wasteCost = 0;
      late double producedUnitCost;
      final materialCosts = <ManufacturingMaterialCost>[];
      final wasteLines = <ManufacturingWasteLine>[];
      Future<void> persistCompletion() async {
        for (var lineIndex = 0;
            lineIndex < bom.components.length;
            lineIndex += 1) {
          final component = bom.components[lineIndex];
          final product = _findProductById(component.productId);
          if (product == null || !product.trackStock) continue;
          final requestedActual = actualConsumedQuantities[component.productId];
          final usedQty = requestedActual ?? component.quantity * factor;
          if (usedQty <= 0) continue;
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            sqliteDb,
            product: product,
            warehouseId: rawWarehouse.id,
            at: now,
          );
          // Manufacturing is a physical transformation. A general store
          // negative-stock policy may be used for sales timing differences,
          // but raw materials must exist in real batches before they can be
          // converted into a finished batch with a final cost.
          await batchService.requirePhysicalUnifiedStockInTransaction(
            product: product,
            warehouseId: rawWarehouse.id,
            quantity: usedQty,
            movementDate: now,
            storeId: appIdentity.storeId,
            operation: 'manufacturing',
          );
          final allocations = await batchService.allocateUnifiedInTransaction(
            product: product,
            warehouseId: rawWarehouse.id,
            quantity: usedQty,
            movementDate: now,
            storeId: appIdentity.storeId,
            deviceId: _deviceId,
            branchId: appIdentity.branchId,
            allowNegativeStock: false,
          );
          final lineTotalCost = allocations.fold<double>(
            0,
            (sum, allocation) =>
                sum + (allocation.quantity * allocation.unitCost),
          );
          final lineUnitCost = usedQty <= 0 ? 0.0 : lineTotalCost / usedQty;
          consumedCost += lineTotalCost;
          final requestedWaste = wasteQuantities[component.productId] ?? 0;
          if (requestedWaste < 0 || requestedWaste > usedQty + 0.000001) {
            throw ArgumentError(
                'Manufacturing waste must be between zero and actual consumption for ${product.name}.');
          }
          final lineWasteCost = requestedWaste * lineUnitCost;
          wasteCost += lineWasteCost;
          if (requestedWaste > 0) {
            wasteLines.add(ManufacturingWasteLine(
              productId: product.id,
              productName: product.name,
              quantity: requestedWaste,
              unitCost: lineUnitCost,
              value: lineWasteCost,
              reason: (wasteReasons[product.id] ?? '').trim().isEmpty
                  ? 'Manufacturing waste'
                  : wasteReasons[product.id]!.trim(),
            ));
          }
          final baseMovement = StockMovement(
            id: '$operationReferenceId-$lineIndex-${component.productId}-manufacturing-consume',
            productId: component.productId,
            productName: product.name,
            type: 'manufacturing_consume',
            quantity: -usedQty,
            date: now,
            referenceId: order.id,
            referenceNo: order.orderNo,
            reason: 'Manufacturing component consumption',
            warehouseId: rawWarehouse.id,
            warehouseName: rawWarehouse.name,
            movementGroupId: operationReferenceId,
            documentLineId: '$operationReferenceId-consume-$lineIndex',
            idempotencyKey: '$operationReferenceId:manufacture:consume:$lineIndex',
            unitCost: lineUnitCost,
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          );
          final lineMovementIds = <String>[];
          for (var batchIndex = 0;
              batchIndex < allocations.length;
              batchIndex += 1) {
            final allocation = allocations[batchIndex];
            final movementId = '${baseMovement.id}-batch-$batchIndex';
            lineMovementIds.add(movementId);
            movements.add(baseMovement.copyWith(
              id: movementId,
              quantity: -allocation.quantity,
              batchId: allocation.batchId,
              unitCost: allocation.unitCost,
              documentLineId:
                  '$operationReferenceId-consume-$lineIndex-batch-$batchIndex',
              idempotencyKey:
                  '$operationReferenceId:manufacture:consume:$lineIndex:$batchIndex',
            ));
          }
          materialCosts.add(ManufacturingMaterialCost(
            productId: product.id,
            productName: product.name,
            quantity: usedQty,
            unitCost: lineUnitCost,
            totalCost: lineTotalCost,
            costingMethod: 'unified_batch',
            movementIds: lineMovementIds,
            layerConsumptions: <Map<String, dynamic>>[
              for (final allocation in allocations)
                <String, dynamic>{
                  'batchId': allocation.batchId,
                  'quantity': allocation.quantity,
                  'unitCost': allocation.unitCost,
                },
            ],
          ));
        }
        final eligibleCost = max(0.0, consumedCost - wasteCost);
        producedUnitCost = quantity <= 0 ? 0.0 : eligibleCost / quantity;
        final outputMovement = StockMovement(
          id: '$operationReferenceId-${output.id}-manufacturing-output',
          productId: output.id,
          productName: output.name,
          type: 'manufacturing_produce',
          quantity: quantity,
          date: now,
          referenceId: order.id,
          referenceNo: order.orderNo,
          reason: 'Manufacturing finished goods output',
          warehouseId: finishedWarehouse.id,
          warehouseName: finishedWarehouse.name,
          movementGroupId: operationReferenceId,
          documentLineId: '$operationReferenceId-produce',
          idempotencyKey: '$operationReferenceId:manufacture:produce',
          unitCost: producedUnitCost,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        );
        await _ensureUnifiedBatchCutoverForProductInTransaction(
          sqliteDb,
          product: output,
          warehouseId: finishedWarehouse.id,
          at: now,
        );
        final requestedOutputBatches = output.expiryTrackingEnabled
            ? outputBatchAllocations
            : <BatchAllocation>[
                BatchAllocation(
                  batchId: '$operationReferenceId-${output.id}-manufacturing-batch',
                  quantity: quantity,
                  manufacturingDate: now,
                  unitCost: producedUnitCost,
                ),
              ];
        if (output.expiryTrackingEnabled && requestedOutputBatches.isEmpty) {
          throw LocalizedDomainException(
            'error_expiry_batches_required',
            values: {'product': output.name},
            fallback: 'Expiry batches are required for ${output.name}.',
          );
        }
        final outputBatchTotal = requestedOutputBatches.fold<double>(
          0,
          (sum, allocation) => sum + allocation.quantity,
        );
        if ((outputBatchTotal - quantity).abs() > 0.000001) {
          throw LocalizedDomainException(
            'error_batch_quantity_total',
            values: {'product': output.name, 'quantity': quantity},
            fallback:
                'Batch quantities for ${output.name} must equal $quantity.',
          );
        }
        final resolvedOutputBatches = <BatchAllocation>[];
        for (var batchIndex = 0;
            batchIndex < requestedOutputBatches.length;
            batchIndex += 1) {
          final requested = requestedOutputBatches[batchIndex];
          final resolved = await batchService.addUnifiedBatchStockInTransaction(
            product: output,
            warehouseId: finishedWarehouse.id,
            batchId: operationReferenceId != order.id
                ? '$operationReferenceId-${output.id}-manufacturing-batch-$batchIndex'
                : requested.batchId.trim().isEmpty
                    ? '$operationReferenceId-${output.id}-manufacturing-batch-$batchIndex'
                    : requested.batchId.trim(),
            quantity: requested.quantity,
            unitCost: producedUnitCost,
            sourceType: 'manufacturing_output',
            sourceId: operationReferenceId,
            sourceLineId: '$operationReferenceId:output:$batchIndex',
            receivedAt: now,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
            supplierBatchNumber: requested.supplierBatchNumber,
            manufacturingDate: requested.manufacturingDate ?? now,
            expirationDate: requested.expirationDate,
            costCurrency: 'USD',
            exchangeRate: 1,
          );
          resolvedOutputBatches.add(resolved);
          movements.add(outputMovement.copyWith(
            id: '${outputMovement.id}-batch-$batchIndex',
            quantity: resolved.quantity,
            batchId: resolved.batchId,
            unitCost: producedUnitCost,
            documentLineId: '$operationReferenceId-produce-batch-$batchIndex',
            idempotencyKey: '$operationReferenceId:manufacture:produce:$batchIndex',
          ));
        }
        producedBatchAllocations = resolvedOutputBatches;
        order = order.copyWith(
          actualOutputQuantity: quantity,
          totalMaterialCost: consumedCost,
          totalWasteCost: wasteCost,
          totalEligibleCost: eligibleCost,
          actualUnitCost: producedUnitCost,
          materialCosts: materialCosts,
          wasteLines: wasteLines,
          completedAt: now,
          completedBy: _activeUser?.id ?? '',
          updatedAt: now,
        );
        await BusinessSqliteStore.upsertManufacturingOrderPayloadInTransaction(
          sqliteDb,
          order.toJson(),
          id: order.id,
          payloadJson: jsonEncode(order.toJson()),
          createdAt: order.createdAt.toIso8601String(),
          updatedAt: order.updatedAt.toIso8601String(),
          deletedAt: '',
          sortIndex: 0,
        );
        await stockService.recordMovementsInTransaction(
          operationType: 'manufacturing',
          documentType: 'manufacturing_order',
          documentId: order.id,
          movementGroupId: operationReferenceId,
          idempotencyKey: '$operationReferenceId:manufacture',
          movements: movements,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
        await _assertUnifiedBatchMovementBalancesInTransaction(
          batchService,
          movements,
        );
        await InventoryTraceabilityService(sqliteDb)
            .assertManufacturingTraceabilityInTransaction(
          orderId: order.id,
          storeId: appIdentity.storeId,
          operationReferenceId: operationReferenceId,
          expectedOutputQuantity: quantity,
          expectedMaterialCost: consumedCost,
          expectedWasteCost: wasteCost,
          expectedEligibleCost: eligibleCost,
        );
        // Unified Batch carries finished-goods quantity and cost; no new legacy cost layer is created.

        // Persist the manufactured product's costing state in the same SQLite
        // transaction as stock, cost layers, the manufacturing order and the
        // journal. A crash after commit must never leave ProductCost in RAM only.
        final persistedCosts =
            await BusinessSqliteStore.readProductCosts(sqliteDb);
        final currentCost = persistedCosts.firstWhere(
          (item) => item.productId == output.id,
          orElse: () => ProductCost(
            productId: output.id,
            averageCost: _safeUsdCost(output),
            lastCost: _safeUsdCost(output),
            currencyCode: 'USD',
            createdAt: output.createdAt,
            updatedAt: now,
          ),
        );
        final batchValueRow = await sqliteDb.customSelect(
          '''
          SELECT COALESCE(SUM(bb.quantity), 0) AS quantity,
                 COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS value
          FROM inventory_batch_balances bb
          JOIN inventory_batches b ON b.id = bb.batch_id
            AND b.product_id = bb.product_id AND b.store_id = bb.store_id
          WHERE bb.store_id = ? AND bb.product_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(appIdentity.storeId),
            Variable<String>(output.id),
          ],
        ).getSingle();
        final stockAfter =
            (batchValueRow.data['quantity'] as num? ?? 0).toDouble();
        final carryingValue =
            (batchValueRow.data['value'] as num? ?? 0).toDouble();
        final nextAverageCost = stockAfter <= 0.000001
            ? producedUnitCost
            : carryingValue / stockAfter;
        persistedOutputCost = currentCost.copyWith(
          averageCost: nextAverageCost,
          lastCost: producedUnitCost,
          currencyCode: 'USD',
          updatedAt: now,
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._productCostsKey,
          <Map<String, dynamic>>[persistedOutputCost!.toJson()],
          sortIndices: const <int?>[0],
        );
        // Finished-goods valuation lives in the produced Unified Batch.
        // Keep the product reference cost user-maintained and independent.
        final outputPreview = output.copyWith(stock: stockAfter);
        persistedOutputProduct = suppressPostCommitInternal
            ? outputPreview.copyWith(
                updatedAt: now,
                deviceId: _deviceId,
                syncStatus: 'pending',
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                version: output.version + 1,
                lastModifiedByDeviceId: _deviceId,
              )
            : _withSyncMeta<Product>(outputPreview, now);
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._productsKey,
          <Map<String, dynamic>>[persistedOutputProduct!.toJson()],
          sortIndices: const <int?>[0],
        );

        final journalEntryId =
            await AccountingService.recordManufacturingCompletionInTransaction(
          database: sqliteDb,
          order: order,
          technicalReferenceId: technicalReferenceId,
        );
        if (journalEntryId.isEmpty) {
          throw StateError('Manufacturing accounting journal was not created.');
        }
        order = order.copyWith(journalEntryId: journalEntryId);
        await BusinessSqliteStore.upsertManufacturingOrderPayloadInTransaction(
          sqliteDb,
          order.toJson(),
          id: order.id,
          payloadJson: jsonEncode(order.toJson()),
          createdAt: order.createdAt.toIso8601String(),
          updatedAt: order.updatedAt.toIso8601String(),
          deletedAt: '',
          sortIndex: 0,
        );
      }
      if (withinExistingTransactionInternal) {
        await persistCompletion();
      } else {
        await sqliteDb.transaction(persistCompletion);
      }
      if (suppressPostCommitInternal) return order;
      _mirrorAuthoritativeStockMovements(movements);
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(sqliteDb));
      _rebuildInventoryCostLayerLookupCache();
      final touchedProductIds = <String>{
        for (final component in bom.components) component.productId,
        output.id,
      };
      final outputIndex = _productIndexById[output.id];
      if (outputIndex != null && persistedOutputProduct != null) {
        _products[outputIndex] = persistedOutputProduct!;
      }
      _productCosts
        ..clear()
        ..addAll(await BusinessSqliteStore.readProductCosts(sqliteDb));
      _rebuildProductCostLookupCache();
      await _refreshProductStockCompatibilityCache(touchedProductIds);
      if (existingOrderIndex == -1) {
        _manufacturingOrders.add(order);
      } else {
        _manufacturingOrders[existingOrderIndex] = order;
      }
      if (producedBatchAllocations.isNotEmpty) {
        _recordInventoryBatchSyncChanges(
          product: output,
          allocations: producedBatchAllocations,
          sourceType: 'manufacturing_output',
          sourceId: order.id,
          now: now,
          unitCost: producedUnitCost,
          sourceLineIds: <String>[
            for (var index = 0;
                index < producedBatchAllocations.length;
                index += 1)
              '${order.id}:output:$index',
          ],
        );
      }
      for (final movement in movements) {
        _recordSyncChange(
          entityType: 'stock_movement',
          entityId: movement.id,
          operation: 'manufacturing',
          payload: movement.toJson(),
        );
      }
      _recordSyncChange(
        entityType: 'manufacturing_order',
        entityId: order.id,
        operation: 'complete',
        payload: order.toJson(),
      );
      notifyListeners();
      return order;
    }

    for (var lineIndex = 0; lineIndex < bom.components.length; lineIndex += 1) {
      final component = bom.components[lineIndex];
      final index = _productIndexById[component.productId];
      if (index == null) continue;
      final product = _products[index];
      if (!product.trackStock) continue;
      final usedQty = component.quantity * factor;
      if (usedQty <= 0) continue;
      if (!_storeProfile.allowNegativeStock &&
          stockForWarehouse(component.productId, rawWarehouse.id) < usedQty) {
        throw ArgumentError(
          'Insufficient stock for ${product.name} in ${rawWarehouse.name}.',
        );
      }
      _products[index] = _withSyncMeta<Product>(
        product.copyWith(stock: product.stock - usedQty),
        now,
      );
      _addStockMovement(
        StockMovement(
          id: '${order.id}-$lineIndex-${component.productId}-manufacturing-consume',
          productId: component.productId,
          productName: product.name,
          type: 'manufacturing_consume',
          quantity: -usedQty,
          date: now,
          referenceId: order.id,
          referenceNo: order.orderNo,
          reason: 'Manufacturing component consumption',
          warehouseId: rawWarehouse.id,
          warehouseName: rawWarehouse.name,
          movementGroupId: order.id,
          documentLineId: '${order.id}-consume-$lineIndex',
          idempotencyKey: '${order.id}:manufacture:consume:$lineIndex',
          unitCost: _safeUsdCost(product),
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        recordSync: true,
      );
    }

    final outputIndex = _productIndexById[output.id];
    final producedCost = bom.components.fold<double>(
          0,
          (sum, component) {
            final product = _findProductById(component.productId);
            if (product == null || !product.trackStock) return sum;
            return sum + component.quantity * factor * _safeUsdCost(product);
          },
        ) /
        (quantity <= 0 ? 1 : quantity);
    if (outputIndex != null && output.trackStock) {
      _products[outputIndex] = _withSyncMeta<Product>(
        output.copyWith(stock: output.stock + quantity),
        now,
      );
      _addInventoryCostLayerFromStockIncrease(
        id: '${order.id}-${output.id}-manufacturing-layer',
        product: output,
        quantity: quantity,
        unitCost: producedCost,
        sourceType: 'manufacturing_output',
        sourceId: order.id,
        now: now,
      );
      _addStockMovement(
        StockMovement(
          id: '${order.id}-${output.id}-manufacturing-output',
          productId: output.id,
          productName: output.name,
          type: 'manufacturing_produce',
          quantity: quantity,
          date: now,
          referenceId: order.id,
          referenceNo: order.orderNo,
          reason: 'Manufacturing finished goods output',
          warehouseId: finishedWarehouse.id,
          warehouseName: finishedWarehouse.name,
          movementGroupId: order.id,
          documentLineId: '${order.id}-produce',
          idempotencyKey: '${order.id}:manufacture:produce',
          unitCost: producedCost,
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
        ),
        recordSync: true,
      );
    }

    if (existingOrderIndex == -1) {
      _manufacturingOrders.add(order);
    } else {
      _manufacturingOrders[existingOrderIndex] = order;
    }
    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: order.id,
      operation: 'complete',
      payload: order.toJson(),
    );
    await _saveDirty(
      products: true,
      productDerivedData: true,
      stockMovements: true,
      manufacturingOrders: true,
      sync: true,
    );
    notifyListeners();
    return order;
  }


Future<ManufacturingOrder> editCompletedManufacturingOrder({
    required String orderId,
    required int expectedVersion,
    required String bomId,
    required double quantity,
    required String rawMaterialsWarehouseId,
    required String rawMaterialsWarehouseName,
    required String finishedGoodsWarehouseId,
    required String finishedGoodsWarehouseName,
    String notes = '',
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    if (quantity <= 0) {
      throw ArgumentError('Manufacturing quantity must be greater than zero.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
        'Editing completed manufacturing requires the authoritative SQLite store.',
      );
    }
    await _flushProductDerivedData();
    final persistedOrders = await BusinessSqliteStore.readManufacturingOrders(db);
    final initial = persistedOrders.firstWhere(
      (item) => item.id == orderId && !item.isDeleted,
      orElse: () => throw ArgumentError('Manufacturing order was not found.'),
    );
    if (!<String>{'completed', 'complete'}
        .contains(initial.status.trim().toLowerCase())) {
      throw StateError('Only a completed manufacturing order can be edited.');
    }
    if (initial.version != expectedVersion) {
      throw StateError(
        'Manufacturing order changed concurrently. Reload it before editing.',
      );
    }
    final nextVersion = initial.version + 1;
    final technicalReferenceId =
        '${initial.id}:manufacturing_edit:v$nextVersion';
    final operationReferenceId = technicalReferenceId;
    final reversalOperationReferenceId =
        '${initial.id}:manufacturing_edit_reverse:v$nextVersion';
    late ManufacturingOrder updated;

    await db.transaction(() async {
      updated = await PostedDocumentEditPipeline<ManufacturingOrder>(
        loadAuthoritative: () async {
          final rows = await BusinessSqliteStore.readManufacturingOrders(db);
          return rows.firstWhere(
            (item) => item.id == orderId && !item.isDeleted,
            orElse: () =>
                throw StateError('Manufacturing order disappeared during edit.'),
          );
        },
        validatePermission: (_) async {
          requirePermission(AppPermission.inventoryManufacturingManage);
        },
        validateVersion: (current) async {
          if (current.version != expectedVersion) {
            throw StateError(
              'Manufacturing order changed concurrently. Reload it before editing.',
            );
          }
          if (!<String>{'completed', 'complete'}
              .contains(current.status.trim().toLowerCase())) {
            throw StateError(
              'Only a completed manufacturing order can be edited.',
            );
          }
        },
        validateDependencies: (current) async {
          final activeMovements = await BusinessSqliteStore.readStockMovements(db);
          final reversedIds = activeMovements
              .where((movement) => movement.reversalOfMovementId.isNotEmpty)
              .map((movement) => movement.reversalOfMovementId)
              .toSet();
          final outputMovements = activeMovements.where(
            (movement) =>
                movement.referenceId == current.id &&
                movement.type == 'manufacturing_produce' &&
                movement.reversalOfMovementId.isEmpty &&
                !reversedIds.contains(movement.id),
          );
          if (outputMovements.isEmpty) {
            throw StateError(
              'Active manufacturing output movements are missing.',
            );
          }
          for (final outputMovement in outputMovements) {
            final downstream = activeMovements.any(
              (movement) =>
                  movement.productId == outputMovement.productId &&
                  movement.warehouseId == outputMovement.warehouseId &&
                  (outputMovement.batchId.isEmpty ||
                      movement.batchId == outputMovement.batchId) &&
                  movement.referenceId != current.id &&
                  movement.reversalOfMovementId.isEmpty &&
                  !reversedIds.contains(movement.id) &&
                  movement.date.isAfter(outputMovement.date) &&
                  movement.quantity < -0.000001,
            );
            if (downstream) {
              throw StateError(
                'Manufactured output has downstream consumption. Reverse the downstream movement before editing this order.',
              );
            }
          }
        },
        reverseOperationalEffects: (current) async {
          await reverseManufacturingOrder(
            orderId: current.id,
            reason: 'Manufacturing order edited to version $nextVersion',
            withinExistingTransactionInternal: true,
            suppressPostCommitInternal: true,
            operationReferenceIdOverride: reversalOperationReferenceId,
          );
        },
        reverseAccountingEffects: (current) async {
          final activeJournal = await db.customSelect(
            '''
            SELECT id
            FROM journal_entries je
            WHERE je.reference_type = 'manufacturing_order'
              AND (je.reference_id = ? OR instr(je.reference_id, ?) = 1)
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(current.id),
              Variable<String>('${current.id}:manufacturing_edit:'),
            ],
          ).getSingleOrNull();
          if (activeJournal != null) {
            throw StateError(
              'Manufacturing accounting reversal did not complete.',
            );
          }
        },
        applyChanges: (current) async => current,
        rebuildOperationalEffects: (current) async {
          return completeManufacturingOrder(
            bomId: bomId,
            quantity: quantity,
            rawMaterialsWarehouseId: rawMaterialsWarehouseId,
            rawMaterialsWarehouseName: rawMaterialsWarehouseName,
            finishedGoodsWarehouseId: finishedGoodsWarehouseId,
            finishedGoodsWarehouseName: finishedGoodsWarehouseName,
            notes: notes,
            outputBatchAllocations: outputBatchAllocations,
            actualConsumedQuantities: actualConsumedQuantities,
            wasteQuantities: wasteQuantities,
            wasteReasons: wasteReasons,
            existingOrderId: current.id,
            allowCompletedRepostInternal: true,
            withinExistingTransactionInternal: true,
            suppressPostCommitInternal: true,
            technicalReferenceIdOverride: technicalReferenceId,
            operationReferenceIdOverride: operationReferenceId,
            existingOrderOverride: current,
          );
        },
        buildPostedSnapshot: (current) async => current,
        repostAccounting: (current) async {
          final journal = await db.customSelect(
            '''
            SELECT id
            FROM journal_entries je
            WHERE je.reference_type = 'manufacturing_order'
              AND je.reference_id = ?
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(technicalReferenceId),
            ],
          ).getSingleOrNull();
          if (journal == null || current.journalEntryId.trim().isEmpty) {
            throw StateError(
              'Edited manufacturing accounting journal was not persisted.',
            );
          }
        },
        rebuildDerivedState: (current) async {},
        verifyIntegrity: (current) async {
          if (current.version != nextVersion ||
              current.status.trim().toLowerCase() != 'completed') {
            throw StateError(
              'Edited manufacturing order failed version/status verification.',
            );
          }
          final persisted = (await BusinessSqliteStore.readManufacturingOrders(db))
              .firstWhere(
            (item) => item.id == current.id && !item.isDeleted,
            orElse: () => throw StateError(
              'Edited manufacturing order was not persisted.',
            ),
          );
          if (persisted.version != nextVersion ||
              persisted.journalEntryId != current.journalEntryId) {
            throw StateError(
              'Edited manufacturing order failed persistence verification.',
            );
          }
          final movementRow = await db.customSelect(
            '''
            SELECT
              SUM(CASE WHEN movement_type = 'manufacturing_produce'
                       THEN quantity ELSE 0 END) AS produced,
              COUNT(*) AS movementCount
            FROM stock_movements sm
            WHERE sm.movement_group_id = ? AND sm.deleted_at = ''
              AND sm.movement_type IN ('manufacturing_consume', 'manufacturing_produce')
            ''',
            variables: <Variable<Object>>[
              Variable<String>(operationReferenceId),
            ],
          ).getSingle();
          final produced =
              (movementRow.data['produced'] as num? ?? 0).toDouble();
          final movementCount =
              (movementRow.data['movementCount'] as num? ?? 0).toInt();
          if (movementCount <= 0 || (produced - quantity).abs() > 0.000001) {
            throw StateError(
              'Edited manufacturing order failed stock verification.',
            );
          }
        },
      ).execute();
    });

    final authoritativeOrders =
        await BusinessSqliteStore.readManufacturingOrders(db);
    final persistedUpdated = authoritativeOrders.firstWhere(
      (item) => item.id == updated.id && !item.isDeleted,
      orElse: () => updated,
    );
    final orderIndex =
        _manufacturingOrders.indexWhere((item) => item.id == persistedUpdated.id);
    if (orderIndex == -1) {
      _manufacturingOrders.add(persistedUpdated);
    } else {
      _manufacturingOrders[orderIndex] = persistedUpdated;
    }
    final allMovements = await BusinessSqliteStore.readStockMovements(db);
    _mirrorAuthoritativeStockMovements(allMovements);
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    _productCosts
      ..clear()
      ..addAll(await BusinessSqliteStore.readProductCosts(db));
    _rebuildProductCostLookupCache();

    final newBom = _billsOfMaterials.firstWhere(
      (item) => item.id == bomId && !item.isDeleted,
      orElse: () => throw StateError('Edited manufacturing BOM is missing.'),
    );
    final touchedProductIds = <String>{
      initial.outputProductId,
      persistedUpdated.outputProductId,
      for (final line in initial.materialCosts) line.productId,
      for (final line in newBom.components) line.productId,
    };
    await _refreshProductStockCompatibilityCache(touchedProductIds);

    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: persistedUpdated.id,
      operation: 'edit_completed',
      payload: persistedUpdated.toJson(),
    );
    for (final movement in allMovements.where(
      (movement) =>
          movement.movementGroupId == operationReferenceId ||
          movement.movementGroupId == reversalOperationReferenceId,
    )) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: movement.movementGroupId == operationReferenceId
            ? 'manufacturing_edit'
            : 'manufacturing_edit_reversal',
        payload: movement.toJson(),
      );
    }

    final batchRows = await db.customSelect(
      '''
      SELECT id, initial_quantity, unit_cost, supplier_batch_number,
             manufacturing_date, expiration_date, received_at
      FROM inventory_batches
      WHERE store_id = ? AND source_type = 'manufacturing_output'
        AND source_id = ?
      ORDER BY received_at, id
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(operationReferenceId),
      ],
    ).get();
    final outputProduct = _findProductById(persistedUpdated.outputProductId);
    if (outputProduct != null && batchRows.isNotEmpty) {
      final allocations = batchRows.map((row) {
        final data = row.data;
        return BatchAllocation(
          batchId: data['id']?.toString() ?? '',
          quantity: (data['initial_quantity'] as num? ?? 0).toDouble(),
          unitCost: (data['unit_cost'] as num? ?? 0).toDouble(),
          supplierBatchNumber:
              data['supplier_batch_number']?.toString() ?? '',
          manufacturingDate:
              DateTime.tryParse(data['manufacturing_date']?.toString() ?? ''),
          expirationDate:
              DateTime.tryParse(data['expiration_date']?.toString() ?? ''),
        );
      }).toList(growable: false);
      _recordInventoryBatchSyncChanges(
        product: outputProduct,
        allocations: allocations,
        sourceType: 'manufacturing_output',
        sourceId: operationReferenceId,
        now: persistedUpdated.completedAt ?? DateTime.now(),
        unitCost: persistedUpdated.actualUnitCost,
        sourceLineIds: <String>[
          for (var index = 0; index < allocations.length; index += 1)
            '$operationReferenceId:output:$index',
        ],
        receivedAt: persistedUpdated.completedAt,
      );
    }
    await _saveDirty(sync: true);
    AccountingService.notifyCommittedMutation();
    _invalidateDerivedDataCaches();
    notifyListeners();
    return persistedUpdated;
  }

Future<ManufacturingOrder> reverseManufacturingOrder({
    required String orderId,
    required String reason,
    bool withinExistingTransactionInternal = false,
    bool suppressPostCommitInternal = false,
    String operationReferenceIdOverride = '',
  }) async {
    requirePermission(AppPermission.inventoryManufacturingManage);
    if (reason.trim().isEmpty) {
      throw ArgumentError('A manufacturing reversal reason is required.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
          'Manufacturing reversal requires the authoritative SQLite store.');
    }
    final persistedOrders =
        await BusinessSqliteStore.readManufacturingOrders(db);
    final order = persistedOrders.firstWhere(
      (item) => item.id == orderId && !item.isDeleted,
      orElse: () => throw ArgumentError('Manufacturing order was not found.'),
    );
    if (order.status.trim().toLowerCase() == 'reversed') return order;
    if (order.status.trim().toLowerCase() != 'completed') {
      throw StateError('Only a completed manufacturing order can be reversed.');
    }
    final allMovements = await BusinessSqliteStore.readStockMovements(db);
    final reversedMovementIds = allMovements
        .where((movement) => movement.reversalOfMovementId.isNotEmpty)
        .map((movement) => movement.reversalOfMovementId)
        .toSet();
    final originals = allMovements
        .where((movement) =>
            movement.referenceId == order.id &&
            movement.reversalOfMovementId.isEmpty &&
            !reversedMovementIds.contains(movement.id) &&
            <String>{'manufacturing_consume', 'manufacturing_produce'}
                .contains(movement.type))
        .toList(growable: false);
    if (originals.isEmpty) {
      throw StateError('Manufacturing stock movements are missing.');
    }
    final unifiedOutputBatchRow = await db.customSelect(
      '''
      SELECT id
      FROM inventory_batches
      WHERE store_id = ? AND source_type = 'manufacturing_output'
        AND source_id = ? AND trim(source_line_id) <> ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(order.id),
      ],
    ).getSingleOrNull();
    final unifiedBatchOrder = order.materialCosts.any(
          (line) => line.costingMethod.trim().toLowerCase() == 'unified_batch',
        ) ||
        unifiedOutputBatchRow != null;
    final outputMovements = originals
        .where((movement) => movement.type == 'manufacturing_produce')
        .toList(growable: false);
    final fifoBasis = _inventoryCostingMethod == InventoryCostingMethod.fifo
        ? _currentOpenFifoEffectiveFrom()
        : null;
    if (!unifiedBatchOrder &&
        fifoBasis != null &&
        originals.any((movement) => movement.date.isBefore(fifoBasis))) {
      throw StateError(
        'Cannot reverse a manufacturing order that predates the current FIFO opening basis. Reverse it before changing costing method, or use a documented inventory adjustment.',
      );
    }
    // Historical movements remain immutable. A downstream issue only blocks
    // manufacturing reversal while that movement is still active; if it has
    // already been reversed, its original negative row must not block forever.
    for (final outputMovement in outputMovements) {
      final unsafe = allMovements.any((movement) =>
          movement.productId == outputMovement.productId &&
          movement.warehouseId == outputMovement.warehouseId &&
          (outputMovement.batchId.isEmpty ||
              movement.batchId == outputMovement.batchId) &&
          movement.referenceId != order.id &&
          movement.reversalOfMovementId.isEmpty &&
          !reversedMovementIds.contains(movement.id) &&
          movement.date.isAfter(outputMovement.date) &&
          movement.quantity < 0);
      if (unsafe) {
        throw StateError(
            'This manufacturing order cannot be reversed because its finished goods moved afterward. Reverse the downstream movement first.');
      }
    }
    final now = DateTime.now();
    final actor = _activeUser?.id ?? '';
    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final batchService = BatchInventoryService(db);
    final reversalOperationReferenceId = operationReferenceIdOverride.trim().isEmpty
        ? '${order.id}:reversal'
        : operationReferenceIdOverride.trim();
    final reversalTransactionIdempotencyKey =
        operationReferenceIdOverride.trim().isEmpty
            ? '${order.id}:manufacturing:reversal'
            : '$reversalOperationReferenceId:manufacturing';
    final reversalMovements = originals
        .map((original) => original.copyWith(
              id: '${original.id}-reversal',
              type: '${original.type}_reversal',
              quantity: -original.quantity,
              date: now,
              reason: reason.trim(),
              sourceMovementId: original.id,
              reversalOfMovementId: original.id,
              movementGroupId: reversalOperationReferenceId,
              idempotencyKey: '$reversalOperationReferenceId:${original.id}',
              createdAt: now,
              updatedAt: now,
              reviewedBy: '',
              reviewNote: '',
              clearReviewedAt: true,
            ))
        .toList(growable: false);
    late ManufacturingOrder reversedOrder;
    Product? reversedOutputProduct;
    ProductCost? reversedOutputCost;
    Future<void> persistReversal() async {
      final duplicate = await db.customSelect(
        '''
        SELECT id FROM stock_movements
        WHERE reversal_of_movement_id IN (${List.filled(originals.length, '?').join(',')})
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          for (final movement in originals) Variable<String>(movement.id),
        ],
      ).getSingleOrNull();
      if (duplicate != null) {
        throw StateError('This manufacturing order has already been reversed.');
      }
      for (final movement in originals) {
        if (movement.batchId.isEmpty) continue;
        final product = _findProductById(movement.productId);
        if (product == null) {
          throw StateError('Product ${movement.productId} was not found.');
        }
        await batchService.reverseUnifiedMovementEffectInTransaction(
          product: product,
          warehouseId: movement.warehouseId,
          batchId: movement.batchId,
          movementQuantity: movement.quantity,
          unitCost: movement.unitCost,
          reversedAt: now,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
        );
      }
      await stockService.recordMovementsInTransaction(
        operationType: 'manufacturing_reversal',
        documentType: 'manufacturing_order',
        documentId: order.id,
        movementGroupId: reversalOperationReferenceId,
        idempotencyKey: reversalTransactionIdempotencyKey,
        movements: reversalMovements,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        deviceId: _deviceId,
      );
      if (unifiedBatchOrder) {
        await _assertUnifiedBatchMovementBalancesInTransaction(
          batchService,
          reversalMovements,
        );
      }

      if (!unifiedBatchOrder) {
        final layers = await BusinessSqliteStore.readInventoryCostLayers(db);
        final layersById = <String, InventoryCostLayer>{
          for (final layer in layers) layer.id: layer,
        };
        for (final costLine in order.materialCosts) {
          for (final snapshot in costLine.layerConsumptions) {
            final layerId = snapshot['layerId']?.toString() ?? '';
            if (layerId.isEmpty || layerId.startsWith('negative_stock:')) {
              continue;
            }
            final layer = layersById[layerId];
            if (layer == null) {
              throw StateError('Historical FIFO layer $layerId is missing.');
            }
            final restored = (snapshot['quantity'] as num? ?? 0).toDouble();
            final updated = layer.copyWith(
              quantityRemaining: layer.quantityRemaining + restored,
              isClosed: false,
              updatedAt: now,
            );
            layersById[layerId] = updated;
            await BusinessSqliteStore.upsertEntityPayloads(
              db,
              AppStore._inventoryCostLayersKey,
              <Map<String, dynamic>>[updated.toJson()],
              sortIndices: const <int?>[0],
            );
          }
        }
        final outputLayerId =
            '${order.id}-${order.outputProductId}-manufacturing-layer';
        final outputLayer = layersById[outputLayerId];
        if (outputLayer != null) {
          if (outputLayer.quantityRemaining + 0.000001 <
              outputLayer.quantityReceived) {
            throw StateError(
                'The manufacturing output cost layer has already been consumed.');
          }
          final closed = outputLayer.copyWith(
            quantityRemaining: 0,
            isClosed: true,
            updatedAt: now,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[closed.toJson()],
            sortIndices: const <int?>[0],
          );
        }

      }

      // The manufactured receipt changed both stock and the product costing
      // snapshot. Reverse that costing effect in the same SQLite transaction so
      // a crash cannot leave stock reversed while ProductCost still includes
      // the removed production receipt.
      final outputProduct = _findProductById(order.outputProductId);
      if (outputProduct != null) {
        final costRows = await BusinessSqliteStore.readProductCosts(db);
        final currentCost = costRows.firstWhere(
          (item) => item.productId == order.outputProductId,
          orElse: () => productCostFor(order.outputProductId),
        );
        final stockRow = await db.customSelect(
          '''
          SELECT COALESCE(SUM(quantity), 0) AS qty
          FROM warehouse_inventory
          WHERE product_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(order.outputProductId),
          ],
        ).getSingleOrNull();
        final stockAfter = max(
          0.0,
          (stockRow?.data['qty'] as num? ?? 0).toDouble(),
        );
        final producedQty = outputMovements.fold<double>(
          0,
          (sum, movement) => sum + max(0.0, movement.quantity),
        );
        final stockBefore = stockAfter + producedQty;
        var nextAverage = 0.0;
        if (unifiedBatchOrder) {
          final batchValueRow = await db.customSelect(
            '''
            SELECT COALESCE(SUM(bb.quantity * b.unit_cost), 0) AS value,
                   COALESCE(SUM(bb.quantity), 0) AS qty
            FROM inventory_batch_balances bb
            JOIN inventory_batches b ON b.id = bb.batch_id
              AND b.product_id = bb.product_id AND b.store_id = bb.store_id
            WHERE bb.store_id = ? AND bb.product_id = ?
              AND bb.quantity > 0.000001
            ''',
            variables: <Variable<Object>>[
              Variable<String>(appIdentity.storeId),
              Variable<String>(order.outputProductId),
            ],
          ).getSingleOrNull();
          final batchQty = (batchValueRow?.data['qty'] as num? ?? 0).toDouble();
          final batchValue =
              (batchValueRow?.data['value'] as num? ?? 0).toDouble();
          nextAverage = batchQty <= 0 ? 0.0 : batchValue / batchQty;
        } else if (_inventoryCostingMethod == InventoryCostingMethod.fifo) {
          final fifoRow = await db.customSelect(
            '''
            SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) AS value,
                   COALESCE(SUM(quantity_remaining), 0) AS qty
            FROM inventory_cost_layers
            WHERE product_id = ?
              AND deleted_at = ''
              AND quantity_remaining > 0.000001
            ''',
            variables: <Variable<Object>>[
              Variable<String>(order.outputProductId),
            ],
          ).getSingleOrNull();
          final fifoQty = (fifoRow?.data['qty'] as num? ?? 0).toDouble();
          final fifoValue = (fifoRow?.data['value'] as num? ?? 0).toDouble();
          nextAverage = fifoQty <= 0 ? 0.0 : fifoValue / fifoQty;
        } else if (stockAfter > 0 && stockBefore > 0) {
          final valueBefore = stockBefore * currentCost.averageCost;
          final removedValue = producedQty * order.actualUnitCost;
          nextAverage = max(0.0, (valueBefore - removedValue) / stockAfter);
        }

        final outputOriginalIds =
            outputMovements.map((item) => item.id).toSet();
        final activePositiveCosts = allMovements
            .where((movement) =>
                movement.productId == order.outputProductId &&
                movement.quantity > 0 &&
                movement.unitCost > 0 &&
                movement.reversalOfMovementId.isEmpty &&
                !reversedMovementIds.contains(movement.id) &&
                !outputOriginalIds.contains(movement.id))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final nextLast = activePositiveCosts.isNotEmpty
            ? activePositiveCosts.first.unitCost
            : nextAverage;
        reversedOutputCost = currentCost.copyWith(
          averageCost: nextAverage,
          lastCost: nextLast,
          updatedAt: now,
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          AppStore._productCostsKey,
          <Map<String, dynamic>>[reversedOutputCost!.toJson()],
          sortIndices: const <int?>[0],
        );
        final reversedOutputPreview = outputProduct.copyWith(
          stock: stockAfter,
          updatedAt: now,
        );
        reversedOutputProduct = suppressPostCommitInternal
            ? reversedOutputPreview.copyWith(
                deviceId: _deviceId,
                syncStatus: 'pending',
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                version: outputProduct.version + 1,
                lastModifiedByDeviceId: _deviceId,
              )
            : _withSyncMeta<Product>(reversedOutputPreview, now);
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          AppStore._productsKey,
          <Map<String, dynamic>>[reversedOutputProduct!.toJson()],
          sortIndices: const <int?>[0],
        );
      }
      await AccountingService.reverseEntryForReference(
        referenceType: 'manufacturing_order',
        referenceId: order.id,
        reason: reason.trim(),
        createdBy: actor,
        adjustCashLocationBalance: false,
        notifyChange: false,
        withinExistingTransaction: true,
      );
      final reversalJournal = await db.customSelect(
        '''
        SELECT id FROM journal_entries
        WHERE reference_type = 'manufacturing_order_reversal'
          AND reference_id = ? AND reversed_entry_id = ?
          AND status = 'posted' AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(order.id),
          Variable<String>(order.journalEntryId),
        ],
      ).getSingleOrNull();
      if (reversalJournal == null) {
        throw StateError('Manufacturing reversal journal was not created.');
      }
      reversedOrder = order.copyWith(
        status: 'reversed',
        reversedAt: now,
        reversedBy: actor,
        reversalReason: reason.trim(),
        reversalJournalEntryId: reversalJournal.data['id']?.toString() ?? '',
        updatedAt: now,
      );
      await BusinessSqliteStore.upsertManufacturingOrderPayloadInTransaction(
        db,
        reversedOrder.toJson(),
        id: reversedOrder.id,
        payloadJson: jsonEncode(reversedOrder.toJson()),
        createdAt: reversedOrder.createdAt.toIso8601String(),
        updatedAt: reversedOrder.updatedAt.toIso8601String(),
        deletedAt: '',
        sortIndex: 0,
      );
    }
    if (withinExistingTransactionInternal) {
      await persistReversal();
    } else {
      await db.transaction(persistReversal);
    }
    if (suppressPostCommitInternal) return reversedOrder;
    _mirrorAuthoritativeStockMovements(reversalMovements);
    final index =
        _manufacturingOrders.indexWhere((item) => item.id == order.id);
    if (index == -1) {
      _manufacturingOrders.add(reversedOrder);
    } else {
      _manufacturingOrders[index] = reversedOrder;
    }
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    if (reversedOutputProduct != null) {
      final outputIndex = _productIndexById[reversedOutputProduct!.id];
      if (outputIndex != null) _products[outputIndex] = reversedOutputProduct!;
    }
    if (reversedOutputCost != null) {
      _productCosts
        ..clear()
        ..addAll(await BusinessSqliteStore.readProductCosts(db));
      _rebuildProductCostLookupCache();
    }
    await _refreshProductStockCompatibilityCache(<String>{
      for (final movement in originals) movement.productId,
    });
    _recordSyncChange(
      entityType: 'manufacturing_order',
      entityId: order.id,
      operation: 'reverse',
      payload: reversedOrder.toJson(),
    );
    for (final movement in reversalMovements) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: 'manufacturing_reversal',
        payload: movement.toJson(),
      );
    }
    notifyListeners();
    return reversedOrder;
  }

}
