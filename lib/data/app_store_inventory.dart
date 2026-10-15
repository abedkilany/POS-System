part of 'app_store.dart';

extension _AppStoreSplitInventory on AppStore {
  double _stockAt(String productId, DateTime at) {
    final productIndex = _productIndexById[productId];
    var stock = productIndex == null ? 0.0 : _products[productIndex].stock;
    for (final movement in _stockMovements) {
      if (movement.productId == productId && movement.date.isAfter(at)) {
        stock -= movement.quantity;
      }
    }
    return stock;
  }

  int movementCountAfterInventoryLine(InventoryCountLine line) {
    final countedAt = line.countedAt;
    if (countedAt == null) return 0;
    return _stockMovements
        .where(
          (movement) =>
              movement.productId == line.productId &&
              movement.date.isAfter(countedAt) &&
              movement.type != 'count_adjustment',
        )
        .length;
  }

  Future<InventoryCountSession> createInventoryCountSession({
    String notes = '',
    String warehouseId = '',
    String warehouseName = '',
  }) async {
    requirePermission(AppPermission.inventoryCountsManage);
    if (activeInventoryCountSession != null) {
      throw StateError('There is already an open inventory count session.');
    }
    final now = DateTime.now();
    final warehouse = resolveWarehouseForPurchase(warehouseId: warehouseId);
    final normalizedWarehouseName =
        warehouseName.trim().isEmpty ? warehouse.name : warehouseName.trim();
    final snapshotWarehouseId = warehouse.id;
    final lines = <InventoryCountLine>[];
    for (final product
        in _products.where((item) => item.trackStock && !item.isDeleted)) {
      final snapshotStock = LocalDatabaseService.isSqliteAuthoritative &&
              SqliteMigrationManager.database != null
          ? await warehouseStockFromSqlite(
              product.id,
              warehouseId: snapshotWarehouseId,
            )
          : product.stock;
      lines.add(
        InventoryCountLine(
          productId: product.id,
          productName: product.name,
          productCode: product.code,
          snapshotStock: snapshotStock,
        ),
      );
    }
    final session = InventoryCountSession(
      id: now.microsecondsSinceEpoch.toString(),
      countNo: 'CNT-${now.microsecondsSinceEpoch}',
      createdAt: now,
      createdBy: _actorName(),
      warehouseId: snapshotWarehouseId,
      warehouseName: normalizedWarehouseName,
      notes: notes.trim(),
      lines: lines,
    );
    _inventoryCounts.add(session);
    _rememberSqliteDirtyBusinessRow(
        AppStore._inventoryCountsKey, session.toJson());
    await _saveDirty(inventoryCounts: true);
    notifyListeners();
    return session;
  }

  Future<void> countInventoryLine({
    required String sessionId,
    required String productId,
    required double countedQty,
    String note = '',
  }) async {
    requirePermission(AppPermission.inventoryCountsManage);
    if (countedQty < 0) {
      throw ArgumentError('Counted quantity cannot be negative.');
    }
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isOpen) {
      throw StateError('Only open inventory count sessions can be edited.');
    }
    final lineIndex = session.lines.indexWhere(
      (line) => line.productId == productId,
    );
    if (lineIndex == -1) {
      throw ArgumentError('Product is not part of this count session.');
    }
    final now = DateTime.now();
    final lines = List<InventoryCountLine>.from(session.lines);
    lines[lineIndex] = lines[lineIndex].copyWith(
      countedQty: countedQty,
      countedAt: now,
      countedBy: _actorName(),
      note: note.trim(),
    );
    _inventoryCounts[sessionIndex] = session.copyWith(
      lines: lines,
      updatedAt: now,
    );
    _rememberSqliteDirtyBusinessRow(
      AppStore._inventoryCountsKey,
      _inventoryCounts[sessionIndex].toJson(),
    );
    await _saveDirty(inventoryCounts: true);
    notifyListeners();
  }

  Future<void> resetInventoryCountLine({
    required String sessionId,
    required String productId,
  }) async {
    requirePermission(AppPermission.inventoryCountsManage);
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isOpen) {
      throw StateError('Only open inventory count sessions can be edited.');
    }
    final lineIndex = session.lines.indexWhere(
      (line) => line.productId == productId,
    );
    if (lineIndex == -1) {
      throw ArgumentError('Product is not part of this count session.');
    }
    if (!session.lines[lineIndex].isCounted) return;

    final now = DateTime.now();
    final lines = List<InventoryCountLine>.from(session.lines);
    lines[lineIndex] = lines[lineIndex].resetCount();
    _inventoryCounts[sessionIndex] = session.copyWith(
      lines: lines,
      updatedAt: now,
    );
    _rememberSqliteDirtyBusinessRow(
      AppStore._inventoryCountsKey,
      _inventoryCounts[sessionIndex].toJson(),
    );
    await _saveDirty(inventoryCounts: true);
    notifyListeners();
  }

  Future<void> approveInventoryCount(String sessionId) async {
    requirePermission(AppPermission.inventoryCountsManage);
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isOpen) {
      throw StateError('Only open inventory count sessions can be approved.');
    }
    final countedLines = session.lines.where((line) => line.isCounted).toList();
    if (countedLines.isEmpty) {
      throw StateError('No counted products to approve.');
    }
    final expiryCountedProduct = countedLines
        .map((line) => _findProductById(line.productId))
        .whereType<Product>()
        .where((product) => product.expiryTrackingEnabled)
        .firstOrNull;
    if (expiryCountedProduct != null) {
      throw LocalizedDomainException('error_count_expiry_product_by_batch',
          values: {'product': expiryCountedProduct.name},
          fallback:
              'Expiry-tracked products must be counted by batch. Remove ${expiryCountedProduct.name} from this aggregate count.');
    }
    final now = DateTime.now();
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
      InventoryCountSession? approvedSession;
      final committedMovements = <StockMovement>[];
      var committedJournalEntryId = '';
      await sqliteDb.transaction(() async {
        final existingOperationalRows = await sqliteDb.customSelect(
          '''
          SELECT COUNT(*) AS c
          FROM stock_movements
          WHERE reference_id = ? AND movement_type = 'count_adjustment'
            AND deleted_at = ''
          ''',
          variables: <Variable<Object>>[Variable<String>(session.id)],
        ).getSingle();
        final existingJournalRows = await sqliteDb.customSelect(
          '''
          SELECT COUNT(*) AS c
          FROM journal_entries
          WHERE reference_type = 'inventory_count' AND reference_id = ?
            AND deleted_at = '' AND status = 'posted'
          ''',
          variables: <Variable<Object>>[Variable<String>(session.id)],
        ).getSingle();
        final existingOperationalCount =
            (existingOperationalRows.data['c'] as num?)?.toInt() ?? 0;
        final existingJournalCount =
            (existingJournalRows.data['c'] as num?)?.toInt() ?? 0;
        if (existingOperationalCount > 0 || existingJournalCount > 0) {
          throw StateError(
              'تم العثور على آثار اعتماد سابقة لهذا الجرد. أعد تحميل البيانات قبل المحاولة مجدداً.');
        }

        final updatedLines = List<InventoryCountLine>.from(session.lines);
        final movements = <StockMovement>[];
        final accountingVariances = <InventoryCountVariance>[];
        final warehouseId = session.warehouseId.isEmpty
            ? Warehouse.defaultId
            : session.warehouseId;

        for (final line in countedLines) {
          final countedAt = line.countedAt;
          if (countedAt == null) continue;
          final movementAfterCount = await sqliteDb.customSelect(
            '''
            SELECT id
            FROM stock_movements
            WHERE product_id = ? AND warehouse_id = ? AND deleted_at = ''
              AND movement_date > ?
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(line.productId),
              Variable<String>(warehouseId),
              Variable<String>(countedAt.toUtc().toIso8601String()),
            ],
          ).getSingleOrNull();
          if (movementAfterCount != null) {
            throw StateError(
                'حدثت حركة مخزون بعد عد ${line.productName}. يجب إعادة عد هذا الصنف قبل اعتماد الجرد.');
          }
        }

        for (final line in countedLines) {
          final lineIndex = updatedLines.indexWhere(
            (item) => item.productId == line.productId,
          );
          if (lineIndex == -1) continue;
          final theoreticalAtApproval = await warehouseStockFromSqlite(
            line.productId,
            warehouseId: warehouseId,
          );
          final delta = (line.countedQty ?? theoreticalAtApproval) -
              theoreticalAtApproval;
          final product = _findProductById(line.productId);
          if (product == null) {
            throw StateError(
                'Product not found while approving inventory count.');
          }
          if (!product.trackStock) {
            throw StateError('${product.name} does not track stock.');
          }
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            sqliteDb,
            product: product,
            warehouseId: warehouseId,
            at: now,
          );
          var unitCost = 0.0;
          var differenceValue = 0.0;
          final movementId = delta.abs() < 0.000001
              ? ''
              : '${session.id}-${line.productId}-count-adjustment';
          final lineMovements = <StockMovement>[];
          if (delta < -0.000001) {
            final allocations = await batchService.allocateUnifiedInTransaction(
              product: product,
              warehouseId: warehouseId,
              quantity: delta.abs(),
              movementDate: now,
              storeId: appIdentity.storeId,
              deviceId: _deviceId,
              branchId: appIdentity.branchId,
              allowNegativeStock: _storeProfile.allowNegativeStock,
            );
            differenceValue = allocations.fold<double>(
              0,
              (sum, allocation) =>
                  sum + (allocation.quantity * allocation.unitCost),
            );
            unitCost = delta.abs() <= 0 ? 0 : differenceValue / delta.abs();
            for (var batchIndex = 0;
                batchIndex < allocations.length;
                batchIndex += 1) {
              final allocation = allocations[batchIndex];
              lineMovements.add(StockMovement(
                id: '$movementId-batch-$batchIndex',
                productId: line.productId,
                productName: line.productName,
                type: 'count_adjustment',
                quantity: -allocation.quantity,
                date: now,
                referenceId: session.id,
                referenceNo: session.countNo,
                reason: 'Inventory count adjustment',
                adjustmentCategory: 'stock_count_shortage',
                notes:
                    'Counted at ${line.countedAt?.toIso8601String() ?? session.createdAt.toIso8601String()}. System quantity at approval: $theoreticalAtApproval. Counted: ${line.countedQty}. Batch cost: ${allocation.unitCost}.',
                warehouseId: warehouseId,
                warehouseName: session.warehouseName.isEmpty
                    ? Warehouse.defaultName
                    : session.warehouseName,
                batchId: allocation.batchId,
                movementGroupId: session.id,
                documentLineId:
                    '${session.id}-line-${line.productId}-batch-$batchIndex',
                idempotencyKey:
                    '${session.id}:count:${line.productId}:$batchIndex',
                unitCost: allocation.unitCost,
                createdAt: now,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ));
            }
          } else if (delta > 0.000001) {
            unitCost = await _unifiedOpeningCostForProductInTransaction(
              sqliteDb,
              product: product,
              warehouseId: warehouseId,
            );
            final allocation =
                await batchService.addUnifiedBatchStockInTransaction(
              product: product,
              warehouseId: warehouseId,
              batchId: '${session.id}-${line.productId}-count-batch',
              quantity: delta,
              unitCost: unitCost,
              sourceType: 'inventory_count',
              sourceId: session.id,
              sourceLineId: '${session.id}:count:${line.productId}',
              receivedAt: now,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
            );
            differenceValue = delta * unitCost;
            lineMovements.add(StockMovement(
              id: '$movementId-batch-0',
              productId: line.productId,
              productName: line.productName,
              type: 'count_adjustment',
              quantity: allocation.quantity,
              date: now,
              referenceId: session.id,
              referenceNo: session.countNo,
              reason: 'Inventory count adjustment',
              adjustmentCategory: 'stock_count_overage',
              notes:
                  'Counted at ${line.countedAt?.toIso8601String() ?? session.createdAt.toIso8601String()}. System quantity at approval: $theoreticalAtApproval. Counted: ${line.countedQty}. Batch cost: $unitCost.',
              warehouseId: warehouseId,
              warehouseName: session.warehouseName.isEmpty
                  ? Warehouse.defaultName
                  : session.warehouseName,
              batchId: allocation.batchId,
              movementGroupId: session.id,
              documentLineId: '${session.id}-line-${line.productId}-batch-0',
              idempotencyKey: '${session.id}:count:${line.productId}:0',
              unitCost: unitCost,
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              lastModifiedByDeviceId: _deviceId,
            ));
          }
          updatedLines[lineIndex] = line.copyWith(
            systemQtyAtApproval: theoreticalAtApproval,
            differenceQty: delta,
            unitCost: unitCost,
            differenceValue: differenceValue,
            stockMovementId:
                lineMovements.isEmpty ? '' : lineMovements.first.id,
          );
          if (delta.abs() < 0.000001) continue;
          accountingVariances.add(InventoryCountVariance(
            productId: line.productId,
            productName: line.productName,
            delta: delta,
            amount: differenceValue,
          ));
          movements.addAll(lineMovements);
        }
        if (movements.isNotEmpty) {
          await stockService.recordMovementsInTransaction(
            operationType: 'inventory_count',
            documentType: 'inventory_count',
            documentId: session.id,
            movementGroupId: session.id,
            idempotencyKey: '${session.id}:count',
            movements: movements,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
            skipExistingMovementLookup: true,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            movements,
          );
        }
        committedJournalEntryId =
            await AccountingService.recordInventoryCountAdjustment(
          entryDate: now,
          referenceId: session.id,
          referenceNo: session.countNo,
          variances: accountingVariances,
          createdBy: _actorName(),
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          notes: session.notes,
          database: sqliteDb,
          withinExistingTransaction: true,
        );
        if (accountingVariances.any((item) => item.amount.abs() >= 0.005)) {
          if (committedJournalEntryId.trim().isEmpty) {
            throw StateError(
                'Inventory count variance requires a posted accounting journal.');
          }
          await _requirePostedJournalInTransaction(
            sqliteDb,
            referenceType: 'inventory_count',
            referenceId: session.id,
            failureMessage:
                'Inventory count journal was not persisted; approval was rolled back.',
          );
        }
        approvedSession = session.copyWith(
          status: 'approved',
          approvedAt: now,
          approvedBy: _actorName(),
          journalEntryId: committedJournalEntryId,
          lines: updatedLines,
          updatedAt: now,
        );
        await BusinessSqliteStore.upsertInventoryCountInTransaction(
          sqliteDb,
          approvedSession!,
        );
        await AccountingService.recordInventoryCountAuditInTransaction(
          database: sqliteDb,
          action: 'approve_inventory_count',
          inventoryCountId: session.id,
          details:
              'تم اعتماد الجرد ${session.countNo} بعدد ${countedLines.length} صنف معدود.',
          createdBy: _actorName(),
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          createdAt: now,
        );
        committedMovements.addAll(movements);
      });

      _inventoryCounts[sessionIndex] = approvedSession!;
      if (committedMovements.isNotEmpty) {
        _mirrorAuthoritativeStockMovements(committedMovements);
        for (final movement in committedMovements.where(
          (item) => item.quantity > 0 && item.batchId.isNotEmpty,
        )) {
          final product = _findProductById(movement.productId);
          if (product == null) continue;
          _recordInventoryBatchSyncChanges(
            product: product,
            allocations: <BatchAllocation>[
              BatchAllocation(
                batchId: movement.batchId,
                quantity: movement.quantity,
                unitCost: movement.unitCost,
              ),
            ],
            sourceType: 'inventory_count',
            sourceId: session.id,
            sourceLineId: '${session.id}:count:${movement.productId}',
            now: now,
            unitCost: movement.unitCost,
          );
        }
      }
      await _refreshProductStockCompatibilityCache(
        countedLines.map((line) => line.productId),
      );
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(sqliteDb));
      _rebuildInventoryCostLayerLookupCache();
      _rememberSqliteDirtyBusinessRow(
        AppStore._inventoryCountsKey,
        approvedSession!.toJson(),
      );
      await _saveDirty(inventoryCounts: true, sync: true);
      if (committedJournalEntryId.isNotEmpty) {
        AccountingService.notifyCommittedMutation();
      }
      notifyListeners();
      return;
    }

    // Legacy/non-SQLite fallback. Keep the same business rule: a counted line
    // becomes stale when another stock movement occurs after it was counted.
    for (final line in countedLines) {
      final countedAt = line.countedAt;
      if (countedAt == null) continue;
      final changedAfterCount = _stockMovements.any((movement) {
        if (movement.productId != line.productId) return false;
        if (session.warehouseId.isNotEmpty &&
            movement.warehouseId != session.warehouseId) {
          return false;
        }
        return movement.date.isAfter(countedAt);
      });
      if (changedAfterCount) {
        throw StateError(
            'حدثت حركة مخزون بعد عد ${line.productName}. يجب إعادة عد هذا الصنف قبل اعتماد الجرد.');
      }
    }

    var productDerivedData = false;
    final accountingVariances = <InventoryCountVariance>[];
    final updatedLines = List<InventoryCountLine>.from(session.lines);
    for (final line in countedLines) {
      final productIndex = _productIndexById[line.productId];
      if (productIndex == null) continue;
      final product = _products[productIndex];
      if (!product.trackStock) continue;
      final theoreticalAtCount = _stockAt(
        line.productId,
        line.countedAt ?? session.createdAt,
      );
      final delta =
          (line.countedQty ?? theoreticalAtCount) - theoreticalAtCount;
      final historicalCost = delta < -0.000001
          ? _resolveCostForSaleItem(
              SaleItem(
                productId: product.id,
                productName: product.name,
                unitPrice: 0,
                quantity: delta.abs(),
              ),
              now,
            ).unitCost
          : (() {
              final cost = productCostFor(product.id);
              return _inventoryCostingMethod ==
                      InventoryCostingMethod.lastPurchaseCost
                  ? (cost.lastCost > 0 ? cost.lastCost : _safeUsdCost(product))
                  : (cost.averageCost > 0
                      ? cost.averageCost
                      : _safeUsdCost(product));
            })();
      final lineIndex = updatedLines.indexWhere(
        (item) => item.productId == line.productId,
      );
      final movementId = delta.abs() < 0.000001
          ? ''
          : '${session.id}-${line.productId}-count-adjustment';
      if (lineIndex != -1) {
        updatedLines[lineIndex] = line.copyWith(
          systemQtyAtApproval: theoreticalAtCount,
          differenceQty: delta,
          unitCost: historicalCost,
          differenceValue: delta.abs() * historicalCost,
          stockMovementId: movementId,
        );
      }
      if (delta.abs() < 0.000001) continue;
      accountingVariances.add(InventoryCountVariance(
        productId: line.productId,
        productName: line.productName,
        delta: delta,
        amount: delta.abs() * historicalCost,
      ));
      if (!_storeProfile.allowNegativeStock &&
          product.stock + delta < -0.000001) {
        throw StateError(
            'Inventory count would create negative stock for ${product.name}.');
      }
      _products[productIndex] = _withSyncMeta<Product>(
        product.copyWith(stock: product.stock + delta),
        now,
      );
      if (delta > 0) {
        final cost = productCostFor(product.id);
        _addInventoryCostLayerFromStockIncrease(
          id: '${session.id}-${line.productId}-count-layer',
          product: product,
          quantity: delta,
          unitCost:
              cost.averageCost > 0 ? cost.averageCost : _safeUsdCost(product),
          sourceType: 'inventory_count',
          sourceId: session.id,
          now: now,
        );
        productDerivedData = true;
      }
      _addStockMovement(
        StockMovement(
          id: movementId,
          productId: line.productId,
          productName: line.productName,
          type: 'count_adjustment',
          quantity: delta,
          date: now,
          referenceId: session.id,
          referenceNo: session.countNo,
          reason: 'Inventory count adjustment',
          adjustmentCategory:
              delta < 0 ? 'stock_count_shortage' : 'stock_count_overage',
          notes:
              'Counted at ${line.countedAt?.toIso8601String() ?? session.createdAt.toIso8601String()}. Theoretical at count: $theoreticalAtCount. Counted: ${line.countedQty}.',
          unitCost: historicalCost,
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
    final journalEntryId =
        await AccountingService.recordInventoryCountAdjustment(
      entryDate: now,
      referenceId: session.id,
      referenceNo: session.countNo,
      variances: accountingVariances,
      createdBy: _actorName(),
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      notes: session.notes,
    );
    _inventoryCounts[sessionIndex] = session.copyWith(
      status: 'approved',
      approvedAt: now,
      approvedBy: _actorName(),
      journalEntryId: journalEntryId,
      lines: updatedLines,
      updatedAt: now,
    );
    _rememberSqliteDirtyBusinessRow(
      AppStore._inventoryCountsKey,
      _inventoryCounts[sessionIndex].toJson(),
    );
    await _saveDirty(
      products: true,
      productDerivedData: productDerivedData,
      stockMovements: true,
      inventoryCounts: true,
      sync: true,
    );
    notifyListeners();
  }
}
