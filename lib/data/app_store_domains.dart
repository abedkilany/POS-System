part of 'app_store.dart';

/// Stable, typed entry points into AppStore business domains.
///
/// New UI/services should depend on the narrowest port they need instead of
/// reaching through the complete AppStore compatibility surface. The legacy
/// methods remain available during migration, but these ports are the preferred
/// dependency boundary for new code.
abstract class CatalogDomainPort {
  List<Product> get products;
  List<CatalogItem> get categories;
  List<CatalogItem> get brands;
  List<CatalogItem> get units;
  Product? productById(String id);
  Future<void> ensureLoaded();
}

abstract class CommerceDomainPort {
  List<Customer> get customers;
  List<Supplier> get suppliers;
  List<Sale> get sales;
  List<Purchase> get purchases;
  List<Expense> get expenses;
  Future<void> ensureSalesLoaded();
  Future<void> ensurePurchasesLoaded();
}

abstract class AccountingDomainPort {
  List<AccountTransaction> get transactions;
  int get revision;
  int get ledgerRevision;
  double accountBalance(String accountType, String accountId);
  List<AccountTransaction> transactionsForAccount(
    String accountType,
    String accountId,
  );
  Future<void> refreshFromSqlite();
}

abstract class InventoryDomainPort {
  List<Warehouse> get warehouses;
  List<StockMovement> get stockMovements;
  int get revision;
  Future<void> ensureLoaded();
  Future<Map<String, dynamic>> traceBatch(String batchId, {int maxDepth = 8});
  Future<Map<String, dynamic>> verifyTraceabilityIntegrity();
}

abstract class SecurityDomainPort {
  AppUser? get activeUser;
  String get currentRole;
  bool hasPermission(String permission);
  void requirePermission(String permission);
  Future<bool> authorizeSensitiveAction({
    required String action,
    required String password,
    Duration validity = const Duration(minutes: 3),
  });
  void requireSensitiveActionAuthorization(String action);
  void clearSensitiveActionAuthorization();
}

abstract class SyncDomainPort {
  List<SyncChange> get changes;
  List<SyncQueueItem> get queue;
  int get sequence;
  Future<void> ensureLoaded();
  Future<void> retryFailed({String? target});
  Future<void> recoverStale({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  });
}

abstract class RecoveryDomainPort {
  Future<String> exportBackupJson();
  Future<void> importBackupJson(
    String rawJson, {
    Set<String>? selectedSectionIds,
  });
  String exportRecoveryFileJson({String controlPlaneApiUrl = ''});
  Map<String, String> parseRecoveryFileJson(String rawJson);
}

final class _CatalogDomain implements CatalogDomainPort {
  _CatalogDomain(this._store);
  final AppStore _store;

  @override
  List<Product> get products => _store.products;
  @override
  List<CatalogItem> get categories => _store.categories;
  @override
  List<CatalogItem> get brands => _store.brands;
  @override
  List<CatalogItem> get units => _store.units;
  @override
  Product? productById(String id) => _store.productById(id);
  @override
  Future<void> ensureLoaded() => _store.ensureProductsLoaded();
}

final class _CommerceDomain implements CommerceDomainPort {
  _CommerceDomain(this._store);
  final AppStore _store;

  @override
  List<Customer> get customers => _store.customers;
  @override
  List<Supplier> get suppliers => _store.suppliers;
  @override
  List<Sale> get sales => _store.sales;
  @override
  List<Purchase> get purchases => _store.purchases;
  @override
  List<Expense> get expenses => _store.expenses;
  @override
  Future<void> ensureSalesLoaded() => _store.ensureSalesPageDataLoaded();
  @override
  Future<void> ensurePurchasesLoaded() => _store.ensurePurchasesPageDataLoaded();
}

final class _AccountingDomain implements AccountingDomainPort {
  _AccountingDomain(this._store);
  final AppStore _store;

  @override
  List<AccountTransaction> get transactions => _store.accountTransactions;
  @override
  int get revision => _store.accountingRevision;
  @override
  int get ledgerRevision => _store.accountTransactionsRevision;
  @override
  double accountBalance(String accountType, String accountId) =>
      _store.accountBalance(accountType, accountId);
  @override
  List<AccountTransaction> transactionsForAccount(
    String accountType,
    String accountId,
  ) =>
      _store.accountTransactionsForAccount(accountType, accountId);
  @override
  Future<void> refreshFromSqlite() => _store.refreshAccountTransactionsFromSqlite();
}

final class _InventoryDomain implements InventoryDomainPort {
  _InventoryDomain(this._store);
  final AppStore _store;

  @override
  List<Warehouse> get warehouses => _store.warehouses;
  @override
  List<StockMovement> get stockMovements => _store.stockMovements;
  @override
  int get revision => _store.inventoryRevision;
  @override
  Future<void> ensureLoaded() => _store.ensureInventoryPageDataLoaded();
  @override
  Future<Map<String, dynamic>> traceBatch(
    String batchId, {
    int maxDepth = 8,
  }) =>
      _store.traceInventoryBatch(batchId, maxDepth: maxDepth);
  @override
  Future<Map<String, dynamic>> verifyTraceabilityIntegrity() =>
      _store.verifyInventoryTraceabilityIntegrity();
}

final class _SecurityDomain implements SecurityDomainPort {
  _SecurityDomain(this._store);
  final AppStore _store;

  @override
  AppUser? get activeUser => _store.activeUser;
  @override
  String get currentRole => _store.currentRole;
  @override
  bool hasPermission(String permission) => _store.hasPermission(permission);
  @override
  void requirePermission(String permission) => _store.requirePermission(permission);
  @override
  Future<bool> authorizeSensitiveAction({
    required String action,
    required String password,
    Duration validity = const Duration(minutes: 3),
  }) =>
      _store.authorizeSensitiveAction(
        action: action,
        password: password,
        validity: validity,
      );
  @override
  void requireSensitiveActionAuthorization(String action) =>
      _store.requireSensitiveActionAuthorization(action);
  @override
  void clearSensitiveActionAuthorization() =>
      _store.clearSensitiveActionAuthorization();
}

final class _SyncDomain implements SyncDomainPort {
  _SyncDomain(this._store);
  final AppStore _store;

  @override
  List<SyncChange> get changes => _store.syncChanges;
  @override
  List<SyncQueueItem> get queue => _store.syncQueue;
  @override
  int get sequence => _store.currentSyncSequence;
  @override
  Future<void> ensureLoaded() => _store.ensureSyncDataLoaded();
  @override
  Future<void> retryFailed({String? target}) =>
      _store.retryFailedSyncQueue(target: target);
  @override
  Future<void> recoverStale({
    String? target,
    Duration staleAfter = const Duration(seconds: 45),
  }) =>
      _store.recoverStaleInProgressSyncQueue(
        target: target,
        staleAfter: staleAfter,
      );
}

final class _RecoveryDomain implements RecoveryDomainPort {
  _RecoveryDomain(this._store);
  final AppStore _store;

  @override
  Future<String> exportBackupJson() => _store.exportBackupJson();
  @override
  Future<void> importBackupJson(
    String rawJson, {
    Set<String>? selectedSectionIds,
  }) =>
      _store.importBackupJson(
        rawJson,
        selectedSectionIds: selectedSectionIds,
      );
  @override
  String exportRecoveryFileJson({String controlPlaneApiUrl = ''}) =>
      _store.exportRecoveryFileJson(controlPlaneApiUrl: controlPlaneApiUrl);
  @override
  Map<String, String> parseRecoveryFileJson(String rawJson) =>
      _store.parseRecoveryFileJson(rawJson);
}
