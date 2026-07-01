import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

Future<void> _seedBusinessQueries(VentioDriftDatabase db) async {
  for (var i = 0; i < 12; i += 1) {
    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.productsKey,
      <String, dynamic>{
        'id': 'product-$i',
        'name': i.isEven ? 'Coffee Beans $i' : 'Tea Leaves $i',
        'nameEn': i.isEven ? 'Coffee Beans $i' : 'Tea Leaves $i',
        'nameAr': '',
        'code': 'SKU-$i',
        'barcode': 'BAR-$i',
        'price': 10 + i,
        'cost': 5 + i,
        'stock': i.toDouble(),
        'category': i.isEven ? 'Coffee' : 'Tea',
        'brand': 'Brand $i',
        'supplier': 'Supplier $i',
        'unit': 'pcs',
        if (i == 0) ...{
          'saleUnits': [
            {
              'id': 'box',
              'name': 'Box',
              'conversionToBase': 12,
              'price': 100,
              'barcode': 'BOX-COFFEE',
              'isDefault': false,
            }
          ],
          'purchaseUnits': [
            {
              'id': 'case',
              'name': 'Case',
              'conversionToBase': 24,
              'price': 160,
              'barcode': 'CASE-COFFEE',
              'isDefault': false,
            }
          ],
        },
        'trackStock': true,
        'isActive': i != 11,
      },
      sortIndex: i,
    );
  }

  for (var i = 0; i < 8; i += 1) {
    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.customersKey,
      <String, dynamic>{
        'id': 'customer-$i',
        'name': i.isEven ? 'Alice $i' : 'Bob $i',
        'phone': '555-$i',
        'address': 'Street $i',
      },
      sortIndex: i,
    );
    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.suppliersKey,
      <String, dynamic>{
        'id': 'supplier-$i',
        'name': i.isEven ? 'Main Supplier $i' : 'Backup Supplier $i',
        'phone': '777-$i',
        'address': 'Warehouse $i',
        'notes': 'Note $i',
      },
      sortIndex: i,
    );
    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.expensesKey,
      <String, dynamic>{
        'id': 'expense-$i',
        'title': i.isEven ? 'Rent $i' : 'Fuel $i',
        'category': i.isEven ? 'Office' : 'Transport',
        'amount': 20 + i,
        'date': DateTime(2026, 1, i + 1).toIso8601String(),
        'notes': 'Expense note $i',
        'status': i.isEven ? 'Posted' : 'Draft',
      },
      sortIndex: i,
    );
  }
}

void main() {
  group('SQLite business query layer', () {
    late VentioDriftDatabase db;

    setUp(() async {
      db = VentioDriftDatabase(NativeDatabase.memory());
      await db.initializeFoundation();
      await _seedBusinessQueries(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('queries products with search, category, and pagination', () async {
      final firstPage = await BusinessSqliteStore.queryProducts(
        db,
        query: 'coffee',
        category: 'Coffee',
        limit: 3,
      );
      final secondPage = await BusinessSqliteStore.queryProducts(
        db,
        query: 'coffee',
        category: 'Coffee',
        limit: 3,
        offset: 3,
      );

      expect(firstPage.totalCount, 6);
      expect(firstPage.items, hasLength(3));
      expect(secondPage.items, hasLength(3));
      expect(
          firstPage.items
              .map((item) => item.id)
              .toSet()
              .intersection(secondPage.items.map((item) => item.id).toSet()),
          isEmpty);

      final unitBarcode = await BusinessSqliteStore.queryProducts(
        db,
        query: 'box-coffee',
        limit: 10,
      );

      expect(unitBarcode.totalCount, 1);
      expect(unitBarcode.items.single.saleUnits.single.barcode, 'BOX-COFFEE');
      expect(
          unitBarcode.items.single.purchaseUnits.single.barcode, 'CASE-COFFEE');
    });

    test('queries customers and suppliers without loading full tables',
        () async {
      final customers = await BusinessSqliteStore.queryCustomers(
        db,
        query: 'alice',
        limit: 2,
      );
      final suppliers = await BusinessSqliteStore.querySuppliers(
        db,
        query: 'backup',
        limit: 10,
      );

      expect(customers.totalCount, 4);
      expect(customers.items, hasLength(2));
      expect(customers.hasMore, isTrue);
      expect(suppliers.totalCount, 4);
      expect(suppliers.items.every((item) => item.name.contains('Backup')),
          isTrue);
    });

    test('queries expenses by status and text', () async {
      final postedOffice = await BusinessSqliteStore.queryExpenses(
        db,
        status: 'posted',
        query: 'office',
        limit: 20,
      );

      expect(postedOffice.totalCount, 4);
      expect(postedOffice.items.every((item) => item.isPosted), isTrue);
      expect(postedOffice.items.every((item) => item.category == 'Office'),
          isTrue);

      final postedOfficeTotal = await BusinessSqliteStore.sumPostedExpenses(
        db,
        query: 'office',
      );
      final draftTotal = await BusinessSqliteStore.sumPostedExpenses(
        db,
        status: 'draft',
        query: 'fuel',
      );

      expect(postedOfficeTotal, 92);
      expect(draftTotal, 0);
    });

    test('lists product categories from SQLite', () async {
      final categories = await BusinessSqliteStore.queryProductCategories(db);

      expect(categories, ['Coffee', 'Tea']);
    });
  });
}
