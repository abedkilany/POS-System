part of 'app_store_workflow_test.dart';

void _registerAppStoreWorkflowSalesPart3() {
  test('account payment uses the typed accounting port', () async {
    final store = await readySqliteStore(
      storeId: 'ST-TYPED-ACCOUNT-PAYMENT',
      branchId: 'BR-TYPED-ACCOUNT-PAYMENT',
    );
    final drawerId = await seedOpenCashDrawerForStore(store);
    await store.accounting.settleAccountPayment(
      accountType: 'customer',
      accountId: 'customer-typed-payment',
      accountName: 'Typed Payment Customer',
      amount: 17,
      paymentMethod: 'Cash',
      idempotencyKey: 'typed-account-payment',
    );

    final db = SqliteMigrationManager.database!;
    final drawer = await db.customSelect(
      'SELECT current_balance FROM cash_locations WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(drawerId)],
    ).getSingle();
    final balance = await db.customSelect(
      "SELECT COALESCE(SUM(credit - debit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'customer' AND account_id = ?",
      variables: <Variable<Object>>[
        Variable<String>('customer-typed-payment'),
      ],
    ).getSingle();

    expect((drawer.data['current_balance'] as num).toDouble(), 1017);
    expect((balance.data['balance'] as num).toDouble(), 17);
  });

  test('received purchase edit recalculates payment status from allocations',
      () async {
    final store = await readySqliteStore(storeId: 'ST-PUREDIT4');
    await store
        .catalog.addOrUpdateProduct(product(id: 'p-edit-payment', stock: 0, cost: 2));
    final received = await store.commerce.createPurchase(
      supplierId: 'supplier-edit-payment',
      supplierName: 'Payment Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: true,
      items: const [
        PurchaseItem(
          productId: 'p-edit-payment',
          productName: 'Payment Product',
          quantity: 10,
          unitCost: 10,
        ),
      ],
    );
    final partiallyPaid = await store.commerce.settlePurchasePayment(
      purchaseId: received.id,
      amount: 40,
      paymentMethod: 'Bank',
      idempotencyKey: '${received.id}:payment-status-regression',
    );
    expect(partiallyPaid.paidAmount, closeTo(40, 0.0001));

    final partialEdit = await store.commerce.updatePurchaseDraft(
      purchaseId: partiallyPaid.id,
      expectedVersion: partiallyPaid.version,
      supplierId: partiallyPaid.supplierId,
      supplierName: partiallyPaid.supplierName,
      warehouseId: partiallyPaid.warehouseId,
      warehouseName: partiallyPaid.warehouseName,
      items: const [
        PurchaseItem(
          productId: 'p-edit-payment',
          productName: 'Payment Product',
          quantity: 8,
          unitCost: 10,
        ),
      ],
    );
    expect(partialEdit.paymentStatus, 'partial');
    expect(partialEdit.paidAmount, closeTo(40, 0.0001));
    expect(partialEdit.postedSnapshot!.totals.paid, closeTo(40, 0.0001));
    expect(partialEdit.postedSnapshot!.totals.remaining, closeTo(40, 0.0001));

    final paidEdit = await store.commerce.updatePurchaseDraft(
      purchaseId: partialEdit.id,
      expectedVersion: partialEdit.version,
      supplierId: partialEdit.supplierId,
      supplierName: partialEdit.supplierName,
      warehouseId: partialEdit.warehouseId,
      warehouseName: partialEdit.warehouseName,
      items: const [
        PurchaseItem(
          productId: 'p-edit-payment',
          productName: 'Payment Product',
          quantity: 4,
          unitCost: 10,
        ),
      ],
    );
    expect(paidEdit.paymentStatus, 'paid');
    expect(paidEdit.paidAmount, closeTo(40, 0.0001));
    expect(paidEdit.postedSnapshot!.totals.remaining, closeTo(0, 0.0001));
  });

  test('handles purchase draft, receive, cancel, and manual stock adjustment',
      () async {
    final store = await readySqliteStore(storeId: 'ST-PURFLOW1');
    await store
        .catalog.addOrUpdateProduct(product(id: 'p-purchase-flow', stock: 0, cost: 5));
    await store.inventory.adjustStock(
        productId: 'p-purchase-flow',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 2,
        reason: 'test seed');

    await expectLater(
        store.commerce.createPurchase(
            supplierId: 's1', supplierName: 'Vendor', items: const []),
        throwsArgumentError);
    await expectLater(
      store.commerce.createPurchase(
          supplierId: 's1',
          supplierName: 'Vendor',
          items: const [
            PurchaseItem(
                productId: 'missing',
                productName: 'Ghost',
                quantity: 1,
                unitCost: 1)
          ]),
      throwsArgumentError,
    );

    final draft = await store.commerce.createPurchase(
      supplierId: 's1',
      supplierName: '',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: false,
      items: const [
        PurchaseItem(
            productId: 'p-purchase-flow',
            productName: 'Coffee',
            quantity: 3,
            unitCost: 6)
      ],
    );
    expect(draft.status, 'Draft');
    expect(store.commerce.pendingPurchaseCount, 1);
    expect(store.catalog.products.single.stock, 2);
    final costBeforeReceipt =
        store.catalog.productCostFor('p-purchase-flow').averageCost;

    await store.commerce.receivePurchase(draft.id);
    expect(store.commerce.purchases.single.isReceived, isTrue);
    expect(store.catalog.products.single.stock, 5);
    expect(
      store.catalog.productCostFor('p-purchase-flow').averageCost,
      closeTo(((2 * costBeforeReceipt) + 18) / 5, 0.001),
    );
    expect(store.commerce.totalPurchasesAmount, 18);

    await store.inventory.adjustStock(
      productId: 'p-purchase-flow',
      warehouseId: Warehouse.defaultId,
      quantityDelta: -2,
      reason: 'count correction',
    );
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-purchase-flow',
        warehouseId: Warehouse.defaultId,
        storeId: store.runtime.identity.storeId,
      ),
      3,
    );
    expect(
      store.inventory.stockMovements.where(
        (m) => m.type == 'inventory_loss' || m.type == 'inventory_adjustment',
      ),
      isNotEmpty,
    );

    await store.commerce.cancelPurchase(draft.id);
    expect(store.commerce.purchases.single.isCancelled, isTrue);
    expect(store.commerce.totalPurchasesAmount, 0);
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-purchase-flow',
        warehouseId: Warehouse.defaultId,
        storeId: store.runtime.identity.storeId,
      ),
      0,
    );
  });

  test('SQLite-first purchase ledger is durable immediately after create',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P9-ACCOUNT-SOT',
      branchId: 'BR-P9-ACCOUNT-SOT',
    );
    await store.catalog.addOrUpdateProduct(product(id: 'p-p9-account-sot', stock: 0));

    final purchase = await store.commerce.createPurchase(
      supplierId: 'supplier-p9-account-sot',
      supplierName: 'Phase 9 Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-p9-account-sot',
          productName: 'Coffee',
          quantity: 2,
          unitCost: 10,
        ),
      ],
      receiveNow: true,
    );

    final db = SqliteMigrationManager.database!;
    final row = await db.customSelect(
      'SELECT account_type, account_id, transaction_type, credit '
      "FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[
        Variable<String>('${purchase.id}-purchase-invoice'),
      ],
    ).getSingle();

    expect(row.read<String>('account_type'), 'supplier');
    expect(row.read<String>('account_id'), 'supplier-p9-account-sot');
    expect(row.read<String>('transaction_type'), 'purchaseInvoice');
    expect((row.data['credit'] as num).toDouble(), 20);
  });

  test('phase 6 purchase cancellation never auto-refunds supplier cash',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P6-PURCHASE-CANCEL',
      branchId: 'BR-P6-PURCHASE-CANCEL',
    );
    final drawerId = await seedOpenCashDrawerForStore(store);
    await store.catalog.addOrUpdateProduct(product(id: 'p-p6-purchase', stock: 0));
    final purchase = await store.commerce.createPurchase(
      supplierId: 'supplier-p6-cancel',
      supplierName: 'Phase 6 Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-p6-purchase',
          productName: 'Coffee',
          quantity: 2,
          unitCost: 10,
        ),
      ],
      receiveNow: true,
    );
    await store.commerce.settlePurchasePayment(
      purchaseId: purchase.id,
      amount: 20,
      paymentMethod: 'Cash',
      idempotencyKey: 'p6-purchase-cancel-payment',
    );

    final db = SqliteMigrationManager.database!;
    final beforeCancel = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
        )
        .getSingle();
    expect((beforeCancel.data['current_balance'] as num).toDouble(), 980);

    await store.commerce.cancelPurchase(purchase.id);

    final autoRefunds = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_type = 'purchase_refund' AND deleted_at = ''",
        )
        .getSingle();
    expect(autoRefunds.read<int>('c'), 0);
    expect(
      await PaymentVoucherService(db).refundableCashForPurchase(purchase.id),
      20,
    );
    final afterCancel = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
        )
        .getSingle();
    expect((afterCancel.data['current_balance'] as num).toDouble(), 980);
    final supplierAdvanceAfterCancel = await db
        .customSelect(
          "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'supplier' AND account_id = 'supplier-p6-cancel'",
        )
        .getSingle();
    expect((supplierAdvanceAfterCancel.data['balance'] as num).toDouble(), 20);

    final refunded = await store.commerce.refundPurchaseCash(
      purchaseId: purchase.id,
    );
    expect(refunded, 20);
    final afterRefund = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
        )
        .getSingle();
    expect((afterRefund.data['current_balance'] as num).toDouble(), 1000);
    final supplierBalanceAfterRefund = await db
        .customSelect(
          "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'supplier' AND account_id = 'supplier-p6-cancel'",
        )
        .getSingle();
    expect((supplierBalanceAfterRefund.data['balance'] as num).toDouble(), 0);

    final supplierRefundReference = await db.customSelect(
      "SELECT reference_id FROM cash_ledger_transactions WHERE reference_type = 'purchase_refund' AND reference_id LIKE ? AND reversal_of_id = '' ORDER BY created_at DESC LIMIT 1",
      variables: <Variable<Object>>[
        Variable<String>('${purchase.id}:%'),
      ],
    ).getSingle();

    final reversedRefund = await CashReversalService(db).reverseReference(
      referenceType: 'purchase_refund',
      referenceId: supplierRefundReference.read<String>('reference_id'),
      reason: 'Supplier refund reversal',
      createdBy: 'Phase 6 Tester',
      createdByUserId: 'user-p6-test',
      deviceId: store.runtime.identity.deviceId,
    );
    expect(reversedRefund, 1);
    final afterRefundReversal = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
        )
        .getSingle();
    expect(
        (afterRefundReversal.data['current_balance'] as num).toDouble(), 980);
    final supplierAdvanceAfterRefundReversal = await db
        .customSelect(
          "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'supplier' AND account_id = 'supplier-p6-cancel'",
        )
        .getSingle();
    expect(
        (supplierAdvanceAfterRefundReversal.data['balance'] as num).toDouble(),
        20);
  });

  test('returns received purchase and reverses stock with return movement',
      () async {
    final store = await readySqliteStore(storeId: 'ST-PURRET01');
    await store.catalog.addOrUpdateProduct(product(stock: 0));
    await store.inventory.adjustStock(
        productId: 'p1',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 10,
        reason: 'test seed');
    final draft = await store.commerce.createPurchase(
      supplierId: 's1',
      supplierName: 'Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const [
        PurchaseItem(
            productId: 'p1', productName: 'Coffee', quantity: 5, unitCost: 8)
      ],
      receiveNow: true,
    );
    expect(store.catalog.products.single.stock, 15);

    await store.commerce.returnPurchase(draft.id, reason: 'damaged goods');

    expect(store.commerce.purchases.single.status, 'Returned');
    expect(store.commerce.purchases.single.isReturned, isTrue);
    expect(store.commerce.purchases.single.isCancelled, isTrue);
    expect(store.commerce.totalPurchasesAmount, 0);
    expect(store.catalog.products.single.stock, 10);
    final purchaseReturnMovement =
        await SqliteMigrationManager.database!.customSelect(
      "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND quantity < 0 AND reversal_of_movement_id <> '' AND deleted_at = ''",
      variables: <Variable<Object>>[Variable<String>(draft.id)],
    ).getSingle();
    expect(purchaseReturnMovement.read<int>('c'), greaterThan(0));
    expect(
        store.accounting.transactions
            .where((entry) => entry.type == 'purchaseReturn'),
        isNotEmpty);
  });

  test(
      'warehouse-aware purchases, adjustments, and counts stay in the selected warehouse',
      () async {
    final store = await readySqliteStore();
    await store.catalog.addOrUpdateProduct(product(id: 'p-phase4', stock: 0, cost: 5));
    final branchWarehouse = await store.inventory.createWarehouse(
      name: 'Warehouse B',
      code: 'WB',
    );

    final purchase = await store.commerce.createPurchase(
      supplierId: 's1',
      supplierName: 'Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: true,
      warehouseId: branchWarehouse.id,
      warehouseName: branchWarehouse.name,
      items: const [
        PurchaseItem(
          productId: 'p-phase4',
          productName: 'Coffee',
          quantity: 4,
          unitCost: 5,
        ),
      ],
    );

    expect(purchase.warehouseId, branchWarehouse.id);
    final purchaseRow = await SqliteMigrationManager.database!.customSelect(
      'SELECT warehouse_id AS warehouseId, warehouse_name AS warehouseName FROM purchases WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(purchase.id)],
    ).getSingle();
    expect(purchaseRow.read<String>('warehouseId'), branchWarehouse.id);
    expect(purchaseRow.read<String>('warehouseName'), branchWarehouse.name);
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-phase4',
        warehouseId: branchWarehouse.id,
        storeId: store.runtime.identity.storeId,
      ),
      4,
    );
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-phase4',
        warehouseId: Warehouse.defaultId,
        storeId: store.runtime.identity.storeId,
      ),
      0,
    );

    await store.inventory.adjustStock(
      productId: 'p-phase4',
      warehouseId: branchWarehouse.id,
      quantityDelta: -1,
      reason: 'branch correction',
    );
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-phase4',
        warehouseId: branchWarehouse.id,
        storeId: store.runtime.identity.storeId,
      ),
      3,
    );

    final session = await store.inventory.createInventoryCountSession(
      warehouseId: branchWarehouse.id,
      warehouseName: branchWarehouse.name,
    );
    expect(session.warehouseId, branchWarehouse.id);
    expect(session.lines.single.snapshotStock, 3);
    await store.inventory.countInventoryLine(
      sessionId: session.id,
      productId: 'p-phase4',
      countedQty: 6,
    );
    await store.inventory.approveInventoryCount(session.id);
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-phase4',
        warehouseId: branchWarehouse.id,
        storeId: store.runtime.identity.storeId,
      ),
      6,
    );
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-phase4',
        warehouseId: Warehouse.defaultId,
        storeId: store.runtime.identity.storeId,
      ),
      0,
    );
  });

  test('purchase insights preserve derived metrics and cache invalidation',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-PUR-INSIGHTS',
      branchId: 'BR-PUR-INSIGHTS',
      storeName: 'Purchase Insights Store',
    );
    await store.catalog.addOrUpdateProduct(
      product(id: 'p-purchase-insights', stock: 0, cost: 1),
    );

    await store.commerce.createPurchase(
      supplierId: 'supplier-insights-a',
      supplierName: 'Supplier A',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: false,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-purchase-insights',
          productName: 'Coffee',
          quantity: 2,
          unitCost: 3,
        ),
      ],
    );

    expect(store.commerce.lastPurchasePriceForProduct('p-purchase-insights'), 3);
    expect(store.commerce.averagePurchaseCostForProduct('p-purchase-insights'), 3);
    expect(
      store.commerce.purchasePriceHistoryForProduct('p-purchase-insights'),
      hasLength(1),
    );

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.commerce.createPurchase(
      supplierId: 'supplier-insights-b',
      supplierName: 'Supplier B',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: false,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-purchase-insights',
          productName: 'Coffee',
          quantity: 4,
          unitCost: 5,
        ),
      ],
    );

    final overview = store.commerce.purchasesOverview;
    expect(overview.totalCount, 2);
    expect(overview.totalPurchasesAmount, 26);
    expect(overview.monthlyTotal, 26);
    expect(overview.monthlyCount, 2);
    expect(overview.draftTotal, 26);
    expect(overview.draftCount, 2);
    expect(overview.pendingPurchaseCount, 2);
    expect(overview.receivedCount, 0);
    expect(overview.returnedCount, 0);
    expect(overview.cancelledCount, 0);
    expect(store.commerce.totalPurchasesAmount, 26);
    expect(store.commerce.pendingPurchaseCount, 2);

    final history = store.commerce.purchasePriceHistoryForProduct('p-purchase-insights');
    expect(history, hasLength(2));
    expect(history.map((row) => row.unitCost).toList(), <double>[5, 3]);
    expect(
      history.map((row) => row.supplierId).toList(),
      <String>['supplier-insights-b', 'supplier-insights-a'],
    );

    final comparison =
        store.commerce.supplierPriceComparisonForProduct('p-purchase-insights');
    expect(comparison, hasLength(2));
    expect(comparison.map((row) => row.unitCost).toList(), <double>[3, 5]);
    expect(
      comparison.map((row) => row.supplierId).toList(),
      <String>['supplier-insights-a', 'supplier-insights-b'],
    );

    expect(
      store.commerce.lastPurchasePriceFor(
        productId: 'p-purchase-insights',
        supplierId: 'supplier-insights-a',
      ),
      3,
    );
    expect(
      store.commerce.lastPurchasePriceFor(
        productId: 'p-purchase-insights',
        supplierId: 'supplier-insights-b',
      ),
      5,
    );
    expect(store.commerce.lastPurchasePriceForProduct('p-purchase-insights'), 5);
    expect(
      store.commerce.averagePurchaseCostForProduct('p-purchase-insights'),
      closeTo(26 / 6, 0.000001),
    );
    expect(
      store
          .commerce.lastPurchaseItemFor(
            productId: 'p-purchase-insights',
            supplierId: 'supplier-insights-a',
          )
          ?.unitCost,
      3,
    );
    expect(
      store.commerce.lastPurchaseItemForProduct('p-purchase-insights')?.unitCost,
      5,
    );
  });

  test('legacy purchase and inventory count default to main warehouse',
      () async {
    final store = await readySqliteStore();
    await store.catalog.addOrUpdateProduct(product(id: 'p-legacy-main', stock: 2));

    final purchase = await store.commerce.createPurchase(
      supplierId: 's1',
      supplierName: 'Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: false,
      items: const [
        PurchaseItem(
          productId: 'p-legacy-main',
          productName: 'Coffee',
          quantity: 1,
          unitCost: 5,
        ),
      ],
    );
    expect(purchase.warehouseId, Warehouse.defaultId);
    expect(purchase.warehouseName, Warehouse.defaultName);

    final count = await store.inventory.createInventoryCountSession();
    expect(count.warehouseId, Warehouse.defaultId);
    expect(count.warehouseName, Warehouse.defaultName);
  });

  test('purchase draft lifecycle posts stock and accounting only on receipt',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-PURCHASE-DRAFT-BOUNDARY',
      branchId: 'BR-PURCHASE-DRAFT-BOUNDARY',
    );
    await store.catalog.addOrUpdateProduct(
      product(id: 'p-purchase-draft-boundary', stock: 0, cost: 3),
    );
    final db = SqliteMigrationManager.database!;

    Future<int> rowCount(String sql, String referenceId) async {
      final row = await db.customSelect(
        sql,
        variables: <Variable<Object>>[Variable<String>(referenceId)],
      ).getSingle();
      return row.read<int>('c');
    }

    Future<void> expectNoPosting(
      Purchase purchase, {
      required double expectedStock,
    }) async {
      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-purchase-draft-boundary',
          warehouseId: purchase.warehouseId,
          storeId: store.runtime.identity.storeId,
        ),
        expectedStock,
      );
      expect(
        await rowCount(
          "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND deleted_at = ''",
          purchase.id,
        ),
        0,
      );
      expect(
        await rowCount(
          "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'purchase' AND reference_id = ? AND status = 'posted' AND deleted_at = ''",
          purchase.id,
        ),
        0,
      );
      expect(
        await rowCount(
          'SELECT COUNT(*) AS c FROM account_transactions WHERE reference_id = ?',
          purchase.id,
        ),
        0,
      );
    }

    final draft = await store.commerce.createPurchase(
      supplierId: 'supplier-draft-boundary',
      supplierName: 'Draft Boundary Supplier',
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      receiveNow: false,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-purchase-draft-boundary',
          productName: 'Draft Boundary Product',
          quantity: 4,
          unitCost: 3,
        ),
      ],
    );
    await expectNoPosting(draft, expectedStock: 0);

    final edited = await store.commerce.updatePurchaseDraft(
      purchaseId: draft.id,
      expectedVersion: draft.version,
      supplierId: draft.supplierId,
      supplierName: draft.supplierName,
      paymentStatus: 'credit',
      paymentMethod: draft.paymentMethod,
      warehouseId: draft.warehouseId,
      warehouseName: draft.warehouseName,
      items: draft.items,
    );
    await expectNoPosting(edited, expectedStock: 0);

    await store.commerce.receivePurchase(edited.id);
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-purchase-draft-boundary',
        warehouseId: edited.warehouseId,
        storeId: store.runtime.identity.storeId,
      ),
      4,
    );
    expect(
      await rowCount(
        "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'purchase' AND reference_id = ? AND status = 'posted' AND deleted_at = ''",
        edited.id,
      ),
      greaterThan(0),
    );

    final deletable = await store.commerce.createPurchase(
      supplierId: 'supplier-draft-boundary',
      supplierName: 'Draft Boundary Supplier',
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      receiveNow: false,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-purchase-draft-boundary',
          productName: 'Draft Boundary Product',
          quantity: 1,
          unitCost: 3,
        ),
      ],
    );
    await store.commerce.deleteDraftPurchase(deletable.id);
    final deletedPurchase = await db.customSelect(
      'SELECT deleted_at FROM purchases WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(deletable.id)],
    ).getSingle();
    expect(
      deletedPurchase.read<String>('deleted_at'),
      isNotEmpty,
    );
    await expectNoPosting(deletable, expectedStock: 4);
  });
}

void _registerAppStoreWorkflowGroup3() {
  group('AppStore sales, purchases, stock, and reports', () {
    _registerAppStoreWorkflowSalesPart1();
    _registerAppStoreWorkflowSalesPart2();
    _registerAppStoreWorkflowSalesPart3();
  });
}
