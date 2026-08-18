import 'package:drift/drift.dart';

import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
import 'cash_ledger_service.dart';

/// Phase 6 immutable reversal coordinator for cash events.
///
/// Reversals never delete the original Cash Ledger row. They append an
/// opposite movement linked through reversal_of_id, reverse the journal entry,
/// and mark the operational document as reversed when one exists.
class CashReversalService {
  CashReversalService(this._db) : _ledger = CashLedgerService(_db);

  factory CashReversalService.current() {
    final database = SqliteMigrationManager.database;
    if (database == null) throw StateError('SQLite database is not initialized.');
    return CashReversalService(database);
  }

  final VentioDriftDatabase _db;
  final CashLedgerService _ledger;

  Future<int> reverseReference({
    required String referenceType,
    required String referenceId,
    String reason = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    DateTime? occurredAt,
  }) async {
    final cleanType = referenceType.trim();
    final cleanId = referenceId.trim();
    if (cleanType.isEmpty || cleanId.isEmpty) {
      throw ArgumentError('referenceType and referenceId are required.');
    }

    return _db.transaction(() async {
      final reversed = await _ledger.reverseReference(
        referenceType: cleanType,
        referenceId: cleanId,
        reason: reason,
        createdBy: createdBy,
        createdByUserId: createdByUserId,
        deviceId: deviceId,
        occurredAt: occurredAt,
      );
      await AccountingService.reverseEntryForReference(
        referenceType: cleanType,
        referenceId: cleanId,
        reason: reason,
        createdBy: createdBy,
        adjustCashLocationBalance: false,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      switch (cleanType) {
        case 'cash_deposit':
        case 'cash_withdrawal':
        case 'expense':
          await _db.customUpdate(
            "UPDATE cash_operations SET status = 'reversed', updated_at = ? WHERE (id = ? OR idempotency_key = ?) AND deleted_at = ''",
            variables: <Variable<Object>>[
              Variable<String>(now),
              Variable<String>(cleanId),
              Variable<String>('expense:$cleanId'),
            ],
          );
          break;
        case 'cash_transfer':
          await _db.customUpdate(
            "UPDATE cash_transfers SET status = 'reversed', updated_at = ? WHERE id = ? AND deleted_at = ''",
            variables: <Variable<Object>>[
              Variable<String>(now),
              Variable<String>(cleanId),
            ],
          );
          break;
        case 'receipt_voucher':
          await _db.customUpdate(
            "UPDATE receipt_vouchers SET status = 'reversed', updated_at = ? WHERE id = ? AND deleted_at = ''",
            variables: <Variable<Object>>[
              Variable<String>(now),
              Variable<String>(cleanId),
            ],
          );
          break;
        case 'payment_voucher':
          await _db.customUpdate(
            "UPDATE payment_vouchers SET status = 'reversed', updated_at = ? WHERE id = ? AND deleted_at = ''",
            variables: <Variable<Object>>[
              Variable<String>(now),
              Variable<String>(cleanId),
            ],
          );
          break;
      }
      return reversed.length;
    });
  }
}
