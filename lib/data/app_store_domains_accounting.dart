part of 'app_store.dart';

final class _AccountingDomain implements AccountingDomainPort {
  _AccountingDomain(this._store);
  final AppStore _store;

  @override
  List<AccountTransaction> get transactions =>
      _store._accountTransactionsReadImpl;
  @override
  Future<void> ensureLoaded() => _store._ensureAccountTransactionsLoadedImpl();
  @override
  int get revision => _store._accountingRevisionReadImpl;
  @override
  int get ledgerRevision => _store._accountTransactionsRevision;
  @override
  double accountBalance(String accountType, String accountId) =>
      _store._accountBalanceReadImpl(accountType, accountId);
  @override
  List<AccountTransaction> transactionsForAccount(
    String accountType,
    String accountId,
  ) =>
      _store._accountTransactionsForAccountReadImpl(accountType, accountId);
  @override
  Future<void> refreshFromSqlite() =>
      _AppStoreSplitStartupMigrationsPart2(_store)
          .refreshAccountTransactionsFromSqlite();
  @override
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
      _AppStoreSplitWarehouseCashPart4(_store).settleAccountPayment(
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
        date: date,
      );
  @override
  Future<void> updateTaxConfiguration({
    required List<TaxProfile> profiles,
    required String defaultTaxProfileId,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store).updateTaxConfiguration(
        profiles: profiles,
        defaultTaxProfileId: defaultTaxProfileId,
      );
  @override
  Future<void> updateDefaultTaxRatePercent(double ratePercent) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store)
          .updateDefaultTaxRatePercent(ratePercent);
}
