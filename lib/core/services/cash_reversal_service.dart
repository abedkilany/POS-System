import 'package:drift/drift.dart';

import '../../models/cash_ledger_transaction.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
import 'cash_ledger_service.dart';
import 'payment_voucher_service.dart';

/// Phase 6 immutable reversal coordinator for cash events.
///
/// Reversals never delete the original Cash Ledger row. They append an
/// opposite movement linked through reversal_of_id, reverse the journal entry,
/// and mark the operational document as reversed/void when one exists.
class CashReversalService {
  CashReversalService(this._db) : _ledger = CashLedgerService(_db);

  factory CashReversalService.current() {
    final database = SqliteMigrationManager.database;
    if (database == null) {
      throw StateError('SQLite database is not initialized.');
    }
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

    if (cleanType == 'receipt_voucher') {
      final reversed = await PaymentVoucherService(_db).reverseReceiptVoucher(
        voucherId: cleanId,
        reason: reason,
        createdBy: createdBy,
        createdByUserId: createdByUserId,
        deviceId: deviceId,
        occurredAt: occurredAt,
      );
      return reversed ? 1 : 0;
    }
    if (cleanType == 'payment_voucher') {
      final reversed = await PaymentVoucherService(_db).reversePaymentVoucher(
        voucherId: cleanId,
        reason: reason,
        createdBy: createdBy,
        createdByUserId: createdByUserId,
        deviceId: deviceId,
        occurredAt: occurredAt,
      );
      return reversed ? 1 : 0;
    }

    final result = await _db.transaction(() async {
      final reversed = await _ledger.reverseReference(
        referenceType: cleanType,
        referenceId: cleanId,
        reason: reason,
        createdBy: createdBy,
        createdByUserId: createdByUserId,
        deviceId: deviceId,
        occurredAt: occurredAt,
      );
      if (reversed.isEmpty) {
        // An expense posted on credit has no Cash Ledger movement. It still
        // needs its accounting entry and document state reversed on cancel.
        if (cleanType == 'expense') {
          await AccountingService.reverseEntryForReference(
            referenceType: cleanType,
            referenceId: cleanId,
            reason: reason,
            createdBy: createdBy,
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
          await _finalizeExpenseCancellationInExistingTransaction(
            expenseId: cleanId,
            reason: reason,
            deviceId: deviceId,
            occurredAt: occurredAt,
          );
          return 1;
        }
        return 0;
      }
      await AccountingService.reverseEntryForReference(
        referenceType: cleanType,
        referenceId: cleanId,
        reason: reason,
        createdBy: createdBy,
        adjustCashLocationBalance: false,
        notifyChange: false,
        withinExistingTransaction: true,
      );
      if (cleanType == 'sale_refund' || cleanType == 'purchase_refund') {
        await _reverseCompatibilityRefundTransaction(
          referenceType: cleanType,
          referenceId: cleanId,
          reversedLedgerRows: reversed,
          reason: reason,
          deviceId: deviceId,
          occurredAt: occurredAt,
        );
        await _reverseRefundCoverage(
          refundId: cleanId,
          deviceId: deviceId,
          occurredAt: occurredAt,
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      switch (cleanType) {
        case 'cash_deposit':
        case 'cash_withdrawal':
        case 'expense':
          await _db.customUpdate(
            "UPDATE cash_operations SET status = 'reversed', reversed_at = ?, reversal_reason = ?, reversed_by = ?, reversed_by_user_id = ?, updated_at = ? WHERE (id = ? OR idempotency_key = ? OR idempotency_key LIKE ?) AND deleted_at = '' AND status = 'posted'",
            variables: <Variable<Object>>[
              Variable<String>(now),
              Variable<String>(reason.trim()),
              Variable<String>(createdBy.trim()),
              Variable<String>(createdByUserId.trim()),
              Variable<String>(now),
              Variable<String>(cleanId),
              Variable<String>('expense:$cleanId'),
              Variable<String>('expense:$cleanId:expense_edit:%'),
            ],
          );
          break;
        case 'cash_transfer':
          await _db.customUpdate(
            "UPDATE cash_transfers SET status = 'void', reversed_at = ?, reversal_reason = ?, reversed_by = ?, reversed_by_user_id = ?, updated_at = ? WHERE id = ? AND deleted_at = ''",
            variables: <Variable<Object>>[
              Variable<String>(now),
              Variable<String>(reason.trim()),
              Variable<String>(createdBy.trim()),
              Variable<String>(createdByUserId.trim()),
              Variable<String>(now),
              Variable<String>(cleanId),
            ],
          );
          break;
      }
      if (cleanType == 'expense') {
        await _finalizeExpenseCancellationInExistingTransaction(
          expenseId: cleanId,
          reason: reason,
          deviceId: deviceId,
          occurredAt: occurredAt,
        );
      }
      return reversed.length;
    });
    AccountingService.notifyCommittedMutation();
    return result;
  }

  Future<void> _finalizeExpenseCancellationInExistingTransaction({
    required String expenseId,
    required String reason,
    required String deviceId,
    DateTime? occurredAt,
  }) async {
    final row = await _db.customSelect(
      '''
      SELECT id, title, amount, original_currency, store_id, branch_id,
             version, last_modified_by_device_id
      FROM expenses
      WHERE id = ? AND deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(expenseId)],
    ).getSingleOrNull();
    if (row == null) {
      throw StateError('Expense $expenseId does not exist.');
    }
    final when = (occurredAt ?? DateTime.now()).toUtc();
    final now = when.toIso8601String();
    final cleanReason =
        reason.trim().isEmpty ? 'Expense cancelled' : reason.trim();
    final currentVersion = (row.data['version'] as num?)?.toInt() ?? 1;
    await _db.customUpdate(
      '''
      UPDATE expenses
      SET expense_status = 'Cancelled', cancel_reason = ?,
          cancelled_by_device_id = ?, cancelled_at = ?, updated_at = ?,
          device_id = ?, sync_status = 'pending', version = ?,
          last_modified_by_device_id = ?
      WHERE id = ? AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[
        Variable<String>(cleanReason),
        Variable<String>(deviceId.trim()),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(deviceId.trim()),
        Variable<int>(currentVersion + 1),
        Variable<String>(deviceId.trim()),
        Variable<String>(expenseId),
      ],
    );

    final originals = await _db.customSelect(
      '''
      SELECT id, account_type, account_id, account_name, reference_id,
             reference_no, debit, credit, currency, payment_method,
             store_id, branch_id
      FROM account_transactions
      WHERE deleted_at = ''
        AND transaction_type NOT IN ('cancel', 'paymentReversal')
        AND (id = ? OR id LIKE ? OR id = ? OR id LIKE ?)
      ORDER BY transaction_date, created_at, id
      ''',
      variables: <Variable<Object>>[
        Variable<String>('$expenseId-expense-debit'),
        Variable<String>('$expenseId-expense-debit-edit-v%'),
        Variable<String>('$expenseId-expense-credit'),
        Variable<String>('$expenseId-expense-credit-edit-v%'),
      ],
    ).get();

    for (final original in originals) {
      final originalId = original.data['id']?.toString() ?? '';
      if (originalId.isEmpty) continue;
      final reversalId = '$originalId-reversal';
      final existing = await _db.customSelect(
        "SELECT id FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(reversalId)],
      ).getSingleOrNull();
      if (existing != null) continue;

      final nextSort = await _db.customSelect(
        'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
      ).getSingle();
      final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
      final debit = (original.data['debit'] as num?)?.toDouble() ?? 0.0;
      final credit = (original.data['credit'] as num?)?.toDouble() ?? 0.0;
      final method = original.data['payment_method']?.toString().trim() ?? '';
      await _db.customInsert(
        '''
        INSERT INTO account_transactions
          (id, entity_type, created_at, updated_at, deleted_at,
           device_id, sync_status, store_id, branch_id, version, sort_index,
           account_type, account_id, account_name, transaction_date,
           transaction_type, reference_id, reference_no, debit, credit,
           currency, payment_method, note, last_modified_by_device_id)
        VALUES (?, 'accountTransaction', ?, ?, '', ?, 'pending', ?, ?, 1, ?,
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(reversalId),
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(deviceId.trim()),
          Variable<String>(original.data['store_id']?.toString() ?? ''),
          Variable<String>(original.data['branch_id']?.toString() ?? ''),
          Variable<int>(sortIndex),
          Variable<String>(original.data['account_type']?.toString() ?? 'supplier'),
          Variable<String>(original.data['account_id']?.toString() ?? expenseId),
          Variable<String>(original.data['account_name']?.toString() ?? 'Expense'),
          Variable<String>(now),
          Variable<String>(credit > 0 ? 'paymentReversal' : 'cancel'),
          Variable<String>(original.data['reference_id']?.toString() ?? expenseId),
          Variable<String>(original.data['reference_no']?.toString() ?? ''),
          Variable<double>(credit),
          Variable<double>(debit),
          Variable<String>(original.data['currency']?.toString() ?? 'USD'),
          Variable<String>(method),
          Variable<String>('Reverse expense compatibility movement for $cleanReason'),
          Variable<String>(deviceId.trim()),
        ],
      );
    }

  }

  Future<void> _reverseCompatibilityRefundTransaction({
    required String referenceType,
    required String referenceId,
    required List<CashLedgerTransaction> reversedLedgerRows,
    required String reason,
    required String deviceId,
    DateTime? occurredAt,
  }) async {
    final isSale = referenceType == 'sale_refund';
    final purchaseLedgerOriginalId = reversedLedgerRows.isEmpty
        ? ''
        : reversedLedgerRows.first.reversalOfId.trim();
    final preferredOriginalId = isSale
        ? '$referenceId-customer-refund'
        : (purchaseLedgerOriginalId.isEmpty
            ? '$referenceId-supplier-refund'
            : '$purchaseLedgerOriginalId-supplier-refund');
    var originalId = preferredOriginalId;
    var original = await _db.customSelect(
      '''
      SELECT id, account_type, account_id, account_name, reference_id,
             reference_no, debit, credit, currency, payment_method,
             store_id, branch_id
      FROM account_transactions
      WHERE id = ? AND deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(originalId)],
    ).getSingleOrNull();
    // Backward compatibility for supplier refunds created by an earlier Phase
    // 6 build that used a purchase-level compatibility id.
    if (original == null && !isSale && purchaseLedgerOriginalId.isNotEmpty) {
      originalId = '$referenceId-supplier-refund';
      original = await _db.customSelect(
        '''
        SELECT id, account_type, account_id, account_name, reference_id,
               reference_no, debit, credit, currency, payment_method,
               store_id, branch_id
        FROM account_transactions
        WHERE id = ? AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(originalId)],
      ).getSingleOrNull();
    }
    if (original == null) return;

    final reversalId = '$originalId-reversal';
    final existing = await _db.customSelect(
      "SELECT id FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(reversalId)],
    ).getSingleOrNull();
    if (existing != null) return;

    final now = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    final debit = (original.data['debit'] as num?)?.toDouble() ?? 0.0;
    final credit = (original.data['credit'] as num?)?.toDouble() ?? 0.0;
    final nextSort = await _db
        .customSelect(
          'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
        )
        .getSingle();
    final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
    final cleanReason = reason.trim();
    final note = cleanReason.isEmpty
        ? (isSale
            ? 'Customer cash refund reversed'
            : 'Supplier cash refund reversed')
        : 'Refund reversal: $cleanReason';

    await _db.customInsert(
      '''
      INSERT OR IGNORE INTO account_transactions
        (id, entity_type, created_at, updated_at, deleted_at,
         device_id, sync_status, store_id, branch_id, version, sort_index,
         account_type, account_id, account_name, transaction_date,
         transaction_type, reference_id, reference_no, debit, credit,
         currency, payment_method, note, last_modified_by_device_id)
      VALUES (?, 'accountTransaction', ?, ?, '', ?, 'pending', ?, ?, 1, ?,
              ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(reversalId),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(deviceId.trim()),
        Variable<String>(original.data['store_id']?.toString() ?? ''),
        Variable<String>(original.data['branch_id']?.toString() ?? ''),
        Variable<int>(sortIndex),
        Variable<String>(original.data['account_type']?.toString() ?? ''),
        Variable<String>(original.data['account_id']?.toString() ?? ''),
        Variable<String>(original.data['account_name']?.toString() ?? ''),
        Variable<String>(now),
        Variable<String>(isSale ? 'paymentReceived' : 'paymentPaid'),
        Variable<String>(
            original.data['reference_id']?.toString() ?? referenceId),
        Variable<String>(original.data['reference_no']?.toString() ?? ''),
        Variable<double>(credit),
        Variable<double>(debit),
        Variable<String>(original.data['currency']?.toString() ?? 'USD'),
        Variable<String>(original.data['payment_method']?.toString() ?? 'Cash'),
        Variable<String>(note),
        Variable<String>(deviceId.trim()),
      ],
    );
  }

  Future<void> _reverseRefundCoverage({
    required String refundId,
    required String deviceId,
    DateTime? occurredAt,
  }) async {
    final coverages = await _db.customSelect(
      '''
      SELECT id, voucher_type, voucher_id, allocation_kind, allocation_id,
             amount
      FROM cash_refund_allocations
      WHERE refund_id = ? AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[Variable<String>(refundId)],
    ).get();
    if (coverages.isEmpty) return;

    final now = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    for (final coverage in coverages) {
      final amount = (coverage.data['amount'] as num?)?.toDouble() ?? 0;
      final voucherType = coverage.data['voucher_type']?.toString() ?? '';
      final voucherId = coverage.data['voucher_id']?.toString() ?? '';
      final kind = coverage.data['allocation_kind']?.toString() ?? '';
      final allocationId = coverage.data['allocation_id']?.toString() ?? '';

      if (kind == 'unallocated' && amount > 0) {
        final table =
            voucherType == 'receipt' ? 'receipt_vouchers' : 'payment_vouchers';
        await _db.customUpdate(
          '''
          UPDATE $table
          SET unallocated_amount = unallocated_amount + ?, updated_at = ?,
              sync_status = 'pending', version = version + 1,
              last_modified_by_device_id = ?
          WHERE id = ? AND deleted_at = ''
          ''',
          variables: <Variable<Object>>[
            Variable<double>(amount),
            Variable<String>(now),
            Variable<String>(deviceId.trim()),
            Variable<String>(voucherId),
          ],
        );
      } else if (kind == 'allocated' && allocationId.isNotEmpty && amount > 0) {
        final allocation = await _db.customSelect(
          '''
          SELECT amount, reference_amount
          FROM payment_allocations
          WHERE id = ? AND allocation_kind = 'reversal'
            AND status = 'active' AND deleted_at = ''
          LIMIT 1
          ''',
          variables: <Variable<Object>>[Variable<String>(allocationId)],
        ).getSingleOrNull();
        if (allocation == null) {
          throw StateError('Refund allocation reversal is unavailable.');
        }
        final remainingAmount =
            ((allocation.data['amount'] as num?)?.toDouble() ?? 0) - amount;
        final remainingReference =
            ((allocation.data['reference_amount'] as num?)?.toDouble() ?? 0) -
                amount;
        if (remainingAmount <= 0.000001 || remainingReference <= 0.000001) {
          await _db.customUpdate(
            '''
            UPDATE payment_allocations
            SET status = 'reversed', deleted_at = ?, updated_at = ?,
                sync_status = 'pending', version = version + 1,
                last_modified_by_device_id = ?
            WHERE id = ? AND status = 'active' AND deleted_at = ''
            ''',
            variables: <Variable<Object>>[
              Variable<String>(now),
              Variable<String>(now),
              Variable<String>(deviceId.trim()),
              Variable<String>(allocationId),
            ],
          );
        } else {
          await _db.customUpdate(
            '''
            UPDATE payment_allocations
            SET amount = ?, reference_amount = ?, updated_at = ?,
                sync_status = 'pending', version = version + 1,
                last_modified_by_device_id = ?
            WHERE id = ? AND status = 'active' AND deleted_at = ''
            ''',
            variables: <Variable<Object>>[
              Variable<double>(remainingAmount),
              Variable<double>(remainingReference),
              Variable<String>(now),
              Variable<String>(deviceId.trim()),
              Variable<String>(allocationId),
            ],
          );
        }
      }

      await _db.customUpdate(
        '''
        UPDATE cash_refund_allocations
        SET deleted_at = ?, updated_at = ?, sync_status = 'pending',
            version = version + 1, last_modified_by_device_id = ?
        WHERE id = ? AND deleted_at = ''
        ''',
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(deviceId.trim()),
          Variable<String>(coverage.data['id']?.toString() ?? ''),
        ],
      );
    }
  }
}
