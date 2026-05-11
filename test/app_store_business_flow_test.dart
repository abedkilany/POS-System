import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/sync_change.dart';


const MethodChannel _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
Directory? _testDocumentsDirectory;

Future<void> _installPathProviderMock() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  _testDocumentsDirectory ??= await Directory.systemTemp.createTemp('ventio_app_store_tests_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    _pathProviderChannel,
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationDocumentsPath':
          return _testDocumentsDirectory!.path;
        case 'getTemporaryDirectory':
        case 'getTemporaryPath':
          return _testDocumentsDirectory!.path;
        case 'getApplicationSupportDirectory':
        case 'getApplicationSupportPath':
          return _testDocumentsDirectory!.path;
        default:
          return _testDocumentsDirectory!.path;
      }
    },
  );
}

Future<AppStore> freshStore({AppIdentity? identity}) async {
  await _installPathProviderMock();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  await LocalDatabaseService.initialize();
  await Hive.box<String>(LocalDatabaseService.boxName).clear();

  final store = AppStore();
  await store.initialize();
  if (identity != null) {
    await store.updateAppIdentity(identity);
  }
  return store;
}

Product testProduct({
  String id = 'p-coffee',
  String name = 'Coffee',
  String code = 'SKU-COFFEE',
  String barcode = 'BAR-COFFEE',
  double price = 10,
  double cost = 4,
  int stock = 10,
}) {
  return Product(
    id: id,
    name: name,
    code: code,
    barcode: barcode,
    price: price,
    cost: cost,
    stock: stock,
    category: 'Drinks',
  );
}

void main() {
  setUpAll(() async {
    await _installPathProviderMock();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_pathProviderChannel, null);
    await Hive.close();
    final dir = _testDocumentsDirectory;
    if (dir != null && dir.existsSync()) {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await dir.delete(recursive: true);
          break;
        } on FileSystemException {
          if (attempt == 2) {
            // Windows can keep a recently-closed Hive file locked briefly.
            // Cleanup failure should not make the business-flow tests fail.
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }
  });

  group('AppStore product validation and sync recording', () {
    test('adds product with sync metadata and pending product change', () async {
      final store = await freshStore();

      await store.addOrUpdateProduct(testProduct());

      expect(store.products, hasLength(1));
      expect(store.products.single.syncStatus, 'pending');
      expect(store.products.single.version, 1);
      expect(store.syncChanges.where((change) => change.entityType == 'product'), hasLength(1));
      expect(store.syncChanges.last.operation, 'create');
      expect(store.syncChanges.last.sequence, greaterThan(0));
    });

    test('rejects duplicate product code and duplicate non-empty barcode', () async {
      final store = await freshStore();
      await store.addOrUpdateProduct(testProduct());

      await expectLater(
        store.addOrUpdateProduct(testProduct(id: 'p-copy-code', barcode: 'BAR-OTHER')),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        store.addOrUpdateProduct(testProduct(id: 'p-copy-barcode', code: 'SKU-OTHER')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('soft-deleted product is hidden from product list but retained in sync change payload', () async {
      final store = await freshStore();
      await store.addOrUpdateProduct(testProduct());

      await store.deleteProduct('p-coffee');

      expect(store.products, isEmpty);
      expect(store.syncChanges.last.entityType, 'product');
      expect(store.syncChanges.last.operation, 'delete');
      expect(store.syncChanges.last.payload['deletedAt'], isNotNull);
    });
  });

  group('AppStore sales, purchases, and stock movements', () {
    test('sale decreases stock, captures unit cost, records sale and movement changes', () async {
      final store = await freshStore();
      await store.addOrUpdateProduct(testProduct(stock: 10, cost: 4));

      final sale = await store.createSale(
        customerName: 'Walk-in Customer',
        discount: 1,
        items: const [SaleItem(productId: 'p-coffee', productName: 'Coffee', unitPrice: 10, quantity: 3)],
      );

      expect(sale.total, 29);
      expect(sale.grossProfit, 17);
      expect(sale.items.single.unitCost, 4);
      expect(store.products.single.stock, 7);
      expect(store.stockMovements.where((m) => m.type == 'sale' && m.quantity == -3), hasLength(1));
      expect(store.syncChanges.where((c) => c.entityType == 'sale' && c.entityId == sale.id), hasLength(1));
      expect(store.syncChanges.where((c) => c.entityType == 'stock_movement' && c.operation == 'sale'), hasLength(1));
    });

    test('sale validation rejects empty items, negative discount, over-discount, and insufficient stock', () async {
      final store = await freshStore();
      await store.addOrUpdateProduct(testProduct(stock: 2));

      await expectLater(store.createSale(customerName: 'A', items: const []), throwsA(isA<ArgumentError>()));
      await expectLater(
        store.createSale(
          customerName: 'A',
          discount: -1,
          items: const [SaleItem(productId: 'p-coffee', productName: 'Coffee', unitPrice: 10, quantity: 1)],
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        store.createSale(
          customerName: 'A',
          discount: 99,
          items: const [SaleItem(productId: 'p-coffee', productName: 'Coffee', unitPrice: 10, quantity: 1)],
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        store.createSale(
          customerName: 'A',
          items: const [SaleItem(productId: 'p-coffee', productName: 'Coffee', unitPrice: 10, quantity: 3)],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cancel sale restores stock once and is idempotent on repeated cancellation', () async {
      final store = await freshStore();
      await store.addOrUpdateProduct(testProduct(stock: 10));
      final sale = await store.createSale(
        customerName: 'A',
        items: const [SaleItem(productId: 'p-coffee', productName: 'Coffee', unitPrice: 10, quantity: 4)],
      );

      await store.cancelSale(sale.id);
      await store.cancelSale(sale.id);

      expect(store.sales.single.isCancelled, isTrue);
      expect(store.products.single.stock, 10);
      expect(store.stockMovements.where((m) => m.type == 'sale_restore'), hasLength(1));
      expect(store.totalSalesAmount, 0);
    });

    test('received purchase increases stock, updates product cost, and cancellation reverses stock', () async {
      final store = await freshStore();
      await store.addOrUpdateProduct(testProduct(stock: 5, cost: 4));

      final purchase = await store.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier One',
        items: const [PurchaseItem(productId: 'p-coffee', productName: 'Coffee', quantity: 6, unitCost: 5.5)],
        receiveNow: true,
      );

      expect(purchase.isReceived, isTrue);
      expect(store.products.single.stock, 11);
      expect(store.products.single.cost, 5.5);
      expect(store.stockMovements.where((m) => m.type == 'purchase_receive' && m.quantity == 6), hasLength(1));

      await store.cancelPurchase(purchase.id);

      expect(store.purchases.single.isCancelled, isTrue);
      expect(store.products.single.stock, 5);
      expect(store.stockMovements.where((m) => m.type == 'purchase_cancel' && m.quantity == -6), hasLength(1));
    });

    test('draft purchase does not change stock until receivePurchase is called', () async {
      final store = await freshStore();
      await store.addOrUpdateProduct(testProduct(stock: 5));

      final purchase = await store.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier One',
        items: const [PurchaseItem(productId: 'p-coffee', productName: 'Coffee', quantity: 2, unitCost: 6)],
        receiveNow: false,
      );

      expect(purchase.status, 'Draft');
      expect(store.products.single.stock, 5);
      expect(store.pendingPurchaseCount, 1);

      await store.receivePurchase(purchase.id);

      expect(store.products.single.stock, 7);
      expect(store.pendingPurchaseCount, 0);
    });
  });

  group('AppStore backup and sync behavior', () {
    test('encrypted backup round-trips and rejects wrong password', () async {
      final store = await freshStore();
      await store.addOrUpdateProduct(testProduct(stock: 3));

      final encrypted = store.exportEncryptedBackupJson('strong-pass');

      expect(encrypted, contains('\"data\"'));
      expect(encrypted, contains('\"mac\"'));
      expect(encrypted, contains('\"salt\"'));
      expect(store.decryptBackupJson(encrypted, 'strong-pass'), contains('SKU-COFFEE'));
      expect(() => store.decryptBackupJson(encrypted, 'wrong-pass'), throwsA(isA<ArgumentError>()));
    });

    test('importBackupJson restores business data into a clean store', () async {
      final source = await freshStore();
      await source.addOrUpdateProduct(testProduct(stock: 12));
      final backup = source.exportBackupJson();

      final target = await freshStore();
      await target.importBackupJson(backup);

      expect(target.products, hasLength(1));
      expect(target.products.single.code, 'SKU-COFFEE');
      expect(target.products.single.stock, 12);
    });

    test('applyRemoteSyncChanges ignores duplicate change ids and older store epochs', () async {
      final identity = AppIdentity(
        storeId: 'store-1',
        branchId: 'main',
        deviceId: 'host-1',
        deviceName: 'Host',
        platform: AppPlatformType.windows,
        deviceRole: DeviceRole.host,
        appRole: AppRole.store,
        syncMode: SyncMode.lanOnly,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        storeEpoch: 2,
      );
      final store = await freshStore(identity: identity);
      final product = testProduct(id: 'remote-product', code: 'REMOTE-1', barcode: '', stock: 1).toJson();

      final olderEpochChange = SyncChange(
        id: 'old-epoch',
        entityType: 'product',
        entityId: 'remote-product',
        operation: 'create',
        deviceId: 'client-1',
        createdAt: DateTime.utc(2026, 1, 1),
        payload: product,
        storeId: 'store-1',
        branchId: 'main',
        storeEpoch: 1,
        sequence: 1,
      );
      final accepted = olderEpochChange.copyWith(id: 'accepted', storeEpoch: 2, sequence: 2);

      await store.applyRemoteSyncChanges([olderEpochChange, accepted, accepted]);

      expect(store.products.where((p) => p.id == 'remote-product'), hasLength(1));
      expect(store.syncChanges.where((c) => c.id == 'accepted'), hasLength(1));
      expect(store.syncChanges.where((c) => c.id == 'old-epoch'), isEmpty);
    });
  });
}
