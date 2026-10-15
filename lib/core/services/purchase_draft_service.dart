import '../../models/purchase.dart';
import '../../models/purchase_item.dart';

/// Owns the domain rules for editing a purchase before it is received.
///
/// SQLite persistence, sync events, and post-receipt stock/accounting remain in
/// their respective owners. This service only constructs valid draft state.
class PurchaseDraftService {
  const PurchaseDraftService();

  void validateItems(
    Iterable<PurchaseItem> items, {
    required bool Function(String productId) productExists,
  }) {
    final list = items.toList(growable: false);
    if (list.isEmpty) {
      throw ArgumentError('Purchase must contain at least one item.');
    }
    for (final item in list) {
      if (item.quantity <= 0 ||
          item.conversionToBase <= 0 ||
          item.unitCost < 0) {
        throw ArgumentError('Invalid purchase item values.');
      }
      if (!productExists(item.productId)) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }
  }

  Purchase createPurchase({
    required String id,
    required String purchaseNo,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    required bool receiveNow,
    required String paymentStatus,
    required String paymentMethod,
    required double normalizedPaidAmount,
    required String warehouseId,
    required String warehouseName,
    required DateTime now,
    required String deviceId,
    required String storeId,
    required String branchId,
    String note = '',
  }) {
    final normalizedStatus = normalizePaymentStatus(paymentStatus);
    final normalizedMethod = normalizePaymentMethod(paymentMethod);
    final purchase = Purchase(
      id: id,
      purchaseNo: purchaseNo,
      supplierId: supplierId,
      supplierName:
          supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim(),
      date: now,
      status: receiveNow ? 'Received' : 'Draft',
      items: items,
      note: note,
      paymentStatus: normalizedPaidAmount > 0 ? 'credit' : normalizedStatus,
      paymentMethod: normalizedMethod,
      paidAmount: 0,
      warehouseId: warehouseId,
      warehouseName: warehouseName,
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
      syncStatus: 'pending',
      storeId: storeId,
      branchId: branchId,
      version: 1,
      lastModifiedByDeviceId: deviceId,
    );
    return purchase.copyWith(
      items: purchase.items.indexed.map((entry) {
        return copyItemWith(
          entry.$2,
          lineId: '${purchase.id}:pl:${entry.$1}',
        );
      }).toList(growable: false),
    );
  }

  Purchase updateDraft({
    required Purchase current,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    required String paymentStatus,
    required String paymentMethod,
    required double? paidAmount,
    required String warehouseId,
    required String warehouseName,
    required DateTime now,
    required String deviceId,
    required String storeId,
    required String branchId,
  }) {
    if (!current.isDraft) {
      throw StateError('Only draft purchases can use the draft edit workflow.');
    }
    if (current.isCancelled) {
      throw StateError('Cancelled/returned purchases cannot be edited.');
    }
    if (current.version != expectedVersion) {
      throw StateError(
        'Purchase changed by another user. Reload it before editing.',
      );
    }

    final normalizedStatus = normalizePaymentStatus(paymentStatus);
    final total = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final normalizedPaid = normalizedStatus == 'paid'
        ? total
        : normalizedStatus == 'credit'
            ? 0.0
            : (paidAmount ?? 0).clamp(0, total).toDouble();
    final existingLineIds = current.items
        .map((item) => item.lineId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final usedLineIds = <String>{};
    final normalizedItems = items.indexed.map((entry) {
      final item = entry.$2;
      final requestedLineId = item.lineId.trim();
      if (requestedLineId.isNotEmpty &&
          existingLineIds.contains(requestedLineId) &&
          usedLineIds.add(requestedLineId)) {
        return item;
      }
      var generatedLineId =
          '${current.id}:pl:v${current.version + 1}:${entry.$1}:${now.microsecondsSinceEpoch}';
      var suffix = 0;
      while (!usedLineIds.add(generatedLineId)) {
        suffix += 1;
        generatedLineId =
            '${current.id}:pl:v${current.version + 1}:${entry.$1}:${now.microsecondsSinceEpoch}:$suffix';
      }
      return copyItemWith(item, lineId: generatedLineId);
    }).toList(growable: false);

    return current.copyWith(
      supplierId: supplierId,
      supplierName:
          supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim(),
      items: normalizedItems,
      paymentStatus: normalizedPaid > 0 ? 'credit' : normalizedStatus,
      paymentMethod: normalizePaymentMethod(paymentMethod),
      paidAmount: 0,
      warehouseId: warehouseId,
      warehouseName: warehouseName,
      updatedAt: now,
      version: current.version + 1,
      deviceId: deviceId,
      syncStatus: 'pending',
      storeId: storeId,
      branchId: branchId,
      lastModifiedByDeviceId: deviceId,
    );
  }

  Purchase softDeleteDraft({
    required Purchase current,
    required DateTime now,
    required String deviceId,
    required String storeId,
    required String branchId,
  }) {
    if (current.isReceived) {
      throw StateError(
        'Received purchase invoices cannot be deleted. Cancel them first.',
      );
    }
    if (current.isCancelled) {
      throw StateError(
        'Cancelled purchase invoices require permanent delete permission.',
      );
    }
    return current.copyWith(
      deletedAt: now,
      updatedAt: now,
      deviceId: deviceId,
      syncStatus: 'pending',
      storeId: storeId,
      branchId: branchId,
      version: current.version + 1,
      lastModifiedByDeviceId: deviceId,
      clearDeletedAt: false,
    );
  }

  String normalizePaymentStatus(String value) {
    switch (value.trim().toLowerCase()) {
      case 'credit':
        return 'credit';
      case 'partial':
        return 'partial';
      default:
        return 'paid';
    }
  }

  String normalizePaymentMethod(String value) =>
      value.trim().isEmpty ? 'Cash' : value.trim();

  PurchaseItem copyItemWith(PurchaseItem item, {required String lineId}) =>
      PurchaseItem(
        lineId: lineId,
        sourceLineId: item.sourceLineId,
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
        batchAllocations: item.batchAllocations,
      );
}
