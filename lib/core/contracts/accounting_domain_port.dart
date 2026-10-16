import '../../models/account_transaction.dart';
import '../../models/payment_allocation.dart';
import '../../models/tax_profile.dart';

abstract class AccountingDomainPort {
  List<AccountTransaction> get transactions;
  Future<void> ensureLoaded();
  int get revision;
  int get ledgerRevision;
  double accountBalance(String accountType, String accountId);
  List<AccountTransaction> transactionsForAccount(
    String accountType,
    String accountId,
  );
  Future<void> refreshFromSqlite();
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
  });
  Future<void> updateTaxConfiguration({
    required List<TaxProfile> profiles,
    required String defaultTaxProfileId,
  });
  Future<void> updateDefaultTaxRatePercent(double ratePercent);
}
