import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_store_source.dart';

void main() {
  test(
      'Phase 1/2 authoritative workflows do not re-write financial ledgers after commit',
      () {
    final source = readAppStoreImplementationSource();

    expect(
      source,
      contains('final posted = candidate;'),
      reason: 'Expense post should mirror the atomically persisted preview.',
    );
    expect(
      source,
      contains(
          'await _saveDirty(expenses: false, accountTransactions: false, sync: true);'),
      reason:
          'Expense post must not schedule a second business/account ledger write.',
    );
    expect(
      source,
      contains(
          '// Return ledger and FIFO changes were committed inside the same SQLite'),
    );
    expect(
      source,
      contains(
          '// Cancel ledger and FIFO changes were committed inside the same SQLite'),
    );
    expect(
      source,
      contains('accountTransactions: !saleCreateWasAtomic'),
      reason:
          'Sale create may use legacy ledger writes only in the non-authoritative fallback.',
    );
    expect(
      source,
      contains('accountTransactions: !authoritativeSqlite'),
      reason:
          'Sale return must not schedule a duplicate account ledger write in SQLite-authoritative mode.',
    );
    expect(
      source,
      contains('accountTransactions: !saleCancelWasAtomic'),
      reason:
          'Sale cancel must not schedule a duplicate account ledger write in SQLite-authoritative mode.',
    );
  });
}
