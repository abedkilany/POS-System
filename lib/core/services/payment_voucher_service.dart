import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/cash_ledger_transaction.dart';
import '../../models/journal_entry.dart';
import '../../models/payment_allocation.dart';
import '../../models/payment_voucher.dart';
import '../../models/receipt_voucher.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
import 'cash_ledger_service.dart';

/// Phase 2 authoritative write/read service for independent receipt/payment
/// vouchers and their allocations.
///
/// Important phase boundary:
/// - New vouchers created through this service are authoritative events.
/// - Allocations update Sale/Purchase paid_amount only as a compatibility cache.
/// - Existing Sales/Purchases UI paths are NOT rerouted here until Phase 3.
/// - Sync/snapshot/backup registration is intentionally deferred to Phase 8.
class PaymentVoucherService {
  PaymentVoucherService(this._db) : _cashLedger = CashLedgerService(_db);

  final VentioDriftDatabase _db;
  final CashLedgerService _cashLedger;
  static final Random _random = Random.secure();
  static const double _epsilon = 0.000001;

  String _newId(String prefix) {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return '${prefix}_${micros}_${_random.nextInt(1 << 32).toRadixString(16)}';
  }

  String _newVoucherNo(String prefix, DateTime date) {
    final utc = date.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    final day = '${utc.year}${two(utc.month)}${two(utc.day)}';
    final suffix = utc.microsecondsSinceEpoch.toString().substring(7);
    return '$prefix-$day-$suffix';
  }

  Future<ReceiptVoucher> createReceipt({
    String id = '',
    String voucherNo = '',
    required String customerId,
    required String customerName,
    required double amount,
    String currency = 'USD',
    String paymentMethod = 'Cash',
    String cashLocationId = '',
    String cashDrawerSessionId = '',
    List<PaymentAllocationDraft> allocations = const <PaymentAllocationDraft>[],
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    _validateCommon(
      partyId: customerId,
      amount: amount,
      paymentMethod: paymentMethod,
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
    );
    final when = (date ?? DateTime.now()).toUtc();
    final cleanId = id.trim().isEmpty ? _newId('receipt') : id.trim();
    final cleanCurrency = _currency(currency);
    final cleanPaymentMethod = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();

    return _db.transaction(() async {
      final existing = await _findReceiptByIdentity(cleanId, idempotencyKey);
      if (existing != null) {
        await _postReceiptAccounting(existing);
        return existing;
      }

      final prepared = await _prepareAllocations(
        voucherType: 'receipt',
        voucherId: cleanId,
        expectedReferenceType: 'sale',
        partyId: customerId.trim(),
        voucherAmount: amount,
        voucherCurrency: cleanCurrency,
        drafts: allocations,
        deviceId: deviceId,
      );
      final allocated = prepared.fold<double>(0, (sum, item) => sum + item.amount);
      final unallocated = _money(amount - allocated);

      final now = DateTime.now().toUtc();
      final voucher = ReceiptVoucher(
        id: cleanId,
        voucherNo: voucherNo.trim().isEmpty ? _newVoucherNo('RC', when) : voucherNo.trim(),
        customerId: customerId.trim(),
        customerName: customerName.trim(),
        date: when,
        amount: _money(amount),
        unallocatedAmount: unallocated,
        currency: cleanCurrency,
        paymentMethod: cleanPaymentMethod,
        cashLocationId: cashLocationId.trim(),
        cashDrawerSessionId: cashDrawerSessionId.trim(),
        notes: notes.trim(),
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        idempotencyKey: idempotencyKey.trim(),
        allocations: prepared,
        createdAt: now,
        updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      );

      await _insertReceipt(voucher);
      await _insertAllocations(prepared);
      await _applyAllocationCaches(prepared, deviceId: deviceId);
      await _postReceiptAccounting(voucher);
      if (_isCash(cleanPaymentMethod)) {
        await _appendVoucherCashMovement(
          type: 'receipt',
          direction: 'in',
          voucherId: voucher.id,
          voucherNo: voucher.voucherNo,
          amount: voucher.amount,
          currency: voucher.currency,
          cashLocationId: voucher.cashLocationId,
          sessionId: voucher.cashDrawerSessionId,
          partyType: 'customer',
          partyId: voucher.customerId,
          partyName: voucher.customerName,
          paymentMethod: voucher.paymentMethod,
          createdBy: voucher.createdBy,
          createdByUserId: voucher.createdByUserId,
          deviceId: voucher.deviceId,
          branchId: voucher.branchId,
          storeId: voucher.storeId,
          notes: voucher.notes,
          occurredAt: voucher.date,
        );
        await _moveCashLocation(voucher.cashLocationId, voucher.amount, now);
      }
      return voucher;
    });
  }

  Future<PaymentVoucher> createPayment({
    String id = '',
    String voucherNo = '',
    required String supplierId,
    required String supplierName,
    required double amount,
    String currency = 'USD',
    String paymentMethod = 'Cash',
    String cashLocationId = '',
    String cashDrawerSessionId = '',
    List<PaymentAllocationDraft> allocations = const <PaymentAllocationDraft>[],
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    String idempotencyKey = '',
    DateTime? date,
  }) async {
    _validateCommon(
      partyId: supplierId,
      amount: amount,
      paymentMethod: paymentMethod,
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
    );
    final when = (date ?? DateTime.now()).toUtc();
    final cleanId = id.trim().isEmpty ? _newId('payment') : id.trim();
    final cleanCurrency = _currency(currency);
    final cleanPaymentMethod = paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();

    return _db.transaction(() async {
      final existing = await _findPaymentByIdentity(cleanId, idempotencyKey);
      if (existing != null) {
        await _postPaymentAccounting(existing);
        return existing;
      }

      final prepared = await _prepareAllocations(
        voucherType: 'payment',
        voucherId: cleanId,
        expectedReferenceType: 'purchase',
        partyId: supplierId.trim(),
        voucherAmount: amount,
        voucherCurrency: cleanCurrency,
        drafts: allocations,
        deviceId: deviceId,
      );
      final allocated = prepared.fold<double>(0, (sum, item) => sum + item.amount);
      final unallocated = _money(amount - allocated);

      final now = DateTime.now().toUtc();
      final voucher = PaymentVoucher(
        id: cleanId,
        voucherNo: voucherNo.trim().isEmpty ? _newVoucherNo('PV', when) : voucherNo.trim(),
        supplierId: supplierId.trim(),
        supplierName: supplierName.trim(),
        date: when,
        amount: _money(amount),
        unallocatedAmount: unallocated,
        currency: cleanCurrency,
        paymentMethod: cleanPaymentMethod,
        cashLocationId: cashLocationId.trim(),
        cashDrawerSessionId: cashDrawerSessionId.trim(),
        notes: notes.trim(),
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        idempotencyKey: idempotencyKey.trim(),
        allocations: prepared,
        createdAt: now,
        updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      );

      await _insertPayment(voucher);
      await _insertAllocations(prepared);
      await _applyAllocationCaches(prepared, deviceId: deviceId);
      await _postPaymentAccounting(voucher);
      if (_isCash(cleanPaymentMethod)) {
        await _appendVoucherCashMovement(
          type: 'payment',
          direction: 'out',
          voucherId: voucher.id,
          voucherNo: voucher.voucherNo,
          amount: voucher.amount,
          currency: voucher.currency,
          cashLocationId: voucher.cashLocationId,
          sessionId: voucher.cashDrawerSessionId,
          partyType: 'supplier',
          partyId: voucher.supplierId,
          partyName: voucher.supplierName,
          paymentMethod: voucher.paymentMethod,
          createdBy: voucher.createdBy,
          createdByUserId: voucher.createdByUserId,
          deviceId: voucher.deviceId,
          branchId: voucher.branchId,
          storeId: voucher.storeId,
          notes: voucher.notes,
          occurredAt: voucher.date,
        );
        await _moveCashLocation(voucher.cashLocationId, -voucher.amount, now);
      }
      return voucher;
    });
  }

  Future<void> _postReceiptAccounting(ReceiptVoucher voucher) async {
    await AccountingService.postVoucherPayment(
      database: _db,
      voucherType: 'receipt',
      voucherId: voucher.id,
      voucherNo: voucher.voucherNo,
      date: voucher.date,
      amount: voucher.amount,
      paymentMethod: voucher.paymentMethod,
      partyId: voucher.customerId,
      partyName: voucher.customerName,
      cashLocationId: voucher.cashLocationId,
      createdBy: voucher.createdByUserId.isNotEmpty
          ? voucher.createdByUserId
          : (voucher.createdBy.isNotEmpty ? voucher.createdBy : voucher.deviceId),
      storeId: voucher.storeId,
      branchId: voucher.branchId,
    );
  }

  Future<void> _postPaymentAccounting(PaymentVoucher voucher) async {
    await AccountingService.postVoucherPayment(
      database: _db,
      voucherType: 'payment',
      voucherId: voucher.id,
      voucherNo: voucher.voucherNo,
      date: voucher.date,
      amount: voucher.amount,
      paymentMethod: voucher.paymentMethod,
      partyId: voucher.supplierId,
      partyName: voucher.supplierName,
      cashLocationId: voucher.cashLocationId,
      createdBy: voucher.createdByUserId.isNotEmpty
          ? voucher.createdByUserId
          : (voucher.createdBy.isNotEmpty ? voucher.createdBy : voucher.deviceId),
      storeId: voucher.storeId,
      branchId: voucher.branchId,
    );
  }


  Future<double> refundableCashForSale(String saleId) async {
    final totalRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(pa.reference_amount), 0) AS total
      FROM payment_allocations pa
      INNER JOIN receipt_vouchers rv ON rv.id = pa.voucher_id
      WHERE pa.voucher_type = 'receipt'
        AND pa.reference_type = 'sale'
        AND pa.reference_id = ?
        AND pa.deleted_at = ''
        AND rv.deleted_at = ''
        AND rv.status = 'posted'
        AND LOWER(rv.payment_method) = 'cash'
      ''',
      variables: <Variable<Object>>[Variable<String>(saleId.trim())],
    ).getSingle();
    final refundedRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM cash_ledger_transactions
      WHERE type = 'refund'
        AND direction = 'out'
        AND reference_type = 'sale_refund'
        AND reference_id LIKE ?
        AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[Variable<String>('${saleId.trim()}:%')],
    ).getSingle();
    return _money(_number(totalRow.data['total']) - _number(refundedRow.data['total']))
        .clamp(0, double.infinity)
        .toDouble();
  }

  Future<double> refundSaleCash({
    required String saleId,
    required String invoiceNo,
    required String customerId,
    required String customerName,
    required double requestedAmount,
    required String cashLocationId,
    required String cashDrawerSessionId,
    required String refundKey,
    String currency = 'USD',
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    DateTime? date,
  }) async {
    if (!requestedAmount.isFinite || requestedAmount <= 0) return 0;
    if (cashLocationId.trim().isEmpty || cashDrawerSessionId.trim().isEmpty) {
      throw StateError('Cash refund requires an open cash drawer session.');
    }
    final cleanKey = refundKey.trim();
    if (cleanKey.isEmpty) throw ArgumentError('refundKey is required.');
    final referenceId = '${saleId.trim()}:$cleanKey';
    final existing = await _db.customSelect(
      "SELECT amount FROM cash_ledger_transactions WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>('sale_refund:$referenceId')],
    ).getSingleOrNull();
    if (existing != null) return _number(existing.data['amount']);

    final refundable = await refundableCashForSale(saleId);
    final amount = _money(min(requestedAmount, refundable));
    if (amount <= 0) return 0;
    final when = (date ?? DateTime.now()).toUtc();

    return _db.transaction(() async {
      final session = await _db.customSelect(
        "SELECT id FROM cash_drawer_sessions WHERE id = ? AND cash_location_id = ? AND status = 'open' LIMIT 1",
        variables: <Variable<Object>>[
          Variable<String>(cashDrawerSessionId.trim()),
          Variable<String>(cashLocationId.trim()),
        ],
      ).getSingleOrNull();
      if (session == null) {
        throw StateError('Cash drawer session is not open for this refund.');
      }
      final location = await _db.customSelect(
        "SELECT account_id, current_balance, allow_negative FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(cashLocationId.trim())],
      ).getSingleOrNull();
      if (location == null) throw StateError('Cash location is unavailable.');
      final balance = _number(location.data['current_balance']);
      final allowNegative = _number(location.data['allow_negative']).round() == 1;
      if (!allowNegative && balance + _epsilon < amount) {
        throw StateError('Insufficient cash balance for customer refund.');
      }
      final accounts = await AccountingService.readDefaultAccountMap();
      final customersAccount = accounts['default_customers_account_id']?.trim() ?? '';
      final cashAccount = location.data['account_id']?.toString().trim() ?? '';
      if (customersAccount.isEmpty || cashAccount.isEmpty) {
        throw StateError('Required accounting accounts are not configured.');
      }
      final entryId = await AccountingService.createPostedEntry(
        JournalEntryDraft(
          entryDate: when,
          referenceType: 'sale_refund',
          referenceId: referenceId,
          referenceNo: invoiceNo.trim(),
          description: 'Cash refund for sale ${invoiceNo.trim()}',
          source: 'refund',
          createdBy: createdBy.trim(),
          storeId: storeId.trim(),
          branchId: branchId.trim(),
          lines: <JournalLineDraft>[
            JournalLineDraft(
              accountId: customersAccount,
              debit: amount,
              credit: 0,
              memo: 'Customer refund',
              partyType: 'customer',
              partyId: customerId.trim(),
              partyName: customerName.trim(),
            ),
            JournalLineDraft(
              accountId: cashAccount,
              debit: 0,
              credit: amount,
              memo: 'Cash paid to customer',
              partyType: 'customer',
              partyId: customerId.trim(),
              partyName: customerName.trim(),
            ),
          ],
        ),
        database: _db,
      );
      if (entryId.isEmpty) {
        throw StateError('Refund journal entry was not created.');
      }
      final now = DateTime.now().toUtc();
      await _cashLedger.appendInExistingTransaction(CashLedgerTransaction(
        id: _cashLedger.generateId(),
        type: 'refund',
        direction: 'out',
        amount: amount,
        currency: _currency(currency),
        cashLocationId: cashLocationId.trim(),
        cashDrawerSessionId: cashDrawerSessionId.trim(),
        referenceType: 'sale_refund',
        referenceId: referenceId,
        referenceNumber: invoiceNo.trim(),
        partyType: 'customer',
        partyId: customerId.trim(),
        partyName: customerName.trim(),
        paymentMethod: 'Cash',
        createdBy: createdBy.trim(),
        createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(),
        branchId: branchId.trim(),
        storeId: storeId.trim(),
        notes: notes.trim(),
        idempotencyKey: 'sale_refund:$referenceId',
        occurredAt: when,
        createdAt: now,
        updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      ));
      await _moveCashLocation(cashLocationId.trim(), -amount, now);
      return amount;
    });
  }


  Future<double> refundableCashForPurchase(String purchaseId) async {
    final totalRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(pa.reference_amount), 0) AS total
      FROM payment_allocations pa
      INNER JOIN payment_vouchers pv ON pv.id = pa.voucher_id
      WHERE pa.voucher_type = 'payment'
        AND pa.reference_type = 'purchase'
        AND pa.reference_id = ?
        AND pa.deleted_at = ''
        AND pv.deleted_at = ''
        AND pv.status = 'posted'
        AND LOWER(pv.payment_method) = 'cash'
      ''',
      variables: <Variable<Object>>[Variable<String>(purchaseId.trim())],
    ).getSingle();
    final refundedRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM cash_ledger_transactions
      WHERE type = 'supplier_refund'
        AND direction = 'in'
        AND reference_type = 'purchase_refund'
        AND reference_id = ?
        AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[Variable<String>(purchaseId.trim())],
    ).getSingle();
    return _money(_number(totalRow.data['total']) - _number(refundedRow.data['total']))
        .clamp(0, double.infinity)
        .toDouble();
  }

  Future<double> refundPurchaseCash({
    required String purchaseId,
    required String purchaseNo,
    required String supplierId,
    required String supplierName,
    required String cashLocationId,
    required String cashDrawerSessionId,
    String currency = 'USD',
    String notes = '',
    String createdBy = '',
    String createdByUserId = '',
    String deviceId = '',
    String branchId = '',
    String storeId = '',
    DateTime? date,
  }) async {
    final existing = await _db.customSelect(
      "SELECT amount FROM cash_ledger_transactions WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>('purchase_refund:${purchaseId.trim()}')],
    ).getSingleOrNull();
    if (existing != null) return _number(existing.data['amount']);
    final amount = await refundableCashForPurchase(purchaseId);
    if (amount <= 0) return 0;
    final when = (date ?? DateTime.now()).toUtc();
    return _db.transaction(() async {
      final session = await _db.customSelect(
        "SELECT id FROM cash_drawer_sessions WHERE id = ? AND cash_location_id = ? AND status = 'open' LIMIT 1",
        variables: <Variable<Object>>[
          Variable<String>(cashDrawerSessionId.trim()),
          Variable<String>(cashLocationId.trim()),
        ],
      ).getSingleOrNull();
      if (session == null) throw StateError('Cash drawer session is not open for supplier refund.');
      final location = await _db.customSelect(
        "SELECT account_id FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(cashLocationId.trim())],
      ).getSingleOrNull();
      if (location == null) throw StateError('Cash location is unavailable.');
      final accounts = await AccountingService.readDefaultAccountMap();
      final suppliersAccount = accounts['default_suppliers_account_id']?.trim() ?? '';
      final cashAccount = location.data['account_id']?.toString().trim() ?? '';
      if (suppliersAccount.isEmpty || cashAccount.isEmpty) {
        throw StateError('Required accounting accounts are not configured.');
      }
      final entryId = await AccountingService.createPostedEntry(
        JournalEntryDraft(
          entryDate: when,
          referenceType: 'purchase_refund',
          referenceId: purchaseId.trim(),
          referenceNo: purchaseNo.trim(),
          description: 'Cash refund from supplier for purchase ${purchaseNo.trim()}',
          source: 'refund',
          createdBy: createdBy.trim(),
          storeId: storeId.trim(),
          branchId: branchId.trim(),
          lines: <JournalLineDraft>[
            JournalLineDraft(
              accountId: cashAccount, debit: amount, credit: 0,
              memo: 'Cash received from supplier', partyType: 'supplier',
              partyId: supplierId.trim(), partyName: supplierName.trim(),
            ),
            JournalLineDraft(
              accountId: suppliersAccount, debit: 0, credit: amount,
              memo: 'Supplier payment reversal', partyType: 'supplier',
              partyId: supplierId.trim(), partyName: supplierName.trim(),
            ),
          ],
        ),
        database: _db,
      );
      if (entryId.isEmpty) throw StateError('Supplier refund journal entry was not created.');
      final now = DateTime.now().toUtc();
      await _cashLedger.appendInExistingTransaction(CashLedgerTransaction(
        id: _cashLedger.generateId(), type: 'supplier_refund', direction: 'in',
        amount: amount, currency: _currency(currency),
        cashLocationId: cashLocationId.trim(), cashDrawerSessionId: cashDrawerSessionId.trim(),
        referenceType: 'purchase_refund', referenceId: purchaseId.trim(), referenceNumber: purchaseNo.trim(),
        partyType: 'supplier', partyId: supplierId.trim(), partyName: supplierName.trim(),
        paymentMethod: 'Cash', createdBy: createdBy.trim(), createdByUserId: createdByUserId.trim(),
        deviceId: deviceId.trim(), branchId: branchId.trim(), storeId: storeId.trim(), notes: notes.trim(),
        idempotencyKey: 'purchase_refund:${purchaseId.trim()}', occurredAt: when, createdAt: now, updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      ));
      await _moveCashLocation(cashLocationId.trim(), amount, now);
      return amount;
    });
  }

  /// Backfills Cash Ledger rows for legacy cash receipt/payment vouchers that
  /// pre-date ledger routing. This is history-only and deliberately does not
  /// mutate cash_locations.current_balance because the legacy voucher already
  /// affected the cash balance when it was originally posted.
  ///
  /// Safe to run repeatedly: existing voucher references are skipped.
  Future<void> backfillLegacyCashLedger() async {
    await _db.transaction(() async {
      await _db.customStatement(r'''
        INSERT OR IGNORE INTO cash_ledger_transactions (
          id, type, direction, amount, currency, cash_location_id,
          cash_drawer_session_id, reference_type, reference_id, reference_number,
          party_type, party_id, party_name, payment_method,
          created_by, created_by_user_id, device_id, branch_id, store_id, notes,
          idempotency_key, occurred_at, created_at, updated_at, deleted_at,
          reversal_of_id, sync_status, version, last_modified_by_device_id
        )
        SELECT
          'legacy_receipt_' || rv.id,
          'receipt',
          'in',
          rv.amount,
          CASE WHEN TRIM(rv.currency) = '' THEN 'USD' ELSE UPPER(rv.currency) END,
          COALESCE(NULLIF(TRIM(rv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), '')),
          rv.cash_drawer_session_id,
          'receipt_voucher',
          rv.id,
          rv.voucher_no,
          'customer',
          rv.customer_id,
          rv.customer_name,
          CASE WHEN TRIM(rv.payment_method) = '' THEN 'Cash' ELSE rv.payment_method END,
          rv.created_by,
          rv.created_by_user_id,
          rv.device_id,
          rv.branch_id,
          rv.store_id,
          rv.notes,
          'receipt:' || rv.id,
          rv.voucher_date,
          rv.created_at,
          rv.updated_at,
          '',
          '',
          'synced',
          rv.version,
          rv.last_modified_by_device_id
        FROM receipt_vouchers rv
        LEFT JOIN cash_drawer_sessions cds ON cds.id = rv.cash_drawer_session_id
        WHERE rv.deleted_at = ''
          AND rv.status = 'posted'
          AND (TRIM(rv.payment_method) = '' OR LOWER(TRIM(rv.payment_method)) = 'cash')
          AND COALESCE(NULLIF(TRIM(rv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), '')) IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM cash_locations cl
            WHERE cl.id = COALESCE(NULLIF(TRIM(rv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), ''))
              AND cl.deleted_at = ''
          )
          AND NOT EXISTS (
            SELECT 1 FROM cash_ledger_transactions tx
            WHERE tx.deleted_at = ''
              AND tx.reference_type = 'receipt_voucher'
              AND tx.reference_id = rv.id
          );
      ''');

      await _db.customStatement(r'''
        INSERT OR IGNORE INTO cash_ledger_transactions (
          id, type, direction, amount, currency, cash_location_id,
          cash_drawer_session_id, reference_type, reference_id, reference_number,
          party_type, party_id, party_name, payment_method,
          created_by, created_by_user_id, device_id, branch_id, store_id, notes,
          idempotency_key, occurred_at, created_at, updated_at, deleted_at,
          reversal_of_id, sync_status, version, last_modified_by_device_id
        )
        SELECT
          'legacy_payment_' || pv.id,
          'supplier_payment',
          'out',
          pv.amount,
          CASE WHEN TRIM(pv.currency) = '' THEN 'USD' ELSE UPPER(pv.currency) END,
          COALESCE(NULLIF(TRIM(pv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), '')),
          pv.cash_drawer_session_id,
          'payment_voucher',
          pv.id,
          pv.voucher_no,
          'supplier',
          pv.supplier_id,
          pv.supplier_name,
          CASE WHEN TRIM(pv.payment_method) = '' THEN 'Cash' ELSE pv.payment_method END,
          pv.created_by,
          pv.created_by_user_id,
          pv.device_id,
          pv.branch_id,
          pv.store_id,
          pv.notes,
          'payment:' || pv.id,
          pv.voucher_date,
          pv.created_at,
          pv.updated_at,
          '',
          '',
          'synced',
          pv.version,
          pv.last_modified_by_device_id
        FROM payment_vouchers pv
        LEFT JOIN cash_drawer_sessions cds ON cds.id = pv.cash_drawer_session_id
        WHERE pv.deleted_at = ''
          AND pv.status = 'posted'
          AND (TRIM(pv.payment_method) = '' OR LOWER(TRIM(pv.payment_method)) = 'cash')
          AND COALESCE(NULLIF(TRIM(pv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), '')) IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM cash_locations cl
            WHERE cl.id = COALESCE(NULLIF(TRIM(pv.cash_location_id), ''), NULLIF(TRIM(cds.cash_location_id), ''))
              AND cl.deleted_at = ''
          )
          AND NOT EXISTS (
            SELECT 1 FROM cash_ledger_transactions tx
            WHERE tx.deleted_at = ''
              AND tx.reference_type = 'payment_voucher'
              AND tx.reference_id = pv.id
          );
      ''');
      // Payments that pre-date Phase 2 do not have receipt_vouchers /
      // payment_vouchers rows at all. They live only in account_transactions.
      // Materialize those historical cash receipts/payments into Cash Ledger as
      // immutable history. Resolve their drawer from the original device/branch
      // when possible, then fall back to the default/main drawer. Never move the
      // live balance here: these transactions already affected legacy balances.
      await _db.customStatement(r'''
        INSERT OR IGNORE INTO cash_ledger_transactions (
          id, type, direction, amount, currency, cash_location_id,
          cash_drawer_session_id, reference_type, reference_id, reference_number,
          party_type, party_id, party_name, payment_method,
          created_by, created_by_user_id, device_id, branch_id, store_id, notes,
          idempotency_key, occurred_at, created_at, updated_at, deleted_at,
          reversal_of_id, sync_status, version, last_modified_by_device_id
        )
        SELECT
          'legacy_account_payment_' || at.id,
          CASE WHEN at.transaction_type = 'paymentReceived' THEN 'receipt' ELSE 'supplier_payment' END,
          CASE WHEN at.transaction_type = 'paymentReceived' THEN 'in' ELSE 'out' END,
          CASE WHEN at.debit > 0 THEN at.debit ELSE at.credit END,
          CASE WHEN TRIM(at.currency) = '' THEN 'USD' ELSE UPPER(at.currency) END,
          COALESCE(
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
               AND TRIM(at.device_id) <> '' AND cl.device_id = at.device_id
               AND (TRIM(at.branch_id) = '' OR cl.branch_id = at.branch_id OR TRIM(cl.branch_id) = '')
             ORDER BY cl.is_default DESC, cl.id LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
               AND TRIM(at.branch_id) <> '' AND cl.branch_id = at.branch_id
             ORDER BY cl.is_default DESC, cl.id LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.id = 'cl_main_drawer' AND cl.deleted_at = '' AND cl.is_active = 1 LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
             ORDER BY cl.is_default DESC, cl.id LIMIT 1)
          ),
          '',
          'legacy_account_transaction',
          at.id,
          at.reference_no,
          CASE WHEN at.transaction_type = 'paymentReceived' THEN 'customer' ELSE 'supplier' END,
          at.account_id,
          at.account_name,
          CASE WHEN TRIM(at.payment_method) = '' THEN 'Cash' ELSE at.payment_method END,
          '', '',
          at.device_id,
          at.branch_id,
          at.store_id,
          at.note,
          'legacy_account_payment:' || at.id,
          CASE WHEN TRIM(at.transaction_date) = '' THEN at.created_at ELSE at.transaction_date END,
          at.created_at,
          at.updated_at,
          '', '', 'synced', at.version, at.last_modified_by_device_id
        FROM account_transactions at
        WHERE at.deleted_at = ''
          AND at.transaction_type IN ('paymentReceived', 'paymentPaid')
          AND ((at.transaction_type = 'paymentReceived' AND LOWER(TRIM(at.account_type)) = 'customer')
            OR (at.transaction_type = 'paymentPaid' AND LOWER(TRIM(at.account_type)) = 'supplier'))
          AND (at.debit > 0 OR at.credit > 0)
          AND (TRIM(at.payment_method) = '' OR LOWER(TRIM(at.payment_method)) = 'cash')
          AND NOT EXISTS (
            SELECT 1 FROM receipt_vouchers rv
            WHERE at.id = rv.id || '-customer-payment'
          )
          AND NOT EXISTS (
            SELECT 1 FROM payment_vouchers pv
            WHERE at.id = pv.id || '-supplier-payment'
          )
          AND NOT EXISTS (
            SELECT 1 FROM expenses e WHERE e.id = at.reference_id
          )
          AND COALESCE(
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
               AND TRIM(at.device_id) <> '' AND cl.device_id = at.device_id
               AND (TRIM(at.branch_id) = '' OR cl.branch_id = at.branch_id OR TRIM(cl.branch_id) = '')
             ORDER BY cl.is_default DESC, cl.id LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
               AND TRIM(at.branch_id) <> '' AND cl.branch_id = at.branch_id
             ORDER BY cl.is_default DESC, cl.id LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.id = 'cl_main_drawer' AND cl.deleted_at = '' AND cl.is_active = 1 LIMIT 1),
            (SELECT cl.id FROM cash_locations cl
             WHERE cl.deleted_at = '' AND cl.is_active = 1 AND cl.type = 'cash_drawer'
             ORDER BY cl.is_default DESC, cl.id LIMIT 1)
          ) IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM cash_ledger_transactions tx
            WHERE tx.deleted_at = ''
              AND tx.reference_type = 'legacy_account_transaction'
              AND tx.reference_id = at.id
          );
      ''');
    });
  }

  Future<ReceiptVoucher?> findReceiptById(String id) async {
    if (id.trim().isEmpty) return null;
    final row = await _db.customSelect(
      "SELECT * FROM receipt_vouchers WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id.trim())],
    ).getSingleOrNull();
    return row == null ? null : _receiptFromRow(row.data, await allocationsFor('receipt', id));
  }

  Future<PaymentVoucher?> findPaymentById(String id) async {
    if (id.trim().isEmpty) return null;
    final row = await _db.customSelect(
      "SELECT * FROM payment_vouchers WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id.trim())],
    ).getSingleOrNull();
    return row == null ? null : _paymentFromRow(row.data, await allocationsFor('payment', id));
  }

  Future<List<PaymentAllocation>> allocationsFor(String voucherType, String voucherId) async {
    final rows = await _db.customSelect(
      "SELECT * FROM payment_allocations WHERE voucher_type = ? AND voucher_id = ? AND deleted_at = '' ORDER BY created_at, id",
      variables: <Variable<Object>>[
        Variable<String>(voucherType.trim().toLowerCase()),
        Variable<String>(voucherId.trim()),
      ],
    ).get();
    return rows.map((row) => _allocationFromRow(row.data)).toList(growable: false);
  }

  Future<List<ReceiptVoucher>> listReceipts({String customerId = '', int limit = 100, int offset = 0}) async {
    final where = customerId.trim().isEmpty ? "deleted_at = ''" : "deleted_at = '' AND customer_id = ?";
    final variables = <Variable<Object>>[
      if (customerId.trim().isNotEmpty) Variable<String>(customerId.trim()),
      Variable<int>(limit.clamp(1, 500).toInt()),
      Variable<int>(offset < 0 ? 0 : offset),
    ];
    final rows = await _db.customSelect(
      'SELECT * FROM receipt_vouchers WHERE $where ORDER BY voucher_date DESC, created_at DESC LIMIT ? OFFSET ?',
      variables: variables,
    ).get();
    final result = <ReceiptVoucher>[];
    for (final row in rows) {
      final id = row.data['id']?.toString() ?? '';
      result.add(_receiptFromRow(row.data, await allocationsFor('receipt', id)));
    }
    return result;
  }

  Future<List<PaymentVoucher>> listPayments({String supplierId = '', int limit = 100, int offset = 0}) async {
    final where = supplierId.trim().isEmpty ? "deleted_at = ''" : "deleted_at = '' AND supplier_id = ?";
    final variables = <Variable<Object>>[
      if (supplierId.trim().isNotEmpty) Variable<String>(supplierId.trim()),
      Variable<int>(limit.clamp(1, 500).toInt()),
      Variable<int>(offset < 0 ? 0 : offset),
    ];
    final rows = await _db.customSelect(
      'SELECT * FROM payment_vouchers WHERE $where ORDER BY voucher_date DESC, created_at DESC LIMIT ? OFFSET ?',
      variables: variables,
    ).get();
    final result = <PaymentVoucher>[];
    for (final row in rows) {
      final id = row.data['id']?.toString() ?? '';
      result.add(_paymentFromRow(row.data, await allocationsFor('payment', id)));
    }
    return result;
  }

  void _validateCommon({
    required String partyId,
    required double amount,
    required String paymentMethod,
    required String cashLocationId,
    required String cashDrawerSessionId,
  }) {
    if (partyId.trim().isEmpty) {
      throw ArgumentError.value(partyId, 'partyId', 'Must not be empty.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero.');
    }
    if (_isCash(paymentMethod)) {
      if (cashLocationId.trim().isEmpty || cashDrawerSessionId.trim().isEmpty) {
        throw StateError('Cash vouchers require an open cash drawer location and session.');
      }
    }
  }

  Future<List<PaymentAllocation>> _prepareAllocations({
    required String voucherType,
    required String voucherId,
    required String expectedReferenceType,
    required String partyId,
    required double voucherAmount,
    required String voucherCurrency,
    required List<PaymentAllocationDraft> drafts,
    required String deviceId,
  }) async {
    final prepared = <PaymentAllocation>[];
    final seenTargets = <String>{};
    double allocatedVoucherAmount = 0;
    for (final draft in drafts) {
      if (draft.referenceId.trim().isEmpty || !draft.amount.isFinite || draft.amount <= 0) {
        throw ArgumentError('Allocation reference and amount must be valid.');
      }
      if (!seenTargets.add(draft.referenceId.trim())) {
        throw StateError('A voucher cannot allocate the same document more than once.');
      }
      allocatedVoucherAmount += draft.amount;
      if (allocatedVoucherAmount - voucherAmount > _epsilon) {
        throw StateError('Allocated amount cannot exceed voucher amount.');
      }

      final target = expectedReferenceType == 'sale'
          ? await _saleTarget(draft.referenceId.trim())
          : await _purchaseTarget(draft.referenceId.trim(), voucherCurrency);
      if (target == null) {
        throw StateError('${expectedReferenceType == 'sale' ? 'Sale' : 'Purchase'} ${draft.referenceId} does not exist.');
      }
      if (target.partyId.isNotEmpty && target.partyId != partyId) {
        throw StateError('Allocation target belongs to a different ${voucherType == 'receipt' ? 'customer' : 'supplier'}.');
      }
      if (target.isClosedDocument) {
        throw StateError('Cannot allocate a cancelled/returned document.');
      }

      final requestedReferenceCurrency = draft.referenceCurrency.trim().isEmpty
          ? target.currency
          : _currency(draft.referenceCurrency);
      if (requestedReferenceCurrency != target.currency) {
        throw StateError('Allocation reference currency does not match the target document currency.');
      }
      final sameCurrency = voucherCurrency == target.currency;
      final referenceAmount = draft.referenceAmount > 0
          ? draft.referenceAmount
          : (sameCurrency ? draft.amount : 0.0);
      if (!referenceAmount.isFinite || referenceAmount <= 0) {
        throw StateError('Cross-currency allocations require a positive referenceAmount.');
      }
      final exchangeRate = draft.exchangeRate;
      if (!sameCurrency && (!exchangeRate.isFinite || exchangeRate <= 0)) {
        throw StateError('Cross-currency allocations require a positive exchangeRate.');
      }
      if (referenceAmount - target.balanceDue > _epsilon) {
        throw StateError('Allocation exceeds remaining balance of ${target.referenceNumber}.');
      }

      final now = DateTime.now().toUtc();
      prepared.add(PaymentAllocation(
        id: _newId('alloc'),
        voucherType: voucherType,
        voucherId: voucherId,
        referenceType: expectedReferenceType,
        referenceId: target.id,
        referenceNumber: draft.referenceNumber.trim().isEmpty ? target.referenceNumber : draft.referenceNumber.trim(),
        amount: _money(draft.amount),
        referenceAmount: _money(referenceAmount),
        currency: voucherCurrency,
        referenceCurrency: target.currency,
        exchangeRate: sameCurrency ? 1.0 : exchangeRate,
        createdAt: now,
        updatedAt: now,
        lastModifiedByDeviceId: deviceId.trim(),
      ));
    }
    return prepared;
  }

  Future<_AllocationTarget?> _saleTarget(String id) async {
    final row = await _db.customSelect(
      '''
      SELECT s.id, s.invoice_no, s.customer_id, s.customer_name, s.invoice_currency,
             s.paid_amount, s.transaction_amount, s.discount, s.status,
             COALESCE((SELECT SUM(si.unit_price * si.quantity)
                       FROM sale_items si WHERE si.sale_id = s.id), 0) AS item_total
      FROM sales s
      WHERE s.id = ? AND s.deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    final data = row.data;
    final txTotal = _number(data['transaction_amount']);
    final itemTotal = _number(data['item_total']);
    final discount = _number(data['discount']);
    final total = txTotal > 0 ? txTotal : max(0, itemTotal - discount).toDouble();
    return _AllocationTarget(
      id: id,
      referenceNumber: data['invoice_no']?.toString() ?? '',
      partyId: data['customer_id']?.toString() ?? '',
      partyName: data['customer_name']?.toString() ?? '',
      currency: _currency(data['invoice_currency']?.toString() ?? 'USD'),
      total: total,
      paid: _number(data['paid_amount']),
      status: data['status']?.toString() ?? '',
    );
  }

  Future<_AllocationTarget?> _purchaseTarget(String id, String currency) async {
    final row = await _db.customSelect(
      '''
      SELECT p.id, p.purchase_no, p.supplier_id, p.supplier_name,
             p.paid_amount, p.status,
             COALESCE((SELECT SUM(pi.quantity * pi.unit_cost)
                       FROM purchase_items pi WHERE pi.purchase_id = p.id), 0) AS item_total
      FROM purchases p
      WHERE p.id = ? AND p.deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    final data = row.data;
    return _AllocationTarget(
      id: id,
      referenceNumber: data['purchase_no']?.toString() ?? '',
      partyId: data['supplier_id']?.toString() ?? '',
      partyName: data['supplier_name']?.toString() ?? '',
      currency: currency,
      total: _number(data['item_total']),
      paid: _number(data['paid_amount']),
      status: data['status']?.toString() ?? '',
    );
  }

  Future<void> _insertReceipt(ReceiptVoucher item) async {
    await _db.customInsert(
      '''
      INSERT INTO receipt_vouchers
        (id, voucher_no, customer_id, customer_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, notes, created_by, created_by_user_id,
         device_id, branch_id, store_id, idempotency_key, created_at, updated_at,
         deleted_at, sync_status, version, last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'posted', ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 'pending', 1, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(item.id), Variable<String>(item.voucherNo),
        Variable<String>(item.customerId), Variable<String>(item.customerName),
        Variable<String>(item.date.toIso8601String()), Variable<double>(item.amount),
        Variable<double>(item.unallocatedAmount), Variable<String>(item.currency),
        Variable<String>(item.paymentMethod), Variable<String>(item.cashLocationId),
        Variable<String>(item.cashDrawerSessionId), Variable<String>(item.notes),
        Variable<String>(item.createdBy), Variable<String>(item.createdByUserId),
        Variable<String>(item.deviceId), Variable<String>(item.branchId),
        Variable<String>(item.storeId), Variable<String>(item.idempotencyKey),
        Variable<String>(item.createdAt.toIso8601String()), Variable<String>(item.updatedAt.toIso8601String()),
        Variable<String>(item.lastModifiedByDeviceId),
      ],
    );
  }

  Future<void> _insertPayment(PaymentVoucher item) async {
    await _db.customInsert(
      '''
      INSERT INTO payment_vouchers
        (id, voucher_no, supplier_id, supplier_name, voucher_date, amount,
         unallocated_amount, currency, payment_method, cash_location_id,
         cash_drawer_session_id, status, notes, created_by, created_by_user_id,
         device_id, branch_id, store_id, idempotency_key, created_at, updated_at,
         deleted_at, sync_status, version, last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'posted', ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 'pending', 1, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(item.id), Variable<String>(item.voucherNo),
        Variable<String>(item.supplierId), Variable<String>(item.supplierName),
        Variable<String>(item.date.toIso8601String()), Variable<double>(item.amount),
        Variable<double>(item.unallocatedAmount), Variable<String>(item.currency),
        Variable<String>(item.paymentMethod), Variable<String>(item.cashLocationId),
        Variable<String>(item.cashDrawerSessionId), Variable<String>(item.notes),
        Variable<String>(item.createdBy), Variable<String>(item.createdByUserId),
        Variable<String>(item.deviceId), Variable<String>(item.branchId),
        Variable<String>(item.storeId), Variable<String>(item.idempotencyKey),
        Variable<String>(item.createdAt.toIso8601String()), Variable<String>(item.updatedAt.toIso8601String()),
        Variable<String>(item.lastModifiedByDeviceId),
      ],
    );
  }

  Future<void> _insertAllocations(List<PaymentAllocation> items) async {
    for (final item in items) {
      await _db.customInsert(
        '''
        INSERT INTO payment_allocations
          (id, voucher_type, voucher_id, reference_type, reference_id,
           reference_number, amount, reference_amount, currency,
           reference_currency, exchange_rate, created_at, updated_at, deleted_at,
           sync_status, version, last_modified_by_device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 'pending', 1, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(item.id), Variable<String>(item.voucherType),
          Variable<String>(item.voucherId), Variable<String>(item.referenceType),
          Variable<String>(item.referenceId), Variable<String>(item.referenceNumber),
          Variable<double>(item.amount), Variable<double>(item.effectiveReferenceAmount),
          Variable<String>(item.currency), Variable<String>(item.referenceCurrency),
          Variable<double>(item.exchangeRate), Variable<String>(item.createdAt.toIso8601String()),
          Variable<String>(item.updatedAt.toIso8601String()), Variable<String>(item.lastModifiedByDeviceId),
        ],
      );
    }
  }

  Future<void> _applyAllocationCaches(List<PaymentAllocation> items, {required String deviceId}) async {
    final grouped = <String, double>{};
    final types = <String, String>{};
    for (final item in items) {
      grouped[item.referenceId] = (grouped[item.referenceId] ?? 0) + item.effectiveReferenceAmount;
      types[item.referenceId] = item.referenceType;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    for (final entry in grouped.entries) {
      if (types[entry.key] == 'sale') {
        final target = await _saleTarget(entry.key);
        if (target == null) throw StateError('Sale ${entry.key} disappeared during allocation.');
        final newPaid = _money(target.paid + entry.value).clamp(0, target.total).toDouble();
        final paymentStatus = newPaid + _epsilon >= target.total ? 'paid' : (newPaid > 0 ? 'partial' : 'unpaid');
        await _db.customUpdate(
          '''
          UPDATE sales
          SET paid_amount = ?, payment_status = ?, updated_at = ?, sync_status = 'pending',
              version = version + 1, last_modified_by_device_id = ?
          WHERE id = ? AND deleted_at = ''
          ''',
          variables: <Variable<Object>>[
            Variable<double>(newPaid), Variable<String>(paymentStatus),
            Variable<String>(now), Variable<String>(deviceId.trim()), Variable<String>(entry.key),
          ],
        );
      } else {
        final target = await _purchaseTarget(entry.key, 'USD');
        if (target == null) throw StateError('Purchase ${entry.key} disappeared during allocation.');
        final newPaid = _money(target.paid + entry.value).clamp(0, target.total).toDouble();
        final paymentStatus = newPaid + _epsilon >= target.total ? 'paid' : (newPaid > 0 ? 'partial' : 'unpaid');
        await _db.customUpdate(
          '''
          UPDATE purchases
          SET paid_amount = ?, payment_status = ?, updated_at = ?, sync_status = 'pending',
              version = version + 1, last_modified_by_device_id = ?
          WHERE id = ? AND deleted_at = ''
          ''',
          variables: <Variable<Object>>[
            Variable<double>(newPaid), Variable<String>(paymentStatus),
            Variable<String>(now), Variable<String>(deviceId.trim()), Variable<String>(entry.key),
          ],
        );
      }
    }
  }

  Future<void> _appendVoucherCashMovement({
    required String type,
    required String direction,
    required String voucherId,
    required String voucherNo,
    required double amount,
    required String currency,
    required String cashLocationId,
    required String sessionId,
    required String partyType,
    required String partyId,
    required String partyName,
    required String paymentMethod,
    required String createdBy,
    required String createdByUserId,
    required String deviceId,
    required String branchId,
    required String storeId,
    required String notes,
    required DateTime occurredAt,
  }) async {
    final now = DateTime.now().toUtc();
    await _cashLedger.appendInExistingTransaction(CashLedgerTransaction(
      id: _cashLedger.generateId(),
      type: type == 'receipt' ? 'receipt' : 'supplier_payment',
      direction: direction,
      amount: amount,
      currency: currency,
      cashLocationId: cashLocationId,
      cashDrawerSessionId: sessionId,
      referenceType: type == 'receipt' ? 'receipt_voucher' : 'payment_voucher',
      referenceId: voucherId,
      referenceNumber: voucherNo,
      partyType: partyType,
      partyId: partyId,
      partyName: partyName,
      paymentMethod: paymentMethod,
      createdBy: createdBy,
      createdByUserId: createdByUserId,
      deviceId: deviceId,
      branchId: branchId,
      storeId: storeId,
      notes: notes,
      idempotencyKey: '$type:$voucherId',
      occurredAt: occurredAt,
      createdAt: now,
      updatedAt: now,
      lastModifiedByDeviceId: deviceId,
    ));
  }

  Future<void> _moveCashLocation(String locationId, double delta, DateTime now) async {
    final updated = await _db.customUpdate(
      '''
      UPDATE cash_locations
      SET current_balance = current_balance + ?, updated_at = ?
      WHERE id = ? AND deleted_at = '' AND is_active = 1
      ''',
      variables: <Variable<Object>>[
        Variable<double>(delta), Variable<String>(now.toIso8601String()), Variable<String>(locationId),
      ],
    );
    if (updated != 1) throw StateError('Cash location is unavailable.');
  }

  Future<ReceiptVoucher?> _findReceiptByIdentity(String id, String idempotencyKey) async {
    final key = idempotencyKey.trim();
    final row = await _db.customSelect(
      key.isEmpty
          ? "SELECT * FROM receipt_vouchers WHERE id = ? AND deleted_at = '' LIMIT 1"
          : "SELECT * FROM receipt_vouchers WHERE (id = ? OR idempotency_key = ?) AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[
        Variable<String>(id),
        if (key.isNotEmpty) Variable<String>(key),
      ],
    ).getSingleOrNull();
    if (row == null) return null;
    final existingId = row.data['id']?.toString() ?? '';
    return _receiptFromRow(row.data, await allocationsFor('receipt', existingId));
  }

  Future<PaymentVoucher?> _findPaymentByIdentity(String id, String idempotencyKey) async {
    final key = idempotencyKey.trim();
    final row = await _db.customSelect(
      key.isEmpty
          ? "SELECT * FROM payment_vouchers WHERE id = ? AND deleted_at = '' LIMIT 1"
          : "SELECT * FROM payment_vouchers WHERE (id = ? OR idempotency_key = ?) AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[
        Variable<String>(id),
        if (key.isNotEmpty) Variable<String>(key),
      ],
    ).getSingleOrNull();
    if (row == null) return null;
    final existingId = row.data['id']?.toString() ?? '';
    return _paymentFromRow(row.data, await allocationsFor('payment', existingId));
  }

  ReceiptVoucher _receiptFromRow(Map<String, Object?> row, List<PaymentAllocation> allocations) {
    return ReceiptVoucher(
      id: row['id']?.toString() ?? '', voucherNo: row['voucher_no']?.toString() ?? '',
      customerId: row['customer_id']?.toString() ?? '', customerName: row['customer_name']?.toString() ?? '',
      date: _date(row['voucher_date']), amount: _number(row['amount']), unallocatedAmount: _number(row['unallocated_amount']),
      currency: row['currency']?.toString() ?? 'USD', paymentMethod: row['payment_method']?.toString() ?? 'Cash',
      cashLocationId: row['cash_location_id']?.toString() ?? '', cashDrawerSessionId: row['cash_drawer_session_id']?.toString() ?? '',
      status: row['status']?.toString() ?? 'posted', notes: row['notes']?.toString() ?? '', createdBy: row['created_by']?.toString() ?? '',
      createdByUserId: row['created_by_user_id']?.toString() ?? '', deviceId: row['device_id']?.toString() ?? '', branchId: row['branch_id']?.toString() ?? '',
      storeId: row['store_id']?.toString() ?? '', idempotencyKey: row['idempotency_key']?.toString() ?? '', allocations: allocations,
      createdAt: _date(row['created_at']), updatedAt: _date(row['updated_at']), deletedAt: _nullableDate(row['deleted_at']),
      syncStatus: row['sync_status']?.toString() ?? 'pending', version: (row['version'] as num?)?.toInt() ?? 1,
      lastModifiedByDeviceId: row['last_modified_by_device_id']?.toString() ?? '',
    );
  }

  PaymentVoucher _paymentFromRow(Map<String, Object?> row, List<PaymentAllocation> allocations) {
    return PaymentVoucher(
      id: row['id']?.toString() ?? '', voucherNo: row['voucher_no']?.toString() ?? '',
      supplierId: row['supplier_id']?.toString() ?? '', supplierName: row['supplier_name']?.toString() ?? '',
      date: _date(row['voucher_date']), amount: _number(row['amount']), unallocatedAmount: _number(row['unallocated_amount']),
      currency: row['currency']?.toString() ?? 'USD', paymentMethod: row['payment_method']?.toString() ?? 'Cash',
      cashLocationId: row['cash_location_id']?.toString() ?? '', cashDrawerSessionId: row['cash_drawer_session_id']?.toString() ?? '',
      status: row['status']?.toString() ?? 'posted', notes: row['notes']?.toString() ?? '', createdBy: row['created_by']?.toString() ?? '',
      createdByUserId: row['created_by_user_id']?.toString() ?? '', deviceId: row['device_id']?.toString() ?? '', branchId: row['branch_id']?.toString() ?? '',
      storeId: row['store_id']?.toString() ?? '', idempotencyKey: row['idempotency_key']?.toString() ?? '', allocations: allocations,
      createdAt: _date(row['created_at']), updatedAt: _date(row['updated_at']), deletedAt: _nullableDate(row['deleted_at']),
      syncStatus: row['sync_status']?.toString() ?? 'pending', version: (row['version'] as num?)?.toInt() ?? 1,
      lastModifiedByDeviceId: row['last_modified_by_device_id']?.toString() ?? '',
    );
  }

  PaymentAllocation _allocationFromRow(Map<String, Object?> row) => PaymentAllocation(
        id: row['id']?.toString() ?? '', voucherType: row['voucher_type']?.toString() ?? '', voucherId: row['voucher_id']?.toString() ?? '',
        referenceType: row['reference_type']?.toString() ?? '', referenceId: row['reference_id']?.toString() ?? '',
        referenceNumber: row['reference_number']?.toString() ?? '', amount: _number(row['amount']), referenceAmount: _number(row['reference_amount']),
        currency: row['currency']?.toString() ?? 'USD', referenceCurrency: row['reference_currency']?.toString() ?? 'USD',
        exchangeRate: _number(row['exchange_rate']) <= 0 ? 1 : _number(row['exchange_rate']), createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']), deletedAt: _nullableDate(row['deleted_at']), syncStatus: row['sync_status']?.toString() ?? 'pending',
        version: (row['version'] as num?)?.toInt() ?? 1, lastModifiedByDeviceId: row['last_modified_by_device_id']?.toString() ?? '',
      );

  bool _isCash(String method) {
    final value = method.trim().toLowerCase();
    return value.isEmpty || value == 'cash';
  }

  String _currency(String value) => value.trim().isEmpty ? 'USD' : value.trim().toUpperCase();
  double _money(double value) => (value * 1000000).roundToDouble() / 1000000;
  double _number(Object? value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
  DateTime _date(Object? value) => DateTime.tryParse(value?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  DateTime? _nullableDate(Object? value) => DateTime.tryParse(value?.toString() ?? '');
}

class _AllocationTarget {
  const _AllocationTarget({
    required this.id,
    required this.referenceNumber,
    required this.partyId,
    required this.partyName,
    required this.currency,
    required this.total,
    required this.paid,
    required this.status,
  });

  final String id, referenceNumber, partyId, partyName, currency, status;
  final double total, paid;
  double get balanceDue => max(0, total - paid).toDouble();
  bool get isClosedDocument {
    final value = status.trim().toLowerCase();
    return value == 'cancelled' || value == 'returned' || value == 'void';
  }
}
