import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/journal_entry.dart';

Future<VentioDriftDatabase> _db() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  SqliteMigrationManager.useDatabaseForTesting(db);
  return db;
}

void main() {
  late VentioDriftDatabase db;

  setUp(() async {
    db = await _db();
  });

  tearDown(() async {
    await SqliteMigrationManager.resetForTesting();
  });

  test('Phase 1 seeds the complete chart idempotently', () async {
    await db.initializeFoundation();
    final rows = await db
        .customSelect(
          "SELECT id, code, parent_id, is_system, is_postable FROM accounts WHERE deleted_at = '' ORDER BY code",
        )
        .get();

    final codes = rows.map((row) => row.read<String>('code')).toList();
    expect(codes.toSet().length, codes.length);
    for (final requiredCode in <String>[
      '1000',
      '1410',
      '1420',
      '1430',
      '3200',
      '3300',
      '4110',
      '4400',
      '7100',
      '7200',
      '8100',
    ]) {
      expect(codes, contains(requiredCode));
    }

    final root = rows.firstWhere((row) => row.read<String>('code') == '1000');
    expect(root.read<int>('is_postable'), 0);

    // Existing control accounts stay postable in Phase 1 so current posting
    // rules are not changed before Phase 2 remaps them to dedicated children.
    final inventory =
        rows.firstWhere((row) => row.read<String>('code') == '1400');
    expect(inventory.read<int>('is_postable'), 1);
  });

  test('user account supports hierarchy and duplicate-code protection',
      () async {
    final created = await AccountingService.createAccount(
      code: '6111',
      name: 'إيجار مستودع',
      type: 'expense',
      normalBalance: 'debit',
      parentId: 'acc_rent_expense',
    );
    expect(created.parentId, 'acc_rent_expense');
    expect(created.isSystem, isFalse);
    expect(created.isPostable, isTrue);

    await expectLater(
      AccountingService.createAccount(
        code: '6111',
        name: 'Duplicate',
        type: 'expense',
        normalBalance: 'debit',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('non-postable grouping account cannot receive a new journal line',
      () async {
    final group = await AccountingService.createAccount(
      code: '6990',
      name: 'مجموعة اختبار',
      type: 'expense',
      normalBalance: 'debit',
      isPostable: false,
    );

    await expectLater(
      AccountingService.createPostedEntry(
        JournalEntryDraft(
          entryDate: DateTime(2026, 8, 23),
          referenceType: 'phase1_test',
          referenceId: 'non-postable',
          description: 'Non-postable account test',
          lines: <JournalLineDraft>[
            JournalLineDraft(accountId: group.id, debit: 10, credit: 0),
            const JournalLineDraft(accountId: 'acc_cash', debit: 0, credit: 10),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('used account cannot be deleted and custom account can be reactivated',
      () async {
    final account = await AccountingService.createAccount(
      code: '6991',
      name: 'مصروف اختبار',
      type: 'expense',
      normalBalance: 'debit',
      parentId: 'acc_expenses',
    );

    await AccountingService.createPostedEntry(
      JournalEntryDraft(
        entryDate: DateTime(2026, 8, 23),
        referenceType: 'phase1_test',
        referenceId: 'used-account',
        description: 'Used account test',
        lines: <JournalLineDraft>[
          JournalLineDraft(accountId: account.id, debit: 5, credit: 0),
          const JournalLineDraft(accountId: 'acc_cash', debit: 0, credit: 5),
        ],
      ),
    );

    await expectLater(
      AccountingService.deleteAccount(account.id),
      throwsA(isA<StateError>()),
    );

    final unused = await AccountingService.createAccount(
      code: '6992',
      name: 'حساب غير مستخدم',
      type: 'expense',
      normalBalance: 'debit',
      parentId: 'acc_expenses',
    );
    await AccountingService.setAccountActive(
        accountId: unused.id, active: false);
    await AccountingService.setAccountActive(
        accountId: unused.id, active: true);
    final rows = await AccountingService.listAccounts(activeOnly: false);
    expect(rows.firstWhere((row) => row.id == unused.id).isActive, isTrue);
  });
}
