part of 'app_store.dart';

extension _AppStoreSplitPurchases on AppStore {
String _stablePurchaseLineId(Purchase purchase, PurchaseItem item, int lineIndex) {
    final existing = item.lineId.trim();
    return existing.isNotEmpty ? existing : '${purchase.id}:line:$lineIndex';
  }

Future<double> _unifiedOpeningCostForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
  }) async {
    final row = await sqliteDb.customSelect(
      '''
      SELECT
        COALESCE((
          SELECT wi.quantity
          FROM warehouse_inventory wi
          WHERE wi.store_id = ? AND wi.warehouse_id = ? AND wi.product_id = ?
          LIMIT 1
        ), 0) AS warehouse_quantity,
        COUNT(sm.id) AS movement_count,
        COALESCE(SUM(sm.quantity), 0) AS movement_quantity,
        COALESCE(SUM(sm.quantity * sm.unit_cost), 0) AS carrying_value
      FROM stock_movements sm
      WHERE sm.store_id = ? AND sm.warehouse_id = ? AND sm.product_id = ?
        AND sm.deleted_at = ''
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
        Variable<String>(appIdentity.storeId),
        Variable<String>(warehouseId),
        Variable<String>(product.id),
      ],
    ).getSingle();
    final warehouseQuantity =
        (row.data['warehouse_quantity'] as num? ?? 0).toDouble();
    final movementCount = (row.data['movement_count'] as num? ?? 0).toInt();
    final movementQuantity =
        (row.data['movement_quantity'] as num? ?? 0).toDouble();
    final carryingValue = (row.data['carrying_value'] as num? ?? 0).toDouble();
    const tolerance = 0.000001;
    if (warehouseQuantity > tolerance &&
        movementCount > 0 &&
        (movementQuantity - warehouseQuantity).abs() <= tolerance &&
        carryingValue >= -tolerance) {
      return max(0.0, carryingValue) / warehouseQuantity;
    }

    final cost = productCostFor(product.id);
    if (cost.averageCost > 0) return cost.averageCost;
    if (product.usdCost > 0) return product.usdCost;
    if (product.cost > 0) return product.cost;
    return 0;
  }

Future<void> _ensureUnifiedBatchCutoverForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
    required DateTime at,
  }) async {
    final openingUnitCost = await _unifiedOpeningCostForProductInTransaction(
      sqliteDb,
      product: product,
      warehouseId: warehouseId,
    );
    await BatchInventoryService(sqliteDb).ensureUnifiedCutoverInTransaction(
      product: product,
      warehouseId: warehouseId,
      openingUnitCost: openingUnitCost,
      cutoverAt: at,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      deviceId: _deviceId,
    );
  }

Future<void> _assertUnifiedBatchMovementBalancesInTransaction(
    BatchInventoryService batchService,
    Iterable<StockMovement> movements,
  ) async {
    final unique = <String, StockMovement>{};
    for (final movement in movements) {
      if (movement.batchId.trim().isEmpty) continue;
      final storeId = movement.storeId.trim().isEmpty
          ? appIdentity.storeId
          : movement.storeId.trim();
      final warehouseId = movement.warehouseId.trim().isEmpty
          ? Warehouse.defaultId
          : movement.warehouseId.trim();
      unique['$storeId::$warehouseId::${movement.productId}'] = movement;
    }
    for (final movement in unique.values) {
      await batchService.assertWarehouseBatchBalanceInTransaction(
        productId: movement.productId,
        warehouseId: movement.warehouseId.trim().isEmpty
            ? Warehouse.defaultId
            : movement.warehouseId.trim(),
        storeId: movement.storeId.trim().isEmpty
            ? appIdentity.storeId
            : movement.storeId.trim(),
      );
    }
  }

double _purchaseInventoryUnitCostPerBase(
  PurchaseItem item, {
  required double legacyDefaultVatRatePercent,
}) {
  final product = _findProductById(item.productId);
  if (product == null || item.baseQuantity <= 0) return item.unitCostPerBase;
  final taxProfile = _storeProfile.taxProfileById(
    product.taxProfileId,
    legacyDefaultRatePercent: legacyDefaultVatRatePercent,
  );
  final decimals =
      _storeProfile.currencyByCode(_storeProfile.baseCurrency).decimalPlaces;
  final tax = TaxCalculator.inclusive(
    item.lineTotal,
    taxProfile,
    decimals: decimals,
  );
  // Recoverable input VAT is not inventory cost. Keep the Batch/subledger cost
  // aligned with the taxable base posted to the inventory GL account.
  return tax.taxableBase / item.baseQuantity;
}

Future<BatchAllocation> _receiveUnifiedPurchaseLineInTransaction(
    dynamic sqliteDb, {
    required BatchInventoryService batchService,
    required Purchase purchase,
    required PurchaseItem item,
    required int lineIndex,
    required Product product,
    required String warehouseId,
    required DateTime receivedAt,
    required double inventoryUnitCost,
    Set<String>? ensuredCutovers,
  }) async {
    final cutoverKey = '${product.id}::$warehouseId';
    if (ensuredCutovers == null || ensuredCutovers.add(cutoverKey)) {
      await _ensureUnifiedBatchCutoverForProductInTransaction(
        sqliteDb,
        product: product,
        warehouseId: warehouseId,
        at: receivedAt,
      );
    }
    if (item.batchAllocations.length > 1) {
      throw StateError('Each purchase line must create exactly one batch.');
    }
    final requested = item.batchAllocations.isEmpty
        ? null
        : item.batchAllocations.first;
    final expiry = requested?.expirationDate;
    if (product.expiryTrackingEnabled && expiry == null) {
      throw StateError('Expiration date is required for ${product.name}.');
    }
    if (!product.expiryTrackingEnabled && expiry != null) {
      throw StateError('${product.name} does not track expiration dates.');
    }
    final stableLineId = _stablePurchaseLineId(purchase, item, lineIndex);
    final sourceLineId = '$stableLineId:v${purchase.version}';
    final batchId = 'batch:${purchase.id}:$sourceLineId';
    return batchService.addUnifiedBatchStockInTransaction(
      product: product,
      warehouseId: warehouseId,
      batchId: batchId,
      quantity: item.baseQuantity,
      unitCost: inventoryUnitCost,
      sourceType: 'purchase',
      sourceId: purchase.id,
      sourceLineId: sourceLineId,
      receivedAt: receivedAt,
      storeId: purchase.storeId,
      branchId: purchase.branchId,
      deviceId: purchase.deviceId,
      supplierBatchNumber: requested?.supplierBatchNumber ?? '',
      manufacturingDate: requested?.manufacturingDate,
      expirationDate: expiry,
      costCurrency: 'USD',
      exchangeRate: item.exchangeRateAtEntry > 0 ? item.exchangeRateAtEntry : 1,
    );
  }

Future<List<StockMovement>> _activeDownstreamMovementsForPurchaseInTransaction(
    dynamic sqliteDb,
    Purchase purchase,
  ) async {
    final rows = await sqliteDb.customSelect(
      '''
      SELECT sm.*
      FROM stock_movements sm
      WHERE sm.batch_id IN (
        SELECT id FROM inventory_batches
        WHERE store_id = ? AND source_type = 'purchase' AND source_id = ?
      )
        AND sm.movement_type <> 'purchase_receive'
        AND trim(sm.reversal_of_movement_id) = ''
        AND sm.deleted_at = ''
        AND ABS(
          sm.quantity + COALESCE((
            SELECT SUM(reversal.quantity)
            FROM stock_movements reversal
            WHERE reversal.reversal_of_movement_id = sm.id
              AND reversal.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements reversal_of_reversal
                WHERE reversal_of_reversal.reversal_of_movement_id = reversal.id
                  AND reversal_of_reversal.deleted_at = ''
              )
          ), 0)
        ) > 0.000001
      ORDER BY sm.movement_date ASC, sm.id ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(purchase.id),
      ],
    ).get();
    return rows.map<StockMovement>((row) => StockMovement.fromJson(<String, dynamic>{
      'id': row.data['id'],
      'productId': row.data['product_id'],
      'productName': row.data['product_name'],
      'type': row.data['movement_type'],
      'quantity': row.data['quantity'],
      'date': row.data['movement_date'],
      'referenceId': row.data['reference_id'],
      'referenceNo': row.data['reference_no'],
      'reason': row.data['reason'],
      'unitCost': row.data['unit_cost'],
      'warehouseId': row.data['warehouse_id'],
      'warehouseName': row.data['warehouse_name'],
      'batchId': row.data['batch_id'],
      'movementGroupId': row.data['movement_group_id'],
      'documentLineId': row.data['document_line_id'],
      'sourceMovementId': row.data['source_movement_id'],
      'reversalOfMovementId': row.data['reversal_of_movement_id'],
      'idempotencyKey': row.data['idempotency_key'],
      'createdAt': row.data['created_at'],
      'updatedAt': row.data['updated_at'],
      'deviceId': row.data['device_id'],
      'syncStatus': row.data['sync_status'],
      'storeId': row.data['store_id'],
      'branchId': row.data['branch_id'],
      'version': row.data['version'],
      'lastModifiedByDeviceId': row.data['last_modified_by_device_id'],
    })).toList(growable: false);
  }

Future<void> _requirePurchaseBatchesUnusedInTransaction(
    dynamic sqliteDb,
    Purchase purchase,
  ) async {
    final blockers = await _activeDownstreamMovementsForPurchaseInTransaction(
      sqliteDb,
      purchase,
    );
    if (blockers.isNotEmpty) {
      final first = blockers.first;
      throw StateError(
        'Cannot edit or cancel ${purchase.purchaseNo}: batch ${first.batchId} has an active ${first.type} movement (${first.referenceNo.isEmpty ? first.referenceId : first.referenceNo}). Reverse that movement first.',
      );
    }

    // Legacy purchases may be mixed: an expiry line can already own a batch
    // while a non-expiry line from the same invoice has no historical batch.
    // Guard lineage per stock-tracked line rather than per purchase.
    final warehouseId = purchase.warehouseId.trim().isEmpty
        ? Warehouse.defaultId
        : purchase.warehouseId.trim();
    final legacyUnbatchedProductIds = <String>{};
    for (var lineIndex = 0;
        lineIndex < purchase.items.length;
        lineIndex += 1) {
      final item = purchase.items[lineIndex];
      final product = _findProductById(item.productId);
      if (product == null) {
        throw StateError('Product ${item.productId} was not found.');
      }
      if (!product.trackStock) continue;

      var receiptMovements = await _activePurchaseReceiveMovements(
        sqliteDb,
        purchaseId: purchase.id,
        productId: item.productId,
        documentLineId: _stablePurchaseLineId(purchase, item, lineIndex),
      );
      if (receiptMovements.isEmpty) {
        receiptMovements = await _activePurchaseReceiveMovements(
          sqliteDb,
          purchaseId: purchase.id,
          productId: item.productId,
          documentLineId: '${purchase.id}-line-$lineIndex',
        );
      }
      final hasLegacyUnbatchedReceipt = receiptMovements.any(
        (movement) => movement.batchId.trim().isEmpty,
      );
      if (!hasLegacyUnbatchedReceipt) continue;

      // Once a legacy no-batch receipt has been absorbed into an aggregate
      // opening batch, its exact lot lineage no longer exists. Reversing that
      // historical receipt would change warehouse_inventory without a safe
      // batch slice to reverse, so block it until the historical migration.
      final cutoverMarker = await sqliteDb.customSelect(
        '''
        SELECT id
        FROM unified_batch_cutovers
        WHERE store_id = ? AND warehouse_id = ? AND product_id = ?
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(appIdentity.storeId),
          Variable<String>(warehouseId),
          Variable<String>(item.productId),
        ],
      ).getSingleOrNull();
      if (cutoverMarker != null) {
        throw StateError(
          'Cannot edit, cancel, or return legacy ${purchase.purchaseNo}: ${product.name} was already absorbed into the Unified Batch opening balance and has no exact historical batch identity. Complete the historical migration first.',
        );
      }
      legacyUnbatchedProductIds.add(item.productId);
    }

    if (legacyUnbatchedProductIds.isEmpty) return;
    final productIds = legacyUnbatchedProductIds.toList(growable: false);
    final placeholders = List.filled(productIds.length, '?').join(',');
    final legacyRows = await sqliteDb.customSelect(
      '''
      SELECT sm.movement_type, sm.reference_id, sm.reference_no, sm.product_name
      FROM stock_movements sm
      WHERE sm.store_id = ? AND sm.warehouse_id = ?
        AND sm.product_id IN ($placeholders)
        AND sm.quantity < -0.000001
        AND sm.reference_id <> ?
        AND sm.movement_date >= ?
        AND trim(sm.reversal_of_movement_id) = ''
        AND sm.deleted_at = ''
        AND ABS(
          sm.quantity + COALESCE((
            SELECT SUM(reversal.quantity)
            FROM stock_movements reversal
            WHERE reversal.reversal_of_movement_id = sm.id
              AND reversal.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements reversal_of_reversal
                WHERE reversal_of_reversal.reversal_of_movement_id = reversal.id
                  AND reversal_of_reversal.deleted_at = ''
              )
          ), 0)
        ) > 0.000001
      ORDER BY sm.movement_date ASC, sm.id ASC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(appIdentity.storeId),
        Variable<String>(warehouseId),
        ...productIds.map(Variable<String>.new),
        Variable<String>(purchase.id),
        Variable<String>(purchase.date.toUtc().toIso8601String()),
      ],
    ).getSingleOrNull();
    if (legacyRows != null) {
      final type = legacyRows.data['movement_type']?.toString() ?? 'stock';
      final refNo = legacyRows.data['reference_no']?.toString() ?? '';
      final refId = legacyRows.data['reference_id']?.toString() ?? '';
      final productName = legacyRows.data['product_name']?.toString() ?? '';
      throw StateError(
        'Cannot edit or cancel legacy ${purchase.purchaseNo}: $productName has a later active $type movement (${refNo.isEmpty ? refId : refNo}). Reverse it first.',
      );
    }
  }

Future<Purchase> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    bool receiveNow = true,
    String note = '',
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  }) async {
    requirePermission(AppPermission.purchasesManage);
    _traceSync('purchases.createPurchase', 'validate_input', () {
      if (items.isEmpty) {
        throw ArgumentError('Purchase must contain at least one item.');
      }
      for (final item in items) {
        if (item.quantity <= 0 ||
            item.conversionToBase <= 0 ||
            item.unitCost < 0) {
          throw ArgumentError('Invalid purchase item values.');
        }
        if (_findProductById(item.productId) == null) {
          throw ArgumentError('Product not found: ${item.productName}');
        }
      }
    });
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
        'Purchase posting requires the SQLite authoritative store.',
      );
    }
    // A recently created/edited product may still have a debounced derived-data
    // write pending. Flush that snapshot before the authoritative transaction so
    // it cannot overwrite the newer purchase cost after the transaction commits.
    await _flushProductDerivedData();
    if (LocalDatabaseService.isSqliteAuthoritative) {
      final purchaseNoPrefix = 'PO-$_purchaseDevicePrefix-';
      final purchaseIdPrefix = 'purchase_${_purchaseDevicePrefix}_';
      final row = await sqliteDb.customSelect(
        '''
        SELECT MAX(sequence_no) AS max_sequence
        FROM (
          SELECT CAST(substr(purchase_no, length(?) + 1) AS INTEGER) AS sequence_no
          FROM purchases
          WHERE purchase_no LIKE ?
          UNION ALL
          SELECT CAST(substr(entity_id, length(?) + 1) AS INTEGER) AS sequence_no
          FROM sync_events
          WHERE entity_type = 'purchase' AND entity_id LIKE ?
        )
        ''',
        variables: <Variable<Object>>[
          Variable<String>(purchaseNoPrefix),
          Variable<String>('$purchaseNoPrefix%'),
          Variable<String>(purchaseIdPrefix),
          Variable<String>('$purchaseIdPrefix%'),
        ],
      ).getSingleOrNull();
      final persistedMax = (row?.data['max_sequence'] as num?)?.toInt() ?? 0;
      if (persistedMax > _purchaseCounter) {
        _purchaseCounter = persistedMax;
      }
    }
    _purchaseCounter += 1;
    final now = DateTime.now();
    final purchaseTotal = items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    final normalizedPaymentStatus =
        paymentStatus.trim().toLowerCase() == 'credit'
            ? 'credit'
            : paymentStatus.trim().toLowerCase() == 'partial'
                ? 'partial'
                : 'paid';
    final normalizedPaymentMethod =
        paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    final normalizedPaidAmount = normalizedPaymentStatus == 'paid'
        ? purchaseTotal
        : normalizedPaymentStatus == 'credit'
            ? 0.0
            : (paidAmount ?? 0).clamp(0, purchaseTotal).toDouble();
    await AccountingService.validatePurchasePayment(
      paymentMethod: normalizedPaymentMethod,
      paidAmount: normalizedPaidAmount,
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
    );
    final resolvedWarehouse = resolveWarehouseForPurchase(
      warehouseId: warehouseId,
    );
    final normalizedWarehouseName = warehouseName.trim().isEmpty
        ? resolvedWarehouse.name
        : warehouseName.trim();
    var purchase = Purchase(
      id: 'purchase_${_purchaseDevicePrefix}_${_purchaseCounter.toString().padLeft(6, '0')}',
      purchaseNo:
          'PO-$_purchaseDevicePrefix-${_purchaseCounter.toString().padLeft(6, '0')}',
      supplierId: supplierId,
      supplierName:
          supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim(),
      date: now,
      status: receiveNow ? 'Received' : 'Draft',
      items: items,
      note: note,
      paymentStatus:
          normalizedPaidAmount > 0 ? 'credit' : normalizedPaymentStatus,
      paymentMethod: normalizedPaymentMethod,
      paidAmount: 0,
      warehouseId: resolvedWarehouse.id,
      warehouseName: normalizedWarehouseName,
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );
    // A new purchase always owns fresh line identities. Never reuse a lineId
    // copied from a template/duplicated invoice, because purchase_items.id is
    // globally unique and the Batch source identity is anchored to it.
    purchase = purchase.copyWith(
      items: purchase.items.indexed.map((entry) {
        return _copyPurchaseItemWith(
          item: entry.$2,
          lineId: '${purchase.id}:pl:${entry.$1}',
        );
      }).toList(growable: false),
    );
    final legacyDefaultVatRatePercent =
        await AccountingService.readDefaultVatRatePercent();
    final taxProfileIdByProductId = <String, String>{
      for (final product in _products) product.id: product.taxProfileId,
    };
    if (LocalDatabaseService.isSqliteAuthoritative) {
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final batchService = BatchInventoryService(sqliteDb);
      final receiptMovements = <StockMovement>[];
      final productCostPreviews = <String, ProductCost>{};
      final productPreviews = <String, Product>{};
      final resolvedPurchaseItems = List<PurchaseItem>.of(purchase.items);
      if (receiveNow) {
        for (var lineIndex = 0;
            lineIndex < purchase.items.length;
            lineIndex += 1) {
          final item = purchase.items[lineIndex];
          final product = productPreviews[item.productId] ??
              _findProductById(item.productId);
          if (product == null || !product.trackStock) continue;
          final currentCost = productCostPreviews[item.productId] ??
              productCostFor(item.productId);
          final receivedQty = item.baseQuantity;
          final unitCost = _purchaseInventoryUnitCostPerBase(
            item,
            legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
          );
          final stockBefore = productPreviews.containsKey(item.productId)
              ? max(0.0, product.stock)
              : max(0.0, await totalWarehouseStockFromSqlite(item.productId));
          final stockAfter = stockBefore + receivedQty;
          final averageCost = stockAfter <= 0
              ? unitCost
              : ((stockBefore * currentCost.averageCost) +
                      (receivedQty * unitCost)) /
                  stockAfter;
          final updatedCost = currentCost.copyWith(
            averageCost: averageCost,
            lastCost: unitCost,
            currencyCode: 'USD',
            updatedAt: now,
          );
          productCostPreviews[item.productId] = updatedCost;
          final appliedCost =
              _inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost
                  ? updatedCost.lastCost
                  : updatedCost.averageCost;
          productPreviews[item.productId] = product.copyWith(
            stock: stockAfter,
            cost: appliedCost,
            usdCost: appliedCost,
            originalCost: appliedCost,
            costCurrency: 'USD',
            costExchangeRateAtEntry: storeProfile.usdToLbpRate,
            updatedAt: now,
          );
        }
      }
      await _traceAsync<void>('purchases.createPurchase', 'sqlite_transaction',
          () async {
        await sqliteDb.transaction(() async {
          final ensuredUnifiedCutovers = <String>{};
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._purchasesKey,
            <Map<String, dynamic>>[purchase.toJson()],
            sortIndices: <int?>[0],
          );
          if (receiveNow) {
            for (var lineIndex = 0;
                lineIndex < purchase.items.length;
                lineIndex += 1) {
              final item = purchase.items[lineIndex];
              final product = _findProductById(item.productId);
              if (product == null || !product.trackStock) continue;
              final allocation = await _receiveUnifiedPurchaseLineInTransaction(
                sqliteDb,
                batchService: batchService,
                purchase: purchase,
                item: item,
                lineIndex: lineIndex,
                product: product,
                warehouseId: resolvedWarehouse.id,
                receivedAt: now,
                inventoryUnitCost: _purchaseInventoryUnitCostPerBase(
                  item,
                  legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
                ),
                ensuredCutovers: ensuredUnifiedCutovers,
              );
              resolvedPurchaseItems[lineIndex] = _copyPurchaseItemWith(
                item: item,
                batchAllocations: <BatchAllocation>[allocation],
              );
              receiptMovements.add(StockMovement(
                id: '${purchase.id}-$lineIndex-${allocation.batchId}-purchase-receive',
                productId: item.productId,
                productName: item.productName,
                type: 'purchase_receive',
                quantity: allocation.quantity,
                date: now,
                referenceId: purchase.id,
                referenceNo: purchase.purchaseNo,
                reason: 'Purchase received (Unified Batch)',
                unitCost: allocation.unitCost,
                warehouseId: resolvedWarehouse.id,
                warehouseName: normalizedWarehouseName,
                batchId: allocation.batchId,
                movementGroupId: purchase.id,
                documentLineId: _stablePurchaseLineId(purchase, item, lineIndex),
                idempotencyKey: '${purchase.id}:purchase_receive:$lineIndex:${allocation.batchId}',
                createdAt: now,
                updatedAt: now,
                deviceId: purchase.deviceId,
                syncStatus: purchase.syncStatus,
                storeId: purchase.storeId,
                branchId: purchase.branchId,
                version: purchase.version,
                lastModifiedByDeviceId: purchase.lastModifiedByDeviceId,
              ));
            }
            purchase = purchase.copyWith(items: resolvedPurchaseItems);
            Supplier? snapshotSupplier;
            for (final candidate in _suppliers) {
              if (candidate.id == purchase.supplierId && !candidate.isDeleted) {
                snapshotSupplier = candidate;
                break;
              }
            }
            purchase = purchase.copyWith(
              postedSnapshot: PostedDocumentSnapshotService.forPurchase(
                purchase: purchase,
                profile: _storeProfile,
                supplier: snapshotSupplier,
                user: _activeUser,
                role: currentUserRole,
                displayedPaidAmount: normalizedPaidAmount,
                displayedPaymentStatus: normalizedPaidAmount >= purchaseTotal - 0.000001
                    ? 'paid'
                    : normalizedPaidAmount > 0
                        ? 'partial'
                        : normalizedPaymentStatus,
                taxProfileIdByProductId: taxProfileIdByProductId,
                legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
              ),
            );
            await BusinessSqliteStore.upsertEntityPayloads(
              sqliteDb,
              AppStore._purchasesKey,
              <Map<String, dynamic>>[purchase.toJson()],
              sortIndices: <int?>[0],
            );
            await stockService.recordMovementsInTransaction(
              operationType: 'purchase_receive',
              documentType: 'purchase',
              documentId: purchase.id,
              movementGroupId: purchase.id,
              idempotencyKey: '${purchase.id}:purchase_receive',
              movements: receiptMovements,
              storeId: purchase.storeId,
              branchId: purchase.branchId,
              deviceId: purchase.deviceId,
              skipExistingMovementLookup: true,
            );
            await _assertUnifiedBatchMovementBalancesInTransaction(
              batchService,
              receiptMovements,
            );
            if (productCostPreviews.isNotEmpty) {
              await BusinessSqliteStore.upsertEntityPayloads(
                sqliteDb,
                AppStore._productCostsKey,
                productCostPreviews.values
                    .map((item) => item.toJson())
                    .toList(growable: false),
              );
              await BusinessSqliteStore.upsertEntityPayloads(
                sqliteDb,
                AppStore._productsKey,
                productPreviews.values
                    .map((item) => item.toJson())
                    .toList(growable: false),
              );
            }
          }
          if (receiveNow) {
            final accountingPosted = await AccountingService.recordPurchase(
              purchase,
              paymentPostedSeparately: true,
              withinExistingTransaction: true,
            );
            if (!accountingPosted) {
              throw StateError(
                'Purchase accounting posting failed; the purchase transaction was rolled back.',
              );
            }
            await _requirePostedJournalInTransaction(
              sqliteDb,
              referenceType: 'purchase',
              referenceId: purchase.id,
              failureMessage:
                  'Purchase journal was not persisted; the purchase transaction was rolled back.',
            );
            await _persistAccountTransactionInExistingTransaction(
              sqliteDb,
              AccountTransaction(
                id: '${purchase.id}-purchase-invoice',
                accountType: 'supplier',
                accountId: purchase.supplierId,
                accountName: purchase.supplierName,
                date: purchase.date,
                type: 'purchaseInvoice',
                referenceId: purchase.id,
                referenceNo: purchase.purchaseNo,
                credit: purchase.subtotal,
                note: 'Purchase invoice ${purchase.purchaseNo}',
                createdAt: now,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
          }
        });
      });
      if (receiveNow) {
        await refreshAfterDatabaseChange(AppStore._productsKey);
        await refreshAfterDatabaseChange(AppStore._productCostsKey);
        await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
        await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
        if (normalizedPaidAmount > 0) {
          purchase = await settlePurchasePayment(
            purchaseId: purchase.id,
            amount: normalizedPaidAmount,
            paymentMethod: normalizedPaymentMethod,
            notes: 'Initial payment for ${purchase.purchaseNo}',
            idempotencyKey: '${purchase.id}:initial-payment:v1',
            date: now,
          );
        }
      }
      _traceSync('purchases.createPurchase', 'memory_ledger_and_sync', () {
        _putPurchaseAtIndex(purchase, _purchases.length);
        _recordSyncChange(
          entityType: 'purchase',
          entityId: purchase.id,
          operation: 'create',
          payload: purchase.toJson(),
        );
      });
      // Purchase accounting + supplier ledger were committed atomically above.
      // Do not write the financial ledger a second time after commit.
      await _saveDirty(
        // Product costs and FIFO layers were committed and refreshed by the
        // authoritative purchase transaction above. Scheduling the legacy
        // derived-data flush here can replay that pre-sale snapshot after a
        // subsequent sale and overwrite its direct FIFO layer consumption.
        productDerivedData: false,
        purchaseCounter: true,
        sync: true,
      );
      _touchPurchasesData();
      notifyListeners();
      return purchase;
    }
    if (receiveNow && normalizedPaidAmount > 0) {
      throw StateError(
          'Purchase payments require the SQLite authoritative store.');
    }
    _putPurchaseAtIndex(purchase, _purchases.length);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: purchase.id,
      operation: 'create',
      payload: purchase.toJson(),
    );
    if (receiveNow) {
      _applyPurchaseStock(purchase, now);
    }
    await _saveDirty(
      purchases: true,
      products: receiveNow,
      productDerivedData: receiveNow,
      stockMovements: receiveNow,
      accountTransactions: receiveNow,
      purchaseCounter: true,
      sync: true,
    );
    if (receiveNow) {
      final accountingPosted = await _schedulePurchaseAccounting(purchase);
      if (accountingPosted) {
        await _recordPurchaseLedger(purchase, now);
        await _saveDirty(accountTransactions: true);
      }
    }
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'create_purchase',
        message: 'Purchase created successfully.',
        details:
            'purchaseId=${purchase.id} purchaseNo=${purchase.purchaseNo} total=$purchaseTotal receiveNow=$receiveNow',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: purchase.id,
        action: 'create',
        summary: 'Purchase created',
        details: jsonEncode(purchase.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
    return purchase;
  }

Future<Purchase> updatePurchaseDraft({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  }) async {
    requirePermission(AppPermission.purchasesManage);
    if (items.isEmpty) {
      throw ArgumentError('Purchase must contain at least one item.');
    }
    for (final item in items) {
      if (item.quantity <= 0 ||
          item.conversionToBase <= 0 ||
          item.unitCost < 0) {
        throw ArgumentError('Invalid purchase item values.');
      }
      if (_findProductById(item.productId) == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }
    final index = _purchaseIndexForId(purchaseId);
    final current = LocalDatabaseService.isSqliteAuthoritative &&
            SqliteMigrationManager.database != null
        ? await _purchaseByIdFromSqlite(purchaseId)
        : (index == -1
            ? await _purchaseByIdFromSqlite(purchaseId)
            : _purchases[index]);
    if (current == null) throw ArgumentError('Purchase not found.');
    if (current.isCancelled) {
      throw StateError('Cancelled/returned purchases cannot be edited.');
    }
    if (current.version != expectedVersion) {
      throw StateError(
          'Purchase changed by another user. Reload it before editing.');
    }

    final now = DateTime.now();
    final resolvedWarehouse =
        resolveWarehouseForPurchase(warehouseId: warehouseId);
    final normalizedStatus = paymentStatus.trim().toLowerCase() == 'credit'
        ? 'credit'
        : paymentStatus.trim().toLowerCase() == 'partial'
            ? 'partial'
            : 'paid';
    final total = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (current.isReceived && current.paidAmount > total + 0.000001) {
      throw StateError(
        'Cannot reduce the purchase below its already allocated payment. Reverse or adjust the payment first.',
      );
    }
    if (current.isReceived &&
        current.paidAmount > 0.000001 &&
        supplierId.trim() != current.supplierId.trim()) {
      throw StateError(
        'Cannot change the supplier of a received purchase with allocated payments. Reverse the payment first.',
      );
    }
    final normalizedPaid = normalizedStatus == 'paid'
        ? total
        : normalizedStatus == 'credit'
            ? 0.0
            : (paidAmount ?? 0).clamp(0, total).toDouble();
    final existingLineIds = current.items
        .map((item) => item.lineId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final usedLineIds = <String>{};
    final normalizedItems = items.indexed.map((entry) {
      final item = entry.$2;
      final requestedLineId = item.lineId.trim();
      if (requestedLineId.isNotEmpty &&
          existingLineIds.contains(requestedLineId) &&
          usedLineIds.add(requestedLineId)) {
        return item;
      }
      var generatedLineId =
          '${current.id}:pl:v${current.version + 1}:${entry.$1}:${now.microsecondsSinceEpoch}';
      var suffix = 0;
      while (!usedLineIds.add(generatedLineId)) {
        suffix += 1;
        generatedLineId =
            '${current.id}:pl:v${current.version + 1}:${entry.$1}:${now.microsecondsSinceEpoch}:$suffix';
      }
      return _copyPurchaseItemWith(
        item: item,
        lineId: generatedLineId,
      );
    }).toList(growable: false);
    var updated = current.copyWith(
      supplierId: supplierId,
      supplierName:
          supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim(),
      items: normalizedItems,
      paymentStatus: current.isReceived
          ? current.paymentStatus
          : (normalizedPaid > 0 ? 'credit' : normalizedStatus),
      paymentMethod: current.isReceived
          ? current.paymentMethod
          : (paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim()),
      paidAmount: current.isReceived ? current.paidAmount : 0,
      warehouseId: resolvedWarehouse.id,
      warehouseName: warehouseName.trim().isEmpty
          ? resolvedWarehouse.name
          : warehouseName.trim(),
      updatedAt: now,
      version: current.version + 1,
      lastModifiedByDeviceId: _deviceId,
      syncStatus: 'pending',
    );
    final beforeJson = jsonEncode(current.toJson());
    final sqliteDb = SqliteMigrationManager.database;
    final legacyDefaultVatRatePercent =
        await AccountingService.readDefaultVatRatePercent();

    if (current.isDraft) {
      if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
        await sqliteDb.transaction(() async {
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._purchasesKey,
            <Map<String, dynamic>>[updated.toJson()],
            sortIndices: <int?>[index < 0 ? 0 : index],
          );
        });
      }
    } else if (current.isReceived) {
      if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
        throw StateError(
            'Received purchase editing requires the SQLite authoritative store.');
      }
      await _waitForPendingPurchaseAccounting(current.id);
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => false,
      );
      final batchService = BatchInventoryService(sqliteDb);
      final repostMovements = <StockMovement>[];
      await sqliteDb.transaction(() async {
        final ensuredUnifiedCutovers = <String>{};
        DateTime? originalReceiptAt;
        await _requirePurchaseBatchesUnusedInTransaction(sqliteDb, current);
        await _closeInventoryCostLayersForPurchaseInTransaction(
          sqliteDb,
          current,
          now,
        );

        for (var lineIndex = 0;
            lineIndex < current.items.length;
            lineIndex += 1) {
          final oldItem = current.items[lineIndex];
          final product = _findProductById(oldItem.productId);
          if (product == null) {
            throw StateError('Product ${oldItem.productId} was not found.');
          }
          if (!product.trackStock) continue;
          var originalMovements = await _activePurchaseReceiveMovements(
            sqliteDb,
            purchaseId: current.id,
            productId: oldItem.productId,
            documentLineId:
                _stablePurchaseLineId(current, oldItem, lineIndex),
          );
          if (originalMovements.isEmpty) {
            originalMovements = await _activePurchaseReceiveMovements(
              sqliteDb,
              purchaseId: current.id,
              productId: oldItem.productId,
              documentLineId: '${current.id}-line-$lineIndex',
            );
          }
          if (originalMovements.isEmpty) {
            throw StateError(
                'Active stock receipt is missing for ${current.purchaseNo}, line $lineIndex.');
          }
          for (final movement in originalMovements) {
            if (originalReceiptAt == null ||
                movement.date.isBefore(originalReceiptAt)) {
              originalReceiptAt = movement.date;
            }
            if (movement.batchId.trim().isNotEmpty) {
              await batchService.adjustUnifiedBatchInTransaction(
                product: product,
                warehouseId: movement.warehouseId,
                batchId: movement.batchId,
                quantityDelta: -movement.quantity,
                adjustedAt: now,
                storeId: appIdentity.storeId,
                deviceId: _deviceId,
              );
            }
            await stockService.recordReversalInTransaction(
              originalMovement: movement,
              operationType: 'purchase_edit_reverse',
              documentType: 'purchase',
              documentId: current.id,
              reason: 'Purchase edit reverse v${current.version}',
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
            );
            if (movement.batchId.trim().isNotEmpty) {
              await batchService.assertWarehouseBatchBalanceInTransaction(
                productId: oldItem.productId,
                warehouseId: movement.warehouseId.trim().isEmpty
                    ? Warehouse.defaultId
                    : movement.warehouseId.trim(),
                storeId: appIdentity.storeId,
              );
            }
          }
        }

        await AccountingService.reversePurchaseEntriesForPurchase(
          purchaseId: current.id,
          reason: 'Purchase edited',
          createdBy: _deviceId,
          adjustCashLocationBalance: false,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _requireNoActiveJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: current.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Purchase journal reversal did not complete; edit rolled back.',
        );

        final resolvedItems = List<PurchaseItem>.of(updated.items);
        for (var lineIndex = 0;
            lineIndex < updated.items.length;
            lineIndex += 1) {
          final item = updated.items[lineIndex];
          final product = _findProductById(item.productId);
          if (product == null || !product.trackStock) continue;
          final allocation = await _receiveUnifiedPurchaseLineInTransaction(
            sqliteDb,
            batchService: batchService,
            purchase: updated,
            item: item,
            lineIndex: lineIndex,
            product: product,
            warehouseId: updated.warehouseId.isEmpty
                ? Warehouse.defaultId
                : updated.warehouseId,
            receivedAt: originalReceiptAt ?? current.date,
            inventoryUnitCost: _purchaseInventoryUnitCostPerBase(
              item,
              legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
            ),
            ensuredCutovers: ensuredUnifiedCutovers,
          );
          resolvedItems[lineIndex] = _copyPurchaseItemWith(
            item: item,
            batchAllocations: <BatchAllocation>[allocation],
          );
          repostMovements.add(StockMovement(
            id: '${updated.id}-${allocation.batchId}-purchase-edit-v${updated.version}',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_receive',
            quantity: allocation.quantity,
            date: now,
            referenceId: updated.id,
            referenceNo: updated.purchaseNo,
            reason: 'Purchase edited and reposted',
            unitCost: allocation.unitCost,
            warehouseId: updated.warehouseId.isEmpty
                ? Warehouse.defaultId
                : updated.warehouseId,
            warehouseName: updated.warehouseName.isEmpty
                ? Warehouse.defaultName
                : updated.warehouseName,
            batchId: allocation.batchId,
            movementGroupId: '${updated.id}:purchase_edit:v${updated.version}',
            documentLineId: _stablePurchaseLineId(updated, item, lineIndex),
            idempotencyKey:
                '${updated.id}:purchase_edit:v${updated.version}:$lineIndex',
            createdAt: now,
            updatedAt: now,
            deviceId: _deviceId,
            syncStatus: 'pending',
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          ));
        }
        updated = updated.copyWith(items: resolvedItems);
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[updated.toJson()],
          sortIndices: <int?>[index < 0 ? 0 : index],
        );
        if (repostMovements.isNotEmpty) {
          await stockService.recordMovementsInTransaction(
            operationType: 'purchase_edit_repost',
            documentType: 'purchase',
            documentId: updated.id,
            movementGroupId:
                '${updated.id}:purchase_edit:v${updated.version}',
            idempotencyKey:
                '${updated.id}:purchase_edit:v${updated.version}',
            movements: repostMovements,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            repostMovements,
          );
        }
        final accountingPosted = await AccountingService.recordPurchase(
          updated,
          accountingReferenceId:
              '${updated.id}:purchase_edit:v${updated.version}',
          paymentPostedSeparately: true,
          withinExistingTransaction: true,
        );
        if (!accountingPosted) {
          throw StateError(
              'Purchase edit accounting repost failed; edit rolled back.');
        }
        if (updated.supplierId.trim().isNotEmpty && updated.subtotal > 0) {
          await _persistAccountTransactionInExistingTransaction(
            sqliteDb,
            AccountTransaction(
              id: '${updated.id}-purchase-invoice',
              accountType: 'supplier',
              accountId: updated.supplierId,
              accountName: updated.supplierName,
              date: updated.date,
              type: 'purchaseInvoice',
              referenceId: updated.id,
              referenceNo: updated.purchaseNo,
              credit: updated.subtotal,
              note: 'Purchase invoice ${updated.purchaseNo}',
              createdAt: updated.createdAt,
              updatedAt: now,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              lastModifiedByDeviceId: _deviceId,
            ),
          );
        }
      });
      await _refreshProductStockCompatibilityCache(
        <String>{
          ...current.items.map((item) => item.productId),
          ...updated.items.map((item) => item.productId),
        },
      );
      await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
      await refreshAccountTransactionsFromSqlite();
    } else {
      throw StateError('This purchase status cannot be edited.');
    }

    _putPurchaseAtIndex(updated, index < 0 ? _purchases.length : index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: updated.id,
      operation: current.isReceived ? 'edit_repost' : 'update',
      payload: updated.toJson(),
    );
    await _saveDirty(purchases: true, sync: true);
    await AuditLogger.record(
      entityType: 'purchase',
      entityId: updated.id,
      action: 'update',
      summary: current.isReceived
          ? 'Received purchase reversed and reposted'
          : 'Purchase draft edited',
      oldValue: beforeJson,
      newValue: jsonEncode(updated.toJson()),
      details: current.isReceived
          ? 'Unified Batch guarded reverse + repost.'
          : 'Draft purchase edited with optimistic version check.',
      userId: _activeUser?.id ?? '',
      userName: _actorName(),
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'purchases',
      isImportant: true,
    );
    _touchPurchasesData();
    notifyListeners();
    return updated;
  }

Future<void> receivePurchase(
    String id, {
    bool settleInitialPayment = true,
    bool postAccounting = true,
    Map<int, List<BatchAllocation>> batchAllocationsByLine =
        const <int, List<BatchAllocation>>{},
  }) async {
    requirePermission(AppPermission.purchasesManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isReceived || purchase.isCancelled) return;
    final plannedPayment = !settleInitialPayment
        ? 0.0
        : purchase.paidAmount > 0
            ? purchase.paidAmount.clamp(0, purchase.subtotal).toDouble()
            : (purchase.paymentStatus.trim().toLowerCase() == 'paid'
                ? purchase.subtotal
                : 0.0);
    await AccountingService.validatePurchasePayment(
      paymentMethod: purchase.paymentMethod,
      paidAmount: plannedPayment,
      deviceId: purchase.deviceId,
      branchId: purchase.branchId,
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final now = DateTime.now();
      // A received invoice can be reversed and reposted more than once. The
      // posting version must be part of stock movement identity; otherwise a
      // repost reuses the old idempotency key and is silently skipped.
      final receivePostingKey =
          '${purchase.id}:purchase_receive:v${purchase.version}';
      final receivedItems = purchase.items.indexed.map((entry) {
        final allocations = batchAllocationsByLine[entry.$1];
        if (allocations == null) return entry.$2;
        final item = entry.$2;
        return PurchaseItem(
          lineId: item.lineId,
          productId: item.productId,
          productName: item.productName,
          quantity: item.quantity,
          unitCost: item.unitCost,
          purchaseUnitId: item.purchaseUnitId,
          purchaseUnitName: item.purchaseUnitName,
          conversionToBase: item.conversionToBase,
          originalUnitCost: item.originalUnitCost,
          unitCostCurrency: item.unitCostCurrency,
          exchangeRateAtEntry: item.exchangeRateAtEntry,
          batchAllocations: allocations,
        );
      }).toList(growable: false);
      var received = _withSyncMeta<Purchase>(
        purchase.copyWith(
          status: 'Received',
          items: receivedItems,
          paidAmount: settleInitialPayment ? 0 : purchase.paidAmount,
          paymentStatus: plannedPayment > 0 ? 'credit' : purchase.paymentStatus,
        ),
        now,
      );
      final legacyDefaultVatRatePercent =
          await AccountingService.readDefaultVatRatePercent();
      final taxProfileIdByProductId = <String, String>{
        for (final product in _products) product.id: product.taxProfileId,
      };
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final batchService = BatchInventoryService(sqliteDb);
      final receiptMovements = <StockMovement>[];
      final productCostPreviews = <String, ProductCost>{};
      final productPreviews = <String, Product>{};
      for (var lineIndex = 0;
          lineIndex < received.items.length;
          lineIndex += 1) {
        final item = received.items[lineIndex];
        final product =
            productPreviews[item.productId] ?? _findProductById(item.productId);
        if (product == null || !product.trackStock) continue;
        final currentCost = productCostPreviews[item.productId] ??
            productCostFor(item.productId);
        final receivedQty = item.baseQuantity;
        final unitCost = _purchaseInventoryUnitCostPerBase(
          item,
          legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
        );
        final stockBefore = productPreviews.containsKey(item.productId)
            ? max(0.0, product.stock)
            : max(0.0, await totalWarehouseStockFromSqlite(item.productId));
        final stockAfter = stockBefore + receivedQty;
        final averageCost = stockAfter <= 0
            ? unitCost
            : ((stockBefore * currentCost.averageCost) +
                    (receivedQty * unitCost)) /
                stockAfter;
        final updatedCost = currentCost.copyWith(
          averageCost: averageCost,
          lastCost: unitCost,
          currencyCode: 'USD',
          updatedAt: now,
        );
        productCostPreviews[item.productId] = updatedCost;
        final appliedCost =
            _inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost
                ? updatedCost.lastCost
                : updatedCost.averageCost;
        productPreviews[item.productId] = product.copyWith(
          stock: stockAfter,
          cost: appliedCost,
          usdCost: appliedCost,
          originalCost: appliedCost,
          costCurrency: 'USD',
          costExchangeRateAtEntry: storeProfile.usdToLbpRate,
          updatedAt: now,
        );
      }
      await sqliteDb.transaction(() async {
        final ensuredUnifiedCutovers = <String>{};
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[received.toJson()],
          sortIndices: <int?>[0],
        );
        final resolvedReceivedItems = List<PurchaseItem>.of(received.items);
        for (var lineIndex = 0;
            lineIndex < received.items.length;
            lineIndex += 1) {
          final item = received.items[lineIndex];
          final product = _findProductById(item.productId);
          if (product == null || !product.trackStock) continue;
          final warehouseId = received.warehouseId.isEmpty
              ? Warehouse.defaultId
              : received.warehouseId;
          final warehouseName = received.warehouseName.isEmpty
              ? Warehouse.defaultName
              : received.warehouseName;
          final allocation = await _receiveUnifiedPurchaseLineInTransaction(
            sqliteDb,
            batchService: batchService,
            purchase: received,
            item: item,
            lineIndex: lineIndex,
            product: product,
            warehouseId: warehouseId,
            receivedAt: now,
            inventoryUnitCost: _purchaseInventoryUnitCostPerBase(
              item,
              legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
            ),
            ensuredCutovers: ensuredUnifiedCutovers,
          );
          resolvedReceivedItems[lineIndex] = _copyPurchaseItemWith(
            item: item,
            batchAllocations: <BatchAllocation>[allocation],
          );
          receiptMovements.add(StockMovement(
            id: '${received.id}-$lineIndex-${allocation.batchId}-purchase-receive-v${received.version}',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_receive',
            quantity: allocation.quantity,
            date: now,
            referenceId: received.id,
            referenceNo: received.purchaseNo,
            reason: 'Purchase received (Unified Batch)',
            unitCost: allocation.unitCost,
            warehouseId: warehouseId,
            warehouseName: warehouseName,
            batchId: allocation.batchId,
            movementGroupId: received.id,
            documentLineId: _stablePurchaseLineId(received, item, lineIndex),
            idempotencyKey: '$receivePostingKey:$lineIndex:${allocation.batchId}',
            createdAt: now,
            updatedAt: now,
            deviceId: received.deviceId,
            syncStatus: received.syncStatus,
            storeId: received.storeId,
            branchId: received.branchId,
            version: received.version,
            lastModifiedByDeviceId: received.lastModifiedByDeviceId,
          ));
        }
        received = received.copyWith(items: resolvedReceivedItems);
        Supplier? snapshotSupplier;
        for (final candidate in _suppliers) {
          if (candidate.id == received.supplierId && !candidate.isDeleted) {
            snapshotSupplier = candidate;
            break;
          }
        }
        received = received.copyWith(
          postedSnapshot: PostedDocumentSnapshotService.forPurchase(
            purchase: received,
            profile: _storeProfile,
            supplier: snapshotSupplier,
            user: _activeUser,
            role: currentUserRole,
            displayedPaidAmount: plannedPayment,
            displayedPaymentStatus: plannedPayment >= received.subtotal - 0.000001
                ? 'paid'
                : plannedPayment > 0
                    ? 'partial'
                    : received.paymentStatus,
            taxProfileIdByProductId: taxProfileIdByProductId,
            legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
          ),
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[received.toJson()],
          sortIndices: <int?>[0],
        );
        if (receiptMovements.isNotEmpty) {
          await stockService.recordMovementsInTransaction(
            operationType: 'purchase_receive',
            documentType: 'purchase',
            documentId: received.id,
            movementGroupId: '$receivePostingKey:group',
            idempotencyKey: receivePostingKey,
            movements: receiptMovements,
            storeId: received.storeId,
            branchId: received.branchId,
            deviceId: received.deviceId,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            receiptMovements,
          );
        }
        if (productCostPreviews.isNotEmpty) {
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._productCostsKey,
            productCostPreviews.values
                .map((item) => item.toJson())
                .toList(growable: false),
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            sqliteDb,
            AppStore._productsKey,
            productPreviews.values
                .map((item) => item.toJson())
                .toList(growable: false),
          );
        }
        if (postAccounting) {
          final accountingPosted = await AccountingService.recordPurchase(
            received,
            paymentPostedSeparately: true,
            withinExistingTransaction: true,
          );
          if (!accountingPosted) {
            throw StateError(
              'Purchase accounting posting failed; purchase receipt was rolled back.',
            );
          }
          await _requirePostedJournalInTransaction(
            sqliteDb,
            referenceType: 'purchase',
            referenceId: received.id,
            failureMessage:
                'Purchase journal was not persisted; purchase receipt was rolled back.',
          );
          if (received.supplierId.trim().isNotEmpty && received.subtotal > 0) {
            await _persistAccountTransactionInExistingTransaction(
              sqliteDb,
              AccountTransaction(
                id: '${received.id}-purchase-invoice',
                accountType: 'supplier',
                accountId: received.supplierId,
                accountName: received.supplierName,
                date: received.date,
                type: 'purchaseInvoice',
                referenceId: received.id,
                referenceNo: received.purchaseNo,
                credit: received.subtotal,
                note: 'Purchase invoice ${received.purchaseNo}',
                createdAt: now,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
          }
        }
      });
      if (index == -1) {
        _putPurchaseAtIndex(received, _purchases.length);
      } else {
        _putPurchaseAtIndex(received, index);
      }
      _recordSyncChange(
        entityType: 'purchase',
        entityId: received.id,
        operation: 'receive',
        payload: received.toJson(),
      );
      await refreshAfterDatabaseChange(AppStore._productsKey);
      await refreshAfterDatabaseChange(AppStore._productCostsKey);
      await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
      await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
      if (plannedPayment > 0) {
        received = await settlePurchasePayment(
          purchaseId: received.id,
          amount: plannedPayment,
          paymentMethod: purchase.paymentMethod,
          notes: 'Payment on receiving ${received.purchaseNo}',
          idempotencyKey: '${received.id}:receive-payment:v1',
          date: now,
        );
      }
      if (postAccounting) await refreshAccountTransactionsFromSqlite();
      _touchPurchasesData();
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    final received = _withSyncMeta<Purchase>(
      purchase.copyWith(status: 'Received'),
      now,
    );
    if (index != -1) _putPurchaseAtIndex(received, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: received.id,
      operation: 'receive',
      payload: received.toJson(),
    );
    _applyPurchaseStock(received, now);
    await _saveDirty(
      purchases: true,
      products: true,
      productDerivedData: true,
      stockMovements: true,
      accountTransactions: true,
      sync: true,
    );
    if (postAccounting) {
      final accountingPosted = await _schedulePurchaseAccounting(received);
      if (accountingPosted) {
        await _recordPurchaseLedger(received, now);
        await _saveDirty(accountTransactions: true);
      }
    }
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'receive_purchase',
        message: 'Purchase received successfully.',
        details: 'purchaseId=${received.id} purchaseNo=${received.purchaseNo}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: received.id,
        action: 'receive',
        summary: 'Purchase received',
        details: jsonEncode(received.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

Future<void> deleteDraftPurchase(String id) async {
    requirePermission(AppPermission.purchasesManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) return;
    if (purchase.isReceived) {
      throw StateError(
        'Received purchase invoices cannot be deleted. Cancel them first.',
      );
    }
    if (purchase.isCancelled) {
      throw StateError(
        'Cancelled purchase invoices require permanent delete permission.',
      );
    }
    final now = DateTime.now();
    final deleted = _withSyncMeta<Purchase>(
      purchase.copyWith(deletedAt: now),
      now,
      clearDeletedAt: false,
    );
    if (index != -1) _putPurchaseAtIndex(deleted, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(purchases: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'delete_purchase',
        message: 'Draft purchase deleted successfully.',
        details: 'purchaseId=$id purchaseNo=${purchase.purchaseNo}',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: id,
        action: 'delete',
        summary: 'Draft purchase deleted',
        details: jsonEncode(deleted.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

Future<void> permanentlyDeleteCancelledPurchase(String id) async {
    requirePermission(AppPermission.databaseManage);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) return;
    if (purchase.status.toLowerCase() != 'cancelled') {
      throw StateError(
        'Only cancelled purchase invoices can reach this audit guard.',
      );
    }
    throw StateError(
      'Posted/cancelled purchase invoices are retained for audit and cannot be permanently deleted. Use return/reversal and a new document instead.',
    );
  }

Future<int> _activePostedJournalCountInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
  }) async {
    final normalizedType = referenceType.trim();
    final normalizedId = referenceId.trim();
    if (normalizedType.isEmpty || normalizedId.isEmpty) return 0;
    final row = await sqliteDb.customSelect(
      includePurchaseEditFamily
          ? r'''
      SELECT COUNT(*) AS count
      FROM journal_entries je
      WHERE je.reference_type = ?
        AND (je.reference_id = ? OR instr(je.reference_id, ?) = 1)
        AND je.deleted_at = ''
        AND je.status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries reversal
          WHERE reversal.reversed_entry_id = je.id
            AND reversal.deleted_at = ''
            AND reversal.status = 'posted'
        )
      '''
          : r'''
      SELECT COUNT(*) AS count
      FROM journal_entries je
      WHERE je.reference_type = ?
        AND je.reference_id = ?
        AND je.deleted_at = ''
        AND je.status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries reversal
          WHERE reversal.reversed_entry_id = je.id
            AND reversal.deleted_at = ''
            AND reversal.status = 'posted'
        )
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedType),
        Variable<String>(normalizedId),
        if (includePurchaseEditFamily)
          Variable<String>('$normalizedId:purchase_edit:'),
      ],
    ).getSingle();
    return (row.data['count'] as num? ?? 0).toInt();
  }

Future<void> _requirePostedJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    required String failureMessage,
  }) async {
    final count = await _activePostedJournalCountInTransaction(
      sqliteDb,
      referenceType: referenceType,
      referenceId: referenceId,
      includePurchaseEditFamily: includePurchaseEditFamily,
    );
    if (count <= 0) throw StateError(failureMessage);
  }

Future<void> _requireNoActiveJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    required String failureMessage,
  }) async {
    final count = await _activePostedJournalCountInTransaction(
      sqliteDb,
      referenceType: referenceType,
      referenceId: referenceId,
      includePurchaseEditFamily: includePurchaseEditFamily,
    );
    if (count > 0) throw StateError(failureMessage);
  }

Future<List<StockMovement>> _activePurchaseReceiveMovements(
    dynamic sqliteDb, {
    required String purchaseId,
    required String productId,
    required String documentLineId,
  }) async {
    final rows = await sqliteDb.customSelect(
      '''
      SELECT sm.*
      FROM stock_movements sm
      WHERE sm.reference_id = ?
        AND sm.product_id = ?
        AND sm.document_line_id = ?
        AND sm.movement_type = 'purchase_receive'
        AND sm.deleted_at = ''
        AND NOT EXISTS (
          SELECT 1
          FROM stock_movements reversal
          WHERE reversal.reversal_of_movement_id = sm.id
            AND reversal.deleted_at = ''
        )
      ORDER BY sm.created_at DESC, sm.updated_at DESC, sm.id DESC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(purchaseId),
        Variable<String>(productId),
        Variable<String>(documentLineId),
      ],
    ).get();
    return rows.map<StockMovement>((row) {
      final data = row.data;
      return StockMovement.fromJson(<String, dynamic>{
        'id': data['id'],
        'productId': data['product_id'],
        'productName': data['product_name'],
        'type': data['movement_type'],
        'quantity': data['quantity'],
        'date': data['movement_date'],
        'referenceId': data['reference_id'],
        'referenceNo': data['reference_no'],
        'reason': data['reason'],
        'adjustmentCategory': data['adjustment_category'],
        'notes': data['notes'],
        'evidenceRef': data['evidence_ref'],
        'warehouseId': data['warehouse_id'],
        'warehouseName': data['warehouse_name'],
        'batchId': data['batch_id'],
        'movementGroupId': data['movement_group_id'],
        'documentLineId': data['document_line_id'],
        'sourceMovementId': data['source_movement_id'],
        'reversalOfMovementId': data['reversal_of_movement_id'],
        'idempotencyKey': data['idempotency_key'],
        'unitCost': data['unit_cost'],
        'createdAt': data['created_at'],
        'updatedAt': data['updated_at'],
        'deviceId': data['device_id'],
        'syncStatus': data['sync_status'],
        'storeId': data['store_id'],
        'branchId': data['branch_id'],
        'version': data['version'],
        'lastModifiedByDeviceId': data['last_modified_by_device_id'],
        'reviewedAt': data['reviewed_at'],
        'reviewedBy': data['reviewed_by'],
        'reviewNote': data['review_note'],
      });
    }).toList(growable: false);
  }

Future<void> returnPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
    bool recordSupplierReturnLedger = true,
  }) async {
    requirePermission(AppPermission.purchasesCancel);
    requireSensitiveActionAuthorization(SensitiveAction.purchaseReverse);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError(
        'Only received purchase invoices can be returned. Delete draft invoices instead.',
      );
    }
    // A purchase return reverses inventory/accounting only. It does not pay
    // cash out of the drawer, so the original purchase payment must never be
    // revalidated here. Any cash received back from the supplier is posted
    // separately through refundPurchaseCash() as a Cash In operation.
    await _waitForPendingPurchaseAccounting(purchase.id);
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final now = DateTime.now();
      var reversalApplied = purchase.reversalApplied;
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => false,
      );
      late Purchase returned;
      await sqliteDb.transaction(() async {
        if (reverseStock && !purchase.reversalApplied) {
          await _requirePurchaseBatchesUnusedInTransaction(sqliteDb, purchase);
          await _closeInventoryCostLayersForPurchaseInTransaction(
            sqliteDb,
            purchase,
            now,
          );
          for (var lineIndex = 0;
              lineIndex < purchase.items.length;
              lineIndex += 1) {
            final item = purchase.items[lineIndex];
            final product = _findProductById(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) continue;
            var originalMovements = await _activePurchaseReceiveMovements(
              sqliteDb,
              purchaseId: purchase.id,
              productId: item.productId,
              documentLineId: _stablePurchaseLineId(purchase, item, lineIndex),
            );
            if (originalMovements.isEmpty) {
              originalMovements = await _activePurchaseReceiveMovements(
                sqliteDb,
                purchaseId: purchase.id,
                productId: item.productId,
                documentLineId: '${purchase.id}-line-$lineIndex',
              );
            }
            if (originalMovements.isEmpty) {
              throw StateError(
                'Active stock receipt is missing for ${purchase.purchaseNo}, line $lineIndex.',
              );
            }
            final activeReceivedQuantity = originalMovements.fold<double>(
              0,
              (sum, movement) => sum + movement.quantity,
            );
            if ((activeReceivedQuantity - item.baseQuantity).abs() > 0.000001) {
              throw StateError(
                'Active stock receipt quantity mismatch for ${purchase.purchaseNo}, line $lineIndex.',
              );
            }
            final batchService = BatchInventoryService(sqliteDb);
            for (final originalMovement in originalMovements) {
              if (originalMovement.batchId.trim().isNotEmpty) {
                await batchService.adjustUnifiedBatchInTransaction(
                  product: product,
                  warehouseId: originalMovement.warehouseId,
                  batchId: originalMovement.batchId,
                  quantityDelta: -originalMovement.quantity,
                  adjustedAt: now,
                  storeId: appIdentity.storeId,
                  deviceId: _deviceId,
                );
              }
              await stockService.recordReversalInTransaction(
                originalMovement: originalMovement,
                operationType: 'purchase_return',
                documentType: 'purchase',
                documentId: purchase.id,
                reason:
                    reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                deviceId: _deviceId,
              );
              if (originalMovement.batchId.trim().isNotEmpty) {
                await batchService.assertWarehouseBatchBalanceInTransaction(
                  productId: item.productId,
                  warehouseId: originalMovement.warehouseId.trim().isEmpty
                      ? Warehouse.defaultId
                      : originalMovement.warehouseId.trim(),
                  storeId: appIdentity.storeId,
                );
              }
            }
          }
          reversalApplied = true;
        }
        returned = _purchaseSyncMetaPreview(
          purchase.copyWith(
            status: 'Returned',
            cancelledAt: now,
            cancelledByDeviceId: _deviceId,
            cancelReason: reason.trim(),
            reversalApplied: reversalApplied,
            note: 'Returned on ${now.toIso8601String()}',
          ),
          now,
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[returned.toJson()],
          sortIndices: <int?>[0],
        );
        await _requirePostedJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: purchase.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Active purchase journal is missing; purchase return was rolled back.',
        );
        await AccountingService.reversePurchaseEntriesForPurchase(
          purchaseId: purchase.id,
          reason: reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
          createdBy: _deviceId,
          adjustCashLocationBalance: false,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _requireNoActiveJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: purchase.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Purchase journal reversal did not complete; purchase return was rolled back.',
        );
        if (recordSupplierReturnLedger &&
            purchase.supplierId.trim().isNotEmpty &&
            purchase.subtotal > 0) {
          await _persistAccountTransactionInExistingTransaction(
            sqliteDb,
            AccountTransaction(
              id: '${purchase.id}-purchase-return',
              accountType: 'supplier',
              accountId: purchase.supplierId,
              accountName: purchase.supplierName,
              date: now,
              type: 'purchaseReturn',
              referenceId: purchase.id,
              referenceNo: purchase.purchaseNo,
              debit: purchase.subtotal,
              note: reason.trim().isEmpty
                  ? 'Purchase return ${purchase.purchaseNo}'
                  : reason.trim(),
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              lastModifiedByDeviceId: _deviceId,
            ),
          );
        }
      });
      if (index != -1) {
        _putPurchaseAtIndex(returned, index);
      } else {
        _putPurchaseAtIndex(returned, _purchases.length);
      }
      _recordSyncChange(
        entityType: 'purchase',
        entityId: id,
        operation: 'return',
        payload: returned.toJson(),
      );
      // Refresh the derived product inventory projection from authoritative warehouse stock
      // before refreshing product rows. This keeps the in-memory projection aligned
      // immediately without relying on a later dirty-row flush.
      await _refreshProductStockCompatibilityCache(
        purchase.items.map((item) => item.productId),
      );
      // Return ledger and FIFO changes were committed inside the same SQLite
      // transaction, so only product-metadata/sync rows remain to be flushed.
      await _saveDirty(
        purchases: false,
        products: reverseStock && !purchase.reversalApplied,
        productDerivedData: false,
        stockMovements: false,
        accountTransactions: false,
        sync: true,
      );
      await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
      await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
      await refreshAccountTransactionsFromSqlite();
      _touchPurchasesData();
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    var reversalApplied = purchase.reversalApplied;
    if (reverseStock && !purchase.reversalApplied) {
      if (_inventoryCostingMethod == InventoryCostingMethod.fifo &&
          _purchaseHasConsumedCostLayers(purchase.id)) {
        throw StateError(
            'Cannot reverse this purchase after FIFO layers have been consumed by sales. Return/cancel the related sales first or create a stock revaluation.');
      }
      for (var lineIndex = 0;
          lineIndex < purchase.items.length;
          lineIndex += 1) {
        final item = purchase.items[lineIndex];
        final productIndex = _productIndexById[item.productId];
        if (productIndex == null) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final qty = -item.baseQuantity;
        if (!_storeProfile.allowNegativeStock &&
            product.stock + qty < -0.000001) {
          throw StateError('Insufficient stock in ${product.name}.');
        }
        _products[productIndex] = _withSyncMeta<Product>(
          product.copyWith(stock: product.stock + qty),
          now,
        );
        _addStockMovement(
          StockMovement(
            id: '${purchase.id}-$lineIndex-${item.productId}-purchase-return',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_return',
            quantity: qty,
            date: now,
            referenceId: purchase.id,
            referenceNo: purchase.purchaseNo,
            reason: reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
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
      _closeInventoryCostLayersForPurchase(purchase.id, now);
      reversalApplied = true;
    }
    final returned = _withSyncMeta<Purchase>(
      purchase.copyWith(
        status: 'Returned',
        cancelledAt: now,
        cancelledByDeviceId: _deviceId,
        cancelReason: reason.trim(),
        reversalApplied: reversalApplied,
        note: 'Returned on ${now.toIso8601String()}',
      ),
      now,
    );
    if (index != -1) _putPurchaseAtIndex(returned, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'return',
      payload: returned.toJson(),
    );
    await AccountingService.reversePurchaseEntriesForPurchase(
      purchaseId: purchase.id,
      reason: reason.trim().isEmpty ? 'Purchase returned' : reason.trim(),
      createdBy: _deviceId,
      adjustCashLocationBalance: false,
    );
    if (recordSupplierReturnLedger) {
      await _recordPurchaseCancelLedger(purchase, now,
          reason: reason, isReturn: true);
    }
    await _saveDirty(
      purchases: true,
      products: reverseStock && !purchase.reversalApplied,
      stockMovements: reverseStock && !purchase.reversalApplied,
      accountTransactions: true,
      sync: true,
    );
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'return_purchase',
        message: 'Purchase returned successfully.',
        details:
            'purchaseId=$id purchaseNo=${purchase.purchaseNo} reverseStock=$reverseStock',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: id,
        action: 'return',
        summary: 'Purchase returned',
        details: jsonEncode(returned.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

Future<void> cancelPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  }) async {
    requirePermission(AppPermission.purchasesCancel);
    requireSensitiveActionAuthorization(SensitiveAction.purchaseReverse);
    final index = _purchaseIndexForId(id);
    final purchase =
        index == -1 ? await _purchaseByIdFromSqlite(id) : _purchases[index];
    if (purchase == null) throw ArgumentError('Purchase not found.');
    if (purchase.isCancelled) return;
    if (!purchase.isReceived) {
      throw StateError(
        'Only received purchase invoices can be cancelled. Delete draft invoices instead.',
      );
    }
    // Cancelling a received purchase reverses its business/accounting effect;
    // it is not a new cash payment. Cash recovery from a supplier is handled
    // explicitly by the supplier-refund Cash In workflow.
    final sqliteDb = SqliteMigrationManager.database;
    await _waitForPendingPurchaseAccounting(purchase.id);
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final now = DateTime.now();
      var reversalApplied = purchase.reversalApplied;
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => false,
      );
      await sqliteDb.transaction(() async {
        if (reverseStock && !purchase.reversalApplied) {
          await _requirePurchaseBatchesUnusedInTransaction(sqliteDb, purchase);
          await _closeInventoryCostLayersForPurchaseInTransaction(
            sqliteDb,
            purchase,
            now,
          );
          for (var lineIndex = 0;
              lineIndex < purchase.items.length;
              lineIndex += 1) {
            final item = purchase.items[lineIndex];
            final product = _findProductById(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) continue;
            var originalMovements = await _activePurchaseReceiveMovements(
              sqliteDb,
              purchaseId: purchase.id,
              productId: item.productId,
              documentLineId: _stablePurchaseLineId(purchase, item, lineIndex),
            );
            if (originalMovements.isEmpty) {
              originalMovements = await _activePurchaseReceiveMovements(
                sqliteDb,
                purchaseId: purchase.id,
                productId: item.productId,
                documentLineId: '${purchase.id}-line-$lineIndex',
              );
            }
            if (originalMovements.isEmpty) {
              throw StateError(
                'Active stock receipt is missing for ${purchase.purchaseNo}, line $lineIndex.',
              );
            }
            final activeReceivedQuantity = originalMovements.fold<double>(
              0,
              (sum, movement) => sum + movement.quantity,
            );
            if ((activeReceivedQuantity - item.baseQuantity).abs() > 0.000001) {
              throw StateError(
                'Active stock receipt quantity mismatch for ${purchase.purchaseNo}, line $lineIndex.',
              );
            }
            final batchService = BatchInventoryService(sqliteDb);
            for (final originalMovement in originalMovements) {
              if (originalMovement.batchId.trim().isNotEmpty) {
                await batchService.adjustUnifiedBatchInTransaction(
                  product: product,
                  warehouseId: originalMovement.warehouseId,
                  batchId: originalMovement.batchId,
                  quantityDelta: -originalMovement.quantity,
                  adjustedAt: now,
                  storeId: appIdentity.storeId,
                  deviceId: _deviceId,
                );
              }
              await stockService.recordReversalInTransaction(
                originalMovement: originalMovement,
                operationType: 'purchase_cancel',
                documentType: 'purchase',
                documentId: purchase.id,
                reason: reason.trim().isEmpty
                    ? 'Purchase cancelled'
                    : reason.trim(),
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                deviceId: _deviceId,
              );
              if (originalMovement.batchId.trim().isNotEmpty) {
                await batchService.assertWarehouseBatchBalanceInTransaction(
                  productId: item.productId,
                  warehouseId: originalMovement.warehouseId.trim().isEmpty
                      ? Warehouse.defaultId
                      : originalMovement.warehouseId.trim(),
                  storeId: appIdentity.storeId,
                );
              }
            }
          }
          reversalApplied = true;
        }
        final cancelled = _purchaseSyncMetaPreview(
          purchase.copyWith(
            status: 'Cancelled',
            cancelledAt: now,
            cancelledByDeviceId: _deviceId,
            cancelReason: reason.trim(),
            reversalApplied: reversalApplied,
          ),
          now,
        );
        await _requirePostedJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: purchase.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Active purchase journal is missing; purchase cancellation was rolled back.',
        );
        await AccountingService.reversePurchaseEntriesForPurchase(
          purchaseId: purchase.id,
          reason: reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
          createdBy: _deviceId,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        await _requireNoActiveJournalInTransaction(
          sqliteDb,
          referenceType: 'purchase',
          referenceId: purchase.id,
          includePurchaseEditFamily: true,
          failureMessage:
              'Purchase journal reversal did not complete; purchase cancellation was rolled back.',
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb,
          AppStore._purchasesKey,
          <Map<String, dynamic>>[cancelled.toJson()],
          sortIndices: <int?>[0],
        );
        if (purchase.supplierId.trim().isNotEmpty && purchase.subtotal > 0) {
          await _persistAccountTransactionInExistingTransaction(
            sqliteDb,
            AccountTransaction(
              id: '${purchase.id}-purchase-cancel',
              accountType: 'supplier',
              accountId: purchase.supplierId,
              accountName: purchase.supplierName,
              date: now,
              type: 'cancel',
              referenceId: purchase.id,
              referenceNo: purchase.purchaseNo,
              debit: purchase.subtotal,
              note:
                  reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              lastModifiedByDeviceId: _deviceId,
            ),
          );
        }
      });
      final cancelled = _purchaseSyncMetaPreview(
        purchase.copyWith(
          status: 'Cancelled',
          cancelledAt: now,
          cancelledByDeviceId: _deviceId,
          cancelReason: reason.trim(),
          reversalApplied: reversalApplied,
        ),
        now,
      );
      if (index != -1) {
        _putPurchaseAtIndex(cancelled, index);
      } else {
        _putPurchaseAtIndex(cancelled, _purchases.length);
      }
      _recordSyncChange(
        entityType: 'purchase',
        entityId: id,
        operation: 'cancel',
        payload: cancelled.toJson(),
      );
      // Refresh the derived product inventory projection from authoritative warehouse stock
      // before persisting product rows. This avoids leaving a RAM-only cache
      // update after a fully committed purchase cancellation.
      await _refreshProductStockCompatibilityCache(
        purchase.items.map((item) => item.productId),
      );
      // Cancel ledger and FIFO changes were committed inside the same SQLite
      // transaction, so only product-metadata/sync rows remain to be flushed.
      await _saveDirty(
        purchases: false,
        products: reverseStock && !purchase.reversalApplied,
        productDerivedData: false,
        stockMovements: false,
        accountTransactions: false,
        sync: true,
      );
      await refreshAfterDatabaseChange(AppStore._inventoryCostLayersKey);
      await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
      await refreshAccountTransactionsFromSqlite();
      _touchPurchasesData();
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    var reversalApplied = purchase.reversalApplied;
    if (reverseStock && purchase.isReceived && !purchase.reversalApplied) {
      if (_inventoryCostingMethod == InventoryCostingMethod.fifo &&
          _purchaseHasConsumedCostLayers(purchase.id)) {
        throw StateError(
            'Cannot reverse this purchase after FIFO layers have been consumed by sales. Return/cancel the related sales first or create a stock revaluation.');
      }
      for (var lineIndex = 0;
          lineIndex < purchase.items.length;
          lineIndex += 1) {
        final item = purchase.items[lineIndex];
        final productIndex = _productIndexById[item.productId];
        if (productIndex == null) continue;
        final product = _products[productIndex];
        if (!product.trackStock) continue;
        final qty = -item.baseQuantity;
        if (!_storeProfile.allowNegativeStock &&
            product.stock + qty < -0.000001) {
          throw StateError('Insufficient stock in ${product.name}.');
        }
        _products[productIndex] = _withSyncMeta<Product>(
          product.copyWith(stock: product.stock + qty),
          now,
        );
        _addStockMovement(
          StockMovement(
            id: '${purchase.id}-$lineIndex-${item.productId}-purchase-cancel',
            productId: item.productId,
            productName: item.productName,
            type: 'purchase_cancel',
            quantity: qty,
            date: now,
            referenceId: purchase.id,
            referenceNo: purchase.purchaseNo,
            reason:
                reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
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
      _closeInventoryCostLayersForPurchase(purchase.id, now);
      reversalApplied = true;
    }
    final cancelled = _withSyncMeta<Purchase>(
      purchase.copyWith(
        status: 'Cancelled',
        cancelledAt: now,
        cancelledByDeviceId: _deviceId,
        cancelReason: reason.trim(),
        reversalApplied: reversalApplied,
      ),
      now,
    );
    if (index != -1) _putPurchaseAtIndex(cancelled, index);
    _recordSyncChange(
      entityType: 'purchase',
      entityId: id,
      operation: 'cancel',
      payload: cancelled.toJson(),
    );
    await _recordPurchaseCancelLedger(purchase, now, reason: reason);
    await _waitForPendingPurchaseAccounting(purchase.id);
    await AccountingService.reversePurchaseEntriesForPurchase(
      purchaseId: purchase.id,
      reason: reason.trim().isEmpty ? 'Purchase cancelled' : reason.trim(),
      createdBy: _deviceId,
    );
    await _saveDirty(
      purchases: true,
      products: reverseStock && !purchase.reversalApplied,
      stockMovements: reverseStock && !purchase.reversalApplied,
      accountTransactions: true,
      sync: true,
    );
    unawaited(
      AppLogger.info(
        area: 'purchases',
        action: 'cancel_purchase',
        message: 'Purchase cancelled successfully.',
        details:
            'purchaseId=$id purchaseNo=${purchase.purchaseNo} reverseStock=$reverseStock',
        userId: _activeUser?.id ?? '',
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        devicePlatform: appIdentity.platform.name,
        deviceModel: appIdentity.deviceName.isNotEmpty
            ? appIdentity.deviceName
            : _deviceId,
        isImportant: true,
      ),
    );
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: id,
        action: 'cancel',
        summary: 'Purchase cancelled',
        details: jsonEncode(cancelled.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    _touchPurchasesData();
    notifyListeners();
  }

}
