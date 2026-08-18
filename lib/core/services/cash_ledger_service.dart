import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/cash_ledger_transaction.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';

/// Phase 1 authoritative access layer for cash-ledger movements.
///
/// Phase 2 vouchers may append to this ledger atomically, while legacy
/// sales/purchases UI paths remain unchanged until Phase 3. The service provides
/// transaction-safe append, idempotency, paging and balance queries over SQLite
/// without hydrating AppStore lists.
class CashLedgerService {
  CashLedgerService(this._db);

  factory CashLedgerService.current() {
    final database = SqliteMigrationManager.database;
    if (database == null) {
      throw StateError('SQLite database is not initialized.');
    }
    return CashLedgerService(database);
  }

  final VentioDriftDatabase _db;
  static final Random _random = Random.secure();

  String generateId() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'cash_tx_${micros}_${_random.nextInt(1 << 32).toRadixString(16)}';
  }

  Future<CashLedgerTransaction> append({
    required String type,
    required String direction,
    required double amount,
    required String cashLocationId,
    String id = '',
    String currency = 'USD',
    String cashDrawerSessionId = '',
    String referenceType = '',
    String referenceId = '',
    String referenceNumber = '',
    String partyType = '',
    String partyId = '',
    String partyName = '',
    String paymentMethod = 'Cash',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    String notes = '',
    String idempotencyKey = '',
    DateTime? occurredAt,
    String reversalOfId = '',
  }) async {
    final normalizedDirection = direction.trim().toLowerCase();
    if (normalizedDirection != 'in' && normalizedDirection != 'out') {
      throw ArgumentError.value(direction, 'direction', 'Must be in or out.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero.');
    }
    if (type.trim().isEmpty) {
      throw ArgumentError.value(type, 'type', 'Must not be empty.');
    }
    if (cashLocationId.trim().isEmpty) {
      throw ArgumentError.value(
          cashLocationId, 'cashLocationId', 'Must not be empty.');
    }

    final now = DateTime.now().toUtc();
    final transaction = CashLedgerTransaction(
      id: id.trim().isEmpty ? generateId() : id.trim(),
      type: type.trim(),
      direction: normalizedDirection,
      amount: amount,
      currency: currency.trim().isEmpty ? 'USD' : currency.trim().toUpperCase(),
      cashLocationId: cashLocationId.trim(),
      cashDrawerSessionId: cashDrawerSessionId.trim(),
      referenceType: referenceType.trim(),
      referenceId: referenceId.trim(),
      referenceNumber: referenceNumber.trim(),
      partyType: partyType.trim(),
      partyId: partyId.trim(),
      partyName: partyName.trim(),
      paymentMethod: paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim(),
      createdBy: createdBy.trim(),
      createdByUserId: createdByUserId.trim(),
      deviceId: deviceId.trim(),
      branchId: branchId.trim(),
      storeId: storeId.trim(),
      notes: notes.trim(),
      idempotencyKey: idempotencyKey.trim(),
      occurredAt: (occurredAt ?? now).toUtc(),
      createdAt: now,
      updatedAt: now,
      reversalOfId: reversalOfId.trim(),
      lastModifiedByDeviceId: deviceId.trim(),
    );

    return _db.transaction(() => appendInExistingTransaction(transaction));
  }

  /// Appends a pre-built ledger row inside the caller's active Drift transaction.
  /// This is used by Phase 2 vouchers so voucher + allocations + ledger + cache
  /// updates commit atomically. Callers outside a transaction should use [append].
  Future<CashLedgerTransaction> appendInExistingTransaction(
      CashLedgerTransaction transaction) async {
    await _validateLinks(transaction);

    if (transaction.idempotencyKey.isNotEmpty) {
      final existing = await _findByIdempotencyKey(transaction.idempotencyKey);
      if (existing != null) return existing;
    }

    await _db.customInsert(
        r'''
        INSERT INTO cash_ledger_transactions (
          id, type, direction, amount, currency, cash_location_id,
          cash_drawer_session_id, reference_type, reference_id, reference_number,
          party_type, party_id, party_name, payment_method,
          created_by, created_by_user_id, device_id, branch_id, store_id, notes,
          idempotency_key, occurred_at, created_at, updated_at, deleted_at,
          reversal_of_id, sync_status, version, last_modified_by_device_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, 'pending', 1, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(transaction.id),
          Variable<String>(transaction.type),
          Variable<String>(transaction.direction),
          Variable<double>(transaction.amount),
          Variable<String>(transaction.currency),
          Variable<String>(transaction.cashLocationId),
          Variable<String>(transaction.cashDrawerSessionId),
          Variable<String>(transaction.referenceType),
          Variable<String>(transaction.referenceId),
          Variable<String>(transaction.referenceNumber),
          Variable<String>(transaction.partyType),
          Variable<String>(transaction.partyId),
          Variable<String>(transaction.partyName),
          Variable<String>(transaction.paymentMethod),
          Variable<String>(transaction.createdBy),
          Variable<String>(transaction.createdByUserId),
          Variable<String>(transaction.deviceId),
          Variable<String>(transaction.branchId),
          Variable<String>(transaction.storeId),
          Variable<String>(transaction.notes),
          Variable<String>(transaction.idempotencyKey),
          Variable<String>(transaction.occurredAt.toIso8601String()),
          Variable<String>(transaction.createdAt.toIso8601String()),
          Variable<String>(transaction.updatedAt.toIso8601String()),
          Variable<String>(transaction.reversalOfId),
          Variable<String>(transaction.lastModifiedByDeviceId),
        ],
    );
    return transaction;
  }


  Future<CashLedgerTransaction?> reverseTransaction({
    required String transactionId,
    String reason = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    DateTime? occurredAt,
  }) async {
    final original = await findById(transactionId);
    if (original == null) return null;
    return _db.transaction(() => reverseTransactionInExistingTransaction(
          original,
          reason: reason,
          createdBy: createdBy,
          createdByUserId: createdByUserId,
          deviceId: deviceId,
          occurredAt: occurredAt,
        ));
  }

  Future<CashLedgerTransaction> reverseTransactionInExistingTransaction(
    CashLedgerTransaction original, {
    String reason = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    DateTime? occurredAt,
  }) async {
    final existing = await _db.customSelect(
      "SELECT * FROM cash_ledger_transactions WHERE reversal_of_id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(original.id)],
    ).getSingleOrNull();
    if (existing != null) return _fromRow(existing.data);

    final when = (occurredAt ?? DateTime.now()).toUtc();
    final reversal = CashLedgerTransaction(
      id: generateId(),
      type: 'reversal',
      direction: original.direction == 'in' ? 'out' : 'in',
      amount: original.amount,
      currency: original.currency,
      cashLocationId: original.cashLocationId,
      cashDrawerSessionId: original.cashDrawerSessionId,
      referenceType: '${original.referenceType}_reversal',
      referenceId: original.referenceId,
      referenceNumber: original.referenceNumber,
      partyType: original.partyType,
      partyId: original.partyId,
      partyName: original.partyName,
      paymentMethod: original.paymentMethod,
      createdBy: createdBy.trim().isEmpty ? original.createdBy : createdBy.trim(),
      createdByUserId: createdByUserId.trim(),
      deviceId: deviceId.trim().isEmpty ? original.deviceId : deviceId.trim(),
      branchId: original.branchId,
      storeId: original.storeId,
      notes: reason.trim().isEmpty ? 'Reversal of ${original.id}' : reason.trim(),
      idempotencyKey: 'reversal:${original.id}',
      occurredAt: when,
      createdAt: when,
      updatedAt: when,
      reversalOfId: original.id,
      lastModifiedByDeviceId: deviceId.trim().isEmpty ? original.lastModifiedByDeviceId : deviceId.trim(),
    );
    final saved = await appendInExistingTransaction(reversal);
    final delta = saved.direction == 'in' ? saved.amount : -saved.amount;
    await _db.customUpdate(
      "UPDATE cash_locations SET current_balance = current_balance + ?, updated_at = ? WHERE id = ? AND deleted_at = ''",
      variables: <Variable<Object>>[
        Variable<double>(delta),
        Variable<String>(when.toIso8601String()),
        Variable<String>(saved.cashLocationId),
      ],
    );
    return saved;
  }

  Future<List<CashLedgerTransaction>> reverseReference({
    required String referenceType,
    required String referenceId,
    String reason = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    DateTime? occurredAt,
  }) async {
    final rows = await list(
      referenceType: referenceType,
      referenceId: referenceId,
      limit: 500,
    );
    if (rows.isEmpty) return const <CashLedgerTransaction>[];
    return _db.transaction(() async {
      final result = <CashLedgerTransaction>[];
      for (final row in rows) {
        if (row.reversalOfId.isNotEmpty) continue;
        result.add(await reverseTransactionInExistingTransaction(
          row,
          reason: reason,
          createdBy: createdBy,
          createdByUserId: createdByUserId,
          deviceId: deviceId,
          occurredAt: occurredAt,
        ));
      }
      return result;
    });
  }

  Future<CashLedgerTransaction?> findById(String id) async {
    if (id.trim().isEmpty) return null;
    final row = await _db.customSelect(
      "SELECT * FROM cash_ledger_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id.trim())],
    ).getSingleOrNull();
    return row == null ? null : _fromRow(row.data);
  }

  Future<List<CashLedgerTransaction>> list({
    String cashLocationId = '',
    String cashDrawerSessionId = '',
    String referenceType = '',
    String referenceId = '',
    String direction = '',
    String type = '',
    String paymentMethod = '',
    String userId = '',
    String search = '',
    DateTime? from,
    DateTime? to,
    int limit = 100,
    int offset = 0,
  }) async {
    final query = _buildFilterQuery(
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      referenceType: referenceType,
      referenceId: referenceId,
      direction: direction,
      type: type,
      paymentMethod: paymentMethod,
      userId: userId,
      search: search,
      from: from,
      to: to,
    );
    final variables = <Variable<Object>>[...query.variables];
    variables.add(Variable<int>(limit.clamp(1, 500).toInt()));
    variables.add(Variable<int>(offset < 0 ? 0 : offset));
    final rows = await _db.customSelect(
      'SELECT * FROM cash_ledger_transactions WHERE ${query.whereSql} '
      'ORDER BY occurred_at DESC, created_at DESC LIMIT ? OFFSET ?',
      variables: variables,
    ).get();
    return rows.map((row) => _fromRow(row.data)).toList(growable: false);
  }

  Future<int> count({
    String cashLocationId = '',
    String cashDrawerSessionId = '',
    String referenceType = '',
    String referenceId = '',
    String direction = '',
    String type = '',
    String paymentMethod = '',
    String userId = '',
    String search = '',
    DateTime? from,
    DateTime? to,
  }) async {
    final query = _buildFilterQuery(
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      referenceType: referenceType,
      referenceId: referenceId,
      direction: direction,
      type: type,
      paymentMethod: paymentMethod,
      userId: userId,
      search: search,
      from: from,
      to: to,
    );
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS total FROM cash_ledger_transactions WHERE ${query.whereSql}',
      variables: query.variables,
    ).getSingle();
    return (row.data['total'] as num?)?.toInt() ?? 0;
  }

  Future<CashLedgerSummary> summary({
    String cashLocationId = '',
    String cashDrawerSessionId = '',
    String referenceType = '',
    String referenceId = '',
    String direction = '',
    String type = '',
    String paymentMethod = '',
    String userId = '',
    String search = '',
    DateTime? from,
    DateTime? to,
  }) async {
    final query = _buildFilterQuery(
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
      referenceType: referenceType,
      referenceId: referenceId,
      direction: direction,
      type: type,
      paymentMethod: paymentMethod,
      userId: userId,
      search: search,
      from: from,
      to: to,
    );
    final row = await _db.customSelect(
      '''
      SELECT
        COUNT(*) AS movement_count,
        COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END), 0) AS cash_in,
        COALESCE(SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END), 0) AS cash_out
      FROM cash_ledger_transactions
      WHERE ${query.whereSql}
      ''',
      variables: query.variables,
    ).getSingle();
    final cashIn = (row.data['cash_in'] as num?)?.toDouble() ?? 0;
    final cashOut = (row.data['cash_out'] as num?)?.toDouble() ?? 0;
    return CashLedgerSummary(
      movementCount: (row.data['movement_count'] as num?)?.toInt() ?? 0,
      cashIn: cashIn,
      cashOut: cashOut,
    );
  }


  Future<DateTime?> sessionOpenedAt(String sessionId) async {
    final id = sessionId.trim();
    if (id.isEmpty) return null;
    final row = await _db.customSelect(
      'SELECT opened_at FROM cash_drawer_sessions WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    return DateTime.tryParse(row?.data['opened_at']?.toString() ?? '');
  }

  Future<CashLedgerDetails> detailsFor(CashLedgerTransaction item) async {
    final location = await _db.customSelect(
      "SELECT name, code FROM cash_locations WHERE id = ? LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(item.cashLocationId)],
    ).getSingleOrNull();
    final session = item.cashDrawerSessionId.isEmpty
        ? null
        : await _db.customSelect(
            '''
            SELECT drawer_no, opened_at, closed_at, status, opened_by, closed_by
            FROM cash_drawer_sessions WHERE id = ? LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(item.cashDrawerSessionId),
            ],
          ).getSingleOrNull();
    final allocations = item.referenceId.isEmpty
        ? const <QueryRow>[]
        : await _db.customSelect(
            '''
            SELECT reference_type, reference_id, reference_number,
                   reference_amount, reference_currency
            FROM payment_allocations
            WHERE voucher_id = ? AND deleted_at = ''
            ORDER BY created_at ASC
            ''',
            variables: <Variable<Object>>[Variable<String>(item.referenceId)],
          ).get();
    final journal = item.referenceType.isEmpty || item.referenceId.isEmpty
        ? null
        : await _db.customSelect(
            '''
            SELECT id, entry_no, entry_date, status, description
            FROM journal_entries
            WHERE reference_type = ? AND reference_id = ? AND deleted_at = ''
            ORDER BY created_at DESC LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(item.referenceType),
              Variable<String>(item.referenceId),
            ],
          ).getSingleOrNull();
    return CashLedgerDetails(
      cashLocationName: location?.data['name']?.toString() ?? '',
      cashLocationCode: location?.data['code']?.toString() ?? '',
      sessionNumber: session?.data['drawer_no']?.toString() ?? '',
      sessionStatus: session?.data['status']?.toString() ?? '',
      sessionOpenedAt: DateTime.tryParse(session?.data['opened_at']?.toString() ?? ''),
      sessionClosedAt: DateTime.tryParse(session?.data['closed_at']?.toString() ?? ''),
      sessionOpenedBy: session?.data['opened_by']?.toString() ?? '',
      sessionClosedBy: session?.data['closed_by']?.toString() ?? '',
      journalEntryId: journal?.data['id']?.toString() ?? '',
      journalEntryNo: journal?.data['entry_no']?.toString() ?? '',
      journalStatus: journal?.data['status']?.toString() ?? '',
      journalDescription: journal?.data['description']?.toString() ?? '',
      allocationReferences: allocations
          .map((row) => CashLedgerAllocationReference(
                referenceType: row.data['reference_type']?.toString() ?? '',
                referenceId: row.data['reference_id']?.toString() ?? '',
                referenceNumber: row.data['reference_number']?.toString() ?? '',
                amount: (row.data['reference_amount'] as num?)?.toDouble() ?? 0,
                currency: row.data['reference_currency']?.toString() ?? 'USD',
              ))
          .toList(growable: false),
    );
  }

  _CashLedgerFilterQuery _buildFilterQuery({
    required String cashLocationId,
    required String cashDrawerSessionId,
    required String referenceType,
    required String referenceId,
    required String direction,
    required String type,
    required String paymentMethod,
    required String userId,
    required String search,
    required DateTime? from,
    required DateTime? to,
  }) {
    final clauses = <String>["deleted_at = ''"];
    final variables = <Variable<Object>>[];
    void eq(String column, String value) {
      if (value.trim().isEmpty) return;
      clauses.add('$column = ?');
      variables.add(Variable<String>(value.trim()));
    }

    eq('cash_location_id', cashLocationId);
    eq('cash_drawer_session_id', cashDrawerSessionId);
    eq('reference_type', referenceType);
    eq('reference_id', referenceId);
    eq('direction', direction.toLowerCase());
    eq('type', type);
    eq('payment_method', paymentMethod);
    eq('created_by_user_id', userId);
    if (from != null) {
      clauses.add('occurred_at >= ?');
      variables.add(Variable<String>(from.toUtc().toIso8601String()));
    }
    if (to != null) {
      clauses.add('occurred_at <= ?');
      variables.add(Variable<String>(to.toUtc().toIso8601String()));
    }
    final normalizedSearch = search.trim();
    if (normalizedSearch.isNotEmpty) {
      final pattern = '%$normalizedSearch%';
      clauses.add('''(
        id LIKE ? OR reference_number LIKE ? OR reference_id LIKE ? OR
        party_name LIKE ? OR created_by LIKE ? OR notes LIKE ? OR payment_method LIKE ? OR
        EXISTS (
          SELECT 1 FROM payment_allocations pa
          WHERE pa.voucher_id = cash_ledger_transactions.reference_id
            AND pa.deleted_at = ''
            AND (pa.reference_number LIKE ? OR pa.reference_id LIKE ?)
        )
      )''');
      for (var index = 0; index < 9; index += 1) {
        variables.add(Variable<String>(pattern));
      }
    }
    return _CashLedgerFilterQuery(clauses.join(' AND '), variables);
  }

  Future<double> balanceForLocation(String cashLocationId,
      {DateTime? through}) async {
    if (cashLocationId.trim().isEmpty) return 0;
    final timeClause = through == null ? '' : 'AND occurred_at <= ?';
    final row = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END), 0) AS balance
      FROM cash_ledger_transactions
      WHERE cash_location_id = ? AND deleted_at = '' $timeClause
      ''',
      variables: <Variable<Object>>[
        Variable<String>(cashLocationId.trim()),
        if (through != null)
          Variable<String>(through.toUtc().toIso8601String()),
      ],
    ).getSingle();
    return (row.data['balance'] as num?)?.toDouble() ?? 0;
  }

  Future<double> movementTotalForSession(String sessionId) async {
    if (sessionId.trim().isEmpty) return 0;
    final row = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END), 0) AS total
      FROM cash_ledger_transactions
      WHERE cash_drawer_session_id = ? AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[Variable<String>(sessionId.trim())],
    ).getSingle();
    return (row.data['total'] as num?)?.toDouble() ?? 0;
  }

  Future<void> _validateLinks(CashLedgerTransaction item) async {
    final location = await _db.customSelect(
      "SELECT id FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(item.cashLocationId)],
    ).getSingleOrNull();
    if (location == null) {
      throw StateError('Cash location ${item.cashLocationId} does not exist or is inactive.');
    }
    if (item.cashDrawerSessionId.isNotEmpty) {
      final allowClosedSession = item.reversalOfId.isNotEmpty ||
          item.type == 'shortage' || item.type == 'overage' || item.type == 'closing';
      final session = await _db.customSelect(
        allowClosedSession
            ? '''
              SELECT id FROM cash_drawer_sessions
              WHERE id = ? AND cash_location_id = ? AND status IN ('open', 'closed')
              LIMIT 1
              '''
            : '''
              SELECT id FROM cash_drawer_sessions
              WHERE id = ? AND cash_location_id = ? AND status = 'open'
              LIMIT 1
              ''',
        variables: <Variable<Object>>[
          Variable<String>(item.cashDrawerSessionId),
          Variable<String>(item.cashLocationId),
        ],
      ).getSingleOrNull();
      if (session == null) {
        throw StateError(allowClosedSession
            ? 'Cash drawer session does not match this cash location.'
            : 'Cash drawer session is not open for this cash location.');
      }
    }
  }

  Future<CashLedgerTransaction?> _findByIdempotencyKey(String key) async {
    final row = await _db.customSelect(
      "SELECT * FROM cash_ledger_transactions WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(key)],
    ).getSingleOrNull();
    return row == null ? null : _fromRow(row.data);
  }

  CashLedgerTransaction _fromRow(Map<String, Object?> row) {
    DateTime parseDate(String key) =>
        DateTime.tryParse(row[key]?.toString() ?? '') ?? DateTime.now().toUtc();
    return CashLedgerTransaction(
      id: row['id']?.toString() ?? '',
      type: row['type']?.toString() ?? '',
      direction: row['direction']?.toString() ?? '',
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      currency: row['currency']?.toString() ?? 'USD',
      cashLocationId: row['cash_location_id']?.toString() ?? '',
      cashDrawerSessionId: row['cash_drawer_session_id']?.toString() ?? '',
      referenceType: row['reference_type']?.toString() ?? '',
      referenceId: row['reference_id']?.toString() ?? '',
      referenceNumber: row['reference_number']?.toString() ?? '',
      partyType: row['party_type']?.toString() ?? '',
      partyId: row['party_id']?.toString() ?? '',
      partyName: row['party_name']?.toString() ?? '',
      paymentMethod: row['payment_method']?.toString() ?? 'Cash',
      createdBy: row['created_by']?.toString() ?? '',
      createdByUserId: row['created_by_user_id']?.toString() ?? '',
      deviceId: row['device_id']?.toString() ?? '',
      branchId: row['branch_id']?.toString() ?? '',
      storeId: row['store_id']?.toString() ?? '',
      notes: row['notes']?.toString() ?? '',
      idempotencyKey: row['idempotency_key']?.toString() ?? '',
      occurredAt: parseDate('occurred_at'),
      createdAt: parseDate('created_at'),
      updatedAt: parseDate('updated_at'),
      deletedAt: DateTime.tryParse(row['deleted_at']?.toString() ?? ''),
      reversalOfId: row['reversal_of_id']?.toString() ?? '',
      syncStatus: row['sync_status']?.toString() ?? 'pending',
      version: (row['version'] as num?)?.toInt() ?? 1,
      lastModifiedByDeviceId:
          row['last_modified_by_device_id']?.toString() ?? '',
    );
  }
}

class CashLedgerSummary {
  const CashLedgerSummary({required this.movementCount, required this.cashIn, required this.cashOut});
  final int movementCount;
  final double cashIn;
  final double cashOut;
  double get net => cashIn - cashOut;
}

class CashLedgerDetails {
  const CashLedgerDetails({
    required this.cashLocationName, required this.cashLocationCode,
    required this.sessionNumber, required this.sessionStatus,
    required this.sessionOpenedAt, required this.sessionClosedAt,
    required this.sessionOpenedBy, required this.sessionClosedBy,
    required this.journalEntryId, required this.journalEntryNo,
    required this.journalStatus, required this.journalDescription,
    this.allocationReferences = const <CashLedgerAllocationReference>[],
  });
  final String cashLocationName;
  final String cashLocationCode;
  final String sessionNumber;
  final String sessionStatus;
  final DateTime? sessionOpenedAt;
  final DateTime? sessionClosedAt;
  final String sessionOpenedBy;
  final String sessionClosedBy;
  final String journalEntryId;
  final String journalEntryNo;
  final String journalStatus;
  final String journalDescription;
  final List<CashLedgerAllocationReference> allocationReferences;
}

class CashLedgerAllocationReference {
  const CashLedgerAllocationReference({
    required this.referenceType, required this.referenceId,
    required this.referenceNumber, required this.amount, required this.currency,
  });
  final String referenceType;
  final String referenceId;
  final String referenceNumber;
  final double amount;
  final String currency;
}

class _CashLedgerFilterQuery {
  const _CashLedgerFilterQuery(this.whereSql, this.variables);
  final String whereSql;
  final List<Variable<Object>> variables;
}

