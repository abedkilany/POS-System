import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/purchase_draft_service.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/purchase_item.dart';

void main() {
  const service = PurchaseDraftService();

  Purchase draft({int version = 1}) => Purchase(
        id: 'purchase_draft_1',
        purchaseNo: 'PO-draft-1',
        supplierId: 'supplier-1',
        supplierName: 'Supplier',
        date: DateTime(2026, 1, 1),
        status: 'Draft',
        items: const <PurchaseItem>[
          PurchaseItem(
            lineId: 'purchase_draft_1:pl:0',
            productId: 'product-1',
            productName: 'Product',
            quantity: 2,
            unitCost: 10,
          ),
        ],
        version: version,
      );

  test('validates purchase draft lines and product references', () {
    expect(
      () => service.validateItems(
        const <PurchaseItem>[],
        productExists: (_) => true,
      ),
      throwsArgumentError,
    );
    expect(
      () => service.validateItems(
        const <PurchaseItem>[
          PurchaseItem(
            productId: 'missing',
            productName: 'Missing product',
            quantity: 1,
            unitCost: 2,
          ),
        ],
        productExists: (_) => false,
      ),
      throwsArgumentError,
    );
  });

  test('draft edit preserves known lines and assigns unique new identities',
      () {
    final now = DateTime(2026, 2, 1);
    final updated = service.updateDraft(
      current: draft(),
      expectedVersion: 1,
      supplierId: 'supplier-2',
      supplierName: '',
      items: const <PurchaseItem>[
        PurchaseItem(
          lineId: 'purchase_draft_1:pl:0',
          productId: 'product-1',
          productName: 'Product',
          quantity: 3,
          unitCost: 8,
        ),
        PurchaseItem(
          lineId: 'copied-line-from-template',
          productId: 'product-2',
          productName: 'Other product',
          quantity: 1,
          unitCost: 5,
        ),
      ],
      paymentStatus: 'partial',
      paymentMethod: '  ',
      paidAmount: 2,
      warehouseId: 'warehouse-2',
      warehouseName: 'Warehouse 2',
      now: now,
      deviceId: 'device-1',
      storeId: 'store-1',
      branchId: 'branch-1',
    );

    expect(updated.version, 2);
    expect(updated.supplierName, 'Supplier');
    expect(updated.paymentStatus, 'credit');
    expect(updated.paymentMethod, 'Cash');
    expect(updated.paidAmount, 0);
    expect(updated.items.first.lineId, 'purchase_draft_1:pl:0');
    expect(updated.items.last.lineId, isNot('copied-line-from-template'));
    expect(updated.items.map((item) => item.lineId).toSet(), hasLength(2));
    expect(updated.updatedAt, now);
    expect(updated.lastModifiedByDeviceId, 'device-1');
  });

  test('draft edit rejects stale versions and received invoices', () {
    final arguments = <String, Object?>{
      'current': draft(),
      'expectedVersion': 2,
      'supplierId': 'supplier-1',
      'supplierName': 'Supplier',
      'items': const <PurchaseItem>[
        PurchaseItem(
          productId: 'product-1',
          productName: 'Product',
          quantity: 1,
          unitCost: 1,
        ),
      ],
      'paymentStatus': 'credit',
      'paymentMethod': 'Cash',
      'paidAmount': null,
      'warehouseId': 'main',
      'warehouseName': 'Main',
      'now': DateTime(2026, 2, 1),
      'deviceId': 'device-1',
      'storeId': 'store-1',
      'branchId': 'branch-1',
    };
    expect(
      () => service.updateDraft(
        current: arguments['current']! as Purchase,
        expectedVersion: arguments['expectedVersion']! as int,
        supplierId: arguments['supplierId']! as String,
        supplierName: arguments['supplierName']! as String,
        items: arguments['items']! as List<PurchaseItem>,
        paymentStatus: arguments['paymentStatus']! as String,
        paymentMethod: arguments['paymentMethod']! as String,
        paidAmount: arguments['paidAmount'] as double?,
        warehouseId: arguments['warehouseId']! as String,
        warehouseName: arguments['warehouseName']! as String,
        now: arguments['now']! as DateTime,
        deviceId: arguments['deviceId']! as String,
        storeId: arguments['storeId']! as String,
        branchId: arguments['branchId']! as String,
      ),
      throwsStateError,
    );
  });

  test('soft delete keeps the audit row and advances sync metadata', () {
    final now = DateTime(2026, 3, 1);
    final deleted = service.softDeleteDraft(
      current: draft(),
      now: now,
      deviceId: 'device-1',
      storeId: 'store-1',
      branchId: 'branch-1',
    );

    expect(deleted.deletedAt, now);
    expect(deleted.version, 2);
    expect(deleted.syncStatus, 'pending');
    expect(deleted.deviceId, 'device-1');
    expect(
      () => service.softDeleteDraft(
        current: draft().copyWith(status: 'Received'),
        now: now,
        deviceId: 'device-1',
        storeId: 'store-1',
        branchId: 'branch-1',
      ),
      throwsStateError,
    );
  });
}
