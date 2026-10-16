import '../../models/store_profile.dart';
import 'dart:async';

/// Session-local cache state. SQLite remains authoritative.
class RuntimeState {
  int storeRevision = 0;
  int productsRevision = 0;
  int customersRevision = 0;
  int salesRevision = 0;
  int deliveryNotesRevision = 0;
  int suppliersRevision = 0;
  int supplierProductPricesRevision = 0;
  int purchasesRevision = 0;
  int expensesRevision = 0;
  int stockMovementsRevision = 0;
  int inventoryCountsRevision = 0;
  int warehousesRevision = 0;
  int accountTransactionsRevision = 0;
  int storeProfileRevision = 0;
  StoreProfile storeProfile = StoreProfile.defaults;
  bool productDerivedDataDirty = false;
  Timer? productDerivedDataFlushTimer;
  Future<void>? productDerivedDataFlushInFlight;
  int derivedListCacheGeneration = 0;
  bool isReady = false;
  bool heavyDataLoadCompleted = false;
  bool ledgerDataLoadCompleted = false;
  Future<void>? ledgerDataLoadFuture;
  bool syncDataLoadCompleted = false;
  Future<void>? syncDataLoadFuture;
  final Map<String, Future<void>> deferredGroupLoadFutures =
      <String, Future<void>>{};
  final Set<String> deferredGroupLoadCompleted = <String>{};
  final Map<String, Object> deferredGroupLoadErrors = <String, Object>{};
  bool shutdownPrepared = false;
}
