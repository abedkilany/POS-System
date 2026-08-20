import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
import 'payment_voucher_service.dart';

class CashPhase7Issue {
  const CashPhase7Issue({
    required this.type,
    required this.details,
    this.severity = 'warning',
    this.entityType = '',
    this.entityId = '',
    this.referenceNo = '',
  });

  final String severity;
  final String type;
  final String entityType;
  final String entityId;
  final String referenceNo;
  final String details;
}

class CashPhase7Report {
  const CashPhase7Report({
    required this.runId,
    required this.legacyReceiptsFound,
    required this.legacyPaymentsFound,
    required this.vouchersCreated,
    required this.allocationsCreated,
    required this.invoiceEntriesCreated,
    required this.voucherEntriesCreated,
    required this.ledgerRowsCreated,
    required this.paymentCachesRebuilt,
    required this.issues,
  });

  final String runId;
  final int legacyReceiptsFound;
  final int legacyPaymentsFound;
  final int vouchersCreated;
  final int allocationsCreated;
  final int invoiceEntriesCreated;
  final int voucherEntriesCreated;
  final int ledgerRowsCreated;
  final int paymentCachesRebuilt;
  final List<CashPhase7Issue> issues;

  bool get hasErrors => issues.any((issue) => issue.severity == 'error');
}

/// Phase 7 migration/reconciliation for the rebuilt cash module.
///
/// Guarantees:
/// - legacy account_transactions payments become first-class vouchers exactly once;
/// - historical cash is never moved a second time;
/// - invoice paid_amount is rebuilt from active allocations, not trusted as a source;
/// - missing invoice/voucher journal entries and Cash Ledger history are repaired;
/// - unresolved history is reported instead of guessed.
class CashPhase7MigrationService {
  CashPhase7MigrationService(this._db);

  final VentioDriftDatabase _db;
  static const double _epsilon = 0.000001;
  static final Random _random = Random.secure();

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}';

  Future<CashPhase7Report> run() async {
    final runId = _id('cash_p7');
    final startedAt = DateTime.now().toUtc().toIso8601String();
    await _db.customInsert(
      '''
      INSERT INTO cash_phase7_runs (id, status, started_at, message)
      VALUES (?, 'running', ?, 'Phase 7 legacy cash migration and accounting reconciliation')
      ''',
      variables: <Variable<Object>>[
        Variable<String>(runId),
        Variable<String>(startedAt),
      ],
    );

    final issues = <CashPhase7Issue>[];
    var legacyReceiptsFound = 0;
    var legacyPaymentsFound = 0;
    var vouchersCreated = 0;
    var allocationsCreated = 0;
    var invoiceEntriesCreated = 0;
    var voucherEntriesCreated = 0;
    var ledgerRowsCreated = 0;
    var paymentCachesRebuilt = 0;

    try {
      final salesBeforeMigration = await BusinessSqliteStore.readSales(_db);
      final purchasesBeforeMigration = await BusinessSqliteStore.readPurchases(_db);
      final saleTotals = <String, double>{for (final sale in salesBeforeMigration) sale.id: sale.total};
      final purchaseTotals = <String, double>{for (final purchase in purchasesBeforeMigration) purchase.id: purchase.subtotal};

      final legacyRows = await _legacyPaymentRows();
      legacyReceiptsFound = legacyRows.where((row) => row['transaction_type'] == 'paymentReceived').length;
      legacyPaymentsFound = legacyRows.where((row) => row['transaction_type'] == 'paymentPaid').length;

      for (final row in legacyRows) {
        final result = await _migrateLegacyPayment(
          row, issues,
          saleTotals: saleTotals,
          purchaseTotals: purchaseTotals,
        );
        vouchersCreated += result.$1;
        allocationsCreated += result.$2;
      }

      await _remapLegacyPaymentJournals();
      await _normalizeLegacyInvoiceAccounting(
        salesBeforeMigration,
        purchasesBeforeMigration,
        issues,
      );

      final beforeInvoiceEntries = await _countJournalEntries(<String>['sale', 'purchase']);
      final sales = await BusinessSqliteStore.readSales(_db);
      for (final sale in sales) {
        if (sale.isDeleted || sale.isCancelled || sale.total <= 0) continue;
        await AccountingService.recordSale(sale, paymentPostedSeparately: true);
      }
      final purchases = await BusinessSqliteStore.readPurchases(_db);
      for (final purchase in purchases) {
        if (purchase.isDeleted || purchase.isCancelled || !purchase.isReceived || purchase.subtotal <= 0) continue;
        await AccountingService.recordPurchase(purchase, paymentPostedSeparately: true);
      }
      final afterInvoiceEntries = await _countJournalEntries(<String>['sale', 'purchase']);
      invoiceEntriesCreated = max(0, afterInvoiceEntries - beforeInvoiceEntries);

      final beforeVoucherEntries = await _countJournalEntries(<String>['receipt_voucher', 'payment_voucher']);
      await _repairVoucherAccounting(issues);
      final afterVoucherEntries = await _countJournalEntries(<String>['receipt_voucher', 'payment_voucher']);
      voucherEntriesCreated = max(0, afterVoucherEntries - beforeVoucherEntries);

      final beforeLedger = await _countLedger();
      await PaymentVoucherService(_db).backfillLegacyCashLedger();
      final afterLedger = await _countLedger();
      ledgerRowsCreated = max(0, afterLedger - beforeLedger);

      paymentCachesRebuilt = await _rebuildPaymentCaches(issues);
      await _runIntegrityChecks(issues);
      await _persistIssues(runId, issues);

      final finishedAt = DateTime.now().toUtc().toIso8601String();
      await _db.customUpdate(
        '''
        UPDATE cash_phase7_runs
        SET status = ?, finished_at = ?, legacy_receipts_found = ?,
            legacy_payments_found = ?, vouchers_created = ?, allocations_created = ?,
            invoice_entries_created = ?, voucher_entries_created = ?,
            ledger_rows_created = ?, payment_caches_rebuilt = ?, issue_count = ?, message = ?
        WHERE id = ?
        ''',
        variables: <Variable<Object>>[
          Variable<String>(issues.any((i) => i.severity == 'error') ? 'blocked' : 'completed'),
          Variable<String>(finishedAt),
          Variable<int>(legacyReceiptsFound),
          Variable<int>(legacyPaymentsFound),
          Variable<int>(vouchersCreated),
          Variable<int>(allocationsCreated),
          Variable<int>(invoiceEntriesCreated),
          Variable<int>(voucherEntriesCreated),
          Variable<int>(ledgerRowsCreated),
          Variable<int>(paymentCachesRebuilt),
          Variable<int>(issues.length),
          Variable<String>(issues.any((i) => i.severity == 'error') ? 'Phase 7 blocked by reconciliation errors.' : (issues.isEmpty ? 'Phase 7 completed cleanly.' : 'Phase 7 completed with ${issues.length} non-blocking reconciliation issue(s).')),
          Variable<String>(runId),
        ],
      );
    } catch (error) {
      final finishedAt = DateTime.now().toUtc().toIso8601String();
      await _db.customUpdate(
        "UPDATE cash_phase7_runs SET status = 'failed', finished_at = ?, message = ? WHERE id = ?",
        variables: <Variable<Object>>[
          Variable<String>(finishedAt),
          Variable<String>(error.toString()),
          Variable<String>(runId),
        ],
      );
      rethrow;
    }

    return CashPhase7Report(
      runId: runId,
      legacyReceiptsFound: legacyReceiptsFound,
      legacyPaymentsFound: legacyPaymentsFound,
      vouchersCreated: vouchersCreated,
      allocationsCreated: allocationsCreated,
      invoiceEntriesCreated: invoiceEntriesCreated,
      voucherEntriesCreated: voucherEntriesCreated,
      ledgerRowsCreated: ledgerRowsCreated,
      paymentCachesRebuilt: paymentCachesRebuilt,
      issues: List<CashPhase7Issue>.unmodifiable(issues),
    );
  }

  Future<List<Map<String, Object?>>> _legacyPaymentRows() async {
    final rows = await _db.customSelect(r'''
      SELECT at.*
      FROM account_transactions at
      WHERE at.deleted_at = ''
        AND at.transaction_type IN ('paymentReceived', 'paymentPaid')
        AND ((at.transaction_type = 'paymentReceived' AND lower(trim(at.account_type)) = 'customer')
          OR (at.transaction_type = 'paymentPaid' AND lower(trim(at.account_type)) = 'supplier'))
        AND (at.debit > 0 OR at.credit > 0)
        AND NOT EXISTS (SELECT 1 FROM expenses e WHERE e.id = at.reference_id AND e.deleted_at = '')
        AND NOT EXISTS (
          SELECT 1 FROM receipt_vouchers rv
          WHERE at.id = rv.id || '-customer-payment' AND rv.deleted_at = ''
        )
        AND NOT EXISTS (
          SELECT 1 FROM payment_vouchers pv
          WHERE at.id = pv.id || '-supplier-payment' AND pv.deleted_at = ''
        )
        AND NOT EXISTS (
          SELECT 1 FROM receipt_vouchers rv
          WHERE rv.id = 'legacy_receipt_' || at.id AND rv.deleted_at = ''
        )
        AND NOT EXISTS (
          SELECT 1 FROM payment_vouchers pv
          WHERE pv.id = 'legacy_payment_' || at.id AND pv.deleted_at = ''
        )
      ORDER BY at.transaction_date, at.created_at, at.id
    ''').get();
    return rows.map((row) => Map<String, Object?>.from(row.data)).toList();
  }

  Future<(int, int)> _migrateLegacyPayment(
    Map<String, Object?> row,
    List<CashPhase7Issue> issues, {
    required Map<String, double> saleTotals,
    required Map<String, double> purchaseTotals,
  }) async {
    final type = row['transaction_type']?.toString() ?? '';
    final isReceipt = type == 'paymentReceived';
    final accountId = row['account_id']?.toString().trim() ?? '';
    final accountName = row['account_name']?.toString() ?? '';
    final legacyId = row['id']?.toString() ?? '';
    final referenceId = row['reference_id']?.toString().trim() ?? '';
    final referenceNo = row['reference_no']?.toString() ?? '';
    final amount = _number(row['debit']) > 0 ? _number(row['debit']) : _number(row['credit']);
    if (legacyId.isEmpty || accountId.isEmpty || amount <= 0) {
      issues.add(CashPhase7Issue(
        severity: 'error',
        type: 'invalid_legacy_payment',
        entityType: 'account_transaction',
        entityId: legacyId,
        referenceNo: referenceNo,
        details: 'Legacy payment has an empty party/id or non-positive amount.',
      ));
      return (0, 0);
    }

    final paymentMethod = (row['payment_method']?.toString().trim().isEmpty ?? true)
        ? 'Cash'
        : row['payment_method']!.toString().trim();
    final isCash = paymentMethod.toLowerCase() == 'cash';
    final cashLocationId = isCash ? await _resolveCashLocation(row) : '';
    if (isCash && cashLocationId.isEmpty) {
      issues.add(CashPhase7Issue(
        severity: 'error',
        type: 'missing_cash_location',
        entityType: 'account_transaction',
        entityId: legacyId,
        referenceNo: referenceNo,
        details: 'Historical cash payment cannot be assigned to a valid cash drawer without guessing.',
      ));
      return (0, 0);
    }

    final voucherId = '${isReceipt ? 'legacy_receipt' : 'legacy_payment'}_$legacyId';
    final voucherNo = 'LEG-${isReceipt ? 'RC' : 'PV'}-$legacyId';
    final when = _date(row['transaction_date']?.toString(), fallback: _date(row['created_at']?.toString()));
    final now = DateTime.now().toUtc().toIso8601String();
    final currency = (row['currency']?.toString().trim().isEmpty ?? true) ? 'USD' : row['currency']!.toString().trim().toUpperCase();

    var allocationAmount = 0.0;
    var targetExists = false;
    if (referenceId.isNotEmpty) {
      final target = await _db.customSelect(
        isReceipt
            ? "SELECT id, customer_id AS party_id FROM sales WHERE id = ? AND deleted_at = '' AND lower(status) <> 'cancelled' LIMIT 1"
            : "SELECT id, supplier_id AS party_id FROM purchases WHERE id = ? AND deleted_at = '' AND lower(status) <> 'cancelled' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(referenceId)],
      ).getSingleOrNull();
      if (target != null && target.data['party_id']?.toString() == accountId) {
        targetExists = true;
        final double targetTotal =
            (isReceipt ? saleTotals[referenceId] : purchaseTotals[referenceId]) ?? 0.0;
        final allocatedRow = await _db.customSelect(
          '''
          SELECT COALESCE(SUM(reference_amount), 0) AS allocated
          FROM payment_allocations
          WHERE deleted_at = '' AND status = 'active'
            AND voucher_type = ? AND reference_type = ? AND reference_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(isReceipt ? 'receipt' : 'payment'),
            Variable<String>(isReceipt ? 'sale' : 'purchase'),
            Variable<String>(referenceId),
          ],
        ).getSingle();
        final alreadyAllocated = _number(allocatedRow.data['allocated']);
        final remaining = max(0.0, targetTotal - alreadyAllocated);
        allocationAmount = min(amount, remaining);
        if (amount > allocationAmount + _epsilon) {
          issues.add(CashPhase7Issue(
            type: 'legacy_payment_unallocated_remainder',
            entityType: 'account_transaction',
            entityId: legacyId,
            referenceNo: referenceNo,
            details: 'Only $allocationAmount of $amount could be allocated to the referenced invoice; the remainder stays as party credit/advance.',
          ));
        }
      } else if (target != null) {
        issues.add(CashPhase7Issue(
          type: 'party_reference_mismatch',
          entityType: 'account_transaction',
          entityId: legacyId,
          referenceNo: referenceNo,
          details: 'Payment party does not match the referenced invoice; voucher will remain unallocated.',
        ));
      }
    }

    await _db.transaction(() async {
      if (isReceipt) {
        await _db.customInsert(
          '''
          INSERT OR IGNORE INTO receipt_vouchers
            (id, voucher_no, customer_id, customer_name, voucher_date, amount, unallocated_amount,
             currency, payment_method, cash_location_id, cash_drawer_session_id, status, notes,
             created_by, created_by_user_id, device_id, branch_id, store_id, idempotency_key,
             created_at, updated_at, deleted_at, sync_status, version, last_modified_by_device_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 'posted', ?, '', '', ?, ?, ?, ?, ?, ?, '', 'synced', 1, ?)
          ''',
          variables: <Variable<Object>>[
            Variable<String>(voucherId), Variable<String>(voucherNo), Variable<String>(accountId),
            Variable<String>(accountName), Variable<String>(when.toIso8601String()), Variable<double>(amount),
            Variable<double>(max(0.0, amount - allocationAmount)), Variable<String>(currency), Variable<String>(paymentMethod),
            Variable<String>(cashLocationId), Variable<String>(row['note']?.toString() ?? ''),
            Variable<String>(row['device_id']?.toString() ?? ''), Variable<String>(row['branch_id']?.toString() ?? ''),
            Variable<String>(row['store_id']?.toString() ?? ''), Variable<String>('phase7:legacy:$legacyId'),
            Variable<String>(row['created_at']?.toString().trim().isNotEmpty == true ? row['created_at']!.toString() : now),
            Variable<String>(now), Variable<String>(row['last_modified_by_device_id']?.toString() ?? ''),
          ],
        );
      } else {
        await _db.customInsert(
          '''
          INSERT OR IGNORE INTO payment_vouchers
            (id, voucher_no, supplier_id, supplier_name, voucher_date, amount, unallocated_amount,
             currency, payment_method, cash_location_id, cash_drawer_session_id, status, notes,
             created_by, created_by_user_id, device_id, branch_id, store_id, idempotency_key,
             created_at, updated_at, deleted_at, sync_status, version, last_modified_by_device_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 'posted', ?, '', '', ?, ?, ?, ?, ?, ?, '', 'synced', 1, ?)
          ''',
          variables: <Variable<Object>>[
            Variable<String>(voucherId), Variable<String>(voucherNo), Variable<String>(accountId),
            Variable<String>(accountName), Variable<String>(when.toIso8601String()), Variable<double>(amount),
            Variable<double>(max(0.0, amount - allocationAmount)), Variable<String>(currency), Variable<String>(paymentMethod),
            Variable<String>(cashLocationId), Variable<String>(row['note']?.toString() ?? ''),
            Variable<String>(row['device_id']?.toString() ?? ''), Variable<String>(row['branch_id']?.toString() ?? ''),
            Variable<String>(row['store_id']?.toString() ?? ''), Variable<String>('phase7:legacy:$legacyId'),
            Variable<String>(row['created_at']?.toString().trim().isNotEmpty == true ? row['created_at']!.toString() : now),
            Variable<String>(now), Variable<String>(row['last_modified_by_device_id']?.toString() ?? ''),
          ],
        );
      }
      if (targetExists && allocationAmount > _epsilon) {
        await _db.customInsert(
          '''
          INSERT OR IGNORE INTO payment_allocations
            (id, voucher_type, voucher_id, reference_type, reference_id, reference_number,
             amount, reference_amount, currency, reference_currency, exchange_rate, status,
             created_at, updated_at, deleted_at, sync_status, version, last_modified_by_device_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'active', ?, ?, '', 'synced', 1, ?)
          ''',
          variables: <Variable<Object>>[
            Variable<String>('phase7_alloc_$legacyId'), Variable<String>(isReceipt ? 'receipt' : 'payment'),
            Variable<String>(voucherId), Variable<String>(isReceipt ? 'sale' : 'purchase'), Variable<String>(referenceId),
            Variable<String>(referenceNo), Variable<double>(allocationAmount), Variable<double>(allocationAmount),
            Variable<String>(currency), Variable<String>(currency), Variable<String>(when.toIso8601String()),
            Variable<String>(now), Variable<String>(row['last_modified_by_device_id']?.toString() ?? ''),
          ],
        );
      }

      // Phase 6 may already have materialized this legacy payment directly in
      // Cash Ledger. Re-key that exact immutable history row to the new voucher
      // instead of appending a second cash movement.
      await _db.customUpdate(
        '''
        UPDATE cash_ledger_transactions
        SET reference_type = ?, reference_id = ?, reference_number = ?,
            idempotency_key = ?, updated_at = ?
        WHERE deleted_at = '' AND reference_type = 'legacy_account_transaction'
          AND reference_id = ?
        ''',
        variables: <Variable<Object>>[
          Variable<String>(isReceipt ? 'receipt_voucher' : 'payment_voucher'),
          Variable<String>(voucherId),
          Variable<String>(voucherNo),
          Variable<String>('phase7:voucher:$voucherId'),
          Variable<String>(now),
          Variable<String>(legacyId),
        ],
      );
    });
    return (1, allocationAmount > _epsilon ? 1 : 0);
  }

  Future<void> _remapLegacyPaymentJournals() async {
    for (final spec in <(String, String, String, String)>[
      ('receipt_vouchers', 'legacy_receipt_', 'customer_payment', 'receipt_voucher'),
      ('payment_vouchers', 'legacy_payment_', 'supplier_payment', 'payment_voucher'),
    ]) {
      final rows = await _db.customSelect(
        "SELECT id, voucher_no FROM ${spec.$1} WHERE deleted_at = '' AND id LIKE '${spec.$2}%'",
      ).get();
      for (final row in rows) {
        final voucherId = row.data['id']?.toString() ?? '';
        final legacyId = voucherId.substring(spec.$2.length);
        final existingVoucherJournal = await _db.customSelect(
          "SELECT id FROM journal_entries WHERE deleted_at = '' AND status = 'posted' AND reference_type = ? AND reference_id = ? LIMIT 1",
          variables: <Variable<Object>>[
            Variable<String>(spec.$4), Variable<String>(voucherId),
          ],
        ).getSingleOrNull();
        if (existingVoucherJournal != null) continue;
        await _db.customUpdate(
          '''
          UPDATE journal_entries
          SET reference_type = ?, reference_id = ?, reference_no = ?, source = 'import', updated_at = ?
          WHERE deleted_at = '' AND status = 'posted'
            AND reference_type = ? AND reference_id = ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(spec.$4), Variable<String>(voucherId),
            Variable<String>(row.data['voucher_no']?.toString() ?? ''),
            Variable<String>(DateTime.now().toUtc().toIso8601String()),
            Variable<String>(spec.$3), Variable<String>(legacyId),
          ],
        );
      }
    }
  }

  Future<void> _normalizeLegacyInvoiceAccounting(
    List<Sale> sales,
    List<Purchase> purchases,
    List<CashPhase7Issue> issues,
  ) async {
    for (final sale in sales) {
      if (sale.isDeleted || sale.isCancelled || sale.total <= 0) continue;
      if (!await _invoiceNeedsPaymentSeparation('sale', sale.id)) continue;
      try {
        await AccountingService.reverseEntryForReference(
          referenceType: 'sale',
          referenceId: sale.id,
          reason: 'Phase 7: separate historical invoice accounting from payment accounting',
          createdBy: 'phase7_migration',
          adjustCashLocationBalance: false,
        );
        await AccountingService.recordSale(sale, paymentPostedSeparately: true);
      } catch (error) {
        issues.add(CashPhase7Issue(
          severity: 'error', type: 'legacy_sale_accounting_normalization_failed',
          entityType: 'sale', entityId: sale.id, referenceNo: sale.invoiceNo,
          details: error.toString(),
        ));
      }
    }
    for (final purchase in purchases) {
      if (purchase.isDeleted || purchase.isCancelled || purchase.subtotal <= 0) continue;
      if (!await _invoiceNeedsPaymentSeparation('purchase', purchase.id)) continue;
      try {
        await AccountingService.reverseEntryForReference(
          referenceType: 'purchase',
          referenceId: purchase.id,
          reason: 'Phase 7: separate historical invoice accounting from payment accounting',
          createdBy: 'phase7_migration',
          adjustCashLocationBalance: false,
        );
        await AccountingService.recordPurchase(purchase, paymentPostedSeparately: true);
      } catch (error) {
        issues.add(CashPhase7Issue(
          severity: 'error', type: 'legacy_purchase_accounting_normalization_failed',
          entityType: 'purchase', entityId: purchase.id, referenceNo: purchase.purchaseNo,
          details: error.toString(),
        ));
      }
    }
  }

  Future<bool> _invoiceNeedsPaymentSeparation(String referenceType, String referenceId) async {
    final allocated = await _db.customSelect(
      '''
      SELECT COUNT(*) AS c FROM payment_allocations
      WHERE deleted_at = '' AND status = 'active' AND reference_type = ? AND reference_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(referenceType), Variable<String>(referenceId),
      ],
    ).getSingle();
    if (((allocated.data['c'] as num?)?.toInt() ?? 0) == 0) return false;
    final paymentLine = await _db.customSelect(
      '''
      SELECT jl.id
      FROM journal_entries je
      JOIN journal_lines jl ON jl.entry_id = je.id
      WHERE je.deleted_at = '' AND je.status = 'posted'
        AND je.reference_type = ? AND je.reference_id = ?
        AND (
          EXISTS (SELECT 1 FROM cash_locations cl WHERE cl.deleted_at = '' AND cl.account_id = jl.account_id)
          OR EXISTS (SELECT 1 FROM payment_accounts pa WHERE pa.deleted_at = '' AND pa.account_id = jl.account_id)
        )
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(referenceType), Variable<String>(referenceId),
      ],
    ).getSingleOrNull();
    return paymentLine != null;
  }

  Future<void> _repairVoucherAccounting(List<CashPhase7Issue> issues) async {
    for (final spec in <(String, String, String, String)>[
      ('receipt_vouchers', 'receipt', 'customer_id', 'customer_name'),
      ('payment_vouchers', 'payment', 'supplier_id', 'supplier_name'),
    ]) {
      final rows = await _db.customSelect('SELECT * FROM ${spec.$1} WHERE deleted_at = \'\' AND status = \'posted\'').get();
      for (final result in rows) {
        final row = result.data;
        try {
          await AccountingService.postVoucherPayment(
            database: _db,
            voucherType: spec.$2,
            voucherId: row['id']?.toString() ?? '',
            voucherNo: row['voucher_no']?.toString() ?? '',
            date: _date(row['voucher_date']?.toString()),
            amount: _number(row['amount']),
            paymentMethod: row['payment_method']?.toString() ?? 'Cash',
            partyId: row[spec.$3]?.toString() ?? '',
            partyName: row[spec.$4]?.toString() ?? '',
            cashLocationId: row['cash_location_id']?.toString() ?? '',
            createdBy: row['created_by_user_id']?.toString() ?? '',
            storeId: row['store_id']?.toString() ?? '',
            branchId: row['branch_id']?.toString() ?? '',
          );
        } catch (error) {
          issues.add(CashPhase7Issue(
            severity: 'error',
            type: 'voucher_accounting_repair_failed',
            entityType: spec.$1,
            entityId: row['id']?.toString() ?? '',
            referenceNo: row['voucher_no']?.toString() ?? '',
            details: error.toString(),
          ));
        }
      }
    }
  }

  Future<int> _rebuildPaymentCaches(List<CashPhase7Issue> issues) async {
    var count = 0;
    final sales = await BusinessSqliteStore.readSales(_db);
    for (final sale in sales) {
      if (sale.isDeleted) continue;
      await _rebuildOnePaymentCache(
        table: 'sales', referenceType: 'sale', voucherType: 'receipt',
        id: sale.id, total: sale.total, issues: issues,
      );
      count++;
    }
    final purchases = await BusinessSqliteStore.readPurchases(_db);
    for (final purchase in purchases) {
      if (purchase.isDeleted) continue;
      await _rebuildOnePaymentCache(
        table: 'purchases', referenceType: 'purchase', voucherType: 'payment',
        id: purchase.id, total: purchase.subtotal, issues: issues,
      );
      count++;
    }
    return count;
  }

  Future<void> _rebuildOnePaymentCache({
    required String table,
    required String referenceType,
    required String voucherType,
    required String id,
    required double total,
    required List<CashPhase7Issue> issues,
  }) async {
    final paidRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(pa.reference_amount), 0) AS paid
      FROM payment_allocations pa
      WHERE pa.deleted_at = '' AND pa.status = 'active'
        AND pa.reference_type = ? AND pa.reference_id = ? AND pa.voucher_type = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(referenceType), Variable<String>(id), Variable<String>(voucherType),
      ],
    ).getSingle();
    final rawPaid = _number(paidRow.data['paid']);
    final paid = min(total, max(0.0, rawPaid));
    if (rawPaid > total + _epsilon) {
      issues.add(CashPhase7Issue(
        severity: 'error', type: 'overallocated_invoice',
        entityType: referenceType, entityId: id,
        details: 'Active allocations total $rawPaid while invoice total is $total.',
      ));
    }
    final status = total > 0 && paid + _epsilon >= total
        ? 'paid'
        : (paid > _epsilon ? 'partial' : 'unpaid');
    await _db.customUpdate(
      "UPDATE $table SET paid_amount = ?, payment_status = ? WHERE id = ? AND deleted_at = ''",
      variables: <Variable<Object>>[
        Variable<double>(paid), Variable<String>(status), Variable<String>(id),
      ],
    );
  }

  Future<void> _runIntegrityChecks(List<CashPhase7Issue> issues) async {
    final checks = <(String, String, String)>[
      ('missing_sale_journal', "SELECT id, invoice_no AS ref FROM sales s WHERE s.deleted_at = '' AND lower(s.status) <> 'cancelled' AND NOT EXISTS (SELECT 1 FROM journal_entries je WHERE je.deleted_at = '' AND je.status = 'posted' AND je.reference_type = 'sale' AND je.reference_id = s.id)", 'Authoritative sale journal is still missing after Phase 7 reconciliation.'),
      ('missing_purchase_journal', "SELECT id, purchase_no AS ref FROM purchases p WHERE p.deleted_at = '' AND lower(p.status) <> 'cancelled' AND NOT EXISTS (SELECT 1 FROM journal_entries je WHERE je.deleted_at = '' AND je.status = 'posted' AND je.reference_type = 'purchase' AND je.reference_id = p.id)", 'Authoritative purchase journal is still missing after Phase 7 reconciliation.'),
      ('missing_receipt_journal', "SELECT id, voucher_no AS ref FROM receipt_vouchers v WHERE v.deleted_at = '' AND v.status = 'posted' AND NOT EXISTS (SELECT 1 FROM journal_entries je WHERE je.deleted_at = '' AND je.status = 'posted' AND je.reference_type = 'receipt_voucher' AND je.reference_id = v.id)", 'Posted receipt voucher has no authoritative journal entry.'),
      ('missing_payment_journal', "SELECT id, voucher_no AS ref FROM payment_vouchers v WHERE v.deleted_at = '' AND v.status = 'posted' AND NOT EXISTS (SELECT 1 FROM journal_entries je WHERE je.deleted_at = '' AND je.status = 'posted' AND je.reference_type = 'payment_voucher' AND je.reference_id = v.id)", 'Posted payment voucher has no authoritative journal entry.'),
      ('missing_receipt_cash_ledger', "SELECT id, voucher_no AS ref FROM receipt_vouchers v WHERE v.deleted_at = '' AND v.status = 'posted' AND lower(trim(v.payment_method)) = 'cash' AND NOT EXISTS (SELECT 1 FROM cash_ledger_transactions clt WHERE clt.deleted_at = '' AND clt.reference_type = 'receipt_voucher' AND clt.reference_id = v.id)", 'Posted cash receipt voucher has no Cash Ledger transaction.'),
      ('missing_payment_cash_ledger', "SELECT id, voucher_no AS ref FROM payment_vouchers v WHERE v.deleted_at = '' AND v.status = 'posted' AND lower(trim(v.payment_method)) = 'cash' AND NOT EXISTS (SELECT 1 FROM cash_ledger_transactions clt WHERE clt.deleted_at = '' AND clt.reference_type = 'payment_voucher' AND clt.reference_id = v.id)", 'Posted cash payment voucher has no Cash Ledger transaction.'),
    ];
    for (final check in checks) {
      final rows = await _db.customSelect(check.$2).get();
      for (final row in rows) {
        issues.add(CashPhase7Issue(severity: 'error', type: check.$1, entityId: row.data['id']?.toString() ?? '', referenceNo: row.data['ref']?.toString() ?? '', details: check.$3));
      }
    }

    for (final spec in <(String, String)>[('receipt_vouchers', 'receipt'), ('payment_vouchers', 'payment')]) {
      final rows = await _db.customSelect('''
        SELECT v.id, v.voucher_no AS ref, v.amount, v.unallocated_amount,
               COALESCE(SUM(CASE WHEN pa.status = 'active' AND pa.deleted_at = '' THEN pa.amount ELSE 0 END), 0) AS allocated
        FROM ${spec.$1} v
        LEFT JOIN payment_allocations pa ON pa.voucher_type = ? AND pa.voucher_id = v.id
        WHERE v.deleted_at = '' AND v.status = 'posted'
        GROUP BY v.id, v.voucher_no, v.amount, v.unallocated_amount
        HAVING ABS(v.amount - v.unallocated_amount - COALESCE(SUM(CASE WHEN pa.status = 'active' AND pa.deleted_at = '' THEN pa.amount ELSE 0 END), 0)) > 0.000001
      ''', variables: <Variable<Object>>[Variable<String>(spec.$2)]).get();
      for (final row in rows) {
        issues.add(CashPhase7Issue(severity: 'error', type: 'voucher_allocation_mismatch', entityType: spec.$1, entityId: row.data['id']?.toString() ?? '', referenceNo: row.data['ref']?.toString() ?? '', details: 'Voucher amount=${row.data['amount']}, allocated=${row.data['allocated']}, unallocated=${row.data['unallocated_amount']}.'));
      }
    }

    final invalidAllocations = await _db.customSelect(r'''
      SELECT pa.id, pa.reference_number AS ref,
             CASE
               WHEN pa.voucher_type = 'receipt' AND rv.id IS NULL THEN 'missing_receipt_voucher'
               WHEN pa.voucher_type = 'payment' AND pv.id IS NULL THEN 'missing_payment_voucher'
               WHEN pa.reference_type = 'sale' AND s.id IS NULL THEN 'missing_sale'
               WHEN pa.reference_type = 'purchase' AND p.id IS NULL THEN 'missing_purchase'
               WHEN pa.voucher_type = 'receipt' AND pa.reference_type = 'sale' AND rv.customer_id <> s.customer_id THEN 'party_mismatch'
               WHEN pa.voucher_type = 'payment' AND pa.reference_type = 'purchase' AND pv.supplier_id <> p.supplier_id THEN 'party_mismatch'
               ELSE '' END AS problem
      FROM payment_allocations pa
      LEFT JOIN receipt_vouchers rv ON pa.voucher_type = 'receipt' AND rv.id = pa.voucher_id AND rv.deleted_at = '' AND rv.status = 'posted'
      LEFT JOIN payment_vouchers pv ON pa.voucher_type = 'payment' AND pv.id = pa.voucher_id AND pv.deleted_at = '' AND pv.status = 'posted'
      LEFT JOIN sales s ON pa.reference_type = 'sale' AND s.id = pa.reference_id AND s.deleted_at = '' AND lower(s.status) <> 'cancelled'
      LEFT JOIN purchases p ON pa.reference_type = 'purchase' AND p.id = pa.reference_id AND p.deleted_at = '' AND lower(p.status) <> 'cancelled'
      WHERE pa.deleted_at = '' AND pa.status = 'active' AND (
        (pa.voucher_type = 'receipt' AND rv.id IS NULL) OR (pa.voucher_type = 'payment' AND pv.id IS NULL) OR
        (pa.reference_type = 'sale' AND s.id IS NULL) OR (pa.reference_type = 'purchase' AND p.id IS NULL) OR
        (pa.voucher_type = 'receipt' AND pa.reference_type = 'sale' AND rv.customer_id <> s.customer_id) OR
        (pa.voucher_type = 'payment' AND pa.reference_type = 'purchase' AND pv.supplier_id <> p.supplier_id))
    ''').get();
    for (final row in invalidAllocations) {
      issues.add(CashPhase7Issue(severity: 'error', type: 'invalid_payment_allocation', entityType: 'payment_allocation', entityId: row.data['id']?.toString() ?? '', referenceNo: row.data['ref']?.toString() ?? '', details: 'Allocation integrity failure: ${row.data['problem']}.'));
    }

    final duplicateJournals = await _db.customSelect(r'''
      SELECT reference_type, reference_id, MAX(reference_no) AS ref, COUNT(*) AS c
      FROM journal_entries
      WHERE deleted_at = '' AND status = 'posted' AND reference_type IN ('sale', 'purchase', 'receipt_voucher', 'payment_voucher')
      GROUP BY reference_type, reference_id HAVING COUNT(*) > 1
    ''').get();
    for (final row in duplicateJournals) {
      issues.add(CashPhase7Issue(severity: 'error', type: 'duplicate_posted_journal', entityType: row.data['reference_type']?.toString() ?? '', entityId: row.data['reference_id']?.toString() ?? '', referenceNo: row.data['ref']?.toString() ?? '', details: 'Financial reference has ${row.data['c']} posted journal entries.'));
    }

    final duplicateLedger = await _db.customSelect(r'''
      SELECT reference_type, reference_id, MAX(reference_number) AS ref, COUNT(*) AS c
      FROM cash_ledger_transactions
      WHERE deleted_at = '' AND reference_type IN ('receipt_voucher', 'payment_voucher')
      GROUP BY reference_type, reference_id HAVING COUNT(*) > 1
    ''').get();
    for (final row in duplicateLedger) {
      issues.add(CashPhase7Issue(severity: 'error', type: 'duplicate_cash_ledger_reference', entityType: row.data['reference_type']?.toString() ?? '', entityId: row.data['reference_id']?.toString() ?? '', referenceNo: row.data['ref']?.toString() ?? '', details: 'Voucher reference has ${row.data['c']} active Cash Ledger rows.'));
    }

    for (final row in await _db.customSelect(r'''
      WITH expected AS (
        SELECT account_id AS party_id, SUM(debit - credit) AS balance
        FROM account_transactions
        WHERE deleted_at = '' AND lower(trim(account_type)) = 'customer' AND trim(account_id) <> ''
        GROUP BY account_id
      ), ledger AS (
        SELECT jl.party_id, SUM(jl.debit - jl.credit) AS balance
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.entry_id
        JOIN accounting_settings s ON s.key = 'default_customers_account_id' AND s.account_id = jl.account_id
        WHERE je.deleted_at = '' AND je.status = 'posted' AND jl.party_type = 'customer' AND jl.party_id <> ''
        GROUP BY jl.party_id
      )
      SELECT e.party_id, e.balance AS expected_balance, COALESCE(l.balance, 0) AS ledger_balance
      FROM expected e LEFT JOIN ledger l ON l.party_id = e.party_id
      WHERE ABS(e.balance - COALESCE(l.balance, 0)) > 0.000001
    ''').get()) {
      issues.add(CashPhase7Issue(severity: 'error', type: 'customer_control_balance_mismatch', entityType: 'customer', entityId: row.data['party_id']?.toString() ?? '', details: 'Legacy/customer balance=${row.data['expected_balance']}, accounting receivable=${row.data['ledger_balance']}.'));
    }

    for (final row in await _db.customSelect(r'''
      WITH expected AS (
        SELECT account_id AS party_id, SUM(credit - debit) AS balance
        FROM account_transactions
        WHERE deleted_at = '' AND lower(trim(account_type)) = 'supplier' AND trim(account_id) <> ''
        GROUP BY account_id
      ), ledger AS (
        SELECT jl.party_id, SUM(jl.credit - jl.debit) AS balance
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.entry_id
        JOIN accounting_settings s ON s.key = 'default_suppliers_account_id' AND s.account_id = jl.account_id
        WHERE je.deleted_at = '' AND je.status = 'posted' AND jl.party_type = 'supplier' AND jl.party_id <> ''
        GROUP BY jl.party_id
      )
      SELECT e.party_id, e.balance AS expected_balance, COALESCE(l.balance, 0) AS ledger_balance
      FROM expected e LEFT JOIN ledger l ON l.party_id = e.party_id
      WHERE ABS(e.balance - COALESCE(l.balance, 0)) > 0.000001
    ''').get()) {
      issues.add(CashPhase7Issue(severity: 'error', type: 'supplier_control_balance_mismatch', entityType: 'supplier', entityId: row.data['party_id']?.toString() ?? '', details: 'Legacy/supplier balance=${row.data['expected_balance']}, accounting payable=${row.data['ledger_balance']}.'));
    }

    final unbalanced = await _db.customSelect(r'''
      SELECT je.id, je.entry_no AS ref, ABS(COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0)) AS difference
      FROM journal_entries je JOIN journal_lines jl ON jl.entry_id = je.id
      WHERE je.deleted_at = '' AND je.status = 'posted'
      GROUP BY je.id, je.entry_no HAVING ABS(SUM(jl.debit) - SUM(jl.credit)) > 0.000001
    ''').get();
    for (final row in unbalanced) {
      issues.add(CashPhase7Issue(severity: 'error', type: 'unbalanced_journal_entry', entityType: 'journal_entry', entityId: row.data['id']?.toString() ?? '', referenceNo: row.data['ref']?.toString() ?? '', details: 'Posted journal is not balanced; difference=${row.data['difference']}.'));
    }
  }

  Future<String> _resolveCashLocation(Map<String, Object?> row) async {
    final deviceId = row['device_id']?.toString().trim() ?? '';
    final branchId = row['branch_id']?.toString().trim() ?? '';
    final result = await _db.customSelect(
      '''
      SELECT id FROM cash_locations
      WHERE deleted_at = '' AND is_active = 1 AND type = 'cash_drawer'
      ORDER BY
        CASE WHEN ? <> '' AND device_id = ? THEN 0 ELSE 1 END,
        CASE WHEN ? <> '' AND branch_id = ? THEN 0 ELSE 1 END,
        CASE WHEN id = 'cl_main_drawer' THEN 0 ELSE 1 END,
        is_default DESC, id
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(deviceId), Variable<String>(deviceId),
        Variable<String>(branchId), Variable<String>(branchId),
      ],
    ).getSingleOrNull();
    return result?.data['id']?.toString() ?? '';
  }

  Future<int> _countJournalEntries(List<String> types) async {
    final placeholders = List<String>.filled(types.length, '?').join(',');
    final row = await _db.customSelect(
      "SELECT COUNT(*) AS c FROM journal_entries WHERE deleted_at = '' AND status = 'posted' AND reference_type IN ($placeholders)",
      variables: types.map((e) => Variable<String>(e)).toList(),
    ).getSingle();
    return (row.data['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countLedger() async {
    final row = await _db.customSelect("SELECT COUNT(*) AS c FROM cash_ledger_transactions WHERE deleted_at = ''").getSingle();
    return (row.data['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> _persistIssues(String runId, List<CashPhase7Issue> issues) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final issue in issues) {
      await _db.customInsert(
        '''
        INSERT INTO cash_phase7_issues
          (id, run_id, severity, issue_type, entity_type, entity_id, reference_no, details, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(_id('cash_p7_issue')), Variable<String>(runId), Variable<String>(issue.severity),
          Variable<String>(issue.type), Variable<String>(issue.entityType), Variable<String>(issue.entityId),
          Variable<String>(issue.referenceNo), Variable<String>(issue.details), Variable<String>(now),
        ],
      );
    }
  }

  double _number(Object? value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  DateTime _date(String? value, {DateTime? fallback}) =>
      DateTime.tryParse(value ?? '')?.toUtc() ?? fallback ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
