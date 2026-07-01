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
      expect(summary['estimatedProfit'], 5);
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
