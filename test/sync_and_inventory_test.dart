import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/sync_change.dart';

bool shouldApplyIncoming({
  required int incomingVersion,
  required DateTime incomingUpdatedAt,
  required int currentVersion,
  required DateTime currentUpdatedAt,
}) {
  if (incomingVersion != currentVersion) {
    return incomingVersion > currentVersion;
  }
  return incomingUpdatedAt.isAfter(currentUpdatedAt);
}

List<StockMovement> dedupeStockMovements(Iterable<StockMovement> movements) {
  final seen = <String>{};
  final result = <StockMovement>[];
  for (final movement in movements) {
    if (seen.add(movement.id)) {
      result.add(movement);
    }
  }
  return result;
}

void main() {
  group('inventory calculations', () {
    test('sale totals and profit use captured item cost', () {
      final sale = Sale(
        id: 'sale-1',
        invoiceNo: 'INV-1',
        customerName: 'Walk-in Customer',
        date: DateTime.utc(2026, 1, 1),
        status: 'Paid',
        discount: 5,
        items: const [
          SaleItem(productId: 'p1', productName: 'Coffee', unitPrice: 10, quantity: 3, unitCost: 4),
          SaleItem(productId: 'p2', productName: 'Tea', unitPrice: 8, quantity: 2, unitCost: 3),
        ],
      );

      expect(sale.subtotal, 46);
      expect(sale.total, 41);
      expect(sale.grossProfit, 23);
    });

    test('cancelled sale contributes zero total and zero profit', () {
      final sale = Sale(
        id: 'sale-2',
        invoiceNo: 'INV-2',
        customerName: 'Walk-in Customer',
        date: DateTime.utc(2026, 1, 1),
        status: 'Cancelled',
        discount: 0,
        items: const [SaleItem(productId: 'p1', productName: 'Coffee', unitPrice: 10, quantity: 3, unitCost: 4)],
      );

      expect(sale.isCancelled, isTrue);
      expect(sale.total, 0);
      expect(sale.grossProfit, 0);
    });

    test('stock movement ids are idempotent when merged', () {
      final first = StockMovement(
        id: 'sale-1-p1-sale',
        productId: 'p1',
        productName: 'Coffee',
        type: 'sale',
        quantity: -2,
        date: DateTime.utc(2026, 1, 1),
      );
      final duplicate = first.copyWith(syncStatus: 'synced');
      final restore = StockMovement(
        id: 'sale-1-p1-sale-restore',
        productId: 'p1',
        productName: 'Coffee',
        type: 'sale_restore',
        quantity: 2,
        date: DateTime.utc(2026, 1, 2),
      );

      final merged = dedupeStockMovements([first, duplicate, restore]);

      expect(merged.map((item) => item.id), ['sale-1-p1-sale', 'sale-1-p1-sale-restore']);
      expect(merged.fold<int>(0, (sum, item) => sum + item.quantity), 0);
    });
  });

  group('sync conflict rules', () {
    test('newer version wins over older version even if timestamp is older', () {
      final apply = shouldApplyIncoming(
        incomingVersion: 3,
        incomingUpdatedAt: DateTime.utc(2026, 1, 1),
        currentVersion: 2,
        currentUpdatedAt: DateTime.utc(2026, 2, 1),
      );

      expect(apply, isTrue);
    });

    test('older version is rejected even if timestamp is newer', () {
      final apply = shouldApplyIncoming(
        incomingVersion: 1,
        incomingUpdatedAt: DateTime.utc(2026, 2, 1),
        currentVersion: 2,
        currentUpdatedAt: DateTime.utc(2026, 1, 1),
      );

      expect(apply, isFalse);
    });

    test('same version falls back to updatedAt comparison', () {
      final apply = shouldApplyIncoming(
        incomingVersion: 2,
        incomingUpdatedAt: DateTime.utc(2026, 2, 1),
        currentVersion: 2,
        currentUpdatedAt: DateTime.utc(2026, 1, 1),
      );

      expect(apply, isTrue);
    });
  });

  group('sync serialization', () {
    test('sync change round-trips payload and sequence metadata', () {
      final change = SyncChange(
        id: 'change-1',
        entityType: 'product',
        entityId: 'p1',
        operation: 'update',
        deviceId: 'device-a',
        createdAt: DateTime.utc(2026, 1, 1, 12),
        payload: {'id': 'p1', 'name': 'Coffee', 'version': 4},
        storeId: 'store-1',
        branchId: 'main',
        storeEpoch: 2,
        sequence: 42,
      );

      final decoded = SyncChange.fromJson(change.toJson());

      expect(decoded.id, change.id);
      expect(decoded.payload['name'], 'Coffee');
      expect(decoded.storeEpoch, 2);
      expect(decoded.sequence, 42);
    });

    test('product json preserves sync metadata', () {
      final updatedAt = DateTime.utc(2026, 1, 2);
      final product = Product(
        id: 'p1',
        name: 'Coffee',
        code: 'SKU-1',
        price: 10,
        cost: 4,
        stock: 7,
        category: 'Drinks',
        updatedAt: updatedAt,
        syncStatus: 'pending',
        storeId: 'store-1',
        branchId: 'main',
        version: 5,
        lastModifiedByDeviceId: 'device-a',
      );

      final decoded = Product.fromJson(product.toJson());

      expect(decoded.stock, 7);
      expect(decoded.version, 5);
      expect(decoded.syncStatus, 'pending');
      expect(decoded.lastModifiedByDeviceId, 'device-a');
      expect(decoded.updatedAt, updatedAt);
    });
  });
}
