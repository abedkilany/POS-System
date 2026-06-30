import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

void main() {
  test('stock movements are written and read from typed SQLite columns',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();

    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.stockMovementsKey,
      <String, dynamic>{
        'id': 'movement-1',
        'productId': 'product-1',
        'productName': 'Test product',
        'type': 'purchase_receive',
        'quantity': 12.5,
        'date': '2026-06-30T10:00:00.000Z',
        'referenceId': 'purchase-1',
        'referenceNo': 'PO-1',
        'warehouseId': 'main',
        'warehouseName': 'Main warehouse',
        'unitCost': 4.25,
        'syncStatus': 'pending',
        'version': 2,
      },
    );

    final rawRows = await db.customSelect('''
      SELECT product_id, movement_type, quantity, movement_date, unit_cost
      FROM stock_movements
      WHERE id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('movement-1'),
    ]).get();

    expect(rawRows.single.read<String>('product_id'), 'product-1');
    expect(rawRows.single.read<String>('movement_type'), 'purchase_receive');
    expect(rawRows.single.read<double>('quantity'), 12.5);
    expect(rawRows.single.read<String>('movement_date'),
        '2026-06-30T10:00:00.000Z');
    expect(rawRows.single.read<double>('unit_cost'), 4.25);

    final movements = await BusinessSqliteStore.readStockMovements(db);
    expect(movements, hasLength(1));
    expect(movements.single.productId, 'product-1');
    expect(movements.single.quantity, 12.5);
    expect(movements.single.unitCost, 4.25);
  });

  test('account transactions are written and read from typed SQLite columns',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();

    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.accountTransactionsKey,
      <String, dynamic>{
        'id': 'txn-1',
        'accountType': 'supplier',
        'accountId': 'supplier-1',
        'accountName': 'Supplier One',
        'date': '2026-06-30T11:00:00.000Z',
        'type': 'purchase',
        'referenceId': 'purchase-1',
        'referenceNo': 'PO-1',
        'debit': 0,
        'credit': 99.75,
        'currency': 'USD',
        'paymentMethod': 'cash',
        'note': 'typed write',
        'syncStatus': 'pending',
      },
    );

    final rawRows = await db.customSelect('''
      SELECT account_type, account_id, transaction_type, credit, payment_method
      FROM account_transactions
      WHERE id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('txn-1'),
    ]).get();

    expect(rawRows.single.read<String>('account_type'), 'supplier');
    expect(rawRows.single.read<String>('account_id'), 'supplier-1');
    expect(rawRows.single.read<String>('transaction_type'), 'purchase');
    expect(rawRows.single.read<double>('credit'), 99.75);
    expect(rawRows.single.read<String>('payment_method'), 'cash');

    final transactions = await BusinessSqliteStore.readAccountTransactions(db);
    expect(transactions, hasLength(1));
    expect(transactions.single.accountId, 'supplier-1');
    expect(transactions.single.credit, 99.75);
  });

  test('customers are written and read from typed SQLite columns', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();

    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.customersKey,
      <String, dynamic>{
        'id': 'customer-1',
        'name': 'Client One',
        'phone': '555-1000',
        'address': 'Beirut',
      },
    );

    final rawRows = await db.customSelect('''
      SELECT name, phone, address
      FROM customers
      WHERE id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('customer-1'),
    ]).get();

    expect(rawRows.single.read<String>('name'), 'Client One');
    expect(rawRows.single.read<String>('phone'), '555-1000');
    expect(rawRows.single.read<String>('address'), 'Beirut');

    final customers = await BusinessSqliteStore.readCustomers(db);
    expect(customers, hasLength(1));
    expect(customers.single.name, 'Client One');
  });

  test('price lists are written and read from typed SQLite columns', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();

    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.priceListsKey,
      <String, dynamic>{
        'id': 'retail',
        'name': 'Retail',
        'code': 'RTL',
        'isDefault': true,
        'isActive': true,
      },
    );

    final rawRows = await db.customSelect('''
      SELECT name, code, is_default, is_active
      FROM price_lists
      WHERE id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('retail'),
    ]).get();

    expect(rawRows.single.read<String>('name'), 'Retail');
    expect(rawRows.single.read<int>('is_default'), 1);
    expect(rawRows.single.read<int>('is_active'), 1);

    final priceLists = await BusinessSqliteStore.readPriceLists(db);
    expect(priceLists, hasLength(1));
    expect(priceLists.single.isDefault, isTrue);
    expect(priceLists.single.isActive, isTrue);
  });

  test('products are written and read from typed SQLite columns', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();

    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.productsKey,
      <String, dynamic>{
        'id': 'product-typed-1',
        'name': 'Typed product',
        'code': 'TP-1',
        'nameEn': 'Typed product',
        'nameAr': 'منتج',
        'price': 12.5,
        'cost': 7.25,
        'stock': 24,
        'category': 'General',
        'unit': 'pcs',
        'quantityType': 'countable',
        'trackStock': true,
        'isActive': true,
        'saleUnits': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'box',
            'name': 'Box',
            'conversionToBase': 6,
            'price': 72,
            'originalPrice': 72,
            'originalCurrency': 'USD',
            'barcode': 'BOX-1',
            'isDefault': false,
          },
        ],
        'purchaseUnits': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'carton',
            'name': 'Carton',
            'conversionToBase': 12,
            'price': 138,
            'originalPrice': 138,
            'originalCurrency': 'USD',
            'barcode': 'CRT-1',
            'isDefault': false,
          },
        ],
      },
    );

    final rawRows = await db.customSelect('''
      SELECT name, price, cost, track_stock, is_active
      FROM products
      WHERE id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('product-typed-1'),
    ]).get();
    expect(rawRows.single.read<String>('name'), 'Typed product');
    expect(rawRows.single.read<double>('price'), 12.5);
    expect(rawRows.single.read<double>('cost'), 7.25);
    expect(rawRows.single.read<int>('track_stock'), 1);
    expect(rawRows.single.read<int>('is_active'), 1);

    final saleUnits = await db.customSelect('''
      SELECT name, conversion_to_base, price
      FROM product_sale_units
      WHERE product_id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('product-typed-1'),
    ]).get();
    expect(saleUnits.single.read<String>('name'), 'Box');
    expect(saleUnits.single.read<double>('conversion_to_base'), 6);

    final products = await BusinessSqliteStore.readProducts(db);
    expect(products, hasLength(1));
    expect(products.single.saleUnits, hasLength(1));
    expect(products.single.purchaseUnits, hasLength(1));
  });

  test('sales are written and read from typed parent and item tables',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();

    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.salesKey,
      <String, dynamic>{
        'id': 'sale-typed-1',
        'invoiceNo': 'INV-1',
        'customerName': 'Alice',
        'customerId': 'customer-1',
        'date': '2026-06-30T13:00:00.000Z',
        'status': 'Paid',
        'discount': 2,
        'paymentMethod': 'Cash',
        'paymentStatus': 'paid',
        'invoiceCurrency': 'USD',
        'paymentCurrency': 'USD',
        'exchangeRateAtPayment': 1,
        'baseCurrency': 'USD',
        'exchangeRateAtInvoice': 1,
        'transactionAmount': 20,
        'baseAmount': 18,
        'paidAmount': 20,
        'cashReceivedAmount': 20,
        'note': 'typed sale',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'productId': 'product-1',
            'productName': 'Product 1',
            'unitPrice': 10,
            'quantity': 2,
            'unitName': 'pcs',
            'baseQuantity': 2,
            'conversionToBase': 1,
            'unitCost': 6,
            'costingMethodAtSale': 'weighted_average',
            'costCurrency': 'USD',
            'costExchangeRate': 1,
            'costLayerConsumptions': <Map<String, dynamic>>[
              <String, dynamic>{
                'layerId': 'layer-1',
                'quantity': 2,
                'unitCost': 6,
                'currencyCode': 'USD',
              },
            ],
          },
        ],
      },
    );

    final saleRows = await db.customSelect('''
      SELECT invoice_no, discount, payment_status
      FROM sales
      WHERE id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('sale-typed-1'),
    ]).get();
    expect(saleRows.single.read<String>('invoice_no'), 'INV-1');
    expect(saleRows.single.read<double>('discount'), 2);

    final itemRows = await db.customSelect('''
      SELECT product_name, unit_price, quantity
      FROM sale_items
      WHERE sale_id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('sale-typed-1'),
    ]).get();
    expect(itemRows.single.read<String>('product_name'), 'Product 1');
    expect(itemRows.single.read<double>('quantity'), 2);

    final consumptionRows = await db.customSelect('''
      SELECT layer_id, quantity, unit_cost
      FROM sale_item_cost_layer_consumptions
    ''').get();
    expect(consumptionRows.single.read<String>('layer_id'), 'layer-1');

    final sales = await BusinessSqliteStore.readSales(db);
    expect(sales, hasLength(1));
    expect(sales.single.items, hasLength(1));
    expect(sales.single.items.single.costLayerConsumptions, hasLength(1));
  });

  test('purchases are written and read from typed parent and item tables',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();

    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.purchasesKey,
      <String, dynamic>{
        'id': 'purchase-typed-1',
        'purchaseNo': 'PO-1',
        'supplierId': 'supplier-1',
        'supplierName': 'Supplier One',
        'date': '2026-06-30T14:00:00.000Z',
        'status': 'received',
        'note': 'typed purchase',
        'paymentStatus': 'paid',
        'paymentMethod': 'Cash',
        'paidAmount': 42,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'productId': 'product-1',
            'productName': 'Product 1',
            'quantity': 3,
            'unitCost': 14,
            'purchaseUnitId': 'base',
            'purchaseUnitName': 'pcs',
            'conversionToBase': 1,
            'originalUnitCost': 14,
            'unitCostCurrency': 'USD',
            'exchangeRateAtEntry': 1,
          },
        ],
      },
    );

    final purchaseRows = await db.customSelect('''
      SELECT purchase_no, supplier_name, paid_amount
      FROM purchases
      WHERE id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('purchase-typed-1'),
    ]).get();
    expect(purchaseRows.single.read<String>('purchase_no'), 'PO-1');
    expect(purchaseRows.single.read<String>('supplier_name'), 'Supplier One');

    final itemRows = await db.customSelect('''
      SELECT product_name, quantity, unit_cost
      FROM purchase_items
      WHERE purchase_id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('purchase-typed-1'),
    ]).get();
    expect(itemRows.single.read<double>('quantity'), 3);
    expect(itemRows.single.read<double>('unit_cost'), 14);

    final purchases = await BusinessSqliteStore.readPurchases(db);
    expect(purchases, hasLength(1));
    expect(purchases.single.items, hasLength(1));
    expect(purchases.single.items.single.purchaseUnitId, 'base');
  });

  test('business tables stay payload-json free and roles users use typed columns',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();

    const tablesWithoutPayloadJson = <String>[
      'products',
      'customers',
      'suppliers',
      'sales',
      'sale_quotations',
      'delivery_notes',
      'bill_of_materials',
      'manufacturing_orders',
      'inventory_counts',
      'supplier_product_prices',
      'price_lists',
      'product_prices',
      'product_price_overrides',
      'product_costs',
      'costing_method_history',
      'inventory_cost_layers',
      'expenses',
      'purchases',
      'warehouses',
      'stock_movements',
      'account_transactions',
      'catalog_categories',
      'catalog_brands',
      'catalog_units',
      'user_roles',
      'app_users',
    ];

    for (final table in tablesWithoutPayloadJson) {
      final columns = await db.customSelect('PRAGMA table_info($table);').get();
      final columnNames =
          columns.map((row) => row.read<String>('name')).toList(growable: false);
      expect(
        columnNames,
        isNot(contains('payload_json')),
        reason: '$table still exposes payload_json',
      );
    }

    await BusinessSqliteStore.saveKeyJson(
      db,
      BusinessSqliteStore.rolesKey,
      jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'admin',
          'name': 'Admin',
          'permissions': <String>['dashboard.view', 'settings.view'],
          'isSystem': true,
        },
      ]),
    );
    await BusinessSqliteStore.saveKeyJson(
      db,
      BusinessSqliteStore.usersKey,
      jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'user-1',
          'fullName': 'Test User',
          'username': 'tester',
          'passwordHash': 'hash',
          'roleId': 'admin',
          'extraPermissions': <String>['reports.view'],
          'deniedPermissions': <String>['backup.manage'],
          'isActive': true,
          'isSystem': false,
          'lastLoginAt': '2026-06-30T12:00:00.000Z',
        },
      ]),
    );

    final roleRows = await db.customSelect('''
      SELECT name, permissions_json, is_system
      FROM user_roles
      WHERE id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('admin'),
    ]).get();
    expect(roleRows.single.read<String>('name'), 'Admin');
    expect(roleRows.single.read<String>('permissions_json'),
        contains('dashboard.view'));
    expect(roleRows.single.read<int>('is_system'), 1);

    final userRows = await db.customSelect('''
      SELECT full_name, username, password_hash, role_id, is_active,
             extra_permissions_json, denied_permissions_json
      FROM app_users
      WHERE id = ?
    ''', variables: <Variable<Object>>[
      const Variable<String>('user-1'),
    ]).get();
    expect(userRows.single.read<String>('full_name'), 'Test User');
    expect(userRows.single.read<String>('username'), 'tester');
    expect(userRows.single.read<String>('role_id'), 'admin');
    expect(userRows.single.read<int>('is_active'), 1);
    expect(userRows.single.read<String>('extra_permissions_json'),
        contains('reports.view'));
    expect(userRows.single.read<String>('denied_permissions_json'),
        contains('backup.manage'));

    final rolesJson =
        await BusinessSqliteStore.readEntityListJsonByKey(db, BusinessSqliteStore.rolesKey);
    final usersJson =
        await BusinessSqliteStore.readEntityListJsonByKey(db, BusinessSqliteStore.usersKey);
    expect(rolesJson, contains('"name":"Admin"'));
    expect(usersJson, contains('"username":"tester"'));
  });
}
