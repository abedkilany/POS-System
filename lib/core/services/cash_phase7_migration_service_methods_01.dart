part of 'cash_phase7_migration_service.dart';

extension CashPhase7MigrationServiceSplitPart1 on CashPhase7MigrationService {

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_${CashPhase7MigrationService._random.nextInt(1 << 32).toRadixString(16)}';

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
      final purchasesBeforeMigration =
          await BusinessSqliteStore.readPurchases(_db);
      final saleTotals = <String, double>{
        for (final sale in salesBeforeMigration) sale.id: sale.total
      };
      final purchaseTotals = <String, double>{
        for (final purchase in purchasesBeforeMigration)
          purchase.id: purchase.subtotal
      };

      final legacyRows = await _legacyPaymentRows();
      legacyReceiptsFound = legacyRows
          .where((row) => row['transaction_type'] == 'paymentReceived')
          .length;
      legacyPaymentsFound = legacyRows
          .where((row) => row['transaction_type'] == 'paymentPaid')
          .length;

      for (final row in legacyRows) {
        final result = await _migrateLegacyPayment(
          row,
          issues,
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

      final beforeInvoiceEntries =
          await _countJournalEntries(<String>['sale', 'purchase']);
      final sales = await BusinessSqliteStore.readSales(_db);
      for (final sale in sales) {
        if (sale.isDeleted || sale.isCancelled || sale.total <= 0) continue;
        await AccountingService.recordSale(sale, paymentPostedSeparately: true);
      }
      final purchases = await BusinessSqliteStore.readPurchases(_db);
      for (final purchase in purchases) {
        if (purchase.isDeleted ||
            purchase.isCancelled ||
            !purchase.isReceived ||
            purchase.subtotal <= 0) {
          continue;
        }
        await AccountingService.recordPurchase(purchase,
            paymentPostedSeparately: true);
      }
      final afterInvoiceEntries =
          await _countJournalEntries(<String>['sale', 'purchase']);
      invoiceEntriesCreated =
          max(0, afterInvoiceEntries - beforeInvoiceEntries);

      final beforeVoucherEntries = await _countJournalEntries(
          <String>['receipt_voucher', 'payment_voucher']);
      await _repairVoucherAccounting(issues);
      final afterVoucherEntries = await _countJournalEntries(
          <String>['receipt_voucher', 'payment_voucher']);
      voucherEntriesCreated =
          max(0, afterVoucherEntries - beforeVoucherEntries);

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
          Variable<String>(issues.any((i) => i.severity == 'error')
              ? 'blocked'
              : 'completed'),
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
          Variable<String>(issues.any((i) => i.severity == 'error')
              ? 'Phase 7 blocked by reconciliation errors.'
              : (issues.isEmpty
                  ? 'Phase 7 completed cleanly.'
                  : 'Phase 7 completed with ${issues.length} non-blocking reconciliation issue(s).')),
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
    final amount = _number(row['debit']) > 0
        ? _number(row['debit'])
        : _number(row['credit']);
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

    final paymentMethod =
        (row['payment_method']?.toString().trim().isEmpty ?? true)
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
        details:
            'Historical cash payment cannot be assigned to a valid cash drawer without guessing.',
      ));
      return (0, 0);
    }

    final voucherId =
        '${isReceipt ? 'legacy_receipt' : 'legacy_payment'}_$legacyId';
    final voucherNo = 'LEG-${isReceipt ? 'RC' : 'PV'}-$legacyId';
    final when = _date(row['transaction_date']?.toString(),
        fallback: _date(row['created_at']?.toString()));
    final now = DateTime.now().toUtc().toIso8601String();
    final currency = (row['currency']?.toString().trim().isEmpty ?? true)
        ? 'USD'
        : row['currency']!.toString().trim().toUpperCase();

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
        final double targetTotal = (isReceipt
                ? saleTotals[referenceId]
                : purchaseTotals[referenceId]) ??
            0.0;
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
        if (amount > allocationAmount + CashPhase7MigrationService._epsilon) {
          issues.add(CashPhase7Issue(
            type: 'legacy_payment_unallocated_remainder',
            entityType: 'account_transaction',
            entityId: legacyId,
            referenceNo: referenceNo,
            details:
                'Only $allocationAmount of $amount could be allocated to the referenced invoice; the remainder stays as party credit/advance.',
          ));
        }
      } else if (target != null) {
        issues.add(CashPhase7Issue(
          type: 'party_reference_mismatch',
          entityType: 'account_transaction',
          entityId: legacyId,
          referenceNo: referenceNo,
          details:
              'Payment party does not match the referenced invoice; voucher will remain unallocated.',
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
            Variable<String>(voucherId),
            Variable<String>(voucherNo),
            Variable<String>(accountId),
            Variable<String>(accountName),
            Variable<String>(when.toIso8601String()),
            Variable<double>(amount),
            Variable<double>(max(0.0, amount - allocationAmount)),
            Variable<String>(currency),
            Variable<String>(paymentMethod),
            Variable<String>(cashLocationId),
            Variable<String>(row['note']?.toString() ?? ''),
            Variable<String>(row['device_id']?.toString() ?? ''),
            Variable<String>(row['branch_id']?.toString() ?? ''),
            Variable<String>(row['store_id']?.toString() ?? ''),
            Variable<String>('phase7:legacy:$legacyId'),
            Variable<String>(
                row['created_at']?.toString().trim().isNotEmpty == true
                    ? row['created_at']!.toString()
                    : now),
            Variable<String>(now),
            Variable<String>(
                row['last_modified_by_device_id']?.toString() ?? ''),
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
            Variable<String>(voucherId),
            Variable<String>(voucherNo),
            Variable<String>(accountId),
            Variable<String>(accountName),
            Variable<String>(when.toIso8601String()),
            Variable<double>(amount),
            Variable<double>(max(0.0, amount - allocationAmount)),
            Variable<String>(currency),
            Variable<String>(paymentMethod),
            Variable<String>(cashLocationId),
            Variable<String>(row['note']?.toString() ?? ''),
            Variable<String>(row['device_id']?.toString() ?? ''),
            Variable<String>(row['branch_id']?.toString() ?? ''),
            Variable<String>(row['store_id']?.toString() ?? ''),
            Variable<String>('phase7:legacy:$legacyId'),
            Variable<String>(
                row['created_at']?.toString().trim().isNotEmpty == true
                    ? row['created_at']!.toString()
                    : now),
            Variable<String>(now),
            Variable<String>(
                row['last_modified_by_device_id']?.toString() ?? ''),
          ],
        );
      }
      if (targetExists && allocationAmount > CashPhase7MigrationService._epsilon) {
        await _db.customInsert(
          '''
          INSERT OR IGNORE INTO payment_allocations
            (id, voucher_type, voucher_id, reference_type, reference_id, reference_number,
             amount, reference_amount, currency, reference_currency, exchange_rate, status,
             created_at, updated_at, deleted_at, sync_status, version, last_modified_by_device_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'active', ?, ?, '', 'synced', 1, ?)
          ''',
          variables: <Variable<Object>>[
            Variable<String>('phase7_alloc_$legacyId'),
            Variable<String>(isReceipt ? 'receipt' : 'payment'),
            Variable<String>(voucherId),
            Variable<String>(isReceipt ? 'sale' : 'purchase'),
            Variable<String>(referenceId),
            Variable<String>(referenceNo),
            Variable<double>(allocationAmount),
            Variable<double>(allocationAmount),
            Variable<String>(currency),
            Variable<String>(currency),
            Variable<String>(when.toIso8601String()),
            Variable<String>(now),
            Variable<String>(
                row['last_modified_by_device_id']?.toString() ?? ''),
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
    return (1, allocationAmount > CashPhase7MigrationService._epsilon ? 1 : 0);
  }

  Future<void> _remapLegacyPaymentJournals() async {
    for (final spec in <(String, String, String, String)>[
      (
        'receipt_vouchers',
        'legacy_receipt_',
        'customer_payment',
        'receipt_voucher'
      ),
      (
        'payment_vouchers',
        'legacy_payment_',
        'supplier_payment',
        'payment_voucher'
      ),
    ]) {
      final rows = await _db
          .customSelect(
            "SELECT id, voucher_no FROM ${spec.$1} WHERE deleted_at = '' AND id LIKE '${spec.$2}%'",
          )
          .get();
      for (final row in rows) {
        final voucherId = row.data['id']?.toString() ?? '';
        final legacyId = voucherId.substring(spec.$2.length);
        final existingVoucherJournal = await _db.customSelect(
          "SELECT id FROM journal_entries WHERE deleted_at = '' AND status = 'posted' AND reference_type = ? AND reference_id = ? LIMIT 1",
          variables: <Variable<Object>>[
            Variable<String>(spec.$4),
            Variable<String>(voucherId),
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
            Variable<String>(spec.$4),
            Variable<String>(voucherId),
            Variable<String>(row.data['voucher_no']?.toString() ?? ''),
            Variable<String>(DateTime.now().toUtc().toIso8601String()),
            Variable<String>(spec.$3),
            Variable<String>(legacyId),
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
          reason:
              'Phase 7: separate historical invoice accounting from payment accounting',
          createdBy: 'phase7_migration',
          adjustCashLocationBalance: false,
        );
        await AccountingService.recordSale(sale, paymentPostedSeparately: true);
      } catch (error) {
        issues.add(CashPhase7Issue(
          severity: 'error',
          type: 'legacy_sale_accounting_normalization_failed',
          entityType: 'sale',
          entityId: sale.id,
          referenceNo: sale.invoiceNo,
          details: error.toString(),
        ));
      }
    }
    for (final purchase in purchases) {
      if (purchase.isDeleted ||
          purchase.isCancelled ||
          purchase.subtotal <= 0) {
        continue;
      }
      if (!await _invoiceNeedsPaymentSeparation('purchase', purchase.id)) {
        continue;
      }
      try {
        await AccountingService.reverseEntryForReference(
          referenceType: 'purchase',
          referenceId: purchase.id,
          reason:
              'Phase 7: separate historical invoice accounting from payment accounting',
          createdBy: 'phase7_migration',
          adjustCashLocationBalance: false,
        );
        await AccountingService.recordPurchase(purchase,
            paymentPostedSeparately: true);
      } catch (error) {
        issues.add(CashPhase7Issue(
          severity: 'error',
          type: 'legacy_purchase_accounting_normalization_failed',
          entityType: 'purchase',
          entityId: purchase.id,
          referenceNo: purchase.purchaseNo,
          details: error.toString(),
        ));
      }
    }
  }

  Future<bool> _invoiceNeedsPaymentSeparation(
      String referenceType, String referenceId) async {
    final allocated = await _db.customSelect(
      '''
      SELECT COUNT(*) AS c FROM payment_allocations
      WHERE deleted_at = '' AND status = 'active' AND reference_type = ? AND reference_id = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(referenceType),
        Variable<String>(referenceId),
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
        Variable<String>(referenceType),
        Variable<String>(referenceId),
      ],
    ).getSingleOrNull();
    return paymentLine != null;
  }

  Future<void> _repairVoucherAccounting(List<CashPhase7Issue> issues) async {
    for (final spec in <(String, String, String, String)>[
      ('receipt_vouchers', 'receipt', 'customer_id', 'customer_name'),
      ('payment_vouchers', 'payment', 'supplier_id', 'supplier_name'),
    ]) {
      final rows = await _db
          .customSelect(
              'SELECT * FROM ${spec.$1} WHERE deleted_at = \'\' AND status = \'posted\'')
          .get();
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
        table: 'sales',
        referenceType: 'sale',
        voucherType: 'receipt',
        id: sale.id,
        total: sale.total,
        issues: issues,
      );
      count++;
    }
    final purchases = await BusinessSqliteStore.readPurchases(_db);
    for (final purchase in purchases) {
      if (purchase.isDeleted) continue;
      await _rebuildOnePaymentCache(
        table: 'purchases',
        referenceType: 'purchase',
        voucherType: 'payment',
        id: purchase.id,
        total: purchase.subtotal,
        issues: issues,
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
        Variable<String>(referenceType),
        Variable<String>(id),
        Variable<String>(voucherType),
      ],
    ).getSingle();
    final rawPaid = _number(paidRow.data['paid']);
    final paid = min(total, max(0.0, rawPaid));
    if (rawPaid > total + CashPhase7MigrationService._epsilon) {
      issues.add(CashPhase7Issue(
        severity: 'error',
        type: 'overallocated_invoice',
        entityType: referenceType,
        entityId: id,
        details:
            'Active allocations total $rawPaid while invoice total is $total.',
      ));
    }
    final status = total > 0 && paid + CashPhase7MigrationService._epsilon >= total
        ? 'paid'
        : (paid > CashPhase7MigrationService._epsilon ? 'partial' : 'unpaid');
    await _db.customUpdate(
      "UPDATE $table SET paid_amount = ?, payment_status = ? WHERE id = ? AND deleted_at = ''",
      variables: <Variable<Object>>[
        Variable<double>(paid),
        Variable<String>(status),
        Variable<String>(id),
      ],
    );
  }
}
