part of 'app_store.dart';

/// Transitional instance API kept for source compatibility while callers
/// migrate to typed domain ports (`store.catalog`, `store.commerce`, etc.).
///
/// The business implementation continues to live in focused split modules;
/// this mixin deliberately contains forwarding only and owns no mutable state.
mixin _AppStoreForwardingApiPart5
    on ChangeNotifier, _AppStoreStateAccessors, _AppStoreForwardingApi {
  DeliveryNote? _deliveryNoteForSale(String saleId) =>
      _AppStoreSplitSalesReturns(this as AppStore).deliveryNoteForSale(saleId);

  Future<Sale> _createSale({
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

  Future<void> _rebuildProductStockCache(String productId) =>
      _AppStoreSplitBackupRecovery(this as AppStore)
          .rebuildProductStockCache(productId);

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
  Future<List<Map<String, dynamic>>> _exportUnifiedSnapshotChunks({
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

  Map<String, dynamic> _unifiedSnapshotPayloadFromChunks(
    List<Map<String, dynamic>> chunks,
  ) =>
      _AppStoreSplitBackupRecovery(this as AppStore)
          .unifiedSnapshotPayloadFromChunks(chunks);

  Future<List<Map<String, dynamic>>>
      exportDirectLoginBootstrapSnapshotChunks() =>
          _AppStoreSplitBackupRecovery(this as AppStore)
              .exportDirectLoginBootstrapSnapshotChunks();

  Future<String> _exportBackupJson() =>
      AppStoreRecoveryService(this as AppStore).exportBackupJson();

  String _currentHostRestoreCommandId() =>
      _AppStoreSplitBackupRecoveryPart2(this as AppStore)
          .currentHostRestoreCommandId();

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

  int _readVersion(dynamic item) =>
      _AppStoreSplitBackupRecoveryPart3(this as AppStore)._readVersion(item);

  DateTime _readUpdatedAt(dynamic item) =>
      _AppStoreSplitBackupRecoveryPart3(this as AppStore)._readUpdatedAt(item);

  void _replaceUsersWithoutDuplicates(List<AppUser> incoming) =>
      _AppStoreSplitBackupRecoveryPart4(this as AppStore)
          ._replaceUsersWithoutDuplicates(incoming);

  Future<void> _mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  }) =>
      _AppStoreSplitBackupRecoveryPart4(this as AppStore)
          .mergeBackupJson(rawJson, markSynced: markSynced);

  List<DataConflict> _detectDataConflicts() =>
      _AppStoreSplitSyncApplyPart2(this as AppStore)._detectDataConflicts();
}
