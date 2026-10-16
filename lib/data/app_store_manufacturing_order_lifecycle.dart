part of 'app_store.dart';

extension _AppStoreManufacturingOrderLifecycle on AppStore {
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
        _resolveWarehouseForPurchase(warehouseId: rawMaterialsWarehouseId);
    final finishedWarehouse =
        _resolveWarehouseForSale(warehouseId: finishedGoodsWarehouseId);
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
    final rawWarehouse = _resolveWarehouseForPurchase(
      warehouseId: rawMaterialsWarehouseId,
    );
    final finishedWarehouse = _resolveWarehouseForSale(
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
    return _completeManufacturingOrder(
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
}
