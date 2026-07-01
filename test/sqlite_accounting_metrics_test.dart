import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

Future<void> _seedAccountingData(VentioDriftDatabase db) async {
  final today = DateTime(2026, 6, 30, 10);

  Future<void> addTxn({
    required String id,
    required String accountType,
    required String accountId,
    required String accountName,
    required String type,
    required double debit,
    required double credit,
    required String referenceNo,
  }) async {
    await BusinessSqliteStore.upsertEntityPayload(
      db,
      BusinessSqliteStore.accountTransactionsKey,
      <String, dynamic>{
        'id': id,
        'accountType': accountType,
        'accountId': accountId,
        'accountName': accountName,
        'date': today.toIso8601String(),
        'type': type,
        'referenceId': id,
        'referenceNo': referenceNo,
        'debit': debit,
        'credit': credit,
        'currency': 'USD',
        'paymentMethod': 'Cash',
      },
    );
  }

  await addTxn(
    id: 'cust-recv',
    accountType: 'customer',
    accountId: 'customer-a',
    accountName: 'Customer A',
    type: 'paymentReceived',
    debit: 50,
    credit: 0,
    referenceNo: 'RCV-1',
  );
  await addTxn(
    id: 'cust-credit',
    accountType: 'customer',
    accountId: 'customer-b',
    accountName: 'Customer B',
    type: 'paymentReversal',
    debit: 0,
    credit: 20,
    referenceNo: 'REV-1',
  );
  await addTxn(
    id: 'supp-pay',
    accountType: 'supplier',
    accountId: 'supplier-a',
    accountName: 'Supplier A',
    type: 'paymentPaid',
    debit: 0,
    credit: 70,
    referenceNo: 'PAY-1',
  );
  await addTxn(
    id: 'supp-advance',
    accountType: 'supplier',
    accountId: 'supplier-b',
    accountName: 'Supplier B',
    type: 'paymentReversal',
    debit: 30,
    credit: 0,
    referenceNo: 'REV-2',
  );
}

void main() {
  group('SQLite accounting metrics', () {
    late VentioDriftDatabase db;

    setUp(() async {
      db = VentioDriftDatabase(NativeDatabase.memory());
      await db.initializeFoundation();
      await _seedAccountingData(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('builds accounting metrics from SQLite aggregates', () async {
      final metrics = await BusinessSqliteStore.buildAccountingMetrics(
        db,
        reference: DateTime(2026, 6, 30, 12),
      );

      expect(metrics['customerReceivables'], 50);
      expect(metrics['customerCredits'], 20);
      expect(metrics['supplierPayables'], 70);
      expect(metrics['supplierAdvances'], 30);
      expect(metrics['todayCashIn'], 80);
      expect(metrics['todayCashOut'], 90);
    });
  });
}
