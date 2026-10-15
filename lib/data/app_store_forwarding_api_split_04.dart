part of 'app_store.dart';

/// Transitional instance API kept for source compatibility while callers
/// migrate to typed domain ports (`store.catalog`, `store.commerce`, etc.).
///
/// The business implementation continues to live in focused split modules;
/// this mixin deliberately contains forwarding only and owns no mutable state.
mixin _AppStoreForwardingApiPart4
    on ChangeNotifier, _AppStoreStateAccessors, _AppStoreForwardingApi {
  /// Records a customer receipt or supplier payment at account level. The
  /// payment can optionally be allocated to one or more open documents; an
  /// empty allocation list keeps the amount as an unallocated account payment.
  /// Cash payments always go through the voucher + open-drawer path so the
  /// account ledger, journal and cash ledger cannot diverge.
  Future<void> settleAccountPayment({
    required String accountType,
    required String accountId,
    required String accountName,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String referenceNo = '',
    String notes = '',
    List<PaymentAllocationDraft> allocations = const <PaymentAllocationDraft>[],
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart4(this as AppStore).settleAccountPayment(
          accountType: accountType,
          accountId: accountId,
          accountName: accountName,
          amount: amount,
          discount: discount,
          paymentMethod: paymentMethod,
          referenceNo: referenceNo,
          notes: notes,
          allocations: allocations,
          idempotencyKey: idempotencyKey,
          date: date);

  Future<ReceiptVoucher> editReceiptVoucher({
    required String voucherId,
    required int expectedVersion,
    String? customerId,
    String? customerName,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? cashLocationId,
    String? cashDrawerSessionId,
    List<PaymentAllocationDraft>? allocations,
    String? notes,
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart4(this as AppStore).editReceiptVoucher(
        voucherId: voucherId,
        expectedVersion: expectedVersion,
        customerId: customerId,
        customerName: customerName,
        amount: amount,
        currency: currency,
        paymentMethod: paymentMethod,
        cashLocationId: cashLocationId,
        cashDrawerSessionId: cashDrawerSessionId,
        allocations: allocations,
        notes: notes,
        date: date,
      );

  Future<PaymentVoucher> editPaymentVoucher({
    required String voucherId,
    required int expectedVersion,
    String? supplierId,
    String? supplierName,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? cashLocationId,
    String? cashDrawerSessionId,
    List<PaymentAllocationDraft>? allocations,
    String? notes,
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart4(this as AppStore).editPaymentVoucher(
        voucherId: voucherId,
        expectedVersion: expectedVersion,
        supplierId: supplierId,
        supplierName: supplierName,
        amount: amount,
        currency: currency,
        paymentMethod: paymentMethod,
        cashLocationId: cashLocationId,
        cashDrawerSessionId: cashDrawerSessionId,
        allocations: allocations,
        notes: notes,
        date: date,
      );

  Future<Sale> settleSalePayment({
    required String saleId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart4(this as AppStore).settleSalePayment(
          saleId: saleId,
          amount: amount,
          discount: discount,
          paymentMethod: paymentMethod,
          notes: notes,
          idempotencyKey: idempotencyKey,
          date: date);

  Future<Sale> _settleSalePaymentInternal({
    required String saleId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart4(this as AppStore)
          ._settleSalePaymentInternal(
              saleId: saleId,
              amount: amount,
              discount: discount,
              paymentMethod: paymentMethod,
              notes: notes,
              idempotencyKey: idempotencyKey,
              date: date);

  Future<Purchase> settlePurchasePayment({
    required String purchaseId,
    required double amount,
    double discount = 0,
    String paymentMethod = 'Cash',
    String notes = '',
    String idempotencyKey = '',
    DateTime? date,
  }) =>
      _AppStoreSplitWarehouseCashPart4(this as AppStore).settlePurchasePayment(
          purchaseId: purchaseId,
          amount: amount,
          discount: discount,
          paymentMethod: paymentMethod,
          notes: notes,
          idempotencyKey: idempotencyKey,
          date: date);

  PurchaseItem _copyPurchaseItemWith({
    required PurchaseItem item,
    String? lineId,
    List<BatchAllocation>? batchAllocations,
  }) =>
      _AppStoreSplitWarehouseCashPart4(this as AppStore)._copyPurchaseItemWith(
          item: item, lineId: lineId, batchAllocations: batchAllocations);

  Future<double> _unifiedOpeningCostForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
  }) =>
      _AppStoreSplitPurchases(this as AppStore)
          ._unifiedOpeningCostForProductInTransaction(sqliteDb,
              product: product, warehouseId: warehouseId);

  Future<void> _ensureUnifiedBatchCutoverForProductInTransaction(
    dynamic sqliteDb, {
    required Product product,
    required String warehouseId,
    required DateTime at,
  }) =>
      _AppStoreSplitPurchases(this as AppStore)
          ._ensureUnifiedBatchCutoverForProductInTransaction(sqliteDb,
              product: product, warehouseId: warehouseId, at: at);

  Future<void> _assertUnifiedBatchMovementBalancesInTransaction(
    BatchInventoryService batchService,
    Iterable<StockMovement> movements,
  ) =>
      _AppStoreSplitPurchases(this as AppStore)
          ._assertUnifiedBatchMovementBalancesInTransaction(
              batchService, movements);

  Future<Purchase> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    bool receiveNow = true,
    String note = '',
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  }) =>
      _AppStoreSplitPurchasesPart2(this as AppStore).createPurchase(
          supplierId: supplierId,
          supplierName: supplierName,
          items: items,
          receiveNow: receiveNow,
          note: note,
          paymentStatus: paymentStatus,
          paymentMethod: paymentMethod,
          paidAmount: paidAmount,
          warehouseId: warehouseId,
          warehouseName: warehouseName);

  /// Updates a draft directly, or atomically reverses/reposts a received
  /// purchase when none of its inventory batches has a downstream movement.
  /// The version check prevents silently overwriting a concurrent change.
  Future<Purchase> updatePurchaseDraft({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
    String warehouseId = '',
    String warehouseName = '',
  }) =>
      _AppStoreSplitPurchasesPart3(this as AppStore).updatePurchaseDraft(
          purchaseId: purchaseId,
          expectedVersion: expectedVersion,
          supplierId: supplierId,
          supplierName: supplierName,
          items: items,
          paymentStatus: paymentStatus,
          paymentMethod: paymentMethod,
          paidAmount: paidAmount,
          warehouseId: warehouseId,
          warehouseName: warehouseName);

  Future<void> receivePurchase(
    String id, {
    bool settleInitialPayment = true,
    bool postAccounting = true,
    Map<int, List<BatchAllocation>> batchAllocationsByLine =
        const <int, List<BatchAllocation>>{},
  }) =>
      _AppStoreSplitPurchasesPart4(this as AppStore).receivePurchase(id,
          settleInitialPayment: settleInitialPayment,
          postAccounting: postAccounting,
          batchAllocationsByLine: batchAllocationsByLine);

  Future<Purchase> createPurchaseReturn({
    required String sourcePurchaseId,
    required List<PurchaseItem> items,
    String reason = '',
  }) =>
      _AppStoreSplitPurchasesPart6(this as AppStore).createPurchaseReturn(
        sourcePurchaseId: sourcePurchaseId,
        items: items,
        reason: reason,
      );

  Future<void> deleteDraftPurchase(String id) =>
      _AppStoreSplitPurchasesPart4(this as AppStore).deleteDraftPurchase(id);

  Future<void> permanentlyDeleteCancelledPurchase(String id) =>
      _AppStoreSplitPurchasesPart4(this as AppStore)
          .permanentlyDeleteCancelledPurchase(id);

  Future<void> _requirePostedJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  }) =>
      _AppStoreSplitPurchasesPart4(this as AppStore)
          ._requirePostedJournalInTransaction(sqliteDb,
              referenceType: referenceType,
              referenceId: referenceId,
              includePurchaseEditFamily: includePurchaseEditFamily,
              includeSaleEditFamily: includeSaleEditFamily,
              failureMessage: failureMessage);

  Future<void> _requireNoActiveJournalInTransaction(
    dynamic sqliteDb, {
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  }) =>
      _AppStoreSplitPurchasesPart4(this as AppStore)
          ._requireNoActiveJournalInTransaction(sqliteDb,
              referenceType: referenceType,
              referenceId: referenceId,
              includePurchaseEditFamily: includePurchaseEditFamily,
              includeSaleEditFamily: includeSaleEditFamily,
              failureMessage: failureMessage);

  Future<Purchase> editPurchaseReturn({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String warehouseId = '',
    String warehouseName = '',
  }) =>
      _AppStoreSplitPurchasesPart5(this as AppStore).editPurchaseReturn(
        purchaseId: purchaseId,
        expectedVersion: expectedVersion,
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  Future<void> returnPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
    bool recordSupplierReturnLedger = true,
  }) =>
      _AppStoreSplitPurchasesPart7(this as AppStore).returnPurchase(id,
          reverseStock: reverseStock,
          reason: reason,
          recordSupplierReturnLedger: recordSupplierReturnLedger);

  Future<void> cancelPurchase(
    String id, {
    bool reverseStock = true,
    String reason = '',
  }) =>
      _AppStoreSplitPurchasesPart7(this as AppStore)
          .cancelPurchase(id, reverseStock: reverseStock, reason: reason);

  int movementCountAfterInventoryLine(InventoryCountLine line) =>
      _AppStoreSplitInventory(this as AppStore)
          .movementCountAfterInventoryLine(line);

  Future<InventoryCountSession> createInventoryCountSession({
    String notes = '',
    String warehouseId = '',
    String warehouseName = '',
  }) =>
      _AppStoreSplitInventory(this as AppStore).createInventoryCountSession(
          notes: notes, warehouseId: warehouseId, warehouseName: warehouseName);

  Future<void> countInventoryLine({
    required String sessionId,
    required String productId,
    required double countedQty,
    String note = '',
  }) =>
      _AppStoreSplitInventory(this as AppStore).countInventoryLine(
          sessionId: sessionId,
          productId: productId,
          countedQty: countedQty,
          note: note);

  Future<void> resetInventoryCountLine({
    required String sessionId,
    required String productId,
  }) =>
      _AppStoreSplitInventory(this as AppStore)
          .resetInventoryCountLine(sessionId: sessionId, productId: productId);

  Future<void> approveInventoryCount(String sessionId) =>
      _AppStoreSplitInventory(this as AppStore)
          .approveInventoryCount(sessionId);

  Future<void> reverseInventoryCount(
    String sessionId, {
    String reason = '',
  }) =>
      _AppStoreSplitInventoryPart2(this as AppStore)
          .reverseInventoryCount(sessionId, reason: reason);

  Future<void> cancelInventoryCount(String sessionId) =>
      _AppStoreSplitInventoryPart2(this as AppStore)
          .cancelInventoryCount(sessionId);

  Future<void> reviewAutoCorrection(
    String movementId, {
    String note = '',
  }) =>
      _AppStoreSplitInventoryPart2(this as AppStore)
          .reviewAutoCorrection(movementId, note: note);

  Future<void> setExpiryBatchStatus(String batchId, String status) =>
      _AppStoreSplitInventoryPart2(this as AppStore)
          .setExpiryBatchStatus(batchId, status);

  void _recordInventoryBatchSyncChanges({
    required Product product,
    required List<BatchAllocation> allocations,
    required String sourceType,
    required String sourceId,
    required DateTime now,
    double unitCost = 0,
    String sourceLineId = '',
    List<String> sourceLineIds = const <String>[],
    DateTime? receivedAt,
  }) =>
      _AppStoreSplitInventoryPart2(this as AppStore)
          ._recordInventoryBatchSyncChanges(
              product: product,
              allocations: allocations,
              sourceType: sourceType,
              sourceId: sourceId,
              now: now,
              unitCost: unitCost,
              sourceLineId: sourceLineId,
              sourceLineIds: sourceLineIds,
              receivedAt: receivedAt);

  Future<void> adjustExpiryBatchStock({
    required String productId,
    required String warehouseId,
    required String batchId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
  }) =>
      _AppStoreSplitInventoryPart2(this as AppStore).adjustExpiryBatchStock(
          productId: productId,
          warehouseId: warehouseId,
          batchId: batchId,
          quantityDelta: quantityDelta,
          reason: reason,
          adjustmentCategory: adjustmentCategory);

  /// Reverses a posted expiry/batch adjustment using the movement's immutable
  /// historical quantity and unit cost.  This deliberately never re-prices
  /// the batch from today's product cost.
  Future<void> reverseExpiryBatchAdjustment(
    String movementId, {
    String reason = '',
  }) =>
      _AppStoreSplitInventoryPart3(this as AppStore)
          .reverseExpiryBatchAdjustment(movementId, reason: reason);

  Future<int> manualStockAdjustmentVersion(String operationReferenceId) =>
      _AppStoreSplitInventoryPart3(this as AppStore)
          .manualStockAdjustmentVersion(operationReferenceId);

  Future<void> editStockAdjustment({
    required String operationReferenceId,
    required int expectedVersion,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
  }) =>
      _AppStoreSplitInventoryPart4(this as AppStore).editStockAdjustment(
        operationReferenceId: operationReferenceId,
        expectedVersion: expectedVersion,
        quantityDelta: quantityDelta,
        reason: reason,
        adjustmentCategory: adjustmentCategory,
        notes: notes,
        evidenceRef: evidenceRef,
        batchAllocations: batchAllocations,
      );

  Future<void> adjustStock({
    required String productId,
    required String warehouseId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
    List<BatchAllocation> batchAllocations = const <BatchAllocation>[],
    String operationReferenceId = '',
  }) =>
      _AppStoreSplitInventoryPart5(this as AppStore).adjustStock(
          productId: productId,
          warehouseId: warehouseId,
          quantityDelta: quantityDelta,
          reason: reason,
          adjustmentCategory: adjustmentCategory,
          notes: notes,
          evidenceRef: evidenceRef,
          batchAllocations: batchAllocations,
          operationReferenceId: operationReferenceId);

  Future<void> recordWasteLoss({
    required String productId,
    required String warehouseId,
    required double quantity,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
  }) =>
      _AppStoreSplitInventoryPart5(this as AppStore).recordWasteLoss(
          productId: productId,
          warehouseId: warehouseId,
          quantity: quantity,
          reason: reason,
          adjustmentCategory: adjustmentCategory,
          notes: notes);

  /// Reverses every batch movement created by one waste operation atomically.
  Future<void> reverseWasteLossGroup(String movementId) =>
      _AppStoreSplitInventoryPart5(this as AppStore)
          .reverseWasteLossGroup(movementId);

  Future<void> deleteWasteLoss(String movementId) =>
      _AppStoreSplitInventoryPart6(this as AppStore)
          .deleteWasteLoss(movementId);

  void _applyPurchaseStock(Purchase purchase, DateTime now) =>
      _AppStoreSplitInventoryPart6(this as AppStore)
          ._applyPurchaseStock(purchase, now);

  void _addStockMovement(StockMovement movement, {bool recordSync = false}) =>
      _AppStoreSplitInventoryPart6(this as AppStore)
          ._addStockMovement(movement, recordSync: recordSync);

  Future<void> _reconcileInventoryAccountsAfterBomChange(
    BillOfMaterials bom, {
    VentioDriftDatabase? database,
    bool withinExistingTransaction = false,
  }) =>
      _AppStoreSplitInventoryPart6(this as AppStore)
          ._reconcileInventoryAccountsAfterBomChange(bom,
              database: database,
              withinExistingTransaction: withinExistingTransaction);

  Future<BillOfMaterials> estimateBillOfMaterialsSnapshot(
    BillOfMaterials bom, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitManufacturing(this as AppStore)
          .estimateBillOfMaterialsSnapshot(bom, warehouseId: warehouseId);

  Future<double> estimateBillOfMaterialsUnitCost(
    BillOfMaterials bom, {
    String warehouseId = '',
  }) =>
      _AppStoreSplitManufacturing(this as AppStore)
          .estimateBillOfMaterialsUnitCost(bom, warehouseId: warehouseId);

  Future<BillOfMaterials> createBillOfMaterials({
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  }) =>
      _AppStoreSplitManufacturing(this as AppStore).createBillOfMaterials(
          name: name,
          outputProductId: outputProductId,
          outputQuantity: outputQuantity,
          components: components,
          notes: notes);

  Future<BillOfMaterials> updateBillOfMaterials({
    required String id,
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  }) =>
      _AppStoreSplitManufacturing(this as AppStore).updateBillOfMaterials(
          id: id,
          name: name,
          outputProductId: outputProductId,
          outputQuantity: outputQuantity,
          components: components,
          notes: notes);

  Future<void> deleteBillOfMaterials(String id) =>
      _AppStoreSplitManufacturing(this as AppStore).deleteBillOfMaterials(id);

  Future<void> deleteManufacturingOrder(String id) =>
      _AppStoreSplitManufacturing(this as AppStore)
          .deleteManufacturingOrder(id);

  Future<ManufacturingOrder> updateManufacturingOrder({
    required String id,
    required String bomId,
    required double quantity,
    required String rawMaterialsWarehouseId,
    required String rawMaterialsWarehouseName,
    required String finishedGoodsWarehouseId,
    required String finishedGoodsWarehouseName,
    String notes = '',
  }) =>
      _AppStoreSplitManufacturingPart2(this as AppStore)
          .updateManufacturingOrder(
              id: id,
              bomId: bomId,
              quantity: quantity,
              rawMaterialsWarehouseId: rawMaterialsWarehouseId,
              rawMaterialsWarehouseName: rawMaterialsWarehouseName,
              finishedGoodsWarehouseId: finishedGoodsWarehouseId,
              finishedGoodsWarehouseName: finishedGoodsWarehouseName,
              notes: notes);

  Future<ManufacturingOrder> startManufacturingOrder({
    required String bomId,
    required double quantity,
    String rawMaterialsWarehouseId = '',
    String rawMaterialsWarehouseName = '',
    String finishedGoodsWarehouseId = '',
    String finishedGoodsWarehouseName = '',
    String notes = '',
  }) =>
      _AppStoreSplitManufacturingPart2(this as AppStore)
          .startManufacturingOrder(
              bomId: bomId,
              quantity: quantity,
              rawMaterialsWarehouseId: rawMaterialsWarehouseId,
              rawMaterialsWarehouseName: rawMaterialsWarehouseName,
              finishedGoodsWarehouseId: finishedGoodsWarehouseId,
              finishedGoodsWarehouseName: finishedGoodsWarehouseName,
              notes: notes);

  Future<ManufacturingOrder> finishManufacturingOrder({
    required String orderId,
    required double actualQuantity,
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
  }) =>
      _AppStoreSplitManufacturingPart2(this as AppStore)
          .finishManufacturingOrder(
              orderId: orderId,
              actualQuantity: actualQuantity,
              outputBatchAllocations: outputBatchAllocations,
              actualConsumedQuantities: actualConsumedQuantities,
              wasteQuantities: wasteQuantities,
              wasteReasons: wasteReasons);

  Future<ManufacturingOrder> completeManufacturingOrder({
    required String bomId,
    required double quantity,
    String rawMaterialsWarehouseId = '',
    String rawMaterialsWarehouseName = '',
    String finishedGoodsWarehouseId = '',
    String finishedGoodsWarehouseName = '',
    String notes = '',
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
    String existingOrderId = '',
  }) =>
      _AppStoreSplitManufacturingPart3(this as AppStore)
          .completeManufacturingOrder(
              bomId: bomId,
              quantity: quantity,
              rawMaterialsWarehouseId: rawMaterialsWarehouseId,
              rawMaterialsWarehouseName: rawMaterialsWarehouseName,
              finishedGoodsWarehouseId: finishedGoodsWarehouseId,
              finishedGoodsWarehouseName: finishedGoodsWarehouseName,
              notes: notes,
              outputBatchAllocations: outputBatchAllocations,
              actualConsumedQuantities: actualConsumedQuantities,
              wasteQuantities: wasteQuantities,
              wasteReasons: wasteReasons,
              existingOrderId: existingOrderId);
}
