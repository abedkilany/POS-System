import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

void main() {
  test('builds purchase overview from sqlite without throwing', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();

    final now = DateTime(2026, 7, 2, 1, 8, 11, 733, 302);
    final timestamp = now.toIso8601String();

    await db.customInsert(
      '''
      INSERT INTO purchases (
        id, entity_type, created_at, updated_at, deleted_at, device_id,
        sync_status, store_id, branch_id, version,
        last_modified_by_device_id, sort_index, purchase_no, supplier_id,
        supplier_name, document_date, status, note, payment_status,
        payment_method, paid_amount, cancel_reason, cancelled_by_device_id,
        reversal_applied, cancelled_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>('purchase_test_1'),
        Variable<String>('purchase'),
        Variable<String>(timestamp),
        Variable<String>(timestamp),
        const Variable<String>(''),
        Variable<String>('device-1'),
        Variable<String>('synced'),
        Variable<String>('store-1'),
        Variable<String>('branch-1'),
        const Variable<int>(1),
        Variable<String>('device-1'),
        const Variable<int>(1),
        Variable<String>('PO-001'),
        Variable<String>('supplier-1'),
        Variable<String>('Supplier One'),
        Variable<String>(timestamp),
        Variable<String>('Received'),
        const Variable<String>(''),
        Variable<String>('paid'),
        Variable<String>('Cash'),
        const Variable<num>(0),
        const Variable<String>(''),
        const Variable<String>(''),
        const Variable<int>(0),
        const Variable<String>(''),
      ],
    );

    await db.customInsert(
      '''
      INSERT INTO purchase_items (
        id, purchase_id, line_no, product_id, product_name, quantity,
        unit_cost, purchase_unit_id, purchase_unit_name, conversion_to_base,
        original_unit_cost, unit_cost_currency, exchange_rate_at_entry
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>('purchase_item_test_1'),
        Variable<String>('purchase_test_1'),
        const Variable<int>(1),
        Variable<String>('product-1'),
        Variable<String>('Product One'),
        const Variable<num>(2),
        const Variable<num>(5),
        Variable<String>('base'),
        Variable<String>('Base'),
        const Variable<num>(1),
        const Variable<num>(5),
        Variable<String>('USD'),
        const Variable<num>(0),
      ],
    );

    final page = await BusinessSqliteStore.queryPurchases(
      db,
      limit: 10,
      sortMode: 'newest',
    );
    final overview = await BusinessSqliteStore.buildPurchasesOverview(
      db,
      reference: now,
    );

    expect(page.totalCount, 1);
    expect(page.items, hasLength(1));
    expect(page.items.single.purchaseNo, 'PO-001');
    expect(page.items.single.subtotal, 10);
    expect(overview['totalCount'], 1);
    expect(overview['totalPurchasesAmount'], 10);
    expect(overview['monthlyCount'], 1);
    expect(overview['draftCount'], 0);
    expect(overview['receivedCount'], 1);
  });
}
