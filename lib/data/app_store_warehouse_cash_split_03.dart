part of 'app_store.dart';

extension _AppStoreSplitWarehouseCashPart3 on AppStore {
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String notes = '',
  }) async {
    requirePermission(AppPermission.inventoryWarehousesManage);
    if (quantity <= 0) {
      throw ArgumentError('Transfer quantity must be positive.');
    }
    _ensureDefaultWarehouse();
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('Choose two different warehouses.');
    }
    final productIndex = _productIndexById[productId];
    if (productIndex == null) throw ArgumentError('Product not found.');
    final product = _products[productIndex];
    if (!product.trackStock) {
      throw StateError('This product does not track stock.');
    }
    final fromWarehouse = _warehouses.firstWhere(
      (item) => item.id == fromWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Source warehouse not found.'),
    );
    final toWarehouse = _warehouses.firstWhere(
      (item) => item.id == toWarehouseId && !item.isDeleted,
      orElse: () => throw ArgumentError('Destination warehouse not found.'),
    );
    final sqliteDb = SqliteMigrationManager.database;
    if (LocalDatabaseService.isSqliteAuthoritative && sqliteDb != null) {
      final now = DateTime.now();
      final transferId = now.microsecondsSinceEpoch.toString();
      final stockService = StockTransactionService(
        sqliteDb,
        deviceId: _deviceId,
        defaultStoreId: appIdentity.storeId,
        defaultBranchId: appIdentity.branchId,
        defaultSyncTarget: _stockTransactionSyncTarget,
        allowNegativeStockResolver: (_, __) => _storeProfile.allowNegativeStock,
      );
      final outMovement = StockMovement(
        id: '$transferId-$productId-transfer-out',
        productId: productId,
        productName: product.name,
        type: 'transfer_out',
        quantity: -quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer to ${toWarehouse.name}',
        notes: notes.trim(),
        warehouseId: fromWarehouse.id,
        warehouseName: fromWarehouse.name,
        movementGroupId: transferId,
        documentLineId: '$transferId-line-out',
        idempotencyKey: '$transferId:transfer:out',
        unitCost: _safeUsdCost(product),
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      );
      final inMovement = StockMovement(
        id: '$transferId-$productId-transfer-in',
        productId: productId,
        productName: product.name,
        type: 'transfer_in',
        quantity: quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer from ${fromWarehouse.name}',
        notes: notes.trim(),
        warehouseId: toWarehouse.id,
        warehouseName: toWarehouse.name,
        movementGroupId: transferId,
        documentLineId: '$transferId-line-in',
        idempotencyKey: '$transferId:transfer:in',
        unitCost: _safeUsdCost(product),
        createdAt: now,
        updatedAt: now,
        deviceId: _deviceId,
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        lastModifiedByDeviceId: _deviceId,
      );
      final batchService = BatchInventoryService(sqliteDb);
      var transferMovements = <StockMovement>[outMovement, inMovement];
      await _traceAsync<void>('inventory.transferStock', 'sqlite_transaction',
          () async {
        await sqliteDb.transaction(() async {
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            sqliteDb,
            product: product,
            warehouseId: fromWarehouse.id,
            at: now,
          );
          await _ensureUnifiedBatchCutoverForProductInTransaction(
            sqliteDb,
            product: product,
            warehouseId: toWarehouse.id,
            at: now,
          );
          final allocations = await batchService.transferUnifiedInTransaction(
            product: product,
            fromWarehouseId: fromWarehouse.id,
            toWarehouseId: toWarehouse.id,
            quantity: quantity,
            transferredAt: now,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
            allowNegativeStock: _storeProfile.allowNegativeStock,
          );
          transferMovements = <StockMovement>[
            for (var batchIndex = 0;
                batchIndex < allocations.length;
                batchIndex += 1) ...<StockMovement>[
              outMovement.copyWith(
                id: '${outMovement.id}-batch-$batchIndex',
                quantity: -allocations[batchIndex].quantity,
                batchId: allocations[batchIndex].batchId,
                unitCost: allocations[batchIndex].unitCost,
                documentLineId: '$transferId-line-out-batch-$batchIndex',
                idempotencyKey: '$transferId:transfer:out:$batchIndex',
              ),
              inMovement.copyWith(
                id: '${inMovement.id}-batch-$batchIndex',
                quantity: allocations[batchIndex].quantity,
                batchId: allocations[batchIndex].batchId,
                unitCost: allocations[batchIndex].unitCost,
                documentLineId: '$transferId-line-in-batch-$batchIndex',
                idempotencyKey: '$transferId:transfer:in:$batchIndex',
              ),
            ],
          ];
          await stockService.recordMovementsInTransaction(
            operationType: 'warehouse_transfer',
            documentType: 'stock_transfer',
            documentId: transferId,
            movementGroupId: transferId,
            idempotencyKey: '$transferId:warehouse_transfer',
            movements: transferMovements,
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            deviceId: _deviceId,
          );
          await _assertUnifiedBatchMovementBalancesInTransaction(
            batchService,
            transferMovements,
          );
          await InventoryTraceabilityService(sqliteDb)
              .assertTransferTraceabilityInTransaction(
            movementGroupId: transferId,
            storeId: appIdentity.storeId,
          );
        });
      });
      _mirrorAuthoritativeStockMovements(transferMovements);
      await _refreshProductStockCompatibilityCache(<String>[productId]);
      _recordSyncChange(
        entityType: 'warehouse_transfer',
        entityId: transferId,
        operation: 'transfer',
        payload: <String, dynamic>{
          'id': transferId,
          'referenceNo': 'TR-$transferId',
          'productId': productId,
          'productName': product.name,
          'fromWarehouseId': fromWarehouse.id,
          'fromWarehouseName': fromWarehouse.name,
          'toWarehouseId': toWarehouse.id,
          'toWarehouseName': toWarehouse.name,
          'quantity': quantity,
          'notes': notes.trim(),
          'movementGroupId': transferId,
          'movements': transferMovements.map((item) => item.toJson()).toList(),
        },
      );
      for (final movement in transferMovements) {
        _recordSyncChange(
          entityType: 'stock_movement',
          entityId: movement.id,
          operation: 'transfer',
          payload: movement.toJson(),
        );
      }
      unawaited(
        AppLogger.info(
          area: 'inventory',
          action: 'transfer_stock',
          message: 'Stock transferred successfully.',
          details:
              'productId=$productId from=$fromWarehouseId to=$toWarehouseId quantity=$quantity',
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
          entityType: 'warehouse_transfer',
          entityId: transferId,
          action: 'transfer',
          summary: 'Stock transferred',
          details: jsonEncode(<String, Object?>{
            'productId': productId,
            'fromWarehouseId': fromWarehouseId,
            'toWarehouseId': toWarehouseId,
            'quantity': quantity,
            'notes': notes,
          }),
          userId: _activeUser?.id ?? '',
          userName: _actorName(),
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          sessionId: _deviceId,
          traceId: _deviceId,
          deviceId: _deviceId,
          sourceModule: 'inventory',
          isImportant: true,
        ),
      );
      notifyListeners();
      return;
    }
    final available = _stockForWarehouse(productId, fromWarehouseId);
    if (!_storeProfile.allowNegativeStock && available < quantity) {
      throw StateError('Not enough stock in ${fromWarehouse.name}.');
    }
    final now = DateTime.now();
    final transferId = now.microsecondsSinceEpoch.toString();
    _addStockMovement(
      StockMovement(
        id: '$transferId-$productId-transfer-out',
        productId: productId,
        productName: product.name,
        type: 'transfer_out',
        quantity: -quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer to ${toWarehouse.name}',
        notes: notes.trim(),
        warehouseId: fromWarehouse.id,
        warehouseName: fromWarehouse.name,
        movementGroupId: transferId,
        documentLineId: '$transferId-line-out',
        idempotencyKey: '$transferId:transfer:out',
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
    _addStockMovement(
      StockMovement(
        id: '$transferId-$productId-transfer-in',
        productId: productId,
        productName: product.name,
        type: 'transfer_in',
        quantity: quantity,
        date: now,
        referenceId: transferId,
        referenceNo: 'TR-$transferId',
        reason: 'Warehouse transfer from ${fromWarehouse.name}',
        notes: notes.trim(),
        warehouseId: toWarehouse.id,
        warehouseName: toWarehouse.name,
        movementGroupId: transferId,
        documentLineId: '$transferId-line-in',
        idempotencyKey: '$transferId:transfer:in',
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
    await _saveDirty(stockMovements: true, sync: true);
    unawaited(
      AppLogger.info(
        area: 'inventory',
        action: 'transfer_stock',
        message: 'Stock transferred successfully.',
        details:
            'productId=$productId from=$fromWarehouseId to=$toWarehouseId quantity=$quantity',
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
        entityType: 'warehouse_transfer',
        entityId: transferId,
        action: 'transfer',
        summary: 'Stock transferred',
        details: jsonEncode(<String, Object?>{
          'productId': productId,
          'fromWarehouseId': fromWarehouseId,
          'toWarehouseId': toWarehouseId,
          'quantity': quantity,
          'notes': notes,
        }),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'inventory',
        isImportant: true,
      ),
    );
    notifyListeners();
  }

  Future<Map<String, String>> _openCashVoucherContext() async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError(
          'Payment vouchers require the SQLite authoritative store.');
    }
    final branchFilter =
        appIdentity.branchId.trim().isEmpty ? '' : 'AND cds.branch_id = ?';
    final row = await sqliteDb.customSelect(
      '''
      SELECT cds.id AS session_id, cds.cash_location_id
      FROM cash_drawer_sessions cds
      INNER JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'open'
        AND cl.deleted_at = ''
        AND cl.is_active = 1
        AND cl.type = 'cash_drawer'
        AND cl.device_id = ?
        $branchFilter
      ORDER BY cds.opened_at DESC
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(_deviceId),
        if (appIdentity.branchId.trim().isNotEmpty)
          Variable<String>(appIdentity.branchId.trim()),
      ],
    ).getSingleOrNull();
    if (row == null) {
      throw StateError(
        'لا توجد وردية نقدية مفتوحة لهذا الجهاز. افتح وردية قبل قبول الدفع النقدي.',
      );
    }
    return <String, String>{
      'sessionId': row.data['session_id']?.toString() ?? '',
      'cashLocationId': row.data['cash_location_id']?.toString() ?? '',
    };
  }

  Future<double> _saleReturnEntitlementFromSqlite(String saleId) async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      return 0;
    }
    final row = await sqliteDb.customSelect(
      '''
      SELECT COALESCE(SUM(credit - debit), 0) AS total
      FROM account_transactions
      WHERE deleted_at = ''
        AND account_type = 'customer'
        AND transaction_type = 'saleReturn'
        AND reference_id = ?
      ''',
      variables: <Variable<Object>>[Variable<String>(saleId.trim())],
    ).getSingle();
    return ((row.data['total'] as num?)?.toDouble() ?? 0)
        .clamp(0, double.infinity)
        .toDouble();
  }

  Future<double> refundableSaleCashAmount(String saleId) async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final sale = _sales.where((item) => item.id == saleId).firstOrNull ??
        await _saleByIdFromSqlite(saleId);
    if (sale == null) return 0;

    // returnedAmount is not a dedicated authoritative sales-table column.
    // After a SQLite reload it can be zero although the return itself is
    // already committed. Derive the durable entitlement from SQLite.
    final sqliteReturnEntitlement =
        await _saleReturnEntitlementFromSqlite(sale.id);
    final returnedEntitlement =
        max(sale.returnedAmount, sqliteReturnEntitlement);
    final voucherService = PaymentVoucherService(sqliteDb);
    final unallocatedPool =
        await voucherService.unallocatedCashForSale(sale.id);
    final overpaymentEntitlement = !sale.isCancelled
        ? max(max(0.0, sale.paidAmount - sale.invoiceTotal), unallocatedPool)
        : 0.0;
    final entitlement = max(returnedEntitlement, overpaymentEntitlement) > 0
        ? max(returnedEntitlement, overpaymentEntitlement)
        : (sale.isCancelled
            ? (sale.subtotal - sale.discount)
                .clamp(0, double.infinity)
                .toDouble()
            : 0.0);
    if (entitlement <= 0.000001) return 0;
    return voucherService.refundableCashForSale(
      sale.id,
      maxRefundAmount: entitlement,
    );
  }

  Future<void> normalizeRefundAllocations() async {
    requirePermission(AppPermission.cashBoxManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    await PaymentVoucherService(sqliteDb)
        .normalizeOverAllocatedVouchers(deviceId: _deviceId);
    await refreshAfterDatabaseChange(AppStore._salesKey);
    await refreshAfterDatabaseChange(AppStore._purchasesKey);
  }

  Future<double> refundablePurchaseCashAmount(String purchaseId) async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    // paid_amount is only a compatibility cache. Always rebuild it from the
    // authoritative active allocations before it participates in a refund
    // decision, so a prior refund can never leave a stale overpayment behind.
    final syncedPaidAmount =
        await service.syncPurchasePaymentCacheFromAllocations(
      purchaseId: purchaseId,
      deviceId: _deviceId,
    );
    final purchase = await _purchaseByIdFromSqlite(purchaseId);
    if (purchase == null) return 0;
    final purchaseTotal =
        purchase.items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final unallocatedPool =
        await service.unallocatedCashForPurchase(purchase.id);
    final overpayment =
        max(max(0.0, syncedPaidAmount - purchaseTotal), unallocatedPool);
    return service.refundableCashForPurchase(
      purchase.id,
      maxRefundAmount: purchase.isCancelled ? null : overpayment,
    );
  }

  Future<double> refundSaleCash({
    required String saleId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    requirePermission(AppPermission.salesCancel);
    final index = _sales.indexWhere((sale) => sale.id == saleId);
    final sale =
        index == -1 ? await _saleByIdFromSqlite(saleId) : _sales[index];
    if (sale == null) throw ArgumentError('Sale not found.');
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    final preCancellationTotal =
        (sale.subtotal - sale.discount).clamp(0, double.infinity).toDouble();
    final sqliteReturnEntitlement =
        await _saleReturnEntitlementFromSqlite(sale.id);
    final returnedEntitlement =
        max(sale.returnedAmount, sqliteReturnEntitlement);
    final unallocatedPool = await service.unallocatedCashForSale(sale.id);
    final overpaymentEntitlement = !sale.isCancelled
        ? max(max(0.0, sale.paidAmount - sale.invoiceTotal), unallocatedPool)
        : 0.0;
    final refundEntitlement =
        max(returnedEntitlement, overpaymentEntitlement) > 0
            ? max(returnedEntitlement, overpaymentEntitlement)
            : (sale.isCancelled ? preCancellationTotal : 0.0);
    if (!sale.isCancelled && refundEntitlement <= 0.000001) {
      throw StateError(
        'No cash overpayment is available for this sale.',
      );
    }
    final refundable = await service.refundableCashForSale(
      sale.id,
      maxRefundAmount: refundEntitlement,
    );
    if (refundable <= 0.000001) return 0;
    final requested = amount ?? refundable;
    if (!requested.isFinite || requested <= 0) {
      throw ArgumentError('Refund amount must be greater than zero.');
    }
    final context = await _openCashVoucherContext();
    final refundKey = idempotencyKey.trim().isEmpty
        ? 'manual:${DateTime.now().microsecondsSinceEpoch}'
        : idempotencyKey.trim();
    final refunded = await service.refundSaleCash(
      saleId: sale.id,
      invoiceNo: sale.invoiceNo,
      customerId: sale.customerId,
      customerName: sale.customerName,
      requestedAmount: requested,
      maxRefundAmount: refundEntitlement,
      currency: sale.invoiceCurrency,
      cashLocationId: context['cashLocationId'] ?? '',
      cashDrawerSessionId: context['sessionId'] ?? '',
      refundKey: refundKey,
      notes: notes.trim().isEmpty
          ? 'Cash refund for ${sale.invoiceNo}'
          : notes.trim(),
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      date: date,
    );
    if (refunded <= 0.000001) return 0;

    // PaymentVoucherService persists the customer refund compatibility row
    // inside the same SQLite transaction as journal + Cash Ledger + drawer.
    await _refreshAccountTransactionsFromSqlite();
    await refreshAfterDatabaseChange(AppStore._salesKey);
    return refunded;
  }

  Future<double> refundPurchaseCash({
    required String purchaseId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    requirePermission(AppPermission.suppliersPaymentManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final service = PaymentVoucherService(sqliteDb);
    // Make the refund path self-contained: synchronize the compatibility cache
    // from authoritative allocations before computing any entitlement. Do not
    // rely on the cash dialog having run normalization first.
    final syncedPaidAmount =
        await service.syncPurchasePaymentCacheFromAllocations(
      purchaseId: purchaseId,
      deviceId: _deviceId,
    );
    final purchase = await _purchaseByIdFromSqlite(purchaseId);
    if (purchase == null) throw ArgumentError('Purchase not found.');
    final purchaseTotal =
        purchase.items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final unallocatedPool =
        await service.unallocatedCashForPurchase(purchase.id);
    final overpayment =
        max(max(0.0, syncedPaidAmount - purchaseTotal), unallocatedPool);
    final refundable = await service.refundableCashForPurchase(
      purchase.id,
      maxRefundAmount: purchase.isCancelled ? null : overpayment,
    );
    if (refundable <= 0.000001) return 0;
    final context = await _openCashVoucherContext();
    final refundKey = idempotencyKey.trim().isEmpty
        ? 'manual:${DateTime.now().microsecondsSinceEpoch}:$_deviceId'
        : idempotencyKey.trim();
    final refunded = await service.refundPurchaseCash(
      purchaseId: purchase.id,
      purchaseNo: purchase.purchaseNo,
      supplierId: purchase.supplierId,
      supplierName: purchase.supplierName,
      cashLocationId: context['cashLocationId'] ?? '',
      cashDrawerSessionId: context['sessionId'] ?? '',
      requestedAmount: amount,
      maxRefundAmount: purchase.isCancelled ? null : overpayment,
      currency: storeProfile.baseCurrency,
      notes: notes.trim().isEmpty
          ? 'Cash refund from supplier for ${purchase.purchaseNo}'
          : notes.trim(),
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      refundKey: refundKey,
      date: date,
    );
    if (refunded <= 0.000001) return 0;

    // The supplier compatibility ledger row is inserted atomically by
    // PaymentVoucherService inside the same SQLite transaction as the refund.
    // Refresh the in-memory compatibility view only; do not persist a second
    // copy from AppStore.
    await _refreshAccountTransactionsFromSqlite();
    await refreshAfterDatabaseChange(AppStore._purchasesKey);
    return refunded;
  }

  Future<double> refundablePurchaseReturnCashAmount(
      String purchaseReturnId) async {
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final returned = await _purchaseByIdFromSqlite(purchaseReturnId);
    if (returned == null || returned.isDeleted || !returned.isPurchaseReturn) {
      return 0;
    }
    final service = PaymentVoucherService(sqliteDb);
    await service.ensurePurchaseReturnJournal(
      purchaseReturnId: returned.id,
      purchaseReturnNo: returned.purchaseNo,
      supplierId: returned.supplierId,
      supplierName: returned.supplierName,
      returnDate: returned.date,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      deviceId: _deviceId,
    );
    return service.refundableCashForPurchaseReturn(returned.id);
  }

  Future<double> refundPurchaseReturnCash({
    required String purchaseReturnId,
    double? amount,
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    requirePermission(AppPermission.suppliersPaymentManage);
    final sqliteDb = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || sqliteDb == null) {
      throw StateError('Cash refunds require the SQLite authoritative store.');
    }
    final returned = await _purchaseByIdFromSqlite(purchaseReturnId);
    if (returned == null || returned.isDeleted || !returned.isPurchaseReturn) {
      throw StateError('Purchase return is not available for refund.');
    }
    final refundable = await refundablePurchaseReturnCashAmount(returned.id);
    if (refundable <= 0.000001) return 0;
    final context = await _openCashVoucherContext();
    final refundKey = idempotencyKey.trim().isEmpty
        ? 'manual:${DateTime.now().microsecondsSinceEpoch}:$_deviceId'
        : idempotencyKey.trim();
    final refunded =
        await PaymentVoucherService(sqliteDb).refundPurchaseReturnCash(
      purchaseReturnId: returned.id,
      purchaseReturnNo: returned.purchaseNo,
      supplierId: returned.supplierId,
      supplierName: returned.supplierName,
      cashLocationId: context['cashLocationId'] ?? '',
      cashDrawerSessionId: context['sessionId'] ?? '',
      requestedAmount: amount,
      currency: storeProfile.baseCurrency,
      notes: notes.trim().isEmpty
          ? 'Cash refund for purchase return ${returned.purchaseNo}'
          : notes.trim(),
      createdBy: _actorName(),
      createdByUserId: _activeUser?.id ?? '',
      deviceId: _deviceId,
      branchId: appIdentity.branchId,
      storeId: appIdentity.storeId,
      refundKey: refundKey,
      date: date,
    );
    if (refunded <= 0.000001) return 0;
    await _refreshAccountTransactionsFromSqlite();
    await refreshAfterDatabaseChange(AppStore._purchasesKey);
    return refunded;
  }
}
