part of 'app_store_workflow_test.dart';

void _salePostingTransactionTests() {
  group('Sale posting transaction', () {
    for (final failure in <String, String>{
      'journal_entries': "NEW.reference_type = 'sale'",
      'account_transactions': "NEW.transaction_type = 'saleInvoice'",
    }.entries) {
      test('rolls back every persisted effect when ${failure.key} fails',
          () async {
        final store = await _prepareSalePostingStore();
        final db = SqliteMigrationManager.database!;
        final before = await _salePostingSnapshot();
        final cachedSales =
            store.commerce.sales.map((sale) => sale.id).toList();
        await db.customStatement('''
          CREATE TEMP TRIGGER fail_sale_posting
          BEFORE INSERT ON ${failure.key}
          WHEN ${failure.value}
          BEGIN SELECT RAISE(ABORT, 'injected sale posting failure'); END;
        ''');
        try {
          await expectLater(
            store.commerce.createSale(
              customerId: 'posting-customer',
              customerName: 'Posting Customer',
              paymentMethod: 'Credit',
              paymentStatus: 'credit',
              items: const [
                SaleItem(
                    productId: 'posting-product',
                    productName: 'Posting',
                    quantity: 2,
                    unitPrice: 12),
              ],
            ),
            throwsA(anything),
          );
          expect(await _salePostingSnapshot(), before);
          expect(store.commerce.sales.map((sale) => sale.id).toList(),
              cachedSales);
          expect(await store.inventory.totalStockFromSqlite('posting-product'),
              closeTo(10, 0.000001));
        } finally {
          await db.customStatement('DROP TRIGGER fail_sale_posting');
        }
        // The same session can post successfully after the failure is removed.
        final sale = await store.commerce.createSale(
          customerId: 'posting-customer',
          customerName: 'Posting Customer',
          paymentMethod: 'Credit',
          paymentStatus: 'credit',
          items: const [
            SaleItem(
                productId: 'posting-product',
                productName: 'Posting',
                quantity: 2,
                unitPrice: 12)
          ],
        );
        expect(sale.items.single.batchAllocations, isNotEmpty);
        expect(await store.inventory.totalStockFromSqlite('posting-product'),
            closeTo(8, 0.000001));
        final journal = await db.customSelect(
          "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'sale' AND reference_id = ? AND status = 'posted'",
          variables: [Variable<String>(sale.id)],
        ).getSingle();
        expect(journal.read<int>('c'), 1);
        final ledger = await db.customSelect(
          "SELECT COUNT(*) AS c FROM account_transactions WHERE reference_id = ? AND transaction_type = 'saleInvoice'",
          variables: [Variable<String>(sale.id)],
        ).getSingle();
        expect(ledger.read<int>('c'), 1);
      });
    }

    test('rejects insufficient stock without persisting a partial invoice',
        () async {
      final store = await _prepareSalePostingStore();
      final before = await _salePostingSnapshot();
      await expectLater(
        store.commerce.createSale(
          customerId: 'posting-customer',
          customerName: 'Posting Customer',
          paymentMethod: 'Credit',
          paymentStatus: 'credit',
          items: const [
            SaleItem(
                productId: 'posting-product',
                productName: 'Posting',
                quantity: 11,
                unitPrice: 12)
          ],
        ),
        throwsA(anything),
      );
      expect(await _salePostingSnapshot(), before);
    });
  });
}

Future<AppStore> _prepareSalePostingStore() async {
  final store =
      await readySqliteStore(storeId: 'ST-POSTING', branchId: 'BR-POSTING');
  await store.catalog.addOrUpdateProduct(product(
    id: 'posting-product',
    code: 'POSTING',
    name: 'Posting',
    stock: 0,
    cost: 4,
  ));
  await store.commerce.createPurchase(
    supplierId: 'posting-supplier',
    supplierName: 'Posting Supplier',
    receiveNow: true,
    paymentMethod: 'Credit',
    paymentStatus: 'credit',
    items: const [
      PurchaseItem(
          productId: 'posting-product',
          productName: 'Posting',
          quantity: 10,
          unitCost: 4)
    ],
  );
  return store;
}

Future<Map<String, List<Map<String, Object?>>>> _salePostingSnapshot() async {
  final db = SqliteMigrationManager.database!;
  final result = <String, List<Map<String, Object?>>>{};
  // These are fixed, schema-defined tables, never user-provided SQL identifiers.
  for (final table in [
    'sales',
    'sale_items',
    'stock_movements',
    'stock_operations',
    'warehouse_inventory',
    'inventory_batch_balances',
    'journal_entries',
    'journal_lines',
    'account_transactions'
  ]) {
    result[table] =
        (await db.customSelect('SELECT * FROM $table ORDER BY id').get())
            .map((row) => Map<String, Object?>.from(row.data))
            .toList();
  }
  return result;
}
