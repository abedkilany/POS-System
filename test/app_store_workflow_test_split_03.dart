part of 'app_store_workflow_test.dart';

void _registerAppStoreWorkflowSalesPart2() {
  test('sale cancel is blocked after a partial return', () async {
    final store = await readySqliteStore(
      storeId: 'ST-P1-CANCEL-GUARD',
      branchId: 'BR-P1-CANCEL-GUARD',
      storeName: 'Sale Cancel Guard Store',
    );
    await store.catalog.addOrUpdateProduct(product(
      id: 'p-p1-cancel-guard',
      code: 'P1-CANCEL-GUARD',
      name: 'Sale Cancel Guard Product',
      stock: 0,
      cost: 2,
    ));
    await store.commerce.createPurchase(
      supplierId: 'supplier-p1-cancel-guard',
      supplierName: 'Sale Cancel Guard Supplier',
      receiveNow: true,
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-p1-cancel-guard',
          productName: 'Sale Cancel Guard Product',
          quantity: 5,
          unitCost: 2,
        ),
      ],
    );
    final sale = await store.commerce.createSale(
      customerId: 'customer-p1-cancel-guard',
      customerName: 'Sale Cancel Guard Customer',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <SaleItem>[
        SaleItem(
          productId: 'p-p1-cancel-guard',
          productName: 'Sale Cancel Guard Product',
          unitPrice: 5,
          quantity: 3,
        ),
      ],
    );
    await store.commerce.returnSale(
      sale.id,
      returnedQuantities: const <String, double>{'p-p1-cancel-guard': 1},
    );
    await expectLater(store.commerce.cancelSale(sale.id), throwsStateError);
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-p1-cancel-guard',
        warehouseId: sale.warehouseId,
        storeId: store.runtime.identity.storeId,
      ),
      closeTo(3, 0.000001),
    );
  });

  test('zero-price sale return still reverses COGS journal atomically',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P1-FREE-RETURN',
      branchId: 'BR-P1-FREE-RETURN',
      storeName: 'Free Return Store',
    );
    await store.inventory.setInventoryCostingMethod(
      InventoryCostingMethod.fifo,
      reason: 'COGS-only sale return test',
    );
    await store.catalog.addOrUpdateProduct(product(
      id: 'p-p1-free-return',
      code: 'P1-FREE-RETURN',
      name: 'Free Return Product',
      stock: 0,
      cost: 3,
    ));
    await store.commerce.createPurchase(
      supplierId: 'supplier-p1-free-return',
      supplierName: 'Free Return Supplier',
      receiveNow: true,
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-p1-free-return',
          productName: 'Free Return Product',
          quantity: 1,
          unitCost: 3,
        ),
      ],
    );
    final sale = await store.commerce.createSale(
      customerId: 'customer-p1-free-return',
      customerName: 'Free Return Customer',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <SaleItem>[
        SaleItem(
          productId: 'p-p1-free-return',
          productName: 'Free Return Product',
          unitPrice: 0,
          quantity: 1,
        ),
      ],
    );
    final note = await store.commerce.returnSale(sale.id);
    expect(note.amount, closeTo(0, 0.000001));
    final db = SqliteMigrationManager.database!;
    final journal = await db.customSelect(
      '''
        SELECT id FROM journal_entries
        WHERE reference_type = 'sale_return'
          AND reference_id = ? AND status = 'posted' AND deleted_at = ''
        LIMIT 1
        ''',
      variables: <Variable<Object>>[Variable<String>(note.id)],
    ).getSingleOrNull();
    expect(journal, isNotNull);
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-p1-free-return',
        warehouseId: sale.warehouseId,
        storeId: store.runtime.identity.storeId,
      ),
      closeTo(1, 0.000001),
    );
  });

  test(
      'draft purchase receive rolls back stock, FIFO layer, document and journal when accounting fails',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P1-ATOMIC-RECEIVE',
      branchId: 'BR-P1-ATOMIC-RECEIVE',
      storeName: 'Atomic Receive Store',
    );
    await store.catalog.addOrUpdateProduct(product(
      id: 'p-atomic-receive',
      code: 'ATOMIC-RECEIVE',
      name: 'Atomic Receive Product',
      stock: 0,
      cost: 4,
    ));
    final draft = await store.commerce.createPurchase(
      supplierId: 'supplier-atomic-receive',
      supplierName: 'Atomic Supplier',
      receiveNow: false,
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-atomic-receive',
          productName: 'Atomic Receive Product',
          quantity: 5,
          unitCost: 4,
        ),
      ],
    );
    final db = SqliteMigrationManager.database!;
    final merchandiseAccount =
        await AccountingService.resolveAccountRole('inventory_merchandise');
    final merchandiseSnapshot =
        (await AccountingService.listAccounts(activeOnly: false))
            .firstWhere((account) => account.id == merchandiseAccount);
    Future<void> setMerchandisePostable(bool value) =>
        AccountingService.updateAccount(
          accountId: merchandiseSnapshot.id,
          code: merchandiseSnapshot.code,
          name: merchandiseSnapshot.name,
          type: merchandiseSnapshot.type,
          normalBalance: merchandiseSnapshot.normalBalance,
          subtype: merchandiseSnapshot.subtype,
          parentId: merchandiseSnapshot.parentId,
          currency: merchandiseSnapshot.currency,
          description: merchandiseSnapshot.description,
          isPostable: value,
        );

    await setMerchandisePostable(false);
    try {
      await expectLater(
        () async => store.commerce.receivePurchase(draft.id),
        throwsA(isA<StateError>()),
      );

      final purchaseRow = await db.customSelect(
        'SELECT status FROM purchases WHERE id = ?',
        variables: <Variable<Object>>[Variable<String>(draft.id)],
      ).getSingle();
      expect(purchaseRow.read<String>('status').toLowerCase(), 'draft');

      expect(
        await sqliteWarehouseQuantity(
          productId: 'p-atomic-receive',
          warehouseId: draft.warehouseId,
          storeId: store.runtime.identity.storeId,
        ),
        closeTo(0, 0.000001),
      );
      final layerCount = await db.customSelect(
        "SELECT COUNT(*) AS c FROM inventory_cost_layers WHERE purchase_id = ? AND deleted_at = ''",
        variables: <Variable<Object>>[Variable<String>(draft.id)],
      ).getSingle();
      expect(layerCount.read<int>('c'), 0);
      final movementCount = await db.customSelect(
        "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND deleted_at = ''",
        variables: <Variable<Object>>[Variable<String>(draft.id)],
      ).getSingle();
      expect(movementCount.read<int>('c'), 0);
      final journalCount = await db.customSelect(
        "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'purchase' AND reference_id = ?",
        variables: <Variable<Object>>[Variable<String>(draft.id)],
      ).getSingle();
      expect(journalCount.read<int>('c'), 0);
    } finally {
      await setMerchandisePostable(true);
    }
  });

  test('purchase return is blocked while its Unified Batch is consumed',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P1-BATCH-GUARD',
      branchId: 'BR-P1-BATCH-GUARD',
      storeName: 'Unified Batch Guard Store',
    );
    await store.catalog.addOrUpdateProduct(product(
      id: 'p-batch-guard',
      code: 'BATCH-GUARD',
      name: 'Batch Guard Product',
      stock: 0,
      cost: 3,
    ));
    final purchase = await store.commerce.createPurchase(
      supplierId: 'supplier-batch-guard',
      supplierName: 'Batch Guard Supplier',
      receiveNow: true,
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-batch-guard',
          productName: 'Batch Guard Product',
          quantity: 5,
          unitCost: 3,
        ),
      ],
    );
    final sale = await store.commerce.createSale(
      customerId: 'customer-batch-guard',
      customerName: 'Batch Guard Customer',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <SaleItem>[
        SaleItem(
          productId: 'p-batch-guard',
          productName: 'Batch Guard Product',
          unitPrice: 8,
          quantity: 2,
        ),
      ],
    );
    final db = SqliteMigrationManager.database!;
    final batch = await db.customSelect(
      "SELECT id FROM inventory_batches WHERE source_type = 'purchase' AND source_id = ? LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(purchase.id)],
    ).getSingle();
    final batchId = batch.read<String>('id');

    Future<double> qty() async {
      final row = await db.customSelect(
        'SELECT COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE batch_id = ?',
        variables: <Variable<Object>>[Variable<String>(batchId)],
      ).getSingle();
      return (row.data['qty'] as num? ?? 0).toDouble();
    }

    expect(await qty(), closeTo(3, 0.000001));
    await expectLater(
      () async => store.commerce.returnPurchase(purchase.id),
      throwsA(isA<StateError>()),
    );

    await store.commerce.returnSale(sale.id);
    expect(await qty(), closeTo(5, 0.000001));
    await store.commerce.returnPurchase(purchase.id);
    expect(await qty(), closeTo(0, 0.000001));
    final returnedStatus = await db.customSelect(
      'SELECT status FROM purchases WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(purchase.id)],
    ).getSingle();
    expect(returnedStatus.read<String>('status').toLowerCase(), 'returned');
  });

  test('sale cancel restores Unified Batch balance in SQLite immediately',
      () async {
    final store = await readySqliteStore(
      storeId: 'ST-P1-SALE-CANCEL',
      branchId: 'BR-P1-SALE-CANCEL',
      storeName: 'Sale Cancel Batch Store',
    );
    await store.catalog.addOrUpdateProduct(product(
      id: 'p-sale-cancel-batch',
      code: 'SALE-CANCEL-BATCH',
      name: 'Sale Cancel Batch Product',
      stock: 0,
      cost: 2,
    ));
    final purchase = await store.commerce.createPurchase(
      supplierId: 'supplier-sale-cancel-batch',
      supplierName: 'Sale Cancel Batch Supplier',
      receiveNow: true,
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'p-sale-cancel-batch',
          productName: 'Sale Cancel Batch Product',
          quantity: 5,
          unitCost: 2,
        ),
      ],
    );
    final sale = await store.commerce.createSale(
      customerId: 'customer-sale-cancel-batch',
      customerName: 'Sale Cancel Batch Customer',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <SaleItem>[
        SaleItem(
          productId: 'p-sale-cancel-batch',
          productName: 'Sale Cancel Batch Product',
          unitPrice: 7,
          quantity: 2,
        ),
      ],
    );
    final db = SqliteMigrationManager.database!;
    final batch = await db.customSelect(
      "SELECT id FROM inventory_batches WHERE source_type = 'purchase' AND source_id = ? LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(purchase.id)],
    ).getSingle();
    final batchId = batch.read<String>('id');
    Future<double> qty() async {
      final row = await db.customSelect(
        'SELECT COALESCE(SUM(quantity), 0) AS qty FROM inventory_batch_balances WHERE batch_id = ?',
        variables: <Variable<Object>>[Variable<String>(batchId)],
      ).getSingle();
      return (row.data['qty'] as num? ?? 0).toDouble();
    }

    expect(await qty(), closeTo(3, 0.000001));
    await store.commerce.cancelSale(sale.id);
    expect(await qty(), closeTo(5, 0.000001));
    final saleRow = await db.customSelect(
      'SELECT status FROM sales WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(sale.id)],
    ).getSingle();
    expect(saleRow.read<String>('status').toLowerCase(), 'cancelled');
  });

  test('warehouse-aware sales only use the selected warehouse', () async {
    final store = await readySqliteStore();
    await store.catalog.addOrUpdateProduct(product(id: 'p-wh', stock: 0, price: 10));
    final mainWarehouse = store.inventory.resolveWarehouseForSale();
    final branchWarehouse = await store.inventory.createWarehouse(
      name: 'Warehouse B',
      code: 'WB',
    );

    await store.inventory.adjustStock(
      productId: 'p-wh',
      warehouseId: mainWarehouse.id,
      quantityDelta: 2,
      reason: 'seed main warehouse',
    );
    await store.inventory.adjustStock(
      productId: 'p-wh',
      warehouseId: branchWarehouse.id,
      quantityDelta: 20,
      reason: 'seed branch warehouse',
    );

    await expectLater(
      store.commerce.createSale(
        customerName: 'Alice',
        customerId: 'c1',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        items: const [
          SaleItem(
            productId: 'p-wh',
            productName: 'Coffee',
            unitPrice: 10,
            quantity: 5,
          ),
        ],
        warehouseId: '',
      ),
      throwsA(isA<LocalizedDomainException>()),
    );

    final sale = await store.commerce.createSale(
      customerName: 'Alice',
      customerId: 'c1',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const [
        SaleItem(
          productId: 'p-wh',
          productName: 'Coffee',
          unitPrice: 10,
          quantity: 5,
        ),
      ],
      warehouseId: branchWarehouse.id,
    );

    expect(sale.warehouseId, branchWarehouse.id);
    expect(sale.warehouseName, branchWarehouse.name);
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-wh',
        warehouseId: mainWarehouse.id,
        storeId: store.runtime.identity.storeId,
      ),
      2,
    );
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-wh',
        warehouseId: branchWarehouse.id,
        storeId: store.runtime.identity.storeId,
      ),
      15,
    );
    expect(store.catalog.products.single.stock, 17);

    await store.commerce.cancelSale(sale.id);
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-wh',
        warehouseId: branchWarehouse.id,
        storeId: store.runtime.identity.storeId,
      ),
      20,
    );
  });

  test(
      'editing received purchase rebuilds frozen snapshot, journal and batch-derived cost',
      () async {
    final store = await readySqliteStore(storeId: 'ST-PUREDIT1');
    await store
        .catalog.addOrUpdateProduct(product(id: 'p-edit-cost', stock: 0, cost: 5));

    final received = await store.commerce.createPurchase(
      supplierId: 'supplier-edit',
      supplierName: 'Edit Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: true,
      items: const [
        PurchaseItem(
          productId: 'p-edit-cost',
          productName: 'Editable Product',
          quantity: 2,
          unitCost: 10,
        ),
      ],
    );
    expect(received.postedSnapshot, isNotNull);
    expect(received.postedSnapshot!.totals.grandTotal, closeTo(20, 0.0001));

    final edited = await store.commerce.updatePurchaseDraft(
      purchaseId: received.id,
      expectedVersion: received.version,
      supplierId: received.supplierId,
      supplierName: received.supplierName,
      warehouseId: received.warehouseId,
      warehouseName: received.warehouseName,
      items: const [
        PurchaseItem(
          productId: 'p-edit-cost',
          productName: 'Editable Product',
          quantity: 2,
          unitCost: 20,
        ),
      ],
    );

    expect(edited.version, received.version + 1);
    expect(edited.paymentStatus, 'credit');
    expect(edited.postedSnapshot, isNotNull);
    expect(edited.postedSnapshot!.documentId, edited.id);
    expect(edited.postedSnapshot!.lines.single.productId, 'p-edit-cost');
    expect(edited.postedSnapshot!.lines.single.unitPrice, closeTo(20, 0.0001));
    expect(edited.postedSnapshot!.totals.grandTotal, closeTo(40, 0.0001));
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-edit-cost',
        warehouseId: Warehouse.defaultId,
        storeId: store.runtime.identity.storeId,
      ),
      closeTo(2, 0.0001),
    );
    expect(
      store.catalog.productCostFor('p-edit-cost').averageCost,
      closeTo(20, 0.0001),
    );
    expect(
      store.catalog.productCostFor('p-edit-cost').lastCost,
      closeTo(20, 0.0001),
    );

    final db = SqliteMigrationManager.database!;
    final journal = await db.customSelect(
      '''
        SELECT COUNT(*) AS count
        FROM journal_entries je
        WHERE je.reference_type = 'purchase'
          AND je.reference_id = ?
          AND je.status = 'posted'
          AND je.deleted_at = ''
          AND NOT EXISTS (
            SELECT 1 FROM journal_entries reversal
            WHERE reversal.reversed_entry_id = je.id
              AND reversal.status = 'posted'
              AND reversal.deleted_at = ''
          )
        ''',
      variables: <Variable<Object>>[
        Variable<String>('${edited.id}:purchase_edit:v${edited.version}'),
      ],
    ).getSingle();
    expect((journal.data['count'] as num? ?? 0).toInt(), 1);
  });

  test(
      'editing received purchase can replace a product at the same total without reusing the old snapshot or cost',
      () async {
    final store = await readySqliteStore(storeId: 'ST-PUREDIT2');
    await store.catalog.addOrUpdateProduct(
        product(id: 'p-edit-old', code: 'P-EDIT-OLD', stock: 0, cost: 4));
    await store.catalog.addOrUpdateProduct(
        product(id: 'p-edit-new', code: 'P-EDIT-NEW', stock: 0, cost: 7));

    final received = await store.commerce.createPurchase(
      supplierId: 'supplier-edit-same-total',
      supplierName: 'Same Total Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: true,
      items: const [
        PurchaseItem(
          productId: 'p-edit-old',
          productName: 'Old Product',
          quantity: 1,
          unitCost: 20,
        ),
      ],
    );

    final edited = await store.commerce.updatePurchaseDraft(
      purchaseId: received.id,
      expectedVersion: received.version,
      supplierId: received.supplierId,
      supplierName: received.supplierName,
      warehouseId: received.warehouseId,
      warehouseName: received.warehouseName,
      items: const [
        PurchaseItem(
          productId: 'p-edit-new',
          productName: 'New Product',
          quantity: 2,
          unitCost: 10,
        ),
      ],
    );

    expect(edited.subtotal, closeTo(received.subtotal, 0.0001));
    expect(edited.postedSnapshot, isNotNull);
    expect(edited.postedSnapshot!.lines.single.productId, 'p-edit-new');
    expect(edited.postedSnapshot!.lines.single.quantity, closeTo(2, 0.0001));
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-edit-old',
        warehouseId: Warehouse.defaultId,
        storeId: store.runtime.identity.storeId,
      ),
      closeTo(0, 0.0001),
    );
    expect(
      await sqliteWarehouseQuantity(
        productId: 'p-edit-new',
        warehouseId: Warehouse.defaultId,
        storeId: store.runtime.identity.storeId,
      ),
      closeTo(2, 0.0001),
    );
    expect(store.catalog.productCostFor('p-edit-old').averageCost, closeTo(0, 0.0001));
    expect(store.catalog.productCostFor('p-edit-old').lastCost, closeTo(0, 0.0001));
    expect(store.catalog.productCostFor('p-edit-new').averageCost, closeTo(10, 0.0001));
    expect(store.catalog.productCostFor('p-edit-new').lastCost, closeTo(10, 0.0001));
  });

  test(
      'editing an older received purchase does not overwrite lastCost from a newer purchase',
      () async {
    final store = await readySqliteStore(storeId: 'ST-PUREDIT3');
    await store
        .catalog.addOrUpdateProduct(product(id: 'p-edit-last-cost', stock: 0, cost: 3));

    final older = await store.commerce.createPurchase(
      supplierId: 'supplier-old-cost',
      supplierName: 'Older Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: true,
      items: const [
        PurchaseItem(
          productId: 'p-edit-last-cost',
          productName: 'Last Cost Product',
          quantity: 1,
          unitCost: 5,
        ),
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.commerce.createPurchase(
      supplierId: 'supplier-new-cost',
      supplierName: 'Newer Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      receiveNow: true,
      items: const [
        PurchaseItem(
          productId: 'p-edit-last-cost',
          productName: 'Last Cost Product',
          quantity: 1,
          unitCost: 9,
        ),
      ],
    );
    expect(
        store.catalog.productCostFor('p-edit-last-cost').lastCost, closeTo(9, 0.0001));

    await store.commerce.updatePurchaseDraft(
      purchaseId: older.id,
      expectedVersion: older.version,
      supplierId: older.supplierId,
      supplierName: older.supplierName,
      warehouseId: older.warehouseId,
      warehouseName: older.warehouseName,
      items: const [
        PurchaseItem(
          productId: 'p-edit-last-cost',
          productName: 'Last Cost Product',
          quantity: 1,
          unitCost: 7,
        ),
      ],
    );

    expect(
      store.catalog.productCostFor('p-edit-last-cost').averageCost,
      closeTo(8, 0.0001),
    );
    expect(
        store.catalog.productCostFor('p-edit-last-cost').lastCost, closeTo(9, 0.0001));
  });
}
