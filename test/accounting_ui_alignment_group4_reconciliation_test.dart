import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_production_integrity_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';

import 'phase5_manufacturing_transfer_test.dart' as support;

void main() {
  test('closure gate detects cash-location vs GL mismatch', () async {
    await support.readyPhase5SqliteStore();
    final db = SqliteMigrationManager.database!;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.customInsert(
      '''
      INSERT INTO cash_locations
        (id, code, name, type, account_id, current_balance,
         created_at, updated_at, deleted_at)
      VALUES ('closure-cash-location', 'CLOSE-CASH', 'Closure Cash',
              'cash_drawer', 'acc_cash', 17, ?, ?, '')
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final report = await AccountingProductionIntegrityService(db).audit();
    expect(report.isProductionReady, isFalse);
    expect(
      report.issues.any((issue) => issue.code == 'cash_location_gl_mismatch'),
      isTrue,
    );
  });

  test('closure gate detects customer subledger vs control-account mismatch', () async {
    await support.readyPhase5SqliteStore();
    final db = SqliteMigrationManager.database!;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.customInsert(
      '''
      INSERT INTO account_transactions
        (id, entity_type, account_type, account_id, account_name, transaction_date,
         transaction_type, reference_id, reference_no, debit, credit,
         currency, payment_method, note, created_at, updated_at, deleted_at)
      VALUES ('closure-customer-at', 'account_transaction', 'customer', 'closure-customer',
              'Closure Customer', ?, 'manual_adjustment', 'closure-ref',
              'CLOSE-CUST', 25, 0, 'USD', '', 'forced closure mismatch',
              ?, ?, '')
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final report = await AccountingProductionIntegrityService(db).audit();
    expect(report.isProductionReady, isFalse);
    expect(
      report.issues.any(
        (issue) =>
            issue.code == 'customer_control_balance_mismatch' &&
            issue.entityId == 'closure-customer',
      ),
      isTrue,
    );
  });

  test('closure gate detects supplier subledger vs control-account mismatch', () async {
    await support.readyPhase5SqliteStore();
    final db = SqliteMigrationManager.database!;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.customInsert(
      '''
      INSERT INTO account_transactions
        (id, entity_type, account_type, account_id, account_name, transaction_date,
         transaction_type, reference_id, reference_no, debit, credit,
         currency, payment_method, note, created_at, updated_at, deleted_at)
      VALUES ('closure-supplier-at', 'account_transaction', 'supplier', 'closure-supplier',
              'Closure Supplier', ?, 'manual_adjustment', 'closure-ref',
              'CLOSE-SUP', 0, 31, 'USD', '', 'forced closure mismatch',
              ?, ?, '')
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final report = await AccountingProductionIntegrityService(db).audit();
    expect(report.isProductionReady, isFalse);
    expect(
      report.issues.any(
        (issue) =>
            issue.code == 'supplier_control_balance_mismatch' &&
            issue.entityId == 'closure-supplier',
      ),
      isTrue,
    );
  });
}
