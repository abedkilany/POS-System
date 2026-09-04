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
    _rememberSqliteDirtyBusinessRow(AppStore._inventoryCountsKey, session.toJson());
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

Future<void> reverseInventoryCount(
    String sessionId, {
    String reason = '',
  }) async {
    requirePermission(AppPermission.inventoryCountsManage);
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isApproved) {
      if (session.isReversed) return;
      throw StateError('Only approved inventory counts can be reversed.');
    }
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'عكس الجرد المعتمد يتطلب قاعدة SQLite المهيأة لهذا الإصدار.');
    }
    final now = DateTime.now();
    final stockService = StockTransactionService(
      sqliteDb,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final committedReversals = <StockMovement>[];
    InventoryCountSession? reversedSession;
    var reversalJournalEntryId = '';
    await sqliteDb.transaction(() async {
      final originals =
          await BusinessSqliteStore.readUnreversedInventoryCountMovements(
        sqliteDb,
        session.id,
      );
      final reversals = <StockMovement>[];
      for (final original in originals) {
        if (original.batchId.isNotEmpty) {
          final product = _findProductById(original.productId);
          if (product == null) {
            throw StateError('Count product no longer exists.');
          }
          await BatchInventoryService(sqliteDb).adjustUnifiedBatchInTransaction(
            product: product,
            warehouseId: original.warehouseId,
            batchId: original.batchId,
            quantityDelta: -original.quantity,
            adjustedAt: now,
            storeId: appIdentity.storeId,
            deviceId: _deviceId,
          );
        } else {
          // Restore the exact historical value carried by the original count
          // movement.  A positive count layer may only be removed while it has
          // not been consumed by a downstream document; otherwise a reversal
          // would fabricate quantity/value out of sequence.
          if (original.quantity < -0.000001) {
            final product = _findProductById(original.productId);
            if (product == null) {
              throw StateError('Count product no longer exists.');
            }
            final restoredLayer = InventoryCostLayer(
              id: 'reversal_${original.id}_cost_layer',
              productId: product.id,
              productName: product.name,
              quantityReceived: original.quantity.abs(),
              quantityRemaining: original.quantity.abs(),
              unitCost: original.unitCost,
              currencyCode: 'USD',
              exchangeRate: 1,
              sourceType: 'inventory_count_reversal',
              sourceId: original.id,
              createdAt: now,
              updatedAt: now,
            );
            await BusinessSqliteStore.upsertEntityPayloads(
              sqliteDb,
              AppStore._inventoryCostLayersKey,
              <Map<String, dynamic>>[restoredLayer.toJson()],
              sortIndices: const <int?>[0],
            );
          } else if (original.quantity > 0.000001) {
            final layers =
                await BusinessSqliteStore.readInventoryCostLayers(sqliteDb);
            final layer = layers.firstWhere(
              (item) =>
                  item.productId == original.productId &&
                  item.sourceType == 'inventory_count' &&
                  item.sourceId == session.id,
              orElse: () =>
                  throw StateError('Historical count cost layer is missing.'),
            );
            if (layer.quantityRemaining + 0.000001 < original.quantity) {
              throw StateError(
                  'Inventory count gain has downstream consumption and cannot be reversed.');
            }
            final remaining = layer.quantityRemaining - original.quantity;
            await BusinessSqliteStore.upsertEntityPayloads(
              sqliteDb,
              AppStore._inventoryCostLayersKey,
              <Map<String, dynamic>>[
                layer
                    .copyWith(
                      quantityRemaining: remaining,
                      isClosed: remaining <= 0.000001,
                      updatedAt: now,
                    )
                    .toJson(),
              ],
              sortIndices: const <int?>[0],
            );
          }
        }
        reversals.add(original.copyWith(
          id: 'reversal_${original.id}',
          type: 'count_adjustment_reversal',
          quantity: -original.quantity,
          date: now,
          reason: reason.trim().isEmpty
              ? 'Reversal of inventory count ${session.countNo}'
              : reason.trim(),
          adjustmentCategory: 'stock_count_reversal',
          notes: 'Reversal of ${original.id}',
          movementGroupId: '${session.id}-reversal',
          documentLineId: '${original.documentLineId}-reversal',
          sourceMovementId: original.id,
          reversalOfMovementId: original.id,
          idempotencyKey: '${session.id}:count:reversal:${original.id}',
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          syncStatus: 'pending',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          lastModifiedByDeviceId: _deviceId,
          clearReviewedAt: true,
          reviewedBy: '',
          reviewNote: '',
        ));
      }
      if (reversals.isNotEmpty) {
        await stockService.recordMovementsInTransaction(
          operationType: 'inventory_count_reversal',
          documentType: 'inventory_count',
          documentId: session.id,
          movementGroupId: '${session.id}-reversal',
          idempotencyKey: '${session.id}:count:reversal',
          movements: reversals,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
          skipExistingMovementLookup: true,
        );
        await _assertUnifiedBatchMovementBalancesInTransaction(
          BatchInventoryService(sqliteDb),
          reversals.where((movement) => movement.batchId.isNotEmpty),
        );
      }
      reversalJournalEntryId =
          await AccountingService.reverseInventoryCountAdjustmentInTransaction(
        database: sqliteDb,
        referenceId: session.id,
        reason: reason,
        createdBy: _actorName(),
      );
      reversedSession = session.copyWith(
        status: 'reversed',
        reversalJournalEntryId: reversalJournalEntryId,
        reversedAt: now,
        reversedBy: _actorName(),
        reversalReason: reason.trim(),
        updatedAt: now,
      );
      await BusinessSqliteStore.upsertInventoryCountInTransaction(
        sqliteDb,
        reversedSession!,
      );
      await AccountingService.recordInventoryCountAuditInTransaction(
        database: sqliteDb,
        action: 'reverse_inventory_count',
        inventoryCountId: session.id,
        details: reason.trim().isEmpty
            ? 'تم عكس الجرد ${session.countNo}.'
            : 'تم عكس الجرد ${session.countNo}: ${reason.trim()}',
        createdBy: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        createdAt: now,
      );
      committedReversals.addAll(reversals);
    });

    _inventoryCounts[sessionIndex] = reversedSession!;
    if (committedReversals.isNotEmpty) {
      _mirrorAuthoritativeStockMovements(committedReversals);
      await _refreshProductStockCompatibilityCache(
        committedReversals.map((movement) => movement.productId),
      );
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(sqliteDb));
      _rebuildInventoryCostLayerLookupCache();
    }
    _rememberSqliteDirtyBusinessRow(
      AppStore._inventoryCountsKey,
      reversedSession!.toJson(),
    );
    await _saveDirty(inventoryCounts: true, sync: true);
    if (reversalJournalEntryId.isNotEmpty) {
      AccountingService.notifyCommittedMutation();
    }
    notifyListeners();
  }

Future<void> cancelInventoryCount(String sessionId) async {
    requirePermission(AppPermission.inventoryCountsManage);
    final sessionIndex = _inventoryCounts.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw ArgumentError('Inventory count session not found.');
    }
    final session = _inventoryCounts[sessionIndex];
    if (!session.isOpen) return;
    final now = DateTime.now();
    _inventoryCounts[sessionIndex] = session.copyWith(
      status: 'cancelled',
      updatedAt: now,
    );
    _rememberSqliteDirtyBusinessRow(
      AppStore._inventoryCountsKey,
      _inventoryCounts[sessionIndex].toJson(),
    );
    await _saveDirty(inventoryCounts: true);
    notifyListeners();
  }

Future<void> reviewAutoCorrection(
    String movementId, {
    String note = '',
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    final index = _stockMovements.indexWhere(
      (movement) => movement.id == movementId,
    );
    if (index == -1) throw ArgumentError('Stock movement not found.');
    final movement = _stockMovements[index];
    if (movement.type != 'auto_correction') {
      throw StateError('Only automatic corrections can be reviewed here.');
    }
    if (movement.isReviewed) return;
    final now = DateTime.now();
    final reviewer = _activeUser?.fullName.trim().isNotEmpty == true
        ? _activeUser!.fullName.trim()
        : (_activeUser?.username ?? currentRole);
    final updated = movement.copyWith(
      reviewedAt: now,
      reviewedBy: reviewer,
      reviewNote: note.trim(),
      updatedAt: now,
      syncStatus: 'pending',
      version: movement.version + 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _putStockMovementAtIndex(updated, index);
    _recordSyncChange(
      entityType: 'stock_movement',
      entityId: updated.id,
      operation: 'review',
      payload: updated.toJson(),
    );
    await _saveDirty(stockMovements: true, sync: true);
    notifyListeners();
  }

Future<void> setExpiryBatchStatus(String batchId, String status) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw const LocalizedDomainException('error_batch_database_required',
          fallback: 'Batch management requires the local database.');
    }
    final now = DateTime.now();
    await db.transaction(
        () => BatchInventoryService(db).setBatchStatusInTransaction(
              batchId: batchId,
              status: status,
              updatedAt: now,
              storeId: appIdentity.storeId,
              deviceId: _deviceId,
            ));
    _recordSyncChange(
      entityType: 'inventory_batch',
      entityId: batchId,
      operation: 'status',
      payload: <String, dynamic>{
        'id': batchId,
        'status': status,
        'updatedAt': now.toIso8601String(),
      },
    );
    notifyListeners();
  }

void _recordInventoryBatchSyncChanges({
    required Product product,
    required List<BatchAllocation> allocations,
    required String sourceType,
    required String sourceId,
    required DateTime now,
    double unitCost = 0,
    String sourceLineId = '',
    List<String> sourceLineIds = const <String>[],
    DateTime? receivedAt,
  }) {
    for (var allocationIndex = 0;
        allocationIndex < allocations.length;
        allocationIndex += 1) {
      final allocation = allocations[allocationIndex];
      final resolvedSourceLineId = sourceLineIds.length > allocationIndex
          ? sourceLineIds[allocationIndex]
          : sourceLineId;
      _recordSyncChange(
        entityType: 'inventory_batch',
        entityId: allocation.batchId,
        operation: 'upsert',
        payload: <String, dynamic>{
          'id': allocation.batchId,
          'productId': product.id,
          'productName': product.name,
          'supplierBatchNumber': allocation.supplierBatchNumber,
          'manufacturingDate': allocation.manufacturingDate?.toIso8601String(),
          'expirationDate': allocation.expirationDate?.toIso8601String(),
          'status': 'active',
          'sourceType': sourceType,
          'sourceId': sourceId,
          'sourceLineId': resolvedSourceLineId,
          'unitCost': allocation.unitCost > 0 ? allocation.unitCost : unitCost,
          'initialQuantity': allocation.quantity,
          'costCurrency': 'USD',
          'exchangeRate': 1,
          'receivedAt': (receivedAt ?? now).toIso8601String(),
          'storeId': appIdentity.storeId,
          'branchId': appIdentity.branchId,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'deviceId': _deviceId,
          'lastModifiedByDeviceId': _deviceId,
          'syncStatus': 'pending',
          'version': 1,
        },
      );
    }
  }

Future<void> adjustExpiryBatchStock({
    required String productId,
    required String warehouseId,
    required String batchId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    if (quantityDelta == 0) return;
    final product = _findProductById(productId);
    if (product == null || !product.expiryTrackingEnabled) {
      throw const LocalizedDomainException(
          'error_expiry_tracked_product_not_found',
          fallback: 'Expiry-tracked product not found.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw const LocalizedDomainException('error_batch_database_required',
          fallback: 'Batch management requires the local database.');
    }
    final now = DateTime.now();
    final operationId = '${now.microsecondsSinceEpoch}-$batchId-batch-adjust';
    final warehouse = resolveWarehouseForPurchase(warehouseId: warehouseId);
    var movement = StockMovement(
      id: operationId,
      productId: product.id,
      productName: product.name,
      type: quantityDelta < 0 ? 'inventory_loss' : 'count_adjustment',
      quantity: quantityDelta,
      date: now,
      referenceId: batchId,
      referenceNo: product.code,
      reason: reason,
      adjustmentCategory: adjustmentCategory,
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      batchId: batchId,
      movementGroupId: operationId,
      documentLineId: '$operationId-line',
      idempotencyKey: '$operationId-movement',
      unitCost: 0,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      lastModifiedByDeviceId: _deviceId,
    );
    final batchService = BatchInventoryService(db);
    await db.transaction(() async {
      await _ensureUnifiedBatchCutoverForProductInTransaction(
        db,
        product: product,
        warehouseId: warehouse.id,
        at: now,
      );
      final batchRow = await db.customSelect(
        '''
        SELECT unit_cost
        FROM inventory_batches
        WHERE id = ? AND product_id = ? AND store_id = ?
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(batchId),
          Variable<String>(product.id),
          Variable<String>(appIdentity.storeId),
        ],
      ).getSingleOrNull();
      if (batchRow == null) {
        throw StateError('Inventory batch was not found.');
      }
      final unitCost =
          (batchRow.data['unit_cost'] as num? ?? 0).toDouble();
      movement = movement.copyWith(unitCost: unitCost);
      await batchService.adjustUnifiedBatchInTransaction(
        product: product,
        warehouseId: warehouse.id,
        batchId: batchId,
        quantityDelta: quantityDelta,
        adjustedAt: now,
        storeId: appIdentity.storeId,
        deviceId: _deviceId,
      );
      final normalizedCategory = adjustmentCategory.trim().toLowerCase();
      final isExplicitExpiryDisposal = quantityDelta < 0 &&
          <String>{'expired', 'expiry'}.contains(normalizedCategory);
      if (isExplicitExpiryDisposal) {
        final expiryJournalId = await AccountingService.recordInventoryWaste(
          entryDate: now,
          referenceId: operationId,
          referenceNo: product.code,
          amount: quantityDelta.abs() * unitCost,
          productName: product.name,
          productId: product.id,
          createdBy: _activeUser?.fullName ?? _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          notes: reason,
          expenseRoleKey: 'inventory_expiry',
          database: db,
          withinExistingTransaction: true,
        );
        if (expiryJournalId.trim().isEmpty) {
          throw StateError(
              'Expiry stock loss requires a posted accounting journal.');
        }
        await _requirePostedJournalInTransaction(
          db,
          referenceType: 'inventory_waste',
          referenceId: operationId,
          failureMessage:
              'Expiry stock loss journal was not persisted; the adjustment was rolled back.',
        );
      } else {
        final adjustmentJournalId = await AccountingService
            .recordManualInventoryAdjustmentInTransaction(
          database: db,
          entryDate: now,
          referenceId: operationId,
          referenceNo: product.code,
          productId: product.id,
          productName: product.name,
          quantityDelta: quantityDelta,
          value: quantityDelta * unitCost,
          adjustmentCategory: adjustmentCategory,
          reason: reason,
          createdBy: _activeUser?.fullName ?? _deviceId,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
        );
        if (adjustmentJournalId.trim().isEmpty) {
          throw StateError(
              'Batch inventory adjustment requires a posted accounting journal.');
        }
        await _requirePostedJournalInTransaction(
          db,
          referenceType: 'inventory_adjustment',
          referenceId: operationId,
          failureMessage:
              'Batch inventory adjustment journal was not persisted; the adjustment was rolled back.',
        );
      }
      await StockTransactionService(
        db,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      ).recordMovementsInTransaction(
        operationType: 'batch_adjustment',
        documentType: 'inventory_batch',
        documentId: batchId,
        movementGroupId: operationId,
        idempotencyKey: '$operationId-op',
        movements: <StockMovement>[movement],
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        deviceId: _deviceId,
      );
      await batchService.assertWarehouseBatchBalanceInTransaction(
        productId: product.id,
        warehouseId: warehouse.id,
        storeId: appIdentity.storeId,
      );
    });
    _mirrorAuthoritativeStockMovements(<StockMovement>[movement]);
    await _refreshProductStockCompatibilityCache(<String>[productId]);
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    _recordSyncChange(
      entityType: 'stock_movement',
      entityId: movement.id,
      operation: 'adjust_batch',
      payload: movement.toJson(),
    );
    notifyListeners();
  }

Future<void> reverseExpiryBatchAdjustment(
    String movementId, {
    String reason = '',
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
          'Expiry reversal requires the authoritative SQLite store.');
    }
    final original = (await BusinessSqliteStore.readStockMovements(db))
        .where((movement) => movement.id == movementId)
        .firstOrNull;
    if (original == null || original.batchId.isEmpty) {
      throw ArgumentError('Expiry batch movement not found.');
    }
    if (original.reversalOfMovementId.isNotEmpty ||
        (await BusinessSqliteStore.readStockMovements(db)).any(
          (movement) => movement.reversalOfMovementId == original.id,
        )) {
      throw StateError('This expiry adjustment has already been reversed.');
    }
    final product = _findProductById(original.productId);
    if (product == null) throw StateError('Expiry product no longer exists.');
    final now = DateTime.now();
    final reversalId = 'reversal_${original.id}';
    final operationId = original.movementGroupId.isEmpty
        ? original.id
        : original.movementGroupId;
    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    await db.transaction(() async {
      final activeJournalRow = await db.customSelect(
        '''
        SELECT reference_type
        FROM journal_entries
        WHERE reference_id = ?
          AND reference_type IN ('inventory_waste', 'inventory_adjustment')
          AND deleted_at = '' AND status = 'posted'
        ORDER BY created_at DESC, id DESC
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(operationId)],
      ).getSingleOrNull();
      final accountingReferenceType =
          activeJournalRow?.data['reference_type']?.toString() ?? '';
      if (accountingReferenceType.isEmpty) {
        throw StateError(
            'The accounting journal for this batch adjustment is missing.');
      }

      if (original.quantity < 0) {
        await BatchInventoryService(db).restoreUnifiedInTransaction(
          product: product,
          warehouseId: original.warehouseId,
          allocations: <BatchAllocation>[
            BatchAllocation(
              batchId: original.batchId,
              quantity: original.quantity.abs(),
              unitCost: original.unitCost,
            ),
          ],
          restoredAt: now,
          storeId: appIdentity.storeId,
          deviceId: _deviceId,
        );

        // Only historical pre-Unified adjustments need a compatibility cost
        // layer. New Unified movements restore value through the Batch itself;
        // creating a parallel layer here would re-introduce a second inventory
        // valuation truth.
        final cutoverRow = await db.customSelect(
          '''
          SELECT cutover_at
          FROM unified_batch_cutovers
          WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable<String>(appIdentity.storeId),
            Variable<String>(original.warehouseId),
            Variable<String>(original.productId),
          ],
        ).getSingleOrNull();
        final cutoverAt = DateTime.tryParse(
            cutoverRow?.data['cutover_at']?.toString() ?? '');
        final isHistoricalPreUnified =
            cutoverAt == null || original.date.isBefore(cutoverAt);
        if (isHistoricalPreUnified) {
          final layer = InventoryCostLayer(
            id: '$reversalId-cost-layer',
            productId: product.id,
            productName: product.name,
            quantityReceived: original.quantity.abs(),
            quantityRemaining: original.quantity.abs(),
            unitCost: original.unitCost,
            currencyCode: 'USD',
            exchangeRate: 1,
            sourceType: 'expiry_batch_reversal',
            sourceId: original.id,
            createdAt: now,
            updatedAt: now,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[layer.toJson()],
            sortIndices: const <int?>[0],
          );
        }
      } else {
        // Phase-2/pre-Unified positive expiry adjustments may still own a
        // legacy cost layer. Remove it only when it exists; new Unified
        // adjustments have no parallel layer.
        final layers = await BusinessSqliteStore.readInventoryCostLayers(db);
        final layer = layers
            .where((item) =>
                item.productId == product.id &&
                item.sourceType == 'expiry_batch_adjustment' &&
                item.sourceId == operationId)
            .firstOrNull;
        if (layer != null) {
          if (layer.quantityRemaining + 0.000001 < original.quantity) {
            throw StateError(
                'Expiry gain has downstream consumption and cannot be reversed.');
          }
          final remaining = layer.quantityRemaining - original.quantity;
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[
              layer
                  .copyWith(
                    quantityRemaining: remaining,
                    isClosed: remaining <= 0.000001,
                    updatedAt: now,
                  )
                  .toJson(),
            ],
            sortIndices: const <int?>[0],
          );
        }
        await BatchInventoryService(db).adjustUnifiedBatchInTransaction(
          product: product,
          warehouseId: original.warehouseId,
          batchId: original.batchId,
          quantityDelta: -original.quantity,
          adjustedAt: now,
          storeId: appIdentity.storeId,
          deviceId: _deviceId,
        );
      }

      await _requirePostedJournalInTransaction(
        db,
        referenceType: accountingReferenceType,
        referenceId: operationId,
        failureMessage:
            'Batch adjustment journal is missing; the reversal was rolled back.',
      );
      await AccountingService.reverseEntryForReference(
        referenceType: accountingReferenceType,
        referenceId: operationId,
        reason: reason.trim().isEmpty ? 'Expiry adjustment reversal' : reason,
        createdBy: _actorName(),
        notifyChange: false,
        withinExistingTransaction: true,
      );
      await _requireNoActiveJournalInTransaction(
        db,
        referenceType: accountingReferenceType,
        referenceId: operationId,
        failureMessage:
            'Batch adjustment journal reversal did not complete; the reversal was rolled back.',
      );
      await stockService.recordReversalInTransaction(
        originalMovement: original,
        operationType: 'expiry_batch_reversal',
        documentType: 'inventory_batch',
        documentId: original.batchId,
        reason: reason.trim().isEmpty ? 'Expiry adjustment reversal' : reason,
        reversalMovementId: reversalId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        deviceId: _deviceId,
        syncTarget: _stockTransactionSyncTarget,
      );
      await BatchInventoryService(db).assertWarehouseBatchBalanceInTransaction(
        productId: original.productId,
        warehouseId: original.warehouseId,
        storeId: appIdentity.storeId,
      );
    });
    final reversal = original.copyWith(
      id: reversalId,
      type: '${original.type}_reversal',
      quantity: -original.quantity,
      date: now,
      reason: reason.trim().isEmpty ? 'Expiry adjustment reversal' : reason,
      sourceMovementId: original.id,
      reversalOfMovementId: original.id,
      movementGroupId: 'reversal-${original.id}',
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      lastModifiedByDeviceId: _deviceId,
    );
    _mirrorAuthoritativeStockMovements(<StockMovement>[reversal]);
    await _refreshProductStockCompatibilityCache(<String>[product.id]);
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    _recordSyncChange(
      entityType: 'stock_movement',
      entityId: reversal.id,
      operation: 'reverse_expiry_batch',
      payload: reversal.toJson(),
    );
    AccountingService.notifyCommittedMutation();
    notifyListeners();
  }

Future<int> manualStockAdjustmentVersion(String operationReferenceId) async {
    final operationId = operationReferenceId.trim();
    if (operationId.isEmpty) return 0;
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) return 0;
    final prefix = '$operationId:inventory_adjustment_edit:';
    final row = await db.customSelect(
      '''
      SELECT reference_id
      FROM journal_entries je
      WHERE je.reference_type = 'inventory_adjustment'
        AND (je.reference_id = ? OR instr(je.reference_id, ?) = 1)
        AND je.deleted_at = '' AND je.status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries rev
          WHERE rev.reversed_entry_id = je.id
            AND rev.deleted_at = '' AND rev.status = 'posted'
        )
      ORDER BY je.created_at DESC, je.entry_date DESC, je.id DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(operationId),
        Variable<String>(prefix),
      ],
    ).getSingleOrNull();
    final referenceId = row?.data['reference_id']?.toString() ?? '';
    if (referenceId.isEmpty) return 0;
    if (referenceId == operationId) return 1;
    final parsed = int.tryParse(
      referenceId.substring(prefix.length).replaceFirst('v', ''),
    );
    return parsed ?? 1;
  }

/// Safely edits a posted manual inventory adjustment while preserving the
/// original movement/journal history. The stable [operationReferenceId]
/// identifies the adjustment family; each successful edit reverses the active
/// stock/accounting effects and appends a new `inventory_adjustment_edit:vN`
/// member inside one authoritative SQLite transaction.
Future<void> editStockAdjustment({
    required String operationReferenceId,
    required int expectedVersion,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    final operationId = operationReferenceId.trim();
    if (operationId.isEmpty) {
      throw ArgumentError('Inventory adjustment reference is required.');
    }
    if (!quantityDelta.isFinite || quantityDelta.abs() <= 0.000001) {
      throw ArgumentError('Inventory adjustment quantity must be non-zero.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
        'Editing a posted inventory adjustment requires the authoritative SQLite store.',
      );
    }

    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final batchService = BatchInventoryService(db);
    late Product product;
    late String warehouseId;
    late String warehouseName;
    late int nextVersion;
    late String journalReferenceId;
    var newAdjustmentValue = 0.0;
    var newAdjustmentUnitCost = 0.0;
    var committedMovements = const <StockMovement>[];
    var committedAllocations = const <BatchAllocation>[];
    Product? persistedAdjustedProduct;

    Future<List<StockMovement>> readActiveFamily() async {
      final all = await BusinessSqliteStore.readStockMovements(db);
      final reversedIds = <String>{
        for (final movement in all)
          if (movement.reversalOfMovementId.trim().isNotEmpty)
            movement.reversalOfMovementId.trim(),
      };
      return all
          .where(
            (movement) =>
                movement.movementGroupId == operationId &&
                movement.reversalOfMovementId.isEmpty &&
                !reversedIds.contains(movement.id) &&
                (movement.type == 'inventory_loss' ||
                    movement.type == 'inventory_adjustment'),
          )
          .toList(growable: false);
    }

    await db.transaction(() async {
      final edited = await PostedDocumentEditPipeline<List<StockMovement>>(
        loadAuthoritative: () async {
          final active = await readActiveFamily();
          if (active.isEmpty) {
            throw StateError(
              'The active manual inventory adjustment was not found or has already been reversed.',
            );
          }
          final first = active.first;
          if (active.any(
            (movement) =>
                movement.productId != first.productId ||
                movement.warehouseId != first.warehouseId,
          )) {
            throw StateError(
              'Inventory adjustment family contains inconsistent product or warehouse movements.',
            );
          }
          final resolved = _findProductById(first.productId);
          if (resolved == null || !resolved.trackStock) {
            throw StateError(
              'Adjusted product no longer exists or no longer tracks stock.',
            );
          }
          product = resolved;
          warehouseId = first.warehouseId.trim().isEmpty
              ? Warehouse.defaultId
              : first.warehouseId.trim();
          warehouseName = first.warehouseName.trim().isEmpty
              ? resolveWarehouseForPurchase(warehouseId: warehouseId).name
              : first.warehouseName.trim();
          return active;
        },
        validatePermission: (_) async {
          requirePermission(AppPermission.inventoryCorrectionsManage);
        },
        validateVersion: (_) async {
          final prefix = '$operationId:inventory_adjustment_edit:';
          final row = await db.customSelect(
            '''
            SELECT reference_id
            FROM journal_entries je
            WHERE je.reference_type = 'inventory_adjustment'
              AND (je.reference_id = ? OR instr(je.reference_id, ?) = 1)
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
            ORDER BY je.created_at DESC, je.entry_date DESC, je.id DESC
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(operationId),
              Variable<String>(prefix),
            ],
          ).getSingleOrNull();
          if (row == null) {
            throw StateError(
              'The active accounting journal for this adjustment is missing.',
            );
          }
          final activeReference = row.data['reference_id']?.toString() ?? '';
          var currentVersion = 1;
          if (activeReference.startsWith(prefix)) {
            currentVersion = int.tryParse(
                  activeReference
                      .substring(prefix.length)
                      .replaceFirst('v', ''),
                ) ??
                1;
          }
          if (expectedVersion != currentVersion) {
            throw StateError(
              'Inventory adjustment changed concurrently. Reload it before editing.',
            );
          }
          nextVersion = currentVersion + 1;
          journalReferenceId =
              '$operationId:inventory_adjustment_edit:v$nextVersion';
        },
        validateDependencies: (current) async {
          for (final movement in current) {
            if (movement.batchId.trim().isEmpty) {
              throw StateError(
                'Historical non-batch inventory adjustments cannot be edited safely. Reverse them and create a new adjustment instead.',
              );
            }
            if (movement.quantity > 0.000001) {
              final balanceRow = await db.customSelect(
                '''
                SELECT COALESCE(quantity, 0) AS quantity
                FROM inventory_batch_balances
                WHERE store_id = ? AND warehouse_id = ?
                  AND product_id = ? AND batch_id = ?
                LIMIT 1
                ''',
                variables: <Variable<Object>>[
                  Variable<String>(appIdentity.storeId),
                  Variable<String>(warehouseId),
                  Variable<String>(product.id),
                  Variable<String>(movement.batchId),
                ],
              ).getSingleOrNull();
              final available =
                  (balanceRow?.data['quantity'] as num? ?? 0).toDouble();
              if (available + 0.000001 < movement.quantity) {
                throw StateError(
                  'This inventory gain has downstream consumption and cannot be edited until the downstream movement is reversed.',
                );
              }
            }
          }
        },
        reverseOperationalEffects: (current) async {
          final reversedAt = DateTime.now();
          for (final movement in current) {
            if (movement.quantity < -0.000001) {
              await batchService.restoreUnifiedInTransaction(
                product: product,
                warehouseId: warehouseId,
                allocations: <BatchAllocation>[
                  BatchAllocation(
                    batchId: movement.batchId,
                    quantity: movement.quantity.abs(),
                    unitCost: movement.unitCost,
                  ),
                ],
                restoredAt: reversedAt,
                storeId: appIdentity.storeId,
                deviceId: _deviceId,
              );
            } else if (movement.quantity > 0.000001) {
              await batchService.adjustUnifiedBatchInTransaction(
                product: product,
                warehouseId: warehouseId,
                batchId: movement.batchId,
                quantityDelta: -movement.quantity,
                adjustedAt: reversedAt,
                storeId: appIdentity.storeId,
                deviceId: _deviceId,
              );
            }
            await stockService.recordReversalInTransaction(
              originalMovement: movement,
              operationType: 'manual_adjustment_edit_reversal',
              documentType: 'inventory_adjustment',
              documentId: operationId,
              reason: 'Inventory adjustment edited',
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
              syncTarget: _stockTransactionSyncTarget,
            );
          }
          await batchService.assertWarehouseBatchBalanceInTransaction(
            productId: product.id,
            warehouseId: warehouseId,
            storeId: appIdentity.storeId,
          );
        },
        reverseAccountingEffects: (_) async {
          await AccountingService.reverseEntryForReference(
            referenceType: 'inventory_adjustment',
            referenceId: operationId,
            reason: 'Inventory adjustment edited',
            createdBy: _actorName(),
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
        },
        applyChanges: (current) async => current,
        rebuildOperationalEffects: (_) async {
          final now = DateTime.now();
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            db,
            product: product,
            warehouseId: warehouseId,
            at: now,
          );
          final baseMovementId =
              '$operationId-inventory-adjustment-edit-v$nextVersion';
          final resolved = <BatchAllocation>[];
          final movements = <StockMovement>[];
          if (quantityDelta < 0) {
            final allocations = await batchService.allocateUnifiedInTransaction(
              product: product,
              warehouseId: warehouseId,
              quantity: quantityDelta.abs(),
              movementDate: now,
              storeId: appIdentity.storeId,
              deviceId: _deviceId,
              branchId: appIdentity.branchId,
              allowNegativeStock: _storeProfile.allowNegativeStock,
            );
            resolved.addAll(allocations);
            newAdjustmentValue = allocations.fold<double>(
              0,
              (sum, allocation) =>
                  sum + allocation.quantity * allocation.unitCost,
            );
            newAdjustmentUnitCost = quantityDelta.abs() <= 0
                ? 0
                : newAdjustmentValue / quantityDelta.abs();
          } else {
            newAdjustmentUnitCost =
                await _unifiedOpeningCostForProductInTransaction(
              db,
              product: product,
              warehouseId: warehouseId,
            );
            final requested = product.expiryTrackingEnabled
                ? batchAllocations
                : <BatchAllocation>[
                    BatchAllocation(
                      batchId: '$baseMovementId-batch-0',
                      quantity: quantityDelta,
                      unitCost: newAdjustmentUnitCost,
                    ),
                  ];
            if (product.expiryTrackingEnabled && requested.isEmpty) {
              throw LocalizedDomainException(
                'error_expiry_batches_required',
                values: {'product': product.name},
                fallback: 'Expiry batches are required for ${product.name}.',
              );
            }
            final requestedTotal = requested.fold<double>(
              0,
              (sum, allocation) => sum + allocation.quantity,
            );
            if ((requestedTotal - quantityDelta).abs() > 0.000001) {
              throw LocalizedDomainException(
                'error_batch_quantity_total',
                values: {'product': product.name, 'quantity': quantityDelta},
                fallback:
                    'Batch quantities for ${product.name} must equal $quantityDelta.',
              );
            }
            for (var batchIndex = 0;
                batchIndex < requested.length;
                batchIndex += 1) {
              final input = requested[batchIndex];
              resolved.add(
                await batchService.addUnifiedBatchStockInTransaction(
                  product: product,
                  warehouseId: warehouseId,
                  batchId: input.batchId.trim().isEmpty
                      ? '$baseMovementId-batch-$batchIndex'
                      : input.batchId.trim(),
                  quantity: input.quantity,
                  unitCost: newAdjustmentUnitCost,
                  sourceType: 'manual_adjustment_edit',
                  sourceId: operationId,
                  sourceLineId:
                      '$operationId:inventory_adjustment_edit:v$nextVersion:$batchIndex',
                  receivedAt: now,
                  storeId: appIdentity.storeId,
                  branchId: appIdentity.branchId,
                  deviceId: _deviceId,
                  supplierBatchNumber: input.supplierBatchNumber,
                  manufacturingDate: input.manufacturingDate,
                  expirationDate: input.expirationDate,
                ),
              );
            }
            newAdjustmentValue = quantityDelta * newAdjustmentUnitCost;
          }

          for (var batchIndex = 0;
              batchIndex < resolved.length;
              batchIndex += 1) {
            final allocation = resolved[batchIndex];
            movements.add(
              StockMovement(
                id: '$baseMovementId-batch-$batchIndex',
                productId: product.id,
                productName: product.name,
                type: quantityDelta < 0
                    ? 'inventory_loss'
                    : 'inventory_adjustment',
                quantity: quantityDelta < 0
                    ? -allocation.quantity
                    : allocation.quantity,
                date: now,
                referenceId: product.id,
                referenceNo: product.code,
                reason: reason.trim().isEmpty
                    ? 'Manual adjustment edit'
                    : reason.trim(),
                adjustmentCategory: adjustmentCategory.trim().isEmpty
                    ? 'other'
                    : adjustmentCategory.trim(),
                notes: notes.trim(),
                evidenceRef: evidenceRef.trim(),
                warehouseId: warehouseId,
                warehouseName: warehouseName,
                batchId: allocation.batchId,
                movementGroupId: operationId,
                documentLineId:
                    '$operationId-edit-v$nextVersion-line-batch-$batchIndex',
                idempotencyKey:
                    '$operationId:inventory_adjustment_edit:v$nextVersion:$batchIndex',
                unitCost: allocation.unitCost,
                createdAt: now,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
          }
          await stockService.recordMovementsInTransaction(
            operationType: 'manual_adjustment_edit',
            documentType: 'inventory_adjustment',
            documentId: operationId,
            movementGroupId: operationId,
            idempotencyKey:
                '$operationId:inventory_adjustment_edit:v$nextVersion',
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
          committedAllocations = List<BatchAllocation>.unmodifiable(resolved);
          committedMovements = List<StockMovement>.unmodifiable(movements);
          return movements;
        },
        buildPostedSnapshot: (updated) async => updated,
        repostAccounting: (_) async {
          final journalId = await AccountingService
              .recordManualInventoryAdjustmentInTransaction(
            database: db,
            entryDate: DateTime.now(),
            referenceId: journalReferenceId,
            referenceNo: product.code,
            productId: product.id,
            productName: product.name,
            quantityDelta: quantityDelta,
            value: newAdjustmentValue,
            adjustmentCategory: adjustmentCategory,
            reason: reason,
            createdBy: _activeUser?.fullName ?? _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
          );
          if (newAdjustmentValue.abs() >= 0.005 && journalId.trim().isEmpty) {
            throw StateError(
              'Edited inventory adjustment accounting journal was not created.',
            );
          }
        },
        rebuildDerivedState: (_) async {
          final stockAfterRow = await db.customSelect(
            '''
            SELECT COALESCE(SUM(quantity), 0) AS quantity
            FROM warehouse_inventory
            WHERE product_id = ?
            ''',
            variables: <Variable<Object>>[Variable<String>(product.id)],
          ).getSingleOrNull();
          final stockAfter =
              (stockAfterRow?.data['quantity'] as num? ?? 0).toDouble();
          final changedAt = DateTime.now();
          persistedAdjustedProduct = _withSyncMeta<Product>(
            product.copyWith(stock: stockAfter, updatedAt: changedAt),
            changedAt,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._productsKey,
            <Map<String, dynamic>>[persistedAdjustedProduct!.toJson()],
            sortIndices: const <int?>[0],
          );
        },
        verifyIntegrity: (_) async {
          final activeRows = await db.customSelect(
            '''
            SELECT COALESCE(SUM(sm.quantity), 0) AS quantity
            FROM stock_movements sm
            WHERE sm.movement_group_id = ?
              AND sm.movement_type IN ('inventory_loss', 'inventory_adjustment')
              AND sm.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements rev
                WHERE rev.reversal_of_movement_id = sm.id
                  AND rev.deleted_at = ''
              )
            ''',
            variables: <Variable<Object>>[Variable<String>(operationId)],
          ).getSingle();
          final activeQuantity =
              (activeRows.data['quantity'] as num? ?? 0).toDouble();
          if ((activeQuantity - quantityDelta).abs() > 0.000001) {
            throw StateError(
              'Edited inventory adjustment failed stock integrity verification.',
            );
          }
          final journalRow = await db.customSelect(
            '''
            SELECT je.id
            FROM journal_entries je
            WHERE je.reference_type = 'inventory_adjustment'
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
              Variable<String>(journalReferenceId),
            ],
          ).getSingleOrNull();
          if (newAdjustmentValue.abs() >= 0.005 && journalRow == null) {
            throw StateError(
              'Edited inventory adjustment failed accounting integrity verification.',
            );
          }
          await batchService.assertWarehouseBatchBalanceInTransaction(
            productId: product.id,
            warehouseId: warehouseId,
            storeId: appIdentity.storeId,
          );
        },
      ).execute();
      if (edited.isEmpty) {
        throw StateError(
          'Edited inventory adjustment produced no stock movement.',
        );
      }
    });

    if (persistedAdjustedProduct != null) {
      final productIndex = _productIndexById[product.id];
      if (productIndex != null) {
        _products[productIndex] = persistedAdjustedProduct!;
      }
    }
    await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
    await _refreshProductStockCompatibilityCache(<String>[product.id]);
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    if (quantityDelta > 0 && committedAllocations.isNotEmpty) {
      _recordInventoryBatchSyncChanges(
        product: product,
        allocations: committedAllocations,
        sourceType: 'manual_adjustment_edit',
        sourceId: operationId,
        now: DateTime.now(),
        unitCost: newAdjustmentUnitCost,
        sourceLineIds: <String>[
          for (var index = 0; index < committedAllocations.length; index += 1)
            '$operationId:inventory_adjustment_edit:v$nextVersion:$index',
        ],
      );
    }
    for (final movement in committedMovements) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: 'edit_adjustment',
        payload: movement.toJson(),
      );
    }
    AccountingService.notifyCommittedMutation();
    notifyListeners();
  }

Future<void> adjustStock({
    required String productId,
    required String warehouseId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
    String operationReferenceId = '',
  }) async {
    requirePermission(AppPermission.inventoryCorrectionsManage);
    if (quantityDelta == 0) return;
    final index = _productIndexById[productId];
    if (index == null) throw ArgumentError('Product not found.');
    final now = DateTime.now();
    final product = _products[index];
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    final resolvedWarehouse =
        resolveWarehouseForPurchase(warehouseId: warehouseId);
    if (LocalDatabaseService.isSqliteAuthoritative &&
        SqliteMigrationManager.database != null) {
      final sqliteDb = SqliteMigrationManager.database!;
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final operationId = operationReferenceId.trim().isEmpty
          ? '${now.microsecondsSinceEpoch}-$productId-adjustment'
          : operationReferenceId.trim();
      final existingAdjustment = await sqliteDb.customSelect(
        '''
        SELECT id
        FROM stock_movements
        WHERE movement_group_id = ?
          AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(operationId)],
      ).getSingleOrNull();
      if (existingAdjustment != null) {
        await _refreshProductStockCompatibilityCache(<String>[productId]);
        return;
      }
      final baseMovement = StockMovement(
        id: operationId,
        productId: productId,
        productName: product.name,
        type: quantityDelta < 0 ? 'inventory_loss' : 'inventory_adjustment',
        quantity: quantityDelta,
        date: now,
        referenceId: productId,
        referenceNo: product.code,
        reason: reason.trim().isEmpty ? 'Manual adjustment' : reason.trim(),
        adjustmentCategory: adjustmentCategory.trim().isEmpty
            ? 'other'
            : adjustmentCategory.trim(),
        notes: notes.trim(),
        evidenceRef: evidenceRef.trim(),
        warehouseId: resolvedWarehouse.id,
        warehouseName: resolvedWarehouse.name,
        movementGroupId: operationId,
        documentLineId: '$operationId-line',
        // Replaced with the resolved historic cost before posting.
        unitCost: 0,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      );
      var movements = <StockMovement>[baseMovement];
      var resolvedBatchAllocations = const <BatchAllocation>[];
      var adjustmentUnitCost = _safeUsdCost(product);
      var adjustmentValue = 0.0;
      final batchService = BatchInventoryService(sqliteDb);
      Product? persistedAdjustedProduct;
      await _traceAsync<void>('inventory.adjustStock', 'sqlite_transaction',
          () async {
        await sqliteDb.transaction(() async {
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            sqliteDb,
            product: product,
            warehouseId: resolvedWarehouse.id,
            at: now,
          );
          if (quantityDelta < 0) {
            final allocations = await batchService.allocateUnifiedInTransaction(
              product: product,
              warehouseId: resolvedWarehouse.id,
              quantity: quantityDelta.abs(),
              movementDate: now,
              storeId: appIdentity.storeId,
              deviceId: _deviceId,
              branchId: appIdentity.branchId,
              allowNegativeStock: _storeProfile.allowNegativeStock,
            );
            resolvedBatchAllocations = allocations;
            adjustmentValue = allocations.fold<double>(
              0,
              (sum, allocation) =>
                  sum + (allocation.quantity * allocation.unitCost),
            );
            adjustmentUnitCost = quantityDelta.abs() <= 0
                ? 0
                : adjustmentValue / quantityDelta.abs();
            movements = <StockMovement>[
              for (var batchIndex = 0;
                  batchIndex < allocations.length;
                  batchIndex += 1)
                baseMovement.copyWith(
                  id: '$operationId-batch-$batchIndex',
                  quantity: -allocations[batchIndex].quantity,
                  batchId: allocations[batchIndex].batchId,
                  unitCost: allocations[batchIndex].unitCost,
                  documentLineId: '$operationId-line-batch-$batchIndex',
                  idempotencyKey: '$operationId:batch:$batchIndex',
                ),
            ];
          } else {
            adjustmentUnitCost = await _unifiedOpeningCostForProductInTransaction(
              sqliteDb,
              product: product,
              warehouseId: resolvedWarehouse.id,
            );
            final requested = product.expiryTrackingEnabled
                ? batchAllocations
                : <BatchAllocation>[
                    BatchAllocation(
                      batchId: '$operationId-batch-0',
                      quantity: quantityDelta,
                      unitCost: adjustmentUnitCost,
                    ),
                  ];
            if (product.expiryTrackingEnabled && requested.isEmpty) {
              throw LocalizedDomainException(
                'error_expiry_batches_required',
                values: {'product': product.name},
                fallback: 'Expiry batches are required for ${product.name}.',
              );
            }
            final requestedTotal = requested.fold<double>(
              0,
              (sum, allocation) => sum + allocation.quantity,
            );
            if ((requestedTotal - quantityDelta).abs() > 0.000001) {
              throw LocalizedDomainException(
                'error_batch_quantity_total',
                values: {'product': product.name, 'quantity': quantityDelta},
                fallback:
                    'Batch quantities for ${product.name} must equal $quantityDelta.',
              );
            }
            final allocations = <BatchAllocation>[];
            for (var batchIndex = 0;
                batchIndex < requested.length;
                batchIndex += 1) {
              final input = requested[batchIndex];
              final allocation =
                  await batchService.addUnifiedBatchStockInTransaction(
                product: product,
                warehouseId: resolvedWarehouse.id,
                batchId: input.batchId.trim().isEmpty
                    ? '$operationId-batch-$batchIndex'
                    : input.batchId.trim(),
                quantity: input.quantity,
                unitCost: adjustmentUnitCost,
                sourceType: 'manual_adjustment',
                sourceId: operationId,
                sourceLineId: '$operationId:adjustment:$batchIndex',
                receivedAt: now,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                deviceId: _deviceId,
                supplierBatchNumber: input.supplierBatchNumber,
                manufacturingDate: input.manufacturingDate,
                expirationDate: input.expirationDate,
              );
              allocations.add(allocation);
            }
            resolvedBatchAllocations = allocations;
            adjustmentValue = quantityDelta * adjustmentUnitCost;
            movements = <StockMovement>[
              for (var batchIndex = 0;
                  batchIndex < allocations.length;
                  batchIndex += 1)
                baseMovement.copyWith(
                  id: '$operationId-batch-$batchIndex',
                  quantity: allocations[batchIndex].quantity,
                  batchId: allocations[batchIndex].batchId,
                  unitCost: allocations[batchIndex].unitCost,
                  documentLineId: '$operationId-line-batch-$batchIndex',
                  idempotencyKey: '$operationId:batch:$batchIndex',
                ),
            ];
          }
          await stockService.recordMovementsInTransaction(
            operationType: 'manual_adjustment',
            documentType: 'inventory_adjustment',
            documentId: operationId,
            movementGroupId: operationId,
            idempotencyKey: '$operationId-op',
            movements: movements,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            movements,
          );
          await AccountingService.recordManualInventoryAdjustmentInTransaction(
            database: sqliteDb,
            entryDate: now,
            referenceId: operationId,
            referenceNo: product.code,
            productId: product.id,
            productName: product.name,
            quantityDelta: quantityDelta,
            value: adjustmentValue,
            adjustmentCategory: adjustmentCategory,
            reason: reason,
            createdBy: _activeUser?.fullName ?? _deviceId,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
          );
          final stockAfterRow = await sqliteDb.customSelect(
            '''
            SELECT COALESCE(SUM(quantity), 0) AS quantity
            FROM warehouse_inventory
            WHERE product_id = ?
            ''',
            variables: <Variable<Object>>[Variable<String>(product.id)],
          ).getSingleOrNull();
          final stockAfter =
              (stockAfterRow?.data['quantity'] as num? ?? 0).toDouble();
          persistedAdjustedProduct = _withSyncMeta<Product>(
            product.copyWith(stock: stockAfter, updatedAt: now),
            now,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._productsKey,
            <Map<String, dynamic>>[persistedAdjustedProduct!.toJson()],
            sortIndices: const <int?>[0],
          );
        });
      });
      _mirrorAuthoritativeStockMovements(movements);
      if (persistedAdjustedProduct != null) {
        _products[index] = persistedAdjustedProduct!;
      }
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(sqliteDb));
      _rebuildInventoryCostLayerLookupCache();
      if (quantityDelta > 0 && resolvedBatchAllocations.isNotEmpty) {
        _recordInventoryBatchSyncChanges(
          product: product,
          allocations: resolvedBatchAllocations,
          sourceType: 'manual_adjustment',
          sourceId: operationId,
          now: now,
          unitCost: adjustmentUnitCost,
          sourceLineIds: <String>[
            for (var index = 0;
                index < resolvedBatchAllocations.length;
                index += 1)
              '$operationId:adjustment:$index',
          ],
        );
      }
      await _traceAsync<void>(
        'inventory.adjustStock',
        'refresh_product_stock_cache',
        () => _refreshProductStockCompatibilityCache(<String>[productId]),
      );
      _traceSync('inventory.adjustStock', 'record_sync_change', () {
        for (final movement in movements) {
          _recordSyncChange(
            entityType: 'stock_movement',
            entityId: movement.id,
            operation: 'adjust',
            payload: movement.toJson(),
          );
        }
      });
      notifyListeners();
      return;
    }
    final nextStock = product.stock + quantityDelta;
    if (!_storeProfile.allowNegativeStock && nextStock < -0.000001) {
      throw StateError('Insufficient stock in ${resolvedWarehouse.name}.');
    }
    _products[index] = _withSyncMeta<Product>(
      product.copyWith(stock: product.stock + quantityDelta),
      now,
    );
    _addStockMovement(
      StockMovement(
        id: operationReferenceId.trim().isEmpty
            ? '${now.microsecondsSinceEpoch}-$productId-adjustment'
            : operationReferenceId.trim(),
        productId: productId,
        productName: product.name,
        type: quantityDelta < 0 ? 'inventory_loss' : 'inventory_adjustment',
        quantity: quantityDelta,
        date: now,
        referenceId: productId,
        referenceNo: product.code,
        reason: reason.trim().isEmpty ? 'Manual adjustment' : reason.trim(),
        adjustmentCategory: adjustmentCategory.trim().isEmpty
            ? 'other'
            : adjustmentCategory.trim(),
        notes: notes.trim(),
        evidenceRef: evidenceRef.trim(),
        unitCost: product.usdCost,
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      ),
      recordSync: true,
    );
    await _saveDirty(
      products: true,
      productDerivedData: false,
      stockMovements: true,
      sync: true,
    );
    notifyListeners();
  }

Future<void> recordWasteLoss({
    required String productId,
    required String warehouseId,
    required double quantity,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
  }) async {
    requirePermission(AppPermission.inventoryWasteManage);
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError('يجب أن تكون كمية الهدر أكبر من صفر.');
    }
    final product = _findProductById(productId);
    if (product == null) throw ArgumentError('Product not found.');
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
          'Inventory waste requires the authoritative SQLite store.');
    }
    final now = DateTime.now();
    final operationId = '${now.microsecondsSinceEpoch}-$productId-waste';
    final warehouse = resolveWarehouseForSale(warehouseId: warehouseId);
    var movement = StockMovement(
      id: '$operationId-movement',
      productId: product.id,
      productName: product.name,
      type: 'waste',
      quantity: -quantity,
      date: now,
      referenceId: operationId,
      referenceNo: product.code,
      reason: reason.trim(),
      adjustmentCategory: adjustmentCategory,
      notes: notes.trim(),
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      movementGroupId: operationId,
      documentLineId: '$operationId-line',
      idempotencyKey: '$operationId:waste',
      unitCost: _safeUsdCost(product),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      lastModifiedByDeviceId: _deviceId,
    );
    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final roleKey = switch (adjustmentCategory.trim().toLowerCase()) {
      'expired' || 'expiry' => 'inventory_expiry',
      'weight' || 'weight_variance' => 'inventory_weight_variance',
      _ => 'inventory_damage',
    };
    var movements = <StockMovement>[movement];
    final batchService = BatchInventoryService(db);
    var wasteValue = 0.0;
    await db.transaction(() async {
      await _ensureUnifiedBatchCutoverForProductInTransaction(
        db,
        product: product,
        warehouseId: warehouse.id,
        at: now,
      );
      final allocations = await batchService.allocateUnifiedInTransaction(
        product: product,
        warehouseId: warehouse.id,
        quantity: quantity,
        movementDate: now,
        storeId: appIdentity.storeId,
        deviceId: _deviceId,
        branchId: appIdentity.branchId,
        allowNegativeStock: _storeProfile.allowNegativeStock,
      );
      wasteValue = allocations.fold<double>(
        0,
        (sum, allocation) =>
            sum + (allocation.quantity * allocation.unitCost),
      );
      movements = <StockMovement>[
        for (var index = 0; index < allocations.length; index += 1)
          movement.copyWith(
            id: '$operationId-batch-$index',
            quantity: -allocations[index].quantity,
            batchId: allocations[index].batchId,
            unitCost: allocations[index].unitCost,
            documentLineId: '$operationId-line-batch-$index',
            idempotencyKey: '$operationId:waste:batch:$index',
          ),
      ];
      final wasteJournalId = await AccountingService.recordInventoryWaste(
        entryDate: now,
        referenceId: operationId,
        referenceNo: product.code,
        amount: wasteValue,
        productName: product.name,
        productId: product.id,
        createdBy: _activeUser?.fullName ?? _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        notes: notes,
        expenseRoleKey: roleKey,
        database: db,
        withinExistingTransaction: true,
      );
      if (wasteJournalId.trim().isEmpty) {
        throw StateError('Waste loss requires a posted accounting journal.');
      }
      await _requirePostedJournalInTransaction(
        db,
        referenceType: 'inventory_waste',
        referenceId: operationId,
        failureMessage:
            'Waste journal was not persisted; the waste operation was rolled back.',
      );
      await stockService.recordMovementsInTransaction(
        operationType: 'inventory_waste',
        documentType: 'inventory_waste',
        documentId: operationId,
        movementGroupId: operationId,
        idempotencyKey: '$operationId:waste',
        movements: movements,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        deviceId: _deviceId,
      );
      await _assertUnifiedBatchMovementBalancesInTransaction(
        batchService,
        movements,
      );
    });
    _mirrorAuthoritativeStockMovements(movements);
    await _refreshProductStockCompatibilityCache(<String>{product.id});
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    for (final postedMovement in movements) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: postedMovement.id,
        operation: 'inventory_waste',
        payload: postedMovement.toJson(),
      );
    }
    notifyListeners();
  }

Future<void> reverseWasteLossGroup(String movementId) async {
    requirePermission(AppPermission.inventoryWasteManage);
    final selected = _stockMovements.firstWhere(
      (item) => item.id == movementId,
      orElse: () => throw ArgumentError('Waste movement not found.'),
    );
    final groupId = selected.movementGroupId.isEmpty
        ? selected.id
        : selected.movementGroupId;
    final originals = _stockMovements
        .where((item) =>
            (item.movementGroupId.isEmpty ? item.id : item.movementGroupId) ==
                groupId &&
            <String>{'waste', 'inventory_loss'}.contains(item.type))
        .toList();
    if (originals.isEmpty ||
        originals.any((item) => item.reversalOfMovementId.isNotEmpty) ||
        _stockMovements.any((item) => originals
            .any((original) => item.reversalOfMovementId == original.id))) {
      throw StateError('This waste operation has already been reversed.');
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
          'Waste reversal requires the authoritative SQLite store.');
    }
    final now = DateTime.now();
    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
    );
    final reversals = <StockMovement>[];
    await db.transaction(() async {
      for (final original in originals) {
        final product = _findProductById(original.productId);
        if (product == null) {
          throw StateError('Waste product no longer exists.');
        }
        if (original.batchId.isNotEmpty) {
          await BatchInventoryService(db).restoreUnifiedInTransaction(
            product: product,
            warehouseId: original.warehouseId,
            allocations: <BatchAllocation>[
              BatchAllocation(
                batchId: original.batchId,
                quantity: original.quantity.abs(),
                unitCost: original.unitCost,
              ),
            ],
            restoredAt: now,
            storeId: appIdentity.storeId,
            deviceId: _deviceId,
          );
        } else {
          // Legacy pre-Unified waste rows keep their historical cost-layer
          // reversal behavior for backward compatibility only.
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[
              InventoryCostLayer(
                id: 'reversal_${original.id}_cost_layer',
                productId: product.id,
                productName: product.name,
                quantityReceived: original.quantity.abs(),
                quantityRemaining: original.quantity.abs(),
                unitCost: original.unitCost,
                currencyCode: 'USD',
                exchangeRate: 1,
                sourceType: 'inventory_waste_reversal',
                sourceId: original.id,
                createdAt: now,
                updatedAt: now,
              ).toJson(),
            ],
            sortIndices: const <int?>[0],
          );
        }
        final reversal = original.copyWith(
          id: 'reversal_${original.id}',
          type: '${original.type}_reversal',
          quantity: -original.quantity,
          date: now,
          reason: 'Safe reversal of waste operation',
          sourceMovementId: original.id,
          reversalOfMovementId: original.id,
          movementGroupId: 'reversal-$groupId',
          idempotencyKey: 'reversal:${original.id}',
          createdAt: now,
          updatedAt: now,
          deviceId: _deviceId,
          syncStatus: 'pending',
          lastModifiedByDeviceId: _deviceId,
        );
        await stockService.recordReversalInTransaction(
          originalMovement: original,
          operationType: 'inventory_waste_reversal',
          documentType: 'inventory_waste',
          documentId: groupId,
          reason: reversal.reason,
          reversalMovementId: reversal.id,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
          syncTarget: _stockTransactionSyncTarget,
        );
        reversals.add(reversal);
      }
      await _assertUnifiedBatchMovementBalancesInTransaction(
        BatchInventoryService(db),
        reversals.where((movement) => movement.batchId.isNotEmpty),
      );
      await _requirePostedJournalInTransaction(
        db,
        referenceType: 'inventory_waste',
        referenceId: groupId,
        failureMessage:
            'Waste journal is missing; the waste reversal was rolled back.',
      );
      await AccountingService.reverseEntryForReference(
        referenceType: 'inventory_waste',
        referenceId: groupId,
        reason: 'Safe reversal of waste operation',
        createdBy: _actorName(),
        notifyChange: false,
        withinExistingTransaction: true,
      );
      await _requireNoActiveJournalInTransaction(
        db,
        referenceType: 'inventory_waste',
        referenceId: groupId,
        failureMessage:
            'Waste journal reversal did not complete; the waste reversal was rolled back.',
      );
    });
    _mirrorAuthoritativeStockMovements(reversals);
    await _refreshProductStockCompatibilityCache(
        originals.map((item) => item.productId));
    _inventoryCostLayers
      ..clear()
      ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
    _rebuildInventoryCostLayerLookupCache();
    for (final reversal in reversals) {
      _recordSyncChange(
          entityType: 'stock_movement',
          entityId: reversal.id,
          operation: 'reverse_waste',
          payload: reversal.toJson());
    }
    AccountingService.notifyCommittedMutation();
    notifyListeners();
  }

Future<void> deleteWasteLoss(String movementId) async {
    requirePermission(AppPermission.inventoryWasteManage);
    final index = _stockMovements.indexWhere((item) => item.id == movementId);
    if (index == -1) throw ArgumentError('Waste movement not found.');
    final original = _stockMovements[index];
    // `waste` is canonical; `inventory_loss` remains supported for legacy data.
    if (!<String>{'waste', 'inventory_loss'}.contains(original.type)) {
      throw StateError('Only waste movements can be deleted safely.');
    }
    if (original.movementGroupId.isNotEmpty &&
        _stockMovements
                .where((item) =>
                    item.movementGroupId == original.movementGroupId &&
                    item.reversalOfMovementId.isEmpty)
                .length >
            1) {
      return reverseWasteLossGroup(movementId);
    }
    if (original.reversalOfMovementId.isNotEmpty ||
        _stockMovements.any(
          (item) => item.reversalOfMovementId == original.id,
        )) {
      throw StateError('This waste movement has already been reversed.');
    }

    final now = DateTime.now();
    final reversal = original.copyWith(
      id: 'reversal_${original.id}',
      type: 'inventory_loss_reversal',
      quantity: -original.quantity,
      reason: 'حذف آمن لحركة الهدر',
      sourceMovementId: original.id,
      reversalOfMovementId: original.id,
      movementGroupId: 'reversal-${original.id}',
      idempotencyKey: 'reversal:${original.id}',
      date: now,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      lastModifiedByDeviceId: _deviceId,
    );
    final db = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && db != null) {
      final stockService = StockTransactionService(
        db,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      await db.transaction(() async {
        final product = _findProductById(original.productId);
        if (product == null) {
          throw StateError('Waste product no longer exists.');
        }
        if (original.batchId.isNotEmpty) {
          await BatchInventoryService(db).restoreUnifiedInTransaction(
            product: product,
            warehouseId: original.warehouseId,
            allocations: <BatchAllocation>[
              BatchAllocation(
                batchId: original.batchId,
                quantity: original.quantity.abs(),
                unitCost: original.unitCost,
              ),
            ],
            restoredAt: now,
            storeId: appIdentity.storeId,
            deviceId: _deviceId,
          );
        } else {
          final restoredLayer = InventoryCostLayer(
            id: 'reversal_${original.id}_cost_layer',
            productId: product.id,
            productName: product.name,
            quantityReceived: original.quantity.abs(),
            quantityRemaining: original.quantity.abs(),
            unitCost: original.unitCost,
            currencyCode: 'USD',
            exchangeRate: 1,
            sourceType: 'inventory_waste_reversal',
            sourceId: original.id,
            createdAt: now,
            updatedAt: now,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._inventoryCostLayersKey,
            <Map<String, dynamic>>[restoredLayer.toJson()],
            sortIndices: const <int?>[0],
          );
        }
        await stockService.recordReversalInTransaction(
          originalMovement: original,
          operationType: 'inventory_waste_reversal',
          documentType: 'inventory_waste',
          documentId: original.movementGroupId.isEmpty
              ? original.id
              : original.movementGroupId,
          reason: 'حذف آمن لحركة الهدر',
          reversalMovementId: reversal.id,
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          deviceId: _deviceId,
          syncTarget: _stockTransactionSyncTarget,
        );
        if (original.batchId.isNotEmpty) {
          await BatchInventoryService(db).assertWarehouseBatchBalanceInTransaction(
            productId: original.productId,
            warehouseId: original.warehouseId,
            storeId: appIdentity.storeId,
          );
        }
        final wasteReferenceId = original.movementGroupId.isEmpty
            ? original.id
            : original.movementGroupId;
        await _requirePostedJournalInTransaction(
          db,
          referenceType: 'inventory_waste',
          referenceId: wasteReferenceId,
          failureMessage:
              'Waste journal is missing; the safe delete was rolled back.',
        );
        await AccountingService.reverseEntryForReference(
          referenceType: 'inventory_waste',
          referenceId: wasteReferenceId,
          reason: 'حذف آمن لحركة الهدر',
          createdBy: _deviceId,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _requireNoActiveJournalInTransaction(
          db,
          referenceType: 'inventory_waste',
          referenceId: wasteReferenceId,
          failureMessage:
              'Waste journal reversal did not complete; the safe delete was rolled back.',
        );
      });
      _mirrorAuthoritativeStockMovements(<StockMovement>[reversal]);
      await _refreshProductStockCompatibilityCache(
          <String>[original.productId]);
      _inventoryCostLayers
        ..clear()
        ..addAll(await BusinessSqliteStore.readInventoryCostLayers(db));
      _rebuildInventoryCostLayerLookupCache();
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: reversal.id,
        operation: 'reverse_waste',
        payload: reversal.toJson(),
      );
      AccountingService.notifyCommittedMutation();
      notifyListeners();
      return;
    }

    final productIndex = _productIndexById[original.productId];
    if (productIndex != null) {
      final product = _products[productIndex];
      _products[productIndex] = _withSyncMeta<Product>(
        product.copyWith(stock: product.stock - original.quantity),
        now,
      );
    }
    _addStockMovement(reversal, recordSync: true);
    await AccountingService.reverseEntryForReference(
      referenceType: 'inventory_waste',
      referenceId: original.movementGroupId.isEmpty
          ? original.id
          : original.movementGroupId,
      reason: 'حذف آمن لحركة الهدر',
      createdBy: _deviceId,
    );
    await _saveDirty(
      products: productIndex != null,
      productDerivedData: false,
      stockMovements: true,
      sync: true,
    );
    notifyListeners();
  }

void _applyPurchaseStock(Purchase purchase, DateTime now) {
    for (var lineIndex = 0; lineIndex < purchase.items.length; lineIndex += 1) {
      final item = purchase.items[lineIndex];
      final index = _productIndexById[item.productId];
      if (index == null) continue;
      final product = _products[index];
      if (!product.trackStock) continue;
      final receivedQty = item.baseQuantity;
      final newStock = product.stock + receivedQty;
      final baseUnitCost = item.unitCostPerBase;
      final productCost = _upsertProductCostFromPurchase(
        product: product,
        receivedQty: receivedQty,
        baseUnitCost: baseUnitCost,
        now: now,
      );
      _addInventoryCostLayerFromPurchase(
        purchase: purchase,
        item: item,
        lineIndex: lineIndex,
        quantity: receivedQty,
        unitCost: baseUnitCost,
        now: now,
      );
      final appliedCost =
          _inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost
              ? productCost.lastCost
              : productCost.averageCost;
      _products[index] = _withSyncMeta<Product>(
        product.copyWith(
          stock: newStock,
          cost: appliedCost,
          usdCost: appliedCost,
          originalCost: appliedCost,
          costCurrency: 'USD',
          costExchangeRateAtEntry: storeProfile.usdToLbpRate,
        ),
        now,
      );
      _addStockMovement(
        StockMovement(
          id: '${purchase.id}-$lineIndex-${item.productId}-purchase-receive',
          productId: item.productId,
          productName: item.productName,
          type: 'purchase_receive',
          quantity: item.baseQuantity,
          date: now,
          referenceId: purchase.id,
          referenceNo: purchase.purchaseNo,
          reason: 'Purchase received',
          unitCost: item.unitCostPerBase,
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
  }

void _addStockMovement(StockMovement movement, {bool recordSync = false}) {
    final index = _stockMovementIndexForId(movement.id);
    if (index != -1) return;
    _putStockMovementAtIndex(movement, _stockMovements.length);
    if (recordSync) {
      _recordSyncChange(
        entityType: 'stock_movement',
        entityId: movement.id,
        operation: movement.type,
        payload: movement.toJson(),
      );
    }
  }

Future<void> _reconcileInventoryAccountsAfterBomChange(
    BillOfMaterials bom, {
    VentioDriftDatabase? database,
    bool withinExistingTransaction = false,
  }) async {
    if (kIsWeb ||
        !LocalDatabaseService.isSqliteAuthoritative ||
        !AccountingService.isAvailable) {
      return;
    }
    final reconciled =
        await AccountingService.reconcileInventoryAccountClassification(
      referenceContext: 'bom:${bom.id}:v${bom.version}',
      database: database,
      withinExistingTransaction: withinExistingTransaction,
    );
    if (!reconciled) {
      throw StateError(
        'BOM inventory account reclassification is blocked because inventory GL does not reconcile to Unified Batch valuation.',
      );
    }
  }

}
