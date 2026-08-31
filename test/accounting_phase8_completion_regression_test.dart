import 'helpers/app_store_source.dart';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/models/manufacturing.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/supplier.dart';

import 'phase5_manufacturing_transfer_test.dart' as support;

void main() {
  test('purchase and sale route inventory through semantic product classes',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'raw-routing',
      code: 'RAW-ROUTE',
      stock: 0,
      cost: 3,
    ));
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'fg-routing',
      code: 'FG-ROUTE',
      stock: 0,
      cost: 0,
    ));
    final rawWarehouse =
        await store.createWarehouse(name: 'Raw routing', code: 'RR');
    final finishedWarehouse =
        await store.createWarehouse(name: 'Finished routing', code: 'FR');
    final bom = await store.createBillOfMaterials(
      name: 'Routing BOM',
      outputProductId: 'fg-routing',
      outputQuantity: 1,
      components: const <BillOfMaterialsLine>[
        BillOfMaterialsLine(
          productId: 'raw-routing',
          productName: 'Raw routing',
          quantity: 2,
        ),
      ],
    );
    await store.addOrUpdateSupplier(Supplier(
      id: 'supplier-routing',
      name: 'Routing Supplier',
      phone: '',
      address: '',
      notes: '',
    ));
    await store.addOrUpdateCustomer(Customer(
      id: 'customer-routing',
      name: 'Routing Customer',
      phone: '',
      address: '',
    ));
    final purchase = await store.createPurchase(
      supplierId: 'supplier-routing',
      supplierName: 'Routing Supplier',
      receiveNow: true,
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      warehouseId: rawWarehouse.id,
      warehouseName: rawWarehouse.name,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'raw-routing',
          productName: 'Raw routing',
          quantity: 4,
          unitCost: 3,
        ),
      ],
    );
    final db = SqliteMigrationManager.database!;
    final rawAccount =
        await AccountingService.resolveAccountRole('inventory_raw');
    final generalAccount =
        await AccountingService.resolveAccountRole('inventory_asset');
    final purchaseLines = await db.customSelect('''
      SELECT jl.account_id, SUM(jl.debit) AS debit
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      WHERE je.reference_type = 'purchase' AND je.reference_id = ?
      GROUP BY jl.account_id
    ''', variables: <Variable<Object>>[
      Variable<String>(purchase.id),
    ]).get();
    double debitFor(String accountId) => purchaseLines
        .where((row) => row.data['account_id'] == accountId)
        .fold<double>(
            0, (sum, row) => sum + (row.data['debit'] as num? ?? 0).toDouble());
    expect(debitFor(rawAccount), closeTo(12, 0.0001));
    expect(debitFor(generalAccount), closeTo(0, 0.0001));

    final order = await store.completeManufacturingOrder(
      bomId: bom.id,
      quantity: 1,
      rawMaterialsWarehouseId: rawWarehouse.id,
      finishedGoodsWarehouseId: finishedWarehouse.id,
    );
    final costs = await BusinessSqliteStore.readProductCosts(db);
    final outputCost =
        costs.firstWhere((item) => item.productId == 'fg-routing');
    expect(outputCost.averageCost, closeTo(order.actualUnitCost, 0.0001));

    final sale = await store.createSale(
      customerName: 'Routing Customer',
      customerId: 'customer-routing',
      warehouseId: finishedWarehouse.id,
      warehouseName: finishedWarehouse.name,
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      items: const <SaleItem>[
        SaleItem(
          productId: 'fg-routing',
          productName: 'Finished routing',
          unitPrice: 10,
          quantity: 1,
        ),
      ],
    );
    final finishedAccount =
        await AccountingService.resolveAccountRole('inventory_finished');
    final saleLines = await db.customSelect('''
      SELECT jl.account_id, SUM(jl.credit) AS credit
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      WHERE je.reference_type = 'sale' AND je.reference_id = ?
      GROUP BY jl.account_id
    ''', variables: <Variable<Object>>[
      Variable<String>(sale.id),
    ]).get();
    double creditFor(String accountId) => saleLines
        .where((row) => row.data['account_id'] == accountId)
        .fold<double>(0,
            (sum, row) => sum + (row.data['credit'] as num? ?? 0).toDouble());
    expect(creditFor(finishedAccount), closeTo(order.actualUnitCost, 0.0001));
    expect(creditFor(generalAccount), closeTo(0, 0.0001));
  });

  test('inventory valuation uses Unified Batch carrying value instead of product cost cache',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'batch-valuation-source',
      code: 'BATCH-VAL',
      stock: 0,
      cost: 2,
    ));
    final warehouse =
        await store.createWarehouse(name: 'Batch valuation', code: 'BV');
    await store.addOrUpdateSupplier(Supplier(
      id: 'supplier-batch-valuation',
      name: 'Batch Valuation Supplier',
      phone: '',
      address: '',
      notes: '',
    ));
    await store.addOrUpdateCustomer(Customer(
      id: 'customer-batch-valuation',
      name: 'Batch Valuation Customer',
      phone: '',
      address: '',
    ));
    await store.createPurchase(
      supplierId: 'supplier-batch-valuation',
      supplierName: 'Batch Valuation Supplier',
      receiveNow: true,
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'batch-valuation-source',
          productName: 'Phase5 Product',
          quantity: 4,
          unitCost: 2,
        ),
      ],
    );
    await store.createPurchase(
      supplierId: 'supplier-batch-valuation',
      supplierName: 'Batch Valuation Supplier',
      receiveNow: true,
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'batch-valuation-source',
          productName: 'Phase5 Product',
          quantity: 4,
          unitCost: 5,
        ),
      ],
    );
    await store.createSale(
      customerName: 'Batch Valuation Customer',
      customerId: 'customer-batch-valuation',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      items: const <SaleItem>[
        SaleItem(
          productId: 'batch-valuation-source',
          productName: 'Phase5 Product',
          unitPrice: 9,
          quantity: 6,
        ),
      ],
    );

    final db = SqliteMigrationManager.database!;
    await db.customInsert(
      '''
      INSERT INTO settings (key, value, updated_at)
      VALUES ('inventory_costing_method_v1', 'batch', ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value, updated_at = excluded.updated_at
      ''',
      variables: <Variable<Object>>[
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
    final productCosts = await BusinessSqliteStore.readProductCosts(db);
    final cachedCost = productCosts
        .firstWhere((item) => item.productId == 'batch-valuation-source');
    expect(cachedCost.averageCost, closeTo(3.5, 0.0001));

    final report = await AccountingService.inventoryValuationReport();
    final row = report.firstWhere((item) =>
        item.productId == 'batch-valuation-source' &&
        item.warehouseId == warehouse.id);
    expect(row.quantity, closeTo(2, 0.0001));
    expect(row.unitCost, closeTo(5, 0.0001));
    expect(row.totalValue, closeTo(10, 0.0001));
  });

  test('BOM create update and delete reclassify existing Unified Batch inventory',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'bom-reclass-a',
      code: 'BOM-RA',
      stock: 0,
      cost: 3,
    ));
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'bom-reclass-b',
      code: 'BOM-RB',
      stock: 0,
      cost: 5,
    ));
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'bom-reclass-output',
      code: 'BOM-RO',
      stock: 0,
      cost: 0,
    ));
    final warehouse =
        await store.createWarehouse(name: 'BOM reclass', code: 'BR');
    await store.addOrUpdateSupplier(Supplier(
      id: 'supplier-bom-reclass',
      name: 'BOM Reclass Supplier',
      phone: '',
      address: '',
      notes: '',
    ));
    await store.createPurchase(
      supplierId: 'supplier-bom-reclass',
      supplierName: 'BOM Reclass Supplier',
      receiveNow: true,
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'bom-reclass-a',
          productName: 'Phase5 Product',
          quantity: 4,
          unitCost: 3,
        ),
        PurchaseItem(
          productId: 'bom-reclass-b',
          productName: 'Phase5 Product',
          quantity: 2,
          unitCost: 5,
        ),
      ],
    );

    final db = SqliteMigrationManager.database!;
    final rawAccount =
        await AccountingService.resolveAccountRole('inventory_raw');
    final merchandiseAccount =
        await AccountingService.resolveAccountRole('inventory_merchandise');

    Future<double> accountBalance(String accountId) async {
      final row = await db.customSelect('''
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.entry_id
        WHERE jl.account_id = ? AND je.deleted_at = ''
          AND je.status IN ('posted', 'reversed')
      ''', variables: <Variable<Object>>[
        Variable<String>(accountId),
      ]).getSingle();
      return (row.data['balance'] as num? ?? 0).toDouble();
    }

    expect(await accountBalance(rawAccount), closeTo(0, 0.0001));
    expect(await accountBalance(merchandiseAccount), closeTo(22, 0.0001));

    final bom = await store.createBillOfMaterials(
      name: 'Dynamic classification BOM',
      outputProductId: 'bom-reclass-output',
      outputQuantity: 1,
      components: const <BillOfMaterialsLine>[
        BillOfMaterialsLine(
          productId: 'bom-reclass-a',
          productName: 'Phase5 Product',
          quantity: 1,
        ),
      ],
    );
    expect(await accountBalance(rawAccount), closeTo(12, 0.0001));
    expect(await accountBalance(merchandiseAccount), closeTo(10, 0.0001));

    await store.updateBillOfMaterials(
      id: bom.id,
      name: bom.name,
      outputProductId: 'bom-reclass-output',
      outputQuantity: 1,
      components: const <BillOfMaterialsLine>[
        BillOfMaterialsLine(
          productId: 'bom-reclass-b',
          productName: 'Phase5 Product',
          quantity: 1,
        ),
      ],
    );
    expect(await accountBalance(rawAccount), closeTo(10, 0.0001));
    expect(await accountBalance(merchandiseAccount), closeTo(12, 0.0001));

    await store.deleteBillOfMaterials(bom.id);
    expect(await accountBalance(rawAccount), closeTo(0, 0.0001));
    expect(await accountBalance(merchandiseAccount), closeTo(22, 0.0001));

    final inventoryEntries = await db.customSelect('''
      SELECT COUNT(*) AS count
      FROM journal_entries
      WHERE reference_type = 'inventory_account_reconcile'
        AND deleted_at = '' AND status = 'posted'
    ''').getSingle();
    expect(inventoryEntries.read<int>('count'), 3);
  });

  test('BOM classification re-post is atomic with SQLite BOM persistence',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'bom-atomic-component',
      code: 'BOM-AT-C',
      stock: 0,
      cost: 3,
    ));
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'bom-atomic-output',
      code: 'BOM-AT-O',
      stock: 0,
      cost: 0,
    ));
    final warehouse =
        await store.createWarehouse(name: 'BOM atomic', code: 'BAT');
    await store.addOrUpdateSupplier(Supplier(
      id: 'supplier-bom-atomic',
      name: 'BOM Atomic Supplier',
      phone: '',
      address: '',
      notes: '',
    ));
    await store.createPurchase(
      supplierId: 'supplier-bom-atomic',
      supplierName: 'BOM Atomic Supplier',
      receiveNow: true,
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      warehouseId: warehouse.id,
      warehouseName: warehouse.name,
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: 'bom-atomic-component',
          productName: 'Phase5 Product',
          quantity: 1,
          unitCost: 3,
        ),
      ],
    );

    final db = SqliteMigrationManager.database!;
    final rawAccount =
        await AccountingService.resolveAccountRole('inventory_raw');
    final rawSnapshot = (await AccountingService.listAccounts(activeOnly: false))
        .firstWhere((account) => account.id == rawAccount);
    Future<void> setRawPostable(bool value) => AccountingService.updateAccount(
          accountId: rawSnapshot.id,
          code: rawSnapshot.code,
          name: rawSnapshot.name,
          type: rawSnapshot.type,
          normalBalance: rawSnapshot.normalBalance,
          subtype: rawSnapshot.subtype,
          parentId: rawSnapshot.parentId,
          currency: rawSnapshot.currency,
          description: rawSnapshot.description,
          isPostable: value,
        );

    await setRawPostable(false);
    try {
      await expectLater(
        () => store.createBillOfMaterials(
          name: 'Atomic failure BOM',
          outputProductId: 'bom-atomic-output',
          outputQuantity: 1,
          components: const <BillOfMaterialsLine>[
            BillOfMaterialsLine(
              productId: 'bom-atomic-component',
              productName: 'Phase5 Product',
              quantity: 1,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      final persisted = await db.customSelect(
        "SELECT COUNT(*) AS count FROM bill_of_materials WHERE name = 'Atomic failure BOM' AND deleted_at = ''",
      ).getSingle();
      expect(persisted.read<int>('count'), 0);
      final reclassEntries = await db.customSelect('''
        SELECT COUNT(*) AS count FROM journal_entries
        WHERE reference_type = 'inventory_account_reconcile'
          AND deleted_at = '' AND status = 'posted'
      ''').getSingle();
      expect(reclassEntries.read<int>('count'), 0);
    } finally {
      await setRawPostable(true);
    }
  });

  test('manufacturing reversal ignores downstream movements already reversed',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'raw-reverse-chain',
      code: 'RAW-RC',
      stock: 0,
      cost: 2,
    ));
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'fg-reverse-chain',
      code: 'FG-RC',
      stock: 0,
      cost: 0,
    ));
    final rawWarehouse =
        await store.createWarehouse(name: 'Raw reverse chain', code: 'RRC');
    final finishedWarehouse = await store.createWarehouse(
      name: 'Finished reverse chain',
      code: 'FRC',
    );
    await store.addOrUpdateCustomer(Customer(
      id: 'customer-reverse-chain',
      name: 'Reverse Customer',
      phone: '',
      address: '',
    ));
    await store.adjustStock(
      productId: 'raw-reverse-chain',
      warehouseId: rawWarehouse.id,
      quantityDelta: 10,
      reason: 'Opening raw chain',
    );
    final bom = await store.createBillOfMaterials(
      name: 'Reverse chain BOM',
      outputProductId: 'fg-reverse-chain',
      outputQuantity: 1,
      components: const <BillOfMaterialsLine>[
        BillOfMaterialsLine(
          productId: 'raw-reverse-chain',
          productName: 'Raw reverse chain',
          quantity: 2,
        ),
      ],
    );
    final order = await store.completeManufacturingOrder(
      bomId: bom.id,
      quantity: 1,
      rawMaterialsWarehouseId: rawWarehouse.id,
      finishedGoodsWarehouseId: finishedWarehouse.id,
    );
    final sale = await store.createSale(
      customerName: 'Reverse Customer',
      customerId: 'customer-reverse-chain',
      warehouseId: finishedWarehouse.id,
      warehouseName: finishedWarehouse.name,
      paymentStatus: 'credit',
      paymentMethod: 'Credit',
      items: const <SaleItem>[
        SaleItem(
          productId: 'fg-reverse-chain',
          productName: 'Finished reverse chain',
          unitPrice: 10,
          quantity: 1,
        ),
      ],
    );
    await store.returnSale(sale.id);
    final reversed = await store.reverseManufacturingOrder(
      orderId: order.id,
      reason: 'Test full chain reversal',
    );
    expect(reversed.status.toLowerCase(), 'reversed');
    expect(
      await support.sqliteWarehouseQuantity(
        productId: 'fg-reverse-chain',
        warehouseId: finishedWarehouse.id,
        storeId: store.appIdentity.storeId,
      ),
      closeTo(0, 0.0001),
    );
    expect(
      await support.sqliteWarehouseQuantity(
        productId: 'raw-reverse-chain',
        warehouseId: rawWarehouse.id,
        storeId: store.appIdentity.storeId,
      ),
      closeTo(10, 0.0001),
    );
  });

  test('posted document mutation paths are audit guarded', () {
    final source = readAppStoreImplementationSource();
    final updateStart =
        source.indexOf('Future<Purchase> updatePurchaseDraft({');
    final updateEnd =
        source.indexOf('Future<void> receivePurchase(', updateStart);
    expect(updateStart, isNonNegative);
    expect(updateEnd, greaterThan(updateStart));
    final updateBody = source.substring(updateStart, updateEnd);
    expect(updateBody, contains('if (current.isDraft)'));
    expect(updateBody, contains('else if (current.isReceived)'));
    expect(
      updateBody,
      contains('await _requirePurchaseBatchesUnusedInTransaction(sqliteDb, current);'),
    );
    expect(updateBody, contains(r'Purchase edit reverse v${current.version}'));
    expect(
      source,
      contains('Posted/cancelled purchase invoices are retained for audit'),
    );
    expect(
      source,
      contains('Posted/cancelled expenses are retained for audit'),
    );
    expect(
      source,
      contains("<String>{'completed', 'complete', 'reversed'}"),
    );
  });
}
