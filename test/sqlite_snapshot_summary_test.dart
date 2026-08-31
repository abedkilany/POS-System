import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

Future<void> _seedSnapshotData(VentioDriftDatabase db) async {
  final today = DateTime(2026, 6, 30, 10);
  final yesterday = DateTime(2026, 6, 29, 10);

  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.productsKey,
    <String, dynamic>{
      'id': 'p1',
      'name': 'Coffee',
      'nameEn': 'Coffee',
      'nameAr': '',
      'code': 'C1',
      'barcode': 'BC1',
      'price': 8,
      'cost': 5,
      'usdPrice': 8,
      'usdCost': 5,
      'stock': 2,
      'category': 'Beverages',
      'brand': '',
      'supplier': '',
      'unit': 'pcs',
      'trackStock': true,
      'lowStockThreshold': 3,
      'isActive': true,
    },
    sortIndex: 0,
  );
  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.productsKey,
    <String, dynamic>{
      'id': 'p2',
      'name': 'Tea',
      'nameEn': 'Tea',
      'nameAr': '',
      'code': 'T1',
      'barcode': 'BT1',
      'price': 3,
      'cost': 2,
      'usdPrice': 3,
      'usdCost': 2,
      'stock': 10,
      'category': 'Beverages',
      'brand': '',
      'supplier': '',
      'unit': 'pcs',
      'trackStock': true,
      'lowStockThreshold': 4,
      'isActive': true,
    },
    sortIndex: 1,
  );

  const inventoryTimestamp = '2026-06-30T09:00:00.000Z';
  await db.customStatement(
    '''
    INSERT INTO warehouse_inventory
      (id, store_id, branch_id, warehouse_id, product_id, quantity, version,
       created_at, updated_at, device_id, sync_status,
       last_modified_by_device_id)
    VALUES
      ('wi-p1', '', 'main', 'main', 'p1', 2, 1, ?, ?, '', 'synced', ''),
      ('wi-p2', '', 'main', 'main', 'p2', 10, 1, ?, ?, '', 'synced', '')
    ''',
    <Object?>[
      inventoryTimestamp,
      inventoryTimestamp,
      inventoryTimestamp,
      inventoryTimestamp,
    ],
  );

  await db.customStatement(
    '''
    INSERT INTO inventory_batches
      (id, product_id, product_name, status, source_type, source_id,
       source_line_id, unit_cost, initial_quantity, cost_currency,
       exchange_rate, received_at, store_id, branch_id, created_at,
       updated_at, device_id, last_modified_by_device_id, sync_status, version)
    VALUES
      ('batch-p1', 'p1', 'Coffee', 'active', 'test_seed', 'summary',
       'summary:p1', 5, 2, 'USD', 1, ?, '', 'main', ?, ?, '', '', 'synced', 1),
      ('batch-p2', 'p2', 'Tea', 'active', 'test_seed', 'summary',
       'summary:p2', 2, 10, 'USD', 1, ?, '', 'main', ?, ?, '', '', 'synced', 1)
    ''',
    <Object?>[
      inventoryTimestamp,
      inventoryTimestamp,
      inventoryTimestamp,
      inventoryTimestamp,
      inventoryTimestamp,
      inventoryTimestamp,
    ],
  );
  await db.customStatement(
    '''
    INSERT INTO inventory_batch_balances
      (id, batch_id, product_id, warehouse_id, store_id, branch_id, quantity,
       reserved_quantity, version, created_at, updated_at, device_id,
       last_modified_by_device_id, sync_status)
    VALUES
      ('bb-p1', 'batch-p1', 'p1', 'main', '', 'main', 2, 0, 1, ?, ?, '', '', 'synced'),
      ('bb-p2', 'batch-p2', 'p2', 'main', '', 'main', 10, 0, 1, ?, ?, '', '', 'synced')
    ''',
    <Object?>[
      inventoryTimestamp,
      inventoryTimestamp,
      inventoryTimestamp,
      inventoryTimestamp,
    ],
  );

  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.customersKey,
    <String, dynamic>{
      'id': 'customer-1',
      'name': 'Alice',
      'phone': '555-1',
      'address': 'Street 1',
    },
  );
  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.suppliersKey,
    <String, dynamic>{
      'id': 'supplier-1',
      'name': 'Supplier A',
      'phone': '777-1',
      'address': 'Warehouse 1',
      'notes': 'Preferred',
    },
  );

  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.salesKey,
    <String, dynamic>{
      'id': 'sale-1',
      'invoiceNo': 'INV-1',
      'customerName': 'Alice',
      'customerId': 'customer-1',
      'date': today.toIso8601String(),
      'status': 'Paid',
      'discount': 5,
      'transactionAmount': 130,
      'baseAmount': 130,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'productId': 'p1',
          'productName': 'Coffee',
          'unitPrice': 60,
          'quantity': 2,
          'unitName': 'pcs',
          'unitCost': 30,
          'conversionToBase': 1,
        },
      ],
    },
  );

  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.purchasesKey,
    <String, dynamic>{
      'id': 'purchase-1',
      'purchaseNo': 'PO-1',
      'supplierName': 'Supplier A',
      'supplierId': 'supplier-1',
      'date': today.toIso8601String(),
      'status': 'Draft',
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'productId': 'p2',
          'productName': 'Tea',
          'quantity': 4,
          'unitCost': 10,
          'purchaseUnitId': 'base',
          'purchaseUnitName': 'pcs',
          'conversionToBase': 1,
          'originalUnitCost': 10,
          'unitCostCurrency': 'USD',
          'exchangeRateAtEntry': 1,
        },
      ],
    },
  );

  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.expensesKey,
    <String, dynamic>{
      'id': 'expense-1',
      'title': 'Office rent',
      'category': 'Office',
      'amount': 20,
      'date': today.toIso8601String(),
      'status': 'Posted',
    },
  );
  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.expensesKey,
    <String, dynamic>{
      'id': 'expense-2',
      'title': 'Fuel',
      'category': 'Transport',
      'amount': 30,
      'date': yesterday.toIso8601String(),
      'status': 'Posted',
    },
  );

  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.stockMovementsKey,
    <String, dynamic>{
      'id': 'sm-1',
      'productId': 'p1',
      'productName': 'Coffee',
      'type': 'auto_correction',
      'quantity': -3,
      'date': today.toIso8601String(),
      'referenceNo': 'REF-1',
    },
  );
  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.stockMovementsKey,
    <String, dynamic>{
      'id': 'sm-2',
      'productId': 'p2',
      'productName': 'Tea',
      'type': 'sale',
      'quantity': 5,
      'date': today.toIso8601String(),
      'referenceNo': 'REF-2',
    },
  );

  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.accountTransactionsKey,
    <String, dynamic>{
      'id': 'txn-1',
      'accountType': 'customer',
      'accountId': 'customer-1',
      'accountName': 'Alice',
      'date': today.toIso8601String(),
      'type': 'paymentReceived',
      'referenceNo': 'RCV-1',
      'debit': 50,
      'credit': 0,
      'currency': 'USD',
      'paymentMethod': 'Cash',
    },
  );
  await BusinessSqliteStore.upsertEntityPayload(
    db,
    BusinessSqliteStore.accountTransactionsKey,
    <String, dynamic>{
      'id': 'txn-2',
      'accountType': 'supplier',
      'accountId': 'supplier-1',
      'accountName': 'Supplier A',
      'date': today.toIso8601String(),
      'type': 'paymentPaid',
      'referenceNo': 'PAY-1',
      'debit': 0,
      'credit': 70,
      'currency': 'USD',
      'paymentMethod': 'Cash',
    },
  );

  // Reports cash totals must come from the immutable Cash Ledger, not from
  // customer/supplier account transactions.
  await db.customStatement('''
    INSERT INTO cash_ledger_transactions
      (id, type, direction, amount, cash_location_id, payment_method,
       occurred_at, created_at, updated_at)
    VALUES
      ('clt-in-1', 'receipt', 'in', 50, 'cl_main_drawer', 'Cash',
       '2026-06-30T10:00:00.000', '2026-06-30T10:00:00.000', '2026-06-30T10:00:00.000'),
      ('clt-out-1', 'payment', 'out', 70, 'cl_main_drawer', 'Cash',
       '2026-06-30T11:00:00.000', '2026-06-30T11:00:00.000', '2026-06-30T11:00:00.000')
  ''');

  // Reports net profit must come from posted journal lines. These two
  // balanced entries produce 55 revenue - 50 expense = 5 net profit.
  await db.customStatement('''
    INSERT INTO journal_entries
      (id, entry_no, entry_date, status, source, created_at, updated_at)
    VALUES
      ('je-sales-1', 'JE-TEST-001', '2026-06-30T10:00:00.000', 'posted', 'system',
       '2026-06-30T10:00:00.000', '2026-06-30T10:00:00.000'),
      ('je-expense-1', 'JE-TEST-002', '2026-06-30T11:00:00.000', 'posted', 'system',
       '2026-06-30T11:00:00.000', '2026-06-30T11:00:00.000')
  ''');
  await db.customStatement('''
    INSERT INTO journal_lines
      (id, entry_id, line_no, account_id, debit, credit, created_at, updated_at)
    VALUES
      ('jl-sales-cash', 'je-sales-1', 1, 'acc_main_drawer', 55, 0,
       '2026-06-30T10:00:00.000', '2026-06-30T10:00:00.000'),
      ('jl-sales-revenue', 'je-sales-1', 2, 'acc_sales', 0, 55,
       '2026-06-30T10:00:00.000', '2026-06-30T10:00:00.000'),
      ('jl-expense', 'je-expense-1', 1, 'acc_general_expenses', 50, 0,
       '2026-06-30T11:00:00.000', '2026-06-30T11:00:00.000'),
      ('jl-expense-cash', 'je-expense-1', 2, 'acc_main_drawer', 0, 50,
       '2026-06-30T11:00:00.000', '2026-06-30T11:00:00.000')
  ''');
}

void main() {
  group('SQLite snapshot summaries', () {
    late VentioDriftDatabase db;

    setUp(() async {
      db = VentioDriftDatabase(NativeDatabase.memory());
      await db.initializeFoundation();
      await _seedSnapshotData(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('builds dashboard summary from SQLite aggregates', () async {
      final summary = await BusinessSqliteStore.buildDashboardSummary(
        db,
        reference: DateTime(2026, 6, 30, 12),
      );

      expect(summary['todaySalesTotal'], 130);
      expect(summary['todayProfitTotal'], 55);
      expect(summary['todayInvoiceCount'], 1);
      expect(summary['totalPurchasesAmount'], 40);
      expect(summary['totalExpensesAmount'], 50);
      expect(summary['todayExpenseTotal'], 20);
      expect(summary['last7ExpenseAverage'], closeTo(50 / 7, 1e-9));
      expect(summary['inventoryCostValue'], 30);
      expect(summary['lowStockCount'], 1);
      expect(summary['pendingSyncCount'], 0);
      expect(summary['blockingConflictCount'], 0);
      expect((summary['topProducts'] as List).first['label'], 'Coffee');
      expect((summary['recentOperations'] as List).length, 5);
    });

    test('builds reports summary from SQLite aggregates', () async {
      final summary = await BusinessSqliteStore.buildReportsSummary(
        db,
        reference: DateTime(2026, 6, 30, 12),
      );

      expect(summary['todaySales'], 115);
      expect(summary['monthSales'], 115);
      expect(summary['netProfit'], 5);
      expect(summary['monthPurchases'], 40);
      expect(summary['totalExpenses'], 50);
      expect(summary['movementIn'], 5);
      expect(summary['movementOut'], 3);
      expect(summary['inventoryRetailValue'], 46);
      expect(summary['lowStockCount'], 1);
      expect(summary['customerReceivables'], 50);
      expect(summary['supplierPayables'], 70);
      expect(summary['todayCashIn'], 50);
      expect(summary['todayCashOut'], 70);
      expect((summary['topProductLines'] as List).first['key'], 'Coffee');
      expect((summary['topCustomerDebts'] as List).first['key'], 'Alice');
      expect((summary['topSupplierDebts'] as List).first['key'], 'Supplier A');
    });
  });
}
