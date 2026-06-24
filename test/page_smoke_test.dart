import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/localization/app_localizations.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/features/accounting/accounting_page.dart';
import 'package:ventio/features/customers/customers_page.dart';
import 'package:ventio/features/dashboard/dashboard_page.dart';
import 'package:ventio/features/expenses/expenses_page.dart';
import 'package:ventio/features/inventory/inventory_page.dart';
import 'package:ventio/features/maintenance/maintenance_page.dart';
import 'package:ventio/features/products/products_page.dart';
import 'package:ventio/features/purchases/purchases_page.dart';
import 'package:ventio/features/reports/reports_page.dart';
import 'package:ventio/features/sales/delivery_notes_page.dart';
import 'package:ventio/features/sales/quotations_page.dart';
import 'package:ventio/features/sales/sales_page.dart';
import 'package:ventio/features/settings/settings_page.dart';
import 'package:ventio/features/settings/users_permissions_page.dart';
import 'package:ventio/features/suppliers/suppliers_page.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/supplier.dart';

Map<String, String> _hostIdentitySeed() {
  final now = DateTime(2026, 1, 1).toIso8601String();
  return <String, String>{
    'app_identity_v1': jsonEncode(<String, dynamic>{
      'storeId': 'ST-PAGE',
      'branchId': 'BR-PAGE',
      'deviceId': 'DV-PAGE',
      'deviceName': 'Page Smoke Host',
      'platform': 'windows',
      'deviceRole': 'host',
      'appRole': 'store',
      'syncMode': 'localOnly',
      'createdAt': now,
      'updatedAt': now,
      'hostDeviceId': '',
      'cloudTenantId': '',
      'deviceToken': 'device_page_host',
      'storeEpoch': 1,
      'recoveryKey': 'RK-PAGE-TEST-HOST',
      'activeSyncTransport': 'local',
    }),
  };
}

Future<AppStore> _readyStore() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  LocalDatabaseService.useInMemoryStoreForTesting(_hostIdentitySeed());
  final store = AppStore();
  await store.initialize();
  await store.completeInitialAdminSetup(
    fullName: 'Admin',
    username: 'admin',
    password: 'AdminPass123',
  );
  await store.addOrUpdateProduct(
    Product(
      id: 'p1',
      name: 'Coffee',
      code: 'COF',
      price: 10,
      cost: 4,
      stock: 12,
      category: 'Drinks',
      barcode: '111',
    ),
  );
  await store.addOrUpdateCustomer(
    Customer(id: 'c1', name: 'Alice', phone: '111', address: 'Main St'),
  );
  await store.addOrUpdateSupplier(
    Supplier(
        id: 's1',
        name: 'Supplier',
        phone: '222',
        address: 'Warehouse',
        notes: ''),
  );
  await store.addOrUpdateExpense(
    Expense(
      id: 'e1',
      title: 'Rent',
      category: 'Office',
      amount: 25,
      date: DateTime(2026, 1, 1),
      notes: '',
    ),
  );
  await store.createSale(
    customerId: 'c1',
    customerName: 'Alice',
    items: const [
      SaleItem(
          productId: 'p1', productName: 'Coffee', unitPrice: 10, quantity: 1),
    ],
  );
  await store.createPurchase(
    supplierId: 's1',
    supplierName: 'Supplier',
    receiveNow: false,
    items: const [
      PurchaseItem(
          productId: 'p1', productName: 'Coffee', quantity: 2, unitCost: 5),
    ],
  );
  return store;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('ar')],
    home: Scaffold(body: child),
  );
}

void main() {
  group('Feature page smoke tests', () {
    late AppStore store;

    setUp(() async {
      store = await _readyStore();
    });

    final pages = <String, Widget Function(AppStore)>{
      'dashboard': (store) => DashboardPage(store: store),
      'products': (store) => ProductsPage(store: store),
      'customers': (store) => CustomersPage(store: store),
      'suppliers': (store) => SuppliersPage(store: store),
      'expenses': (store) => ExpensesPage(store: store),
      'inventory': (store) => InventoryPage(store: store),
      'purchases': (store) => PurchasesPage(store: store),
      'sales': (store) => SalesPage(store: store),
      'quotations': (store) => QuotationsPage(store: store),
      'delivery notes': (store) => DeliveryNotesPage(store: store),
      'reports': (store) => ReportsPage(store: store),
      'accounting': (store) => AccountingPage(store: store),
      'users permissions': (store) => UsersPermissionsPage(store: store),
      'maintenance': (store) => MaintenancePage(store: store),
      'settings': (store) => SettingsPage(
            store: store,
            themeMode: ThemeMode.light,
            onLocaleChanged: (_) {},
            onThemeModeChanged: (_) {},
          ),
    };

    for (final entry in pages.entries) {
      testWidgets('${entry.key} page builds', (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_wrap(entry.value(store)));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));

        expect(find.byType(MaterialApp), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
