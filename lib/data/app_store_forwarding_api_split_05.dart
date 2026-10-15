part of 'app_store.dart';

/// Transitional instance API kept for source compatibility while callers
/// migrate to typed domain ports (`store.catalog`, `store.commerce`, etc.).
///
/// The business implementation continues to live in focused split modules;
/// this mixin deliberately contains forwarding only and owns no mutable state.
mixin _AppStoreForwardingApiPart5
    on ChangeNotifier, _AppStoreStateAccessors, _AppStoreForwardingApi {
  Future<ManufacturingOrder> editCompletedManufacturingOrder({
    required String orderId,
    required int expectedVersion,
    required String bomId,
    required double quantity,
    required String rawMaterialsWarehouseId,
    required String rawMaterialsWarehouseName,
    required String finishedGoodsWarehouseId,
    required String finishedGoodsWarehouseName,
    String notes = '',
    List<BatchAllocation> outputBatchAllocations = const <BatchAllocation>[],
    Map<String, double> actualConsumedQuantities = const <String, double>{},
    Map<String, double> wasteQuantities = const <String, double>{},
    Map<String, String> wasteReasons = const <String, String>{},
  }) =>
      _AppStoreSplitManufacturingPart4(this as AppStore)
          .editCompletedManufacturingOrder(
        orderId: orderId,
        expectedVersion: expectedVersion,
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
      );

  /// Reverses a completed manufacturing order without deleting history.
  /// A conservative downstream-movement guard prevents returning raw material
  /// after any of the produced finished goods have subsequently moved out.
  Future<ManufacturingOrder> reverseManufacturingOrder({
    required String orderId,
    required String reason,
  }) =>
      _AppStoreSplitManufacturingPart5(this as AppStore)
          .reverseManufacturingOrder(orderId: orderId, reason: reason);

  Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  }) =>
      _AppStoreSplitSalesReturns(this as AppStore).createSaleQuotation(
          customerName: customerName,
          customerId: customerId,
          items: items,
          discount: discount,
          invoiceCurrency: invoiceCurrency,
          note: note,
          validUntil: validUntil);

  Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  }) =>
      _AppStoreSplitSalesReturns(this as AppStore).convertSaleQuotationToSale(
          quotationId,
          paymentMethod: paymentMethod,
          paymentStatus: paymentStatus);

  Future<void> deleteSaleQuotation(String id) =>
      _AppStoreSplitSalesReturns(this as AppStore).deleteSaleQuotation(id);

  DeliveryNote? deliveryNoteForSale(String saleId) =>
      _AppStoreSplitSalesReturns(this as AppStore).deliveryNoteForSale(saleId);

  Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  }) =>
      _AppStoreSplitSalesReturns(this as AppStore)
          .createDeliveryNoteFromSale(saleId, note: note);

  Future<void> markDeliveryNoteDelivered(String id) =>
      _AppStoreSplitSalesReturns(this as AppStore)
          .markDeliveryNoteDelivered(id);

  Future<void> deleteDeliveryNote(String id) =>
      _AppStoreSplitSalesReturns(this as AppStore).deleteDeliveryNote(id);

  Future<Sale> createSale({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    double? originalDiscount,
    String discountCurrency = 'USD',
    double discountExchangeRateAtEntry = 0,
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
    String invoiceCurrency = 'USD',
    String paymentCurrency = 'USD',
    double? exchangeRateAtPayment,
    double? paidAmount,
    double? cashReceivedAmount,
    double? paidAmountInPaymentCurrency,
    double? cashReceivedAmountInPaymentCurrency,
    String warehouseId = '',
    String warehouseName = '',
  }) =>
      _AppStoreSplitSalesReturnsPart2(this as AppStore).createSale(
          customerName: customerName,
          customerId: customerId,
          items: items,
          discount: discount,
          originalDiscount: originalDiscount,
          discountCurrency: discountCurrency,
          discountExchangeRateAtEntry: discountExchangeRateAtEntry,
          paymentMethod: paymentMethod,
          paymentStatus: paymentStatus,
          invoiceCurrency: invoiceCurrency,
          paymentCurrency: paymentCurrency,
          exchangeRateAtPayment: exchangeRateAtPayment,
          paidAmount: paidAmount,
          cashReceivedAmount: cashReceivedAmount,
          paidAmountInPaymentCurrency: paidAmountInPaymentCurrency,
          cashReceivedAmountInPaymentCurrency:
              cashReceivedAmountInPaymentCurrency,
          warehouseId: warehouseId,
          warehouseName: warehouseName);

  Future<Sale> editPostedSale({
    required String saleId,
    required int expectedVersion,
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    double? originalDiscount,
    String? discountCurrency,
    double? discountExchangeRateAtEntry,
    String warehouseId = '',
    String warehouseName = '',
  }) =>
      _AppStoreSplitSalesReturnsPart3(this as AppStore).editPostedSale(
        saleId: saleId,
        expectedVersion: expectedVersion,
        customerName: customerName,
        customerId: customerId,
        items: items,
        discount: discount,
        originalDiscount: originalDiscount,
        discountCurrency: discountCurrency,
        discountExchangeRateAtEntry: discountExchangeRateAtEntry,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
      );

  Future<CreditNote> returnSale(
    String id, {
    bool restoreStock = true,
    Map<String, double>? returnedQuantities,
  }) =>
      _AppStoreSplitSalesReturnsPart5(this as AppStore).returnSale(id,
          restoreStock: restoreStock, returnedQuantities: returnedQuantities);

  Future<CreditNote> editSaleReturn({
    required String creditNoteId,
    required int expectedVersion,
    required Map<String, double> returnedQuantities,
  }) =>
      _AppStoreSplitSalesReturnsPart6(this as AppStore).editSaleReturn(
        creditNoteId: creditNoteId,
        expectedVersion: expectedVersion,
        returnedQuantities: returnedQuantities,
      );

  Future<void> cancelSale(
    String id, {
    String status = 'Cancelled',
    bool restoreStock = true,
  }) =>
      _AppStoreSplitSalesReturnsPart8(this as AppStore)
          .cancelSale(id, status: status, restoreStock: restoreStock);

  @Deprecated(
    'Use cancelSale instead. Invoices are cancelled, not physically deleted.',
  )
  Future<void> deleteSale(String id, {bool restoreStock = true}) =>
      _AppStoreSplitSalesReturnsPart8(this as AppStore)
          .deleteSale(id, restoreStock: restoreStock);

  double estimateProfit() =>
      _AppStoreSplitSalesReturnsPart8(this as AppStore).estimateProfit();

  Future<void> rebuildProductStockCache(String productId) =>
      _AppStoreSplitBackupRecovery(this as AppStore)
          .rebuildProductStockCache(productId);

  Future<void> rebuildAllProductStockCaches() =>
      _AppStoreSplitBackupRecovery(this as AppStore)
          .rebuildAllProductStockCaches();

  void _applyProductStockCompatibilityDeltas(
    Iterable<StockMovement> movements,
  ) =>
      _AppStoreSplitBackupRecovery(this as AppStore)
          ._applyProductStockCompatibilityDeltas(movements);

  Future<void> _refreshProductStockCompatibilityCache(
    Iterable<String> productIds,
  ) =>
      _AppStoreSplitBackupRecovery(this as AppStore)
          ._refreshProductStockCompatibilityCache(productIds);

  /// The single snapshot builder used by Direct, LAN, restore, repair, and
  /// pairing flows. The same catalog, manifest, payload shape, and chunk
  /// structure are used by both LAN and Direct transports.
  Future<List<Map<String, dynamic>>> exportUnifiedSnapshotChunks({
    String kind = 'full_store',
    Set<String>? sectionIds,
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) =>
      _AppStoreSplitBackupRecovery(this as AppStore)
          .exportUnifiedSnapshotChunks(
              kind: kind,
              sectionIds: sectionIds,
              maxItemsPerChunk: maxItemsPerChunk,
              maxEncodedPayloadBytes: maxEncodedPayloadBytes);

  Map<String, dynamic> unifiedSnapshotPayloadFromChunks(
    List<Map<String, dynamic>> chunks,
  ) =>
      _AppStoreSplitBackupRecovery(this as AppStore)
          .unifiedSnapshotPayloadFromChunks(chunks);

  Future<List<Map<String, dynamic>>>
      exportDirectLoginBootstrapSnapshotChunks() =>
          _AppStoreSplitBackupRecovery(this as AppStore)
              .exportDirectLoginBootstrapSnapshotChunks();

  Future<List<Map<String, dynamic>>> exportDirectBootstrapSnapshotChunks({
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          .exportDirectBootstrapSnapshotChunks(
              maxItemsPerChunk: maxItemsPerChunk,
              maxEncodedPayloadBytes: maxEncodedPayloadBytes);

  String exportRecoveryFileJson({String controlPlaneApiUrl = ''}) {
    requirePermission(AppPermission.backupExport);
    final store = this as AppStore;
    return RecoveryFileService(identityProvider: () => store.appIdentity)
        .exportRecoveryFileJson(controlPlaneApiUrl: controlPlaneApiUrl);
  }

  Map<String, String> parseRecoveryFileJson(String rawJson) {
    final store = this as AppStore;
    return RecoveryFileService(identityProvider: () => store.appIdentity)
        .parseRecoveryFileJson(rawJson);
  }

  Future<String> exportBackupJson() =>
      AppStoreRecoveryService(this as AppStore).exportBackupJson();

  String currentHostSnapshotGeneration() =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          .currentHostSnapshotGeneration();

  String currentHostRestoreCommandId() =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          .currentHostRestoreCommandId();

  Future<Map<String, dynamic>> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          .exportUnifiedSnapshotEnvelope(
              kind: kind,
              maxItemsPerChunk: maxItemsPerChunk,
              maxEncodedPayloadBytes: maxEncodedPayloadBytes);

  Future<String> exportSyncSnapshotJson() =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          .exportSyncSnapshotJson();

  DateTime syncSnapshotGeneratedAtFromJson(String rawJson) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          .syncSnapshotGeneratedAtFromJson(rawJson);

  int syncSnapshotGeneratedSequenceFromJson(String rawJson) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          .syncSnapshotGeneratedSequenceFromJson(rawJson);

  String exportSyncChangesJson({
    DateTime? since,
    int? sinceSequence,
    int? maxEncodedPayloadBytes,
  }) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore).exportSyncChangesJson(
          since: since,
          sinceSequence: sinceSequence,
          maxEncodedPayloadBytes: maxEncodedPayloadBytes);

  List<int> _deriveBackupKey(String password, String salt) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          ._deriveBackupKey(password, salt);

  List<int> _deriveBackupKeyV2(String password, String salt) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          ._deriveBackupKeyV2(password, salt);

  String _generateNonce() =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)._generateNonce();

  List<int> _aesGcmDecrypt(
    List<int> encrypted,
    List<int> key,
    List<int> nonce,
  ) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          ._aesGcmDecrypt(encrypted, key, nonce);

  List<int> _deriveBackupKeyV1(String password, String salt) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          ._deriveBackupKeyV1(password, salt);

  List<int> _xorWithSha256Stream(
          List<int> input, List<int> key, String nonce) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          ._xorWithSha256Stream(input, key, nonce);

  bool _constantTimeEquals(List<int> a, List<int> b) =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          ._constantTimeEquals(a, b);

  Future<void> importBackupJson(String rawJson,
          {Set<String>? selectedSectionIds}) =>
      _AppStoreSplitBackupRecoveryPart3(this as AppStore)
          .importBackupJson(rawJson, selectedSectionIds: selectedSectionIds);

  int _readVersion(dynamic item) =>
      _AppStoreSplitBackupRecoveryPart3(this as AppStore)._readVersion(item);

  DateTime _readUpdatedAt(dynamic item) =>
      _AppStoreSplitBackupRecoveryPart3(this as AppStore)._readUpdatedAt(item);

  void _replaceUsersWithoutDuplicates(List<AppUser> incoming) =>
      _AppStoreSplitBackupRecoveryPart4(this as AppStore)
          ._replaceUsersWithoutDuplicates(incoming);

  Future<void> mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  }) =>
      _AppStoreSplitBackupRecoveryPart4(this as AppStore)
          .mergeBackupJson(rawJson, markSynced: markSynced);

  Future<void> markAllSyncChangesSynced() =>
      _AppStoreSplitSyncApply(this as AppStore).markAllSyncChangesSynced();

  Future<void> importSyncSnapshotJson(String rawJson) =>
      _AppStoreSplitSyncApply(this as AppStore).importSyncSnapshotJson(rawJson);

  /// Cursor-aware sync log compaction.
  ///
  /// Keeps the latest [keepRecentSyncedChanges] synced authoritative changes and
  /// removes older synced queue rows only when they are at/below the active peer
  /// ACK floor. If a Client later asks for a sequence older than the earliest
  /// retained event, [exportSyncChangesJson] returns needsSnapshot=true so the
  /// Client rebuilds from a full Host snapshot instead of applying a partial log.
  Future<Map<String, int>> compactSyncedSyncHistoryForDiagnostics({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
  }) =>
      _AppStoreSplitSyncApply(this as AppStore)
          .compactSyncedSyncHistoryForDiagnostics(
              keepRecentSyncedChanges: keepRecentSyncedChanges);

  Future<Map<String, int>> compactSyncedSyncHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
    int minChangesBeforeCompact =
        AppStore._syncMaintenanceMinChangesBeforeCompact,
  }) =>
      _AppStoreSplitSyncApply(this as AppStore)
          .compactSyncedSyncHistoryForMaintenance(
              keepRecentSyncedChanges: keepRecentSyncedChanges,
              minChangesBeforeCompact: minChangesBeforeCompact);

  /// Client-side sync log compaction. Clients do not own the ACK floor for
  /// other peers, so they compact only their local, already-synced history up
  /// to the latest authoritative sequence they have applied. The Host remains
  /// responsible for serving old events or returning needsSnapshot=true.
  Future<Map<String, int>> compactClientSyncedSyncHistoryForMaintenance({
    int keepRecentSyncedChanges = AppStore._syncMaintenanceKeepRecentChanges,
  }) =>
      _AppStoreSplitSyncApply(this as AppStore)
          .compactClientSyncedSyncHistoryForMaintenance(
              keepRecentSyncedChanges: keepRecentSyncedChanges);

  Future<void> applyRemoteSyncChanges(
    List<SyncChange> incoming, {
    bool markAppliedAsSynced = false,
    bool mirrorToDirect = false,
  }) =>
      _AppStoreSplitSyncApplyPart2(this as AppStore).applyRemoteSyncChanges(
          incoming,
          markAppliedAsSynced: markAppliedAsSynced,
          mirrorToDirect: mirrorToDirect);

  List<DataConflict> _detectDataConflicts() =>
      _AppStoreSplitSyncApplyPart2(this as AppStore)._detectDataConflicts();

  Future<void> assertRemoteSyncChangesApplied(List<SyncChange> changes) =>
      _AppStoreSplitSyncApplyPart3(this as AppStore)
          .assertRemoteSyncChangesApplied(changes);

  Future<void> markSyncChangesSubmittedByIds(Iterable<String> ids) =>
      _AppStoreSplitSyncApplyPart3(this as AppStore)
          .markSyncChangesSubmittedByIds(ids);

  Future<void> markSyncChangesSyncedByIds(Iterable<String> ids) =>
      _AppStoreSplitSyncApplyPart3(this as AppStore)
          .markSyncChangesSyncedByIds(ids);

  /// LAN-only Hosts are already the authority for their local changes. Older
  /// builds incorrectly queued those changes toward `host`, where no client
  /// push loop runs, leaving a permanent pending row on the Host.
  Future<void> settleLegacyLanHostQueue() =>
      _AppStoreSplitSyncApplyPart3(this as AppStore).settleLegacyLanHostQueue();

  /// Marks Host-authored events as complete only after every active peer has
  /// acknowledged the corresponding Host sequence. Direct Host events are
  /// intentionally queued with target="host" so the same queue can be used by
  /// the legacy sync paths, but a Host never runs a Client push loop for that
  /// target. Without this reconciliation those rows remain pending forever
  /// even though the events are already in the authoritative Host timeline.
  Future<int> settleHostQueueThroughPeerAck() =>
      _AppStoreSplitSyncApplyPart3(this as AppStore)
          .settleHostQueueThroughPeerAck();

  Future<void> markSyncQueueChangesInProgress(
    Iterable<String> changeIds,
  ) =>
      _AppStoreSplitSyncApplyPart4(this as AppStore)
          .markSyncQueueChangesInProgress(changeIds);

  Future<void> markSyncChangesRejectedByIds(
    Map<String, String> rejected,
  ) =>
      _AppStoreSplitSyncApplyPart4(this as AppStore)
          .markSyncChangesRejectedByIds(rejected);

  Future<void> markSyncQueueChangesFailed(
    Iterable<String> changeIds,
    String error,
  ) =>
      _AppStoreSplitSyncApplyPart4(this as AppStore)
          .markSyncQueueChangesFailed(changeIds, error);

  Future<void> retryFailedSyncQueue({String? target}) =>
      _AppStoreSplitSyncApplyPart4(this as AppStore)
          .retryFailedSyncQueue(target: target);

  Future<void> recoverStaleInProgressSyncQueue({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  }) =>
      _AppStoreSplitSyncApplyPart4(this as AppStore)
          .recoverStaleInProgressSyncQueue(
              target: target, staleAfter: staleAfter);

  Future<void> recoverSubmittedSyncQueue({String? target}) =>
      _AppStoreSplitSyncApplyPart4(this as AppStore)
          .recoverSubmittedSyncQueue(target: target);

  Future<void> markSyncQueueItemFailed(String queueItemId, String error) =>
      _AppStoreSplitSyncApplyPart4(this as AppStore)
          .markSyncQueueItemFailed(queueItemId, error);

  /// Finishes Ventio-owned buffered work before the SQLite connection is
  /// checkpointed and closed during desktop shutdown.
  Future<void> prepareForShutdown() =>
      _AppStoreSplitSyncApplyPart4(this as AppStore).prepareForShutdown();
}
