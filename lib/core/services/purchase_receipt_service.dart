import '../../models/inventory_batch.dart';
import '../../models/purchase.dart';
import '../../models/purchase_item.dart';

/// Builds the versioned purchase receipt command before its atomic posting.
///
/// This keeps receipt status, initial payment, line allocations, and idempotency
/// identity together while SQLite coordinates the stock and accounting writes.
class PurchaseReceiptService {
  const PurchaseReceiptService();

  double plannedInitialPayment(
    Purchase purchase, {
    required bool settleInitialPayment,
  }) {
    if (!settleInitialPayment) return 0.0;
    if (purchase.paidAmount > 0) {
      return purchase.paidAmount.clamp(0, purchase.subtotal).toDouble();
    }
    return purchase.paymentStatus.trim().toLowerCase() == 'paid'
        ? purchase.subtotal
        : 0.0;
  }

  PurchaseReceiptPlan prepare({
    required Purchase purchase,
    required DateTime now,
    required bool settleInitialPayment,
    required Map<int, List<BatchAllocation>> batchAllocationsByLine,
    required String deviceId,
    required String storeId,
    required String branchId,
  }) {
    final plannedPayment = plannedInitialPayment(
      purchase,
      settleInitialPayment: settleInitialPayment,
    );
    final receivedItems = purchase.items.indexed.map((entry) {
      final allocations = batchAllocationsByLine[entry.$1];
      if (allocations == null) return entry.$2;
      final item = entry.$2;
      return PurchaseItem(
        lineId: item.lineId,
        productId: item.productId,
        productName: item.productName,
        quantity: item.quantity,
        unitCost: item.unitCost,
        purchaseUnitId: item.purchaseUnitId,
        purchaseUnitName: item.purchaseUnitName,
        conversionToBase: item.conversionToBase,
        originalUnitCost: item.originalUnitCost,
        unitCostCurrency: item.unitCostCurrency,
        exchangeRateAtEntry: item.exchangeRateAtEntry,
        batchAllocations: allocations,
      );
    }).toList(growable: false);
    final received = purchase.copyWith(
      status: 'Received',
      items: receivedItems,
      paidAmount: settleInitialPayment ? 0 : purchase.paidAmount,
      paymentStatus: plannedPayment > 0 ? 'credit' : purchase.paymentStatus,
      updatedAt: now,
      deviceId: deviceId,
      syncStatus: 'pending',
      storeId: storeId,
      branchId: branchId,
      version: purchase.version + 1,
      lastModifiedByDeviceId: deviceId,
      clearDeletedAt: true,
    );
    return PurchaseReceiptPlan(
      purchase: received,
      plannedPayment: plannedPayment,
      idempotencyKey: '${purchase.id}:purchase_receive:v${purchase.version}',
    );
  }
}

class PurchaseReceiptPlan {
  const PurchaseReceiptPlan({
    required this.purchase,
    required this.plannedPayment,
    required this.idempotencyKey,
  });

  final Purchase purchase;
  final double plannedPayment;
  final String idempotencyKey;
}
