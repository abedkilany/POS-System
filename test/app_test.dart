import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/localization/app_localizations.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/features/security/pin_lock_page.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/supplier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late Directory tempDirectory;
  final Map<String, String> secureStorageValues = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method.startsWith('get')) {
        return tempDirectory.path;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (MethodCall call) async {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final key = args?['key']?.toString();
      switch (call.method) {
        case 'read':
          return secureStorageValues[key];
        case 'write':
          if (key != null) {
            secureStorageValues[key] = args?['value']?.toString() ?? '';
          }
          return null;
        case 'delete':
          if (key != null) {
            secureStorageValues.remove(key);
          }
          return null;
        case 'deleteAll':
          secureStorageValues.clear();
          return null;
        case 'readAll':
          return secureStorageValues;
        case 'containsKey':
          return key != null && secureStorageValues.containsKey(key);
        default:
          return null;
      }
    });
  });

  setUp(() async {
    tempDirectory = Directory.systemTemp.createTempSync('ventio_test_');
    await Hive.initFlutter(tempDirectory.path);
    secureStorageValues.clear();
    SharedPreferences.setMockInitialValues({});
    await LocalDatabaseService.resetForTesting();
  });

  tearDown(() async {
    await LocalDatabaseService.resetForTesting();
    await Hive.close();
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('AppStore initializes and authenticates admin user', () async {
    await LocalDatabaseService.initialize();
    final store = AppStore();
    await store.initialize();

    expect(store.isReady, isTrue);
    expect(store.users, hasLength(1));
    expect(store.users.first.username.toLowerCase(), 'admin');
    expect(store.activeUser, isNull);
    expect(store.canManageProducts, isTrue);
    expect(store.isAdmin, isFalse);

    final loginSuccess = await store.login('admin', 'admin123');
    expect(loginSuccess, isTrue);
    expect(store.activeUser, isNotNull);
    expect((store.activeUser?.username ?? '').toLowerCase(), 'admin');
    expect(store.currentRole.toLowerCase(), 'admin');

    await store.logout();
    expect(store.activeUser, isNull);
  });

  test('AppStore manages products, customers, suppliers, purchases, sales and expenses', () async {
    await LocalDatabaseService.initialize();
    final store = AppStore();
    await store.initialize();

    final product = Product(
      id: 'product-1',
      name: 'Widget',
      code: 'W123',
      price: 100.0,
      cost: 50.0,
      stock: 100,
      category: 'Gadgets',
    );
    await store.addOrUpdateProduct(product);
    expect(store.products, hasLength(1));
    expect(store.products.first.stock, 100);

    final customer = Customer(
      id: 'customer-1',
      name: 'Test Customer',
      phone: '1234567890',
      address: '123 Store St',
    );
    await store.addOrUpdateCustomer(customer);
    expect(store.customers, hasLength(2));
    expect(store.customers.any((item) => item.id == AppStore.walkInCustomerId), isTrue);
    expect(store.customers.any((item) => item.name == 'Test Customer'), isTrue);

    final supplier = Supplier(
      id: 'supplier-1',
      name: 'Test Supplier',
      phone: '0987654321',
      address: '456 Supply Rd',
      notes: 'Preferred supplier',
    );
    await store.addOrUpdateSupplier(supplier);
    expect(store.suppliers, hasLength(1));
    expect(store.suppliers.first.name, 'Test Supplier');

    final expense = Expense(
      id: 'expense-1',
      title: 'Office expense',
      category: 'Operations',
      amount: 50.0,
      date: DateTime.now(),
      notes: 'Monthly subscription',
    );
    await store.addOrUpdateExpense(expense);
    expect(store.expenses, hasLength(1));
    expect(store.totalExpensesAmount, 50.0);

    final purchase = await store.createPurchase(
      supplierId: supplier.id,
      supplierName: supplier.name,
      items: [
        PurchaseItem(
          productId: product.id,
          productName: product.name,
          quantity: 15,
          unitCost: 50.0,
        ),
      ],
      receiveNow: true,
    );

    expect(store.purchases, hasLength(1));
    expect(store.purchases.first.id, purchase.id);
    expect(store.products.first.stock, 115);
    expect(store.totalPurchasesAmount, 750.0);

    final sale = await store.createSale(
      customerName: customer.name,
      items: [
        SaleItem(
          productId: product.id,
          productName: product.name,
          unitPrice: 100.0,
          quantity: 5,
        ),
      ],
    );

    expect(store.sales, hasLength(1));
    expect(store.sales.first.id, sale.id);
    expect(store.products.first.stock, 110);
    expect(store.totalSalesAmount, 500.0);
    expect(store.estimateProfit(), closeTo(200.0, 1.0));

    await store.cancelSale(sale.id);
    expect(store.sales.first.isCancelled, isTrue);
    expect(store.products.first.stock, 115);
    expect(store.totalSalesAmount, 0.0);

    final snapshot = store.exportSyncSnapshotJson();
    expect(snapshot, contains('"products"'));
  });

  testWidgets('PinLockPage displays initial admin setup and unlocks after setup', (WidgetTester tester) async {
    print('test start');
    await LocalDatabaseService.initialize();
    print('db initialized');
    final store = AppStore();
    await store.initialize();
    print('store initialized');

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: PinLockPage(store: store, child: const Text('Unlocked')),
    ));
    print('widget pumped');

    await tester.pumpAndSettle();
    print('pumpAndSettle done');
    expect(find.text('Welcome to Ventio'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Admin name'), 'Test Admin');
    await tester.enterText(find.widgetWithText(TextField, 'New username'), 'admin2');
    await tester.enterText(find.widgetWithText(TextField, 'New password'), 'admin456');
    await tester.enterText(find.widgetWithText(TextField, 'Confirm password'), 'admin456');
    print('fields filled');

    await tester.tap(find.text('Start using Ventio'));
    print('button tapped');
    await tester.pump();
    print('first pump after tap');

    // Wait manually for the async setup flow to complete.
    for (var i = 0; i < 20; i++) {
      print('pump loop $i');
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('Unlocked').evaluate().isNotEmpty) {
        print('unlocked found');
        break;
      }
    }

    print('after pump loop');
    expect(find.text('Unlocked'), findsOneWidget);
    expect(store.activeUser?.username, 'admin2');
  });

  test('AppLocalizations loads Arabic translation strings', () async {
    final localizations = AppLocalizations(const Locale('ar'));
    await localizations.load();

    expect(localizations.text('dashboard'), 'لوحة التحكم');
    expect(localizations.text('settings'), 'الإعدادات');
  });
}
