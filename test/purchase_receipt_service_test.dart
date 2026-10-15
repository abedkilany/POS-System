import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/purchase_receipt_service.dart';
import 'package:ventio/models/inventory_batch.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/purchase_item.dart';

void main() {
  const service = PurchaseReceiptService();

  Purchase draft({
    double paidAmount = 0,
    String paymentStatus = 'credit',
  }) =>
      Purchase(
        id: 'purchase-receipt-1',
        purchaseNo: 'PO-receipt-1',
        supplierId: 'supplier-1',
        supplierName: 'Supplier',
        date: DateTime(2026, 1, 1),
        status: 'Draft',
        items: const <PurchaseItem>[
          PurchaseItem(
            lineId: 'purchase-receipt-1:pl:0',
            productId: 'product-1',
            productName: 'Product',
            quantity: 2,
            unitCost: 10,
          ),
        ],
        paidAmount: paidAmount,
        paymentStatus: paymentStatus,
      );

  test('prepares a versioned receipt while preserving batch allocations', () {
    final source = draft(paymentStatus: 'paid');
    const allocation = BatchAllocation(batchId: 'batch-1', quantity: 2);
    final plan = service.prepare(
      purchase: source,
      now: DateTime(2026, 2, 1),
      settleInitialPayment: true,
      batchAllocationsByLine: const <int, List<BatchAllocation>>{
        0: <BatchAllocation>[allocation],
      },
      deviceId: 'device-1',
      storeId: 'store-1',
      branchId: 'branch-1',
    );

    expect(plan.plannedPayment, 20);
    expect(plan.purchase.status, 'Received');
    expect(plan.purchase.version, 2);
    expect(plan.purchase.paidAmount, 0);
    expect(plan.purchase.paymentStatus, 'credit');
    expect(plan.purchase.items.single.batchAllocations, <BatchAllocation>[
      allocation,
    ]);
    expect(plan.idempotencyKey, 'purchase-receipt-1:purchase_receive:v1');
    expect(source.status, 'Draft');
    expect(source.items.single.batchAllocations, isEmpty);
  });

  test('does not invent an initial payment when settling is disabled', () {
    final source = draft(paidAmount: 7, paymentStatus: 'partial');
    final plan = service.prepare(
      purchase: source,
      now: DateTime(2026, 2, 1),
      settleInitialPayment: false,
      batchAllocationsByLine: const <int, List<BatchAllocation>>{},
      deviceId: 'device-1',
      storeId: 'store-1',
      branchId: 'branch-1',
    );

    expect(plan.plannedPayment, 0);
    expect(plan.purchase.paidAmount, 7);
    expect(plan.purchase.paymentStatus, 'partial');
  });
}
