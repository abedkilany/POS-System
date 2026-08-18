import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/cash_ledger_transaction.dart';
import '../../models/journal_entry.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
import 'cash_ledger_service.dart';

/// Phase 5 authoritative service for non-invoice cash operations.
///
/// Deposit, withdrawal and expense are committed atomically as:
/// operation row + journal entry + cash ledger row + cash location balance.
/// Transfers remain owned by AccountingService.createCashTransfer so existing
/// callers (shift open/close and accounting UI) use the same authoritative path.
class CashOperationService {
  CashOperationService(this._db) : _ledger = CashLedgerService(_db);

  factory CashOperationService.current() {
    final db = SqliteMigrationManager.database;
    if (db == null) throw StateError('SQLite database is not initialized.');
    return CashOperationService(db);
  }

  final VentioDriftDatabase _db;
  final CashLedgerService _ledger;
  static final Random _random = Random.secure();

  Future<CashOperationResult> deposit({
    required String cashLocationId,
    required double amount,
    String cashDrawerSessionId = '',
    String currency = 'USD',
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    String idempotencyKey = '',
    DateTime? date,
  }) {
    return _post(
      type: 'cash_deposit',
      direction: 'in',
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      amount: amount,
      currency: currency,
      notes: notes,
      createdBy: createdBy,
      createdByUserId: createdByUserId,
      deviceId: deviceId,
      branchId: branchId,
      storeId: storeId,
      idempotencyKey: idempotencyKey,
      date: date,
    );
  }

  Future<CashOperationResult> withdrawal({
    required String cashLocationId,
    required double amount,
    String cashDrawerSessionId = '',
    String currency = 'USD',
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    String idempotencyKey = '',
    DateTime? date,
  }) {
    return _post(
      type: 'cash_withdrawal',
      direction: 'out',
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      amount: amount,
      currency: currency,
      notes: notes,
      createdBy: createdBy,
      createdByUserId: createdByUserId,
      deviceId: deviceId,
      branchId: branchId,
      storeId: storeId,
      idempotencyKey: idempotencyKey,
      date: date,
    );
  }

  Future<CashOperationResult> expense({
    required String cashLocationId,
    required double amount,
    String cashDrawerSessionId = '',
    String currency = 'USD',
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    String idempotencyKey = '',
    DateTime? date,
  }) {
    return _post(
      type: 'expense',
      direction: 'out',
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      amount: amount,
      currency: currency,
      notes: notes,
      createdBy: createdBy,
      createdByUserId: createdByUserId,
      deviceId: deviceId,
      branchId: branchId,
      storeId: storeId,
      idempotencyKey: idempotencyKey,
      date: date,
    );
  }

  Future<CashOperationResult> _post({
    required String type,
    required String direction,
    required String cashLocationId,
    required String cashDrawerSessionId,
    required double amount,
    required String currency,
    required String notes,
    required String createdBy,
    required String createdByUserId,
    required String deviceId,
    required String branchId,
    required String storeId,
    required String idempotencyKey,
    DateTime? date,
  }) async {
    final cleanLocationId = cashLocationId.trim();
    if (cleanLocationId.isEmpty) throw ArgumentError('Cash location is required.');
    final cleanAmount = _money(amount);
    if (cleanAmount <= 0) throw ArgumentError('Amount must be greater than zero.');
    final when = (date ?? DateTime.now()).toUtc();
    final key = idempotencyKey.trim();

    return _db.transaction(() async {
      if (key.isNotEmpty) {
        final existing = await _db.customSelect(
          "SELECT id, journal_entry_id FROM cash_operations WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
          variables: <Variable<Object>>[Variable<String>(key)],
        ).getSingleOrNull();
        if (existing != null) {
          return CashOperationResult(
            id: existing.data['id']?.toString() ?? '',
            journalEntryId: existing.data['journal_entry_id']?.toString() ?? '',
          );
        }
      }

      final location = await _db.customSelect(
        "SELECT id, name, account_id, current_balance, allow_negative FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(cleanLocationId)],
      ).getSingleOrNull();
      if (location == null) throw StateError('Cash location does not exist or is inactive.');
      final cashAccountId = location.data['account_id']?.toString().trim() ?? '';
      if (cashAccountId.isEmpty) throw StateError('Cash location has no accounting account.');

      final sessionId = cashDrawerSessionId.trim();
      if (sessionId.isNotEmpty) {
        final session = await _db.customSelect(
          "SELECT id FROM cash_drawer_sessions WHERE id = ? AND cash_location_id = ? AND status = 'open' LIMIT 1",
          variables: <Variable<Object>>[
            Variable<String>(sessionId),
            Variable<String>(cleanLocationId),
          ],
        ).getSingleOrNull();
        if (session == null) throw StateError('Cash drawer session is not open for this location.');
      }

      if (direction == 'out') {
        final balance = (location.data['current_balance'] as num?)?.toDouble() ?? 0;
        final allowNegative = ((location.data['allow_negative'] as num?)?.toInt() ?? 0) == 1;
        if (!allowNegative && balance + 0.000001 < cleanAmount) {
          throw StateError('Insufficient cash balance for this operation.');
        }
      }

      final settingsRows = await _db.customSelect(
        "SELECT key, account_id FROM accounting_settings WHERE key IN ('default_equity_account_id', 'default_expense_account_id')",
      ).get();
      final settings = <String, String>{
        for (final row in settingsRows)
          row.data['key']?.toString() ?? '': row.data['account_id']?.toString() ?? '',
      };
      final counterpart = type == 'expense'
          ? (settings['default_expense_account_id']?.trim() ?? '')
          : (settings['default_equity_account_id']?.trim().isNotEmpty == true
              ? settings['default_equity_account_id']!.trim()
              : 'acc_equity');
      if (counterpart.isEmpty) throw StateError('Required accounting account is not configured.');

      final id = _newId('cashop');
      final referenceNo = _referenceNo(type, when);
      final isIn = direction == 'in';
      final description = switch (type) {
        'cash_deposit' => 'Cash deposit - ${location.data['name']?.toString() ?? ''}',
        'cash_withdrawal' => 'Cash withdrawal - ${location.data['name']?.toString() ?? ''}',
        'expense' => 'Cash expense - ${location.data['name']?.toString() ?? ''}',
        _ => 'Cash operation',
      };
      final entryId = await AccountingService.createPostedEntry(
        JournalEntryDraft(
          entryDate: when,
          referenceType: type,
          referenceId: id,
          referenceNo: referenceNo,
          description: description,
          source: 'cash',
          createdBy: createdBy.trim(),
          storeId: storeId.trim(),
          branchId: branchId.trim(),
          lines: isIn
              ? <JournalLineDraft>[
                  JournalLineDraft(accountId: cashAccountId, debit: cleanAmount, credit: 0, memo: description),
                  JournalLineDraft(accountId: counterpart, debit: 0, credit: cleanAmount, memo: 'Cash deposit source'),
                ]
              : <JournalLineDraft>[
                  JournalLineDraft(accountId: counterpart, debit: cleanAmount, credit: 0, memo: type == 'expense' ? 'Cash expense' : 'Cash withdrawal destination'),
                  JournalLineDraft(accountId: cashAccountId, debit: 0, credit: cleanAmount, memo: description),
                ],
        ),
        database: _db,
      );
      if (entryId.isEmpty) throw StateError('Cash operation journal was not created.');

      final now = DateTime.now().toUtc();
      await _db.customInsert(
        '''
        INSERT INTO cash_operations
          (id, operation_no, operation_type, operation_date, cash_location_id,
           cash_drawer_session_id, amount, currency, journal_entry_id, notes,
           created_by, created_by_user_id, device_id, store_id, branch_id,
           idempotency_key, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(id), Variable<String>(referenceNo), Variable<String>(type),
          Variable<String>(when.toIso8601String()), Variable<String>(cleanLocationId),
          Variable<String>(sessionId), Variable<double>(cleanAmount),
          Variable<String>(_currency(currency)), Variable<String>(entryId),
          Variable<String>(notes.trim()), Variable<String>(createdBy.trim()),
          Variable<String>(createdByUserId.trim()), Variable<String>(deviceId.trim()),
          Variable<String>(storeId.trim()), Variable<String>(branchId.trim()),
          Variable<String>(key), Variable<String>(now.toIso8601String()),
          Variable<String>(now.toIso8601String()),
        ],
      );

      await _ledger.appendInExistingTransaction(CashLedgerTransaction(
        id: _newId('cashledger'),
        type: type,
        direction: direction,
        amount: cleanAmount,
        currency: _currency(currency),
        cashLocationId: cleanLocationId,
        cashDrawerSessionId: sessionId,
        referenceType: type,
        referenceId: id,
        referenceNumber: referenceNo,
        paymentMethod: 'Cash',
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        notes: notes.trim(),
        idempotencyKey: key.isEmpty ? '' : '$key:ledger',
        occurredAt: when,
        createdAt: now,
        updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      ));

      await _db.customUpdate(
        'UPDATE cash_locations SET current_balance = current_balance + ?, updated_at = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<double>(isIn ? cleanAmount : -cleanAmount),
          Variable<String>(now.toIso8601String()),
          Variable<String>(cleanLocationId),
        ],
      );
      return CashOperationResult(id: id, journalEntryId: entryId);
    });
  }

  String _newId(String prefix) => '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}';
  double _money(double value) => value.isFinite ? (value * 100).roundToDouble() / 100 : 0;
  String _currency(String value) => value.trim().isEmpty ? 'USD' : value.trim().toUpperCase();
  String _referenceNo(String type, DateTime when) {
    final prefix = switch (type) {'cash_deposit' => 'CD', 'cash_withdrawal' => 'CW', 'expense' => 'CE', _ => 'CO'};
    return '$prefix-${when.microsecondsSinceEpoch}';
  }
}

class CashOperationResult {
  const CashOperationResult({required this.id, required this.journalEntryId});
  final String id;
  final String journalEntryId;
}
