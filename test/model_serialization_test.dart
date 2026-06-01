import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/catalog_item.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/store_profile.dart';
import 'package:ventio/models/supplier.dart';
import 'package:ventio/models/sync_change.dart';
import 'package:ventio/models/sync_queue_item.dart';
import 'package:ventio/models/user_role.dart';

void main() {
  final created = DateTime.utc(2026, 1, 1, 10);
  final updated = DateTime.utc(2026, 1, 2, 11);

  group('JSON round trips', () {
    test('Product round trip preserves pricing, stock, and sync metadata', () {
      final product = Product(id: 'p1', name: 'Coffee', code: 'C001', price: 10, cost: 6, stock: 5, category: 'Drinks', barcode: '123', createdAt: created, updatedAt: updated, deviceId: 'd1', storeId: 'store', branchId: 'main', version: 3);
      final decoded = Product.fromJson(product.toJson());

      expect(decoded.id, product.id);
      expect(decoded.barcode, '123');
      expect(decoded.price, 10);
      expect(decoded.cost, 6);
      expect(decoded.stock, 5);
      expect(decoded.version, 3);
    });

    test('Sale round trip preserves nested items and totals', () {
      final sale = Sale(id: 'sale1', invoiceNo: 'INV-1', customerName: 'Customer', date: created, status: 'Paid', items: const [SaleItem(productId: 'p1', productName: 'Coffee', unitPrice: 10, quantity: 2, unitCost: 4)], discount: 2, createdAt: created, updatedAt: updated);
      final decoded = Sale.fromJson(sale.toJson());

      expect(decoded.items, hasLength(1));
      expect(decoded.total, 18);
      expect(decoded.grossProfit, 10);
    });

    test('Purchase round trip preserves nested items and totals', () {
      final purchase = Purchase(id: 'po1', purchaseNo: 'PO-1', supplierId: 'sup1', supplierName: 'Supplier', date: created, status: 'Received', items: const [PurchaseItem(productId: 'p1', productName: 'Beans', quantity: 3, unitCost: 7)], createdAt: created, updatedAt: updated);
      final decoded = Purchase.fromJson(purchase.toJson());

      expect(decoded.isReceived, isTrue);
      expect(decoded.subtotal, 21);
      expect(decoded.totalUnits, 3);
    });

    test('Customer round trip preserves contact fields', () {
      final customer = Customer(id: 'c1', name: 'Alice', phone: '+961', address: 'Beirut', createdAt: created, updatedAt: updated);
      final decoded = Customer.fromJson(customer.toJson());

      expect(decoded.name, 'Alice');
      expect(decoded.phone, '+961');
      expect(decoded.address, 'Beirut');
    });

    test('Supplier round trip preserves bilingual names', () {
      final supplier = Supplier(id: 's1', name: 'Supplier', nameEn: 'Supplier', nameAr: 'مورّد', phone: '1', address: 'A', notes: 'N', createdAt: created, updatedAt: updated);
      final decoded = Supplier.fromJson(supplier.toJson());

      expect(decoded.name, 'Supplier');
      expect(decoded.nameEn, 'Supplier');
      expect(decoded.nameAr, 'مورّد');
    });

    test('Expense round trip preserves amount and date', () {
      final expense = Expense(id: 'e1', title: 'Rent', category: 'Fixed', amount: 250.75, date: created, notes: 'monthly', createdAt: created, updatedAt: updated);
      final decoded = Expense.fromJson(expense.toJson());

      expect(decoded.amount, 250.75);
      expect(decoded.date, created);
    });

    test('CatalogItem round trip preserves localized names and code', () {
      final item = CatalogItem(id: 'cat1', nameEn: 'Beverages', nameAr: 'مشروبات', code: 'bev', createdAt: created, updatedAt: updated);
      final decoded = CatalogItem.fromJson(item.toJson());

      expect(decoded.displayName('en'), 'Beverages');
      expect(decoded.displayName('ar'), 'مشروبات');
      expect(decoded.code, 'bev');
    });

    test('StockMovement round trip preserves reference and value', () {
      final movement = StockMovement(id: 'm1', productId: 'p1', productName: 'Coffee', type: 'sale', quantity: -2, date: created, referenceId: 'sale1', referenceNo: 'INV-1', unitCost: 4);
      final decoded = StockMovement.fromJson(movement.toJson());

      expect(decoded.referenceId, 'sale1');
      expect(decoded.referenceNo, 'INV-1');
      expect(decoded.value, 8);
    });

    test('StoreProfile round trip preserves receipt settings', () {
      const profile = StoreProfile(name: 'My Store', phone: '123', address: 'Street', currency: 'LBP', footerNote: 'Thanks');
      final decoded = StoreProfile.fromJson(profile.toJson());

      expect(decoded.name, 'My Store');
      expect(decoded.currency, 'LBP');
      expect(decoded.footerNote, 'Thanks');
    });

    test('AppUser round trip preserves permission overrides', () {
      final user = AppUser(id: 'u1', fullName: 'Cashier', username: 'cashier', passwordHash: 'hash', roleId: 'cashier', extraPermissions: {'reports.view'}, deniedPermissions: {'products.delete'}, createdAt: created);
      final decoded = AppUser.fromJson(user.toJson());

      expect(decoded.extraPermissions, contains('reports.view'));
      expect(decoded.deniedPermissions, contains('products.delete'));
      expect(decoded.isActive, isTrue);
    });

    test('UserRole round trip preserves permission set and admin flag', () {
      final role = UserRole(id: 'admin', name: 'Admin', permissions: AppPermission.all.toSet(), isSystem: true, createdAt: created);
      final decoded = UserRole.fromJson(role.toJson());

      expect(decoded.isAdmin, isTrue);
      expect(decoded.permissions, contains(AppPermission.salesCreate));
      expect(decoded.isSystem, isTrue);
    });

    test('AppIdentity round trip preserves platform and sync mode enums', () {
      final identity = AppIdentity(storeId: 'store', branchId: 'main', deviceId: 'dev', deviceName: 'Device', platform: AppPlatformType.windows, deviceRole: DeviceRole.host, appRole: AppRole.store, syncMode: SyncMode.cloudConnected, createdAt: created, updatedAt: updated, storeEpoch: 2);
      final decoded = AppIdentity.fromJson(identity.toJson());

      expect(decoded.isHost, isTrue);
      expect(decoded.isCloudEnabled, isTrue);
      expect(decoded.platform, AppPlatformType.windows);
      expect(decoded.storeEpoch, 2);
    });

    test('SyncChange round trip preserves payload and queue metadata', () {
      final change = SyncChange(id: 'chg1', entityType: 'product', entityId: 'p1', operation: 'update', deviceId: 'dev', createdAt: created, payload: {'name': 'Coffee'}, storeId: 'store', branchId: 'main', sequence: 5);
      final decoded = SyncChange.fromJson(change.toJson());

      expect(decoded.payload['name'], 'Coffee');
      expect(decoded.sequence, 5);
      expect(decoded.isSynced, isFalse);
    });

    test('SyncQueueItem round trip preserves retry status', () {
      final item = SyncQueueItem(id: 'q1', changeId: 'chg1', target: 'cloud', status: 'failed', attempts: 2, createdAt: created, updatedAt: updated, lastError: 'timeout', nextRetryAt: updated);
      final decoded = SyncQueueItem.fromJson(item.toJson());

      expect(decoded.isFailed, isTrue);
      expect(decoded.isPending, isTrue);
      expect(decoded.attempts, 2);
      expect(decoded.lastError, 'timeout');
    });
  });

  group('Defensive JSON defaults', () {
    test('Product prefers nameEn when name is missing', () {
      final product = Product.fromJson({'id': 'p1', 'nameEn': 'Coffee', 'price': 1, 'cost': 0, 'stock': 0});
      expect(product.name, 'Coffee');
      expect(product.category, 'General');
    });

    test('Supplier prefers nameEn/nameAr when name is missing', () {
      final supplier = Supplier.fromJson({'id': 's1', 'nameAr': 'مورّد'});
      expect(supplier.name, 'مورّد');
    });

    test('Purchase handles missing items as an empty list', () {
      final purchase = Purchase.fromJson({'id': 'po1'});
      expect(purchase.items, isEmpty);
      expect(purchase.subtotal, 0);
    });

    test('AppIdentity falls back for unknown enums', () {
      final identity = AppIdentity.fromJson({'platform': 'bad', 'deviceRole': 'bad', 'appRole': 'bad', 'syncMode': 'bad'});
      expect(identity.platform, AppPlatformType.unknown);
      expect(identity.deviceRole, DeviceRole.standalone);
      expect(identity.syncMode, SyncMode.localOnly);
    });
  });
}
