import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/features/dashboard/dashboard_service.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/supplier.dart';

Future<AppStore> _readyStore() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final secureStorageChannel =
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStorage = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async {
    switch (call.method) {
      case 'read':
        return secureStorage[call.arguments['key'] as String];
      case 'write':
        secureStorage[call.arguments['key'] as String] =
            call.arguments['value'] as String? ?? '';
        return null;
      case 'delete':
        secureStorage.remove(call.arguments['key'] as String);
        return null;
      case 'containsKey':
        return secureStorage.containsKey(call.arguments['key'] as String);
      case 'readAll':
        return secureStorage;
      case 'deleteAll':
        secureStorage.clear();
        return null;
      default:
        return null;
    }
  });
  LocalDatabaseService.clearInMemoryStoreForTesting();
  await SqliteMigrationManager.initializeFreshSqlite();
  await LocalDatabaseService.useSqliteDatabaseForTesting(
    SqliteMigrationManager.database!,
  );
  await LocalDatabaseService.initialize();
  final store = AppStore();
  await store.initialize();
  await store.factoryResetLocalDevice(enforcePermission: false);
  await store.recoverOnlineStoreOwnerIdentity(
    storeId: 'ST-DASH01',
    branchId: 'BR-DASH01',
    storeName: 'Dashboard Store',
    username: 'admin',
    password: 'AdminPass123',
    deviceRole: DeviceRole.host,
    syncMode: SyncMode.localOnly,
  );
  await store.addOrUpdateProduct(
    Product(
      id: 'p1',
      name: 'Coffee',
      code: 'COF',
      price: 10,
      cost: 4,
      usdCost: 4,
      originalCost: 4,
      stock: 0,
      lowStockThreshold: 5,
      category: 'Drinks',
    ),
  );
  await store.adjustStock(
    productId: 'p1',
    warehouseId: 'main',
    quantityDelta: 3,
    reason: 'dashboard test opening stock',
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
      notes: '',
    ),
  );
  await store.addOrUpdateExpense(
    Expense(
      id: 'e1',
      title: 'Rent',
      category: 'Office',
      amount: 25,
      date: DateTime.now(),
      notes: '',
    ),
  );
  await store.postExpense('e1', paidInCash: false);
  await store.createSale(
    customerId: 'c1',
    customerName: 'Alice',
    paymentStatus: 'credit',
    paymentMethod: 'Credit',
    items: const [
      SaleItem(
        productId: 'p1',
        productName: 'Coffee',
        unitPrice: 10,
        quantity: 1,
      ),
    ],
  );
  await store.createPurchase(
    supplierId: 's1',
    supplierName: 'Supplier',
    receiveNow: false,
    paymentStatus: 'credit',
    paymentMethod: 'Credit',
    items: const [
      PurchaseItem(
        productId: 'p1',
        productName: 'Coffee',
        quantity: 2,
        unitCost: 5,
      ),
    ],
  );
  return store;
}

void main() {
  group('DashboardService', () {
    tearDown(LocalDatabaseService.clearInMemoryStoreForTesting);
    test('builds a dashboard snapshot without widget-side calculations',
        () async {
      final store = await _readyStore();
      final service = DashboardService();
      final state = await service.buildState(store);
      final incomeStatement = await AccountingService.incomeStatementReport();

      expect(state.storeName, isNotEmpty);
      expect(state.todaySalesTotal, 10);
      expect(state.todayInvoiceCount, 1);
      expect(state.lowStockCount, 1);
      expect(state.todayProfitTotal, -19);
      expect(state.alerts, isNotEmpty);
      expect(state.financialSummary.length, 10);
      expect(
        state.financialSummary
            .firstWhere((item) => item.key == 'profit')
            .amount,
        incomeStatement.netProfit,
      );
      expect(
        state.financialSummary
            .firstWhere((item) => item.key == 'expenses')
            .amount,
        incomeStatement.expenses,
      );
      expect(
        state.financialSummary
            .firstWhere((item) => item.key == 'purchases')
            .amount,
        store.totalPurchasesAmount,
      );
      expect(state.charts, isNotEmpty);
      expect(state.recentOperations, isNotEmpty);
      expect(state.recentOperations.length, 5);
      expect(state.recentOperations.map((item) => item.type),
          contains(DashboardOperationType.sale));
      expect(state.recentOperations.map((item) => item.type),
          contains(DashboardOperationType.purchase));
      expect(state.syncStatus.pendingCount, store.pendingSyncCount);
      expect(state.backupStatus.isRunning, isFalse);
      expect(state.generatedAt, isNotNull);
    });
  });
}
