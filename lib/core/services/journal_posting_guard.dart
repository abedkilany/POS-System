import 'package:drift/drift.dart';
import '../storage/sqlite/ventio_drift_database.dart';

/// Verifies persisted journals before the owning business transaction commits.
class JournalPostingGuard {
  const JournalPostingGuard(this.sqliteDb);
  final VentioDriftDatabase sqliteDb;

  Future<int> activeCount({
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
  }) async {
    final normalizedType = referenceType.trim();
    final normalizedId = referenceId.trim();
    if (normalizedType.isEmpty || normalizedId.isEmpty) return 0;
    final row = await sqliteDb.customSelect(
      (includePurchaseEditFamily || includeSaleEditFamily)
          ? r'''
      SELECT COUNT(*) AS count
      FROM journal_entries je
      WHERE je.reference_type = ?
        AND (je.reference_id = ? OR instr(je.reference_id, ?) = 1)
        AND je.deleted_at = ''
        AND je.status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries reversal
          WHERE reversal.reversed_entry_id = je.id
            AND reversal.deleted_at = ''
            AND reversal.status = 'posted'
        )
      '''
          : r'''
      SELECT COUNT(*) AS count
      FROM journal_entries je
      WHERE je.reference_type = ?
        AND je.reference_id = ?
        AND je.deleted_at = ''
        AND je.status = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries reversal
          WHERE reversal.reversed_entry_id = je.id
            AND reversal.deleted_at = ''
            AND reversal.status = 'posted'
        )
      ''',
      variables: <Variable<Object>>[
        Variable<String>(normalizedType),
        Variable<String>(normalizedId),
        if (includePurchaseEditFamily || includeSaleEditFamily)
          Variable<String>(includePurchaseEditFamily
              ? '$normalizedId:purchase_edit:'
              : '$normalizedId:sale_edit:'),
      ],
    ).getSingle();
    return (row.data['count'] as num? ?? 0).toInt();
  }

  Future<void> requirePosted({
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  }) async {
    final count = await activeCount(
      referenceType: referenceType,
      referenceId: referenceId,
      includePurchaseEditFamily: includePurchaseEditFamily,
      includeSaleEditFamily: includeSaleEditFamily,
    );
    if (count <= 0) throw StateError(failureMessage);
  }

  Future<void> requireReversed({
    required String referenceType,
    required String referenceId,
    bool includePurchaseEditFamily = false,
    bool includeSaleEditFamily = false,
    required String failureMessage,
  }) async {
    final count = await activeCount(
      referenceType: referenceType,
      referenceId: referenceId,
      includePurchaseEditFamily: includePurchaseEditFamily,
      includeSaleEditFamily: includeSaleEditFamily,
    );
    if (count > 0) throw StateError(failureMessage);
  }
}
