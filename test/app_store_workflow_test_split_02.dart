part of 'app_store_workflow_test.dart';

void _registerAppStoreWorkflowSalesPart1() {
  test(
      'creates sales, rejects insufficient stock without auto correction, restores stock on cancel, and tracks profit',
      () async {
    final correctionStore = await readySqliteStore(storeId: 'ST-SALECORR');
    await correctionStore.catalog.addOrUpdateProduct(
        product(id: 'p-sale-correction', stock: 0, price: 10, cost: 4));
    await correctionStore.inventory.adjustStock(
        productId: 'p-sale-correction',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 5,
        reason: 'test seed');

    await expectLater(
        correctionStore.commerce
            .createSale(customerName: 'Bob', items: const []),
        throwsArgumentError);
    await expectLater(
      correctionStore.commerce.createSale(
        customerId: 'customer-bob-correction',
        customerName: 'Bob',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const [
          SaleItem(
              productId: 'p-sale-correction',
              productName: 'Coffee',
              unitPrice: 10,
              quantity: 6)
        ],
      ),
      throwsA(isA<LocalizedDomainException>()),
    );
    expect(
        correctionStore.inventory.stockMovements
            .where((m) => m.type == 'auto_correction'),
        isEmpty);

    final store = await readySqliteStore(storeId: 'ST-SALEFLOW');
    await store.catalog.addOrUpdateProduct(
        product(id: 'p-sale-flow', stock: 0, price: 10, cost: 4));
    await store.inventory.adjustStock(
        productId: 'p-sale-flow',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 5,
        reason: 'test seed');

    final sale = await store.commerce.createSale(
      customerId: 'customer-bob-flow',
      customerName: 'Bob',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const [
        SaleItem(
            productId: 'p-sale-flow',
            productName: 'Coffee',
            unitPrice: 10,
            quantity: 2)
      ],
    );

    expect(sale.customerName, 'Bob');
    expect(sale.warehouseId, Warehouse.defaultId);
    expect(sale.warehouseName, Warehouse.defaultName);
    expect(sale.total, 20);
    expect(sale.grossProfit, 12);
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-sale-flow',
        warehouseId: Warehouse.defaultId,
        storeId: store.runtime.identity.storeId,
      ),
      3,
    );
    expect(
      store.inventory.stockMovements.where(
        (m) => m.referenceId == sale.id && m.quantity < 0,
      ),
      isNotEmpty,
    );
    expect(store.commerce.totalSalesAmount, 20);
    expect(store.commerce.estimateProfit(), 12);

    await store.commerce.cancelSale(sale.id);
    final cancelledSale = await SqliteMigrationManager.database!.customSelect(
      'SELECT status FROM sales WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(sale.id)],
    ).getSingle();
    expect(cancelledSale.read<String>('status'), 'Cancelled');
    expect(store.commerce.sales.single.paidAmount, 0);
    expect(store.commerce.sales.single.cashReceivedAmount, 0);
    expect(store.commerce.totalSalesAmount, 0);
    expect(store.catalog.products.single.stock, 5);

    await store.commerce.cancelSale(sale.id);
    expect(store.commerce.sales.length, 1);
  });

  test('phase 6 cancellation never auto-refunds cash; refund is explicit',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P6-CANCEL',
      branchId: 'BR-P6-CANCEL',
    );
    final drawerId = await seedOpenCashDrawerForStore(store);
    await store.catalog
        .addOrUpdateProduct(product(id: 'p-p6-cancel', stock: 0));
    final warehouse = store.inventory.resolveWarehouseForSale();
    await StockTransactionService(
      SqliteMigrationManager.database!,
      defaultStoreId: store.runtime.identity.storeId,
      defaultBranchId: store.runtime.identity.branchId,
    ).applyDelta(
      storeId: store.runtime.identity.storeId,
      warehouseId: warehouse.id,
      productId: 'p-p6-cancel',
      delta: 5,
      branchId: store.runtime.identity.branchId,
    );

    final sale = await store.commerce.createSale(
      customerName: 'Phase 6 Customer',
      customerId: 'customer-p6-cancel',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <SaleItem>[
        SaleItem(
          productId: 'p-p6-cancel',
          productName: 'Coffee',
          unitPrice: 10,
          quantity: 2,
        ),
      ],
      warehouseId: warehouse.id,
    );
    await store.commerce.settleSalePayment(
      saleId: sale.id,
      amount: 20,
      paymentMethod: 'Cash',
      idempotencyKey: 'p6-cancel-payment',
    );

    final db = SqliteMigrationManager.database!;
    final beforeCancel = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
        )
        .getSingle();
    expect((beforeCancel.data['current_balance'] as num).toDouble(), 1020);

    await store.commerce.cancelSale(sale.id);

    final autoRefunds = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE reference_type = 'sale_refund' AND deleted_at = ''",
        )
        .getSingle();
    expect(autoRefunds.read<int>('c'), 0);
    expect(
      await PaymentVoucherService(db).refundableCashForSale(sale.id),
      20,
    );
    final afterCancel = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
        )
        .getSingle();
    expect((afterCancel.data['current_balance'] as num).toDouble(), 1020);
    final customerCreditAfterCancel = await db
        .customSelect(
          "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'customer' AND account_id = 'customer-p6-cancel'",
        )
        .getSingle();
    expect((customerCreditAfterCancel.data['balance'] as num).toDouble(), -20);

    final refunded = await store.commerce.refundSaleCash(
      saleId: sale.id,
      amount: 20,
      idempotencyKey: 'p6-explicit-refund',
    );
    expect(refunded, 20);
    final afterRefund = await db
        .customSelect(
          "SELECT current_balance FROM cash_locations WHERE id = '$drawerId'",
        )
        .getSingle();
    expect((afterRefund.data['current_balance'] as num).toDouble(), 1000);
    final customerBalanceAfterRefund = await db
        .customSelect(
          "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'customer' AND account_id = 'customer-p6-cancel'",
        )
        .getSingle();
    expect((customerBalanceAfterRefund.data['balance'] as num).toDouble(), 0);

    final reversedRefund = await CashReversalService(db).reverseReference(
      referenceType: 'sale_refund',
      referenceId: '${sale.id}:p6-explicit-refund',
      reason: 'Customer kept the cash refund',
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
        (afterRefundReversal.data['current_balance'] as num).toDouble(), 1020);
    final customerCreditAfterRefundReversal = await db
        .customSelect(
          "SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM account_transactions WHERE deleted_at = '' AND account_type = 'customer' AND account_id = 'customer-p6-cancel'",
        )
        .getSingle();
    expect(
        (customerCreditAfterRefundReversal.data['balance'] as num).toDouble(),
        -20);
  });

  test('returns a sale, restores stock, and records a sale return movement',
      () async {
    final store = await readySqliteStore(storeId: 'ST-SALERET1');
    await store.catalog
        .addOrUpdateProduct(product(stock: 0, price: 10, cost: 4));
    await store.inventory.adjustStock(
        productId: 'p1',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 5,
        reason: 'test seed');

    final sale = await store.commerce.createSale(
      customerId: 'customer-bob-return-one',
      customerName: 'Bob',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const [
        SaleItem(
            productId: 'p1', productName: 'Coffee', unitPrice: 10, quantity: 2)
      ],
    );

    expect(store.catalog.products.single.stock, 3);
    await store.commerce.returnSale(sale.id);

    expect(store.commerce.sales.single.status, 'Returned');
    expect(store.commerce.sales.single.isCancelled, isTrue);
    expect(store.commerce.sales.single.paidAmount, 0);
    expect(store.commerce.sales.single.cashReceivedAmount, 0);
    expect(store.commerce.totalSalesAmount, 0);
    expect(store.catalog.products.single.stock, 5);
  });

  test('edits a sale return after rebuilding stock and accounting effects',
      () async {
    final store = await readySqliteStore(storeId: 'ST-SALERET-EDIT');
    await store.catalog
        .addOrUpdateProduct(product(stock: 0, price: 10, cost: 4));
    await store.inventory.adjustStock(
        productId: 'p1',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 5,
        reason: 'test seed');

    final sale = await store.commerce.createSale(
      customerId: 'customer-sale-return-edit',
      customerName: 'Return Edit Customer',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const [
        SaleItem(
          productId: 'p1',
          productName: 'Coffee',
          unitPrice: 10,
          quantity: 2,
        ),
      ],
    );
    await store.commerce.returnSale(sale.id);
    final note = store.commerce.creditNotes
        .singleWhere((item) => item.originalSaleId == sale.id);

    final edited = await store.commerce.editSaleReturn(
      creditNoteId: note.id,
      expectedVersion: note.version,
      returnedQuantities: const <String, double>{'p1': 1},
    );

    expect(edited.items.single.quantity, 1);
    expect(edited.version, 2);
    expect(store.catalog.products.single.stock, 4);
    expect(store.commerce.sales.single.status, 'Partially Returned');
  });

  test(
      'partial sale returns are cumulative and cannot return the same units twice',
      () async {
    final store = await readySqliteStore(storeId: 'ST-SALERET2');
    await store.catalog
        .addOrUpdateProduct(product(stock: 0, price: 10, cost: 4));
    await store.inventory.adjustStock(
        productId: 'p1',
        warehouseId: Warehouse.defaultId,
        quantityDelta: 20,
        reason: 'test seed');

    final sale = await store.commerce.createSale(
      customerId: 'customer-partial-return',
      customerName: 'Partial Return Customer',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <SaleItem>[
        SaleItem(
          productId: 'p1',
          productName: 'Coffee',
          unitPrice: 10,
          quantity: 10,
        ),
      ],
    );

    final first = await store.commerce.returnSale(
      sale.id,
      returnedQuantities: const <String, double>{'p1': 4},
    );
    expect(first.items.single.quantity, 4);
    expect(store.commerce.sales.single.status, 'Partially Returned');
    expect(store.commerce.sales.single.items.single.quantity, 10);
    expect(store.catalog.products.single.stock, 14);

    final second = await store.commerce.returnSale(
      sale.id,
      returnedQuantities: const <String, double>{'p1': 4},
    );
    expect(second.items.single.quantity, 4);
    expect(store.commerce.sales.single.status, 'Partially Returned');
    expect(store.commerce.sales.single.items.single.quantity, 10);
    expect(store.catalog.products.single.stock, 18);
    final partialReturnJournals =
        await SqliteMigrationManager.database!.customSelect(
      "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'sale_return' AND reference_no = ? AND status = 'posted'",
      variables: <Variable<Object>>[
        Variable<String>(sale.invoiceNo),
      ],
    ).getSingle();
    expect(partialReturnJournals.read<int>('c'), 2);

    await expectLater(
      store.commerce.returnSale(
        sale.id,
        returnedQuantities: const <String, double>{'p1': 3},
      ),
      throwsArgumentError,
    );
    expect(store.catalog.products.single.stock, 18);

    final finalReturn = await store.commerce.returnSale(
      sale.id,
      returnedQuantities: const <String, double>{'p1': 2},
    );
    expect(finalReturn.items.single.quantity, 2);
    expect(store.commerce.sales.single.status, 'Returned');
    expect(store.commerce.sales.single.items.single.quantity, 10);
    expect(store.catalog.products.single.stock, 20);
    final allReturnJournals =
        await SqliteMigrationManager.database!.customSelect(
      "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'sale_return' AND reference_no = ? AND status = 'posted'",
      variables: <Variable<Object>>[
        Variable<String>(sale.invoiceNo),
      ],
    ).getSingle();
    expect(allReturnJournals.read<int>('c'), 3);

    // Regression: the final partial slice must credit only its own value.
    // A cumulative full-return state must not credit the original invoice
    // total again in the customer subledger.
    await store.accounting.refreshFromSqlite();
    expect(
      store.accounting.accountBalance('customer', 'customer-partial-return'),
      closeTo(0, 0.0001),
    );
    final returnLedger = await SqliteMigrationManager.database!
        .customSelect(
          "SELECT COUNT(*) AS c, COALESCE(SUM(credit), 0) AS credits FROM account_transactions WHERE deleted_at = '' AND account_type = 'customer' AND account_id = 'customer-partial-return' AND transaction_type = 'saleReturn'",
        )
        .getSingle();
    expect(returnLedger.read<int>('c'), 3);
    expect(returnLedger.read<double>('credits'), closeTo(100, 0.0001));
  });

  test(
      'partial sale returns preserve FEFO batches and actual batch costs by returned slice',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P6-RETURN',
      branchId: 'BR-P6-RETURN',
      storeName: 'Phase 6 Return Store',
    );
    final tracked = Product(
      id: 'p-p6-batch-return',
      name: 'Tracked Product',
      code: 'P6-BATCH',
      price: 10,
      cost: 1,
      stock: 0,
      category: 'Test',
      expiryTrackingEnabled: true,
      expiryEntryRequired: true,
    );
    await store.catalog.addOrUpdateProduct(tracked);
    final warehouse = store.inventory.resolveWarehouseForSale();

    final firstPurchase = await store.commerce.createPurchase(
      supplierId: 'sup-p6-1',
      supplierName: 'Supplier 1',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-p6-batch-return',
          productName: 'Tracked Product',
          quantity: 4,
          unitCost: 1,
        ),
      ],
      receiveNow: false,
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
    );
    await store.commerce.receivePurchase(
      firstPurchase.id,
      batchAllocationsByLine: <int, List<BatchAllocation>>{
        0: <BatchAllocation>[
          BatchAllocation(
            batchId: 'requested-early-p6',
            quantity: 4,
            expirationDate:
                DateTime.now().toUtc().add(const Duration(days: 365)),
          ),
        ],
      },
    );

    final secondPurchase = await store.commerce.createPurchase(
      supplierId: 'sup-p6-2',
      supplierName: 'Supplier 2',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-p6-batch-return',
          productName: 'Tracked Product',
          quantity: 6,
          unitCost: 2,
        ),
      ],
      receiveNow: false,
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
    );
    await store.commerce.receivePurchase(
      secondPurchase.id,
      batchAllocationsByLine: <int, List<BatchAllocation>>{
        0: <BatchAllocation>[
          BatchAllocation(
            batchId: 'requested-late-p6',
            quantity: 6,
            expirationDate:
                DateTime.now().toUtc().add(const Duration(days: 730)),
          ),
        ],
      },
    );

    final db = SqliteMigrationManager.database!;
    Future<String> batchIdForPurchase(String purchaseId) async {
      final row = await db.customSelect(
        "SELECT id FROM inventory_batches WHERE source_type = 'purchase' AND source_id = ? ORDER BY received_at, id LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(purchaseId)],
      ).getSingle();
      return row.read<String>('id');
    }

    Future<double> batchQuantity(String batchId) async {
      final row = await db.customSelect(
        'SELECT COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE batch_id = ?',
        variables: <Variable<Object>>[Variable<String>(batchId)],
      ).getSingle();
      return (row.data['qty'] as num? ?? 0).toDouble();
    }

    final earlyBatchId = await batchIdForPurchase(firstPurchase.id);
    final lateBatchId = await batchIdForPurchase(secondPurchase.id);

    final sale = await store.commerce.createSale(
      customerId: 'cust-p6-return',
      customerName: 'Return Customer',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      items: const <SaleItem>[
        SaleItem(
          productId: 'p-p6-batch-return',
          productName: 'Tracked Product',
          unitPrice: 10,
          quantity: 7,
        ),
      ],
    );
    expect(sale.items.single.batchAllocations, hasLength(2));
    expect(sale.items.single.batchAllocations[0].batchId, earlyBatchId);
    expect(sale.items.single.batchAllocations[0].quantity, 4);
    expect(sale.items.single.batchAllocations[0].unitCost, 1);
    expect(sale.items.single.batchAllocations[1].batchId, lateBatchId);
    expect(sale.items.single.batchAllocations[1].quantity, 3);
    expect(sale.items.single.batchAllocations[1].unitCost, 2);
    expect(await batchQuantity(earlyBatchId), closeTo(0, 0.000001));
    expect(await batchQuantity(lateBatchId), closeTo(3, 0.000001));

    final firstReturn = await store.commerce.returnSale(
      sale.id,
      returnedQuantities: const <String, double>{'p-p6-batch-return': 2},
    );
    expect(firstReturn.items.single.batchAllocations, hasLength(1));
    expect(
        firstReturn.items.single.batchAllocations.single.batchId, earlyBatchId);
    expect(firstReturn.items.single.batchAllocations.single.quantity, 2);
    expect(firstReturn.items.single.batchAllocations.single.unitCost, 1);
    expect(await batchQuantity(earlyBatchId), closeTo(2, 0.000001));
    expect(await batchQuantity(lateBatchId), closeTo(3, 0.000001));

    final secondReturn = await store.commerce.returnSale(
      sale.id,
      returnedQuantities: const <String, double>{'p-p6-batch-return': 3},
    );
    expect(secondReturn.items.single.batchAllocations, hasLength(2));
    expect(secondReturn.items.single.batchAllocations[0].batchId, earlyBatchId);
    expect(secondReturn.items.single.batchAllocations[0].quantity, 2);
    expect(secondReturn.items.single.batchAllocations[0].unitCost, 1);
    expect(secondReturn.items.single.batchAllocations[1].batchId, lateBatchId);
    expect(secondReturn.items.single.batchAllocations[1].quantity, 1);
    expect(secondReturn.items.single.batchAllocations[1].unitCost, 2);
    expect(await batchQuantity(earlyBatchId), closeTo(4, 0.000001));
    expect(await batchQuantity(lateBatchId), closeTo(4, 0.000001));
  });

  test('purchase return reverses every received batch atomically', () async {
    final store = await readySqliteStore(
      storeId: 'ST-P1-BATCH-RETURN',
      branchId: 'BR-P1-BATCH-RETURN',
      storeName: 'Atomic Batch Return Store',
    );
    final tracked = Product(
      id: 'p-p1-batch-return',
      name: 'Atomic Batch Product',
      code: 'P1-BATCH-RETURN',
      price: 10,
      cost: 2,
      stock: 0,
      category: 'Test',
      expiryTrackingEnabled: true,
      expiryEntryRequired: true,
    );
    await store.catalog.addOrUpdateProduct(tracked);
    final warehouse = store.inventory.resolveWarehouseForPurchase();
    final draft = await store.commerce.createPurchase(
      supplierId: 'supplier-p1-batch-return',
      supplierName: 'Atomic Batch Supplier',
      receiveNow: false,
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-p1-batch-return',
          productName: 'Atomic Batch Product',
          quantity: 2,
          unitCost: 2,
        ),
        PurchaseItem(
          productId: 'p-p1-batch-return',
          productName: 'Atomic Batch Product',
          quantity: 3,
          unitCost: 2,
        ),
      ],
    );
    await store.commerce.receivePurchase(
      draft.id,
      batchAllocationsByLine: <int, List<BatchAllocation>>{
        0: <BatchAllocation>[
          BatchAllocation(
            batchId: 'requested-p1-a',
            quantity: 2,
            expirationDate:
                DateTime.now().toUtc().add(const Duration(days: 365)),
          ),
        ],
        1: <BatchAllocation>[
          BatchAllocation(
            batchId: 'requested-p1-b',
            quantity: 3,
            expirationDate:
                DateTime.now().toUtc().add(const Duration(days: 730)),
          ),
        ],
      },
    );

    final db = SqliteMigrationManager.database!;
    final batchRows = await db.customSelect(
      "SELECT id FROM inventory_batches WHERE source_type = 'purchase' AND source_id = ? ORDER BY expiration_date, id",
      variables: <Variable<Object>>[Variable<String>(draft.id)],
    ).get();
    expect(batchRows, hasLength(2));
    final batchIds = batchRows.map((row) => row.read<String>('id')).toList();
    expect(
      await sqliteWarehouseQuantity(
        productId: tracked.id,
        warehouseId: warehouse.id,
        storeId: store.runtime.identity.storeId,
      ),
      closeTo(5, 0.000001),
    );

    await store.commerce.returnPurchase(draft.id);

    expect(
      await sqliteWarehouseQuantity(
        productId: tracked.id,
        warehouseId: warehouse.id,
        storeId: store.runtime.identity.storeId,
      ),
      closeTo(0, 0.000001),
    );
    for (final batchId in batchIds) {
      final row = await db.customSelect(
        'SELECT COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE batch_id = ?',
        variables: <Variable<Object>>[Variable<String>(batchId)],
      ).getSingle();
      expect((row.data['qty'] as num? ?? 0).toDouble(), closeTo(0, 0.000001));
    }
    final purchaseRow = await db.customSelect(
      'SELECT status FROM purchases WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(draft.id)],
    ).getSingle();
    expect(purchaseRow.read<String>('status').toLowerCase(), 'returned');
  });
}
