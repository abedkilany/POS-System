part of 'payment_voucher_service.dart';

extension PaymentVoucherServiceSplitPart5 on PaymentVoucherService {

  Future<void> _insertCompatibilityAccountMovement({
    required String voucherType,
    required String voucherId,
    required String voucherNo,
    required String partyId,
    required String partyName,
    required double amount,
    required String currency,
    required String paymentMethod,
    required List<PaymentAllocation> allocations,
    required String notes,
    required String deviceId,
    required String branchId,
    required String storeId,
    required DateTime occurredAt,
    String movementVersionSuffix = '',
  }) async {
    final isReceipt = voucherType.trim().toLowerCase() == 'receipt';
    if (voucherId.trim().isEmpty || partyId.trim().isEmpty || amount <= 0) {
      return;
    }

    final primaryBase =
        '$voucherId-${isReceipt ? 'customer-payment' : 'supplier-payment'}';
    final accountBase =
        '$voucherId-${isReceipt ? 'customer' : 'supplier'}-account-payment';
    final suffix = movementVersionSuffix.trim();

    String versioned(String base) => suffix.isEmpty ? base : '$base-$suffix';

    Future<void> insertMovement({
      required String id,
      required String referenceId,
      required String referenceNo,
      required double movementAmount,
    }) async {
      if (movementAmount <= PaymentVoucherService._epsilon) return;
      final existing = await _db.customSelect(
        "SELECT id FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(id)],
      ).getSingleOrNull();
      if (existing != null) return;

      final nextSort = await _db
          .customSelect(
            'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
          )
          .getSingle();
      final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
      final iso = occurredAt.toUtc().toIso8601String();

      await _db.customInsert(
        '''
        INSERT OR IGNORE INTO account_transactions
          (id, entity_type, created_at, updated_at, deleted_at, device_id,
           sync_status, store_id, branch_id, version, sort_index, account_type,
           account_id, account_name, transaction_date, transaction_type,
           reference_id, reference_no, debit, credit, currency, payment_method,
           note, last_modified_by_device_id)
        VALUES (?, 'accountTransaction', ?, ?, '', ?, 'pending', ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(id),
          Variable<String>(iso),
          Variable<String>(iso),
          Variable<String>(deviceId.trim()),
          Variable<String>(storeId.trim()),
          Variable<String>(branchId.trim()),
          Variable<int>(sortIndex),
          Variable<String>(isReceipt ? 'customer' : 'supplier'),
          Variable<String>(partyId.trim()),
          Variable<String>(partyName.trim()),
          Variable<String>(iso),
          Variable<String>(isReceipt ? 'paymentReceived' : 'paymentPaid'),
          Variable<String>(referenceId.trim()),
          Variable<String>(referenceNo.trim()),
          Variable<double>(isReceipt ? 0 : _money(movementAmount)),
          Variable<double>(isReceipt ? _money(movementAmount) : 0),
          Variable<String>(_currency(currency)),
          Variable<String>(paymentMethod.trim()),
          Variable<String>(
            notes.trim().isEmpty
                ? (isReceipt ? 'Receipt $voucherNo' : 'Payment $voucherNo')
                : notes.trim(),
          ),
          Variable<String>(deviceId.trim()),
        ],
      );
    }

    var allocated = 0.0;
    for (var index = 0; index < allocations.length; index++) {
      final allocation = allocations[index];
      final allocationAmount = _money(
        allocation.referenceCurrency == currency
            ? allocation.effectiveReferenceAmount
            : allocation.amount,
      );
      if (allocationAmount <= PaymentVoucherService._epsilon) continue;
      allocated = _money(allocated + allocationAmount);

      final baseId = index == 0 ? primaryBase : '$primaryBase-${index + 1}';
      final movementId = versioned(baseId);
      final referenceNo = allocation.referenceNumber.trim().isNotEmpty
          ? allocation.referenceNumber.trim()
          : voucherNo.trim();

      await insertMovement(
        id: movementId,
        referenceId: allocation.referenceId,
        referenceNo: referenceNo,
        movementAmount: allocationAmount,
      );
    }

    final unallocated = _money(amount - allocated);
    if (unallocated > PaymentVoucherService._epsilon || allocations.isEmpty) {
      await insertMovement(
        id: versioned(accountBase),
        referenceId: voucherId,
        referenceNo: voucherNo,
        movementAmount: allocations.isEmpty ? _money(amount) : unallocated,
      );
    }
  }

  Future<void> _reverseCompatibilityAccountMovements({
    required String voucherType,
    required String voucherId,
    required String reason,
    required String deviceId,
    required DateTime occurredAt,
  }) async {
    final isReceipt = voucherType.trim().toLowerCase() == 'receipt';
    final primaryBase =
        '$voucherId-${isReceipt ? 'customer-payment' : 'supplier-payment'}';
    final accountBase =
        '$voucherId-${isReceipt ? 'customer' : 'supplier'}-account-payment';
    final originals = await _db.customSelect(
      '''
      SELECT id, account_type, account_id, account_name, reference_id, reference_no,
             debit, credit, currency, payment_method, store_id, branch_id
      FROM account_transactions
      WHERE deleted_at = ''
        AND transaction_type <> 'paymentReversal'
        AND (id = ? OR id LIKE ? OR id = ? OR id LIKE ?)
      ORDER BY transaction_date, created_at, id
      ''',
      variables: <Variable<Object>>[
        Variable<String>(primaryBase),
        Variable<String>('$primaryBase-%'),
        Variable<String>(accountBase),
        Variable<String>('$accountBase-%'),
      ],
    ).get();
    for (final original in originals) {
      final originalId = original.data['id']?.toString() ?? '';
      if (originalId.isEmpty) continue;
      final reversalId = '$originalId-reversal';
      final exists = await _db.customSelect(
        "SELECT id FROM account_transactions WHERE id = ? AND deleted_at = '' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(reversalId)],
      ).getSingleOrNull();
      if (exists != null) continue;
      final nextSort = await _db
          .customSelect(
            'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM account_transactions',
          )
          .getSingle();
      final sortIndex = (nextSort.data['next_sort'] as num?)?.toInt() ?? 1;
      final iso = occurredAt.toUtc().toIso8601String();
      final debit = (original.data['debit'] as num?)?.toDouble() ?? 0.0;
      final credit = (original.data['credit'] as num?)?.toDouble() ?? 0.0;
      await _db.customInsert(
        '''
        INSERT OR IGNORE INTO account_transactions
          (id, entity_type, created_at, updated_at, deleted_at, device_id,
           sync_status, store_id, branch_id, version, sort_index, account_type,
           account_id, account_name, transaction_date, transaction_type,
           reference_id, reference_no, debit, credit, currency, payment_method,
           note, last_modified_by_device_id)
        VALUES (?, 'accountTransaction', ?, ?, '', ?, 'pending', ?, ?, 1, ?, ?, ?, ?, ?, 'paymentReversal', ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(reversalId),
          Variable<String>(iso),
          Variable<String>(iso),
          Variable<String>(deviceId.trim()),
          Variable<String>(original.data['store_id']?.toString() ?? ''),
          Variable<String>(original.data['branch_id']?.toString() ?? ''),
          Variable<int>(sortIndex),
          Variable<String>(original.data['account_type']?.toString() ?? ''),
          Variable<String>(original.data['account_id']?.toString() ?? ''),
          Variable<String>(original.data['account_name']?.toString() ?? ''),
          Variable<String>(iso),
          Variable<String>(
              original.data['reference_id']?.toString() ?? voucherId),
          Variable<String>(original.data['reference_no']?.toString() ?? ''),
          Variable<double>(credit),
          Variable<double>(debit),
          Variable<String>(original.data['currency']?.toString() ?? 'USD'),
          Variable<String>(original.data['payment_method']?.toString() ?? ''),
          Variable<String>(reason.trim().isEmpty
              ? 'Voucher reversed'
              : 'Voucher reversal: ${reason.trim()}'),
          Variable<String>(deviceId.trim()),
        ],
      );
    }
  }

  /// Rebuilds the purchase paid_amount/payment_status compatibility cache
  /// from the authoritative active payment allocations and returns the synced
  /// paid amount. Safe to call before refund decisions; when the cache already
  /// matches allocations no purchase row/version is mutated.
  Future<double> syncPurchasePaymentCacheFromAllocations({
    required String purchaseId,
    String deviceId = '',
  }) async {
    final id = purchaseId.trim();
    if (id.isEmpty) throw ArgumentError('Purchase id is required.');
    return _db.transaction(() async {
      await _rebuildAllocationCache(
        referenceType: 'purchase',
        referenceId: id,
        deviceId: deviceId,
      );
      final row = await _db.customSelect(
        "SELECT paid_amount FROM purchases WHERE id = ? AND deleted_at = '' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(id)],
      ).getSingleOrNull();
      if (row == null) throw ArgumentError('Purchase not found.');
      return _money(_number(row.data['paid_amount']))
          .clamp(0, double.infinity)
          .toDouble();
    });
  }

  Future<void> _rebuildAllocationCache({
    required String referenceType,
    required String referenceId,
    required String deviceId,
  }) async {
    final type = referenceType.trim().toLowerCase();
    final id = referenceId.trim();
    if (id.isEmpty || (type != 'sale' && type != 'purchase')) return;

    final isSale = type == 'sale';
    final voucherTable = isSale ? 'receipt_vouchers' : 'payment_vouchers';
    final voucherType = isSale ? 'receipt' : 'payment';
    final target =
        isSale ? await _saleTarget(id) : await _purchaseTarget(id, 'USD');
    if (target == null) return;

    final row = await _db.customSelect(
      '''
       SELECT COALESCE(SUM(CASE WHEN pa.allocation_kind = 'reversal'
                               THEN -pa.reference_amount
                               ELSE pa.reference_amount END), 0) AS total
      FROM payment_allocations pa
      INNER JOIN $voucherTable voucher ON voucher.id = pa.voucher_id
      WHERE pa.voucher_type = ?
        AND pa.reference_type = ?
        AND pa.reference_id = ?
        AND pa.deleted_at = ''
        AND pa.status = 'active'
        AND voucher.deleted_at = ''
        AND voucher.status = 'posted'
      ''',
      variables: <Variable<Object>>[
        Variable<String>(voucherType),
        Variable<String>(type),
        Variable<String>(id),
      ],
    ).getSingle();
    // Keep the full active allocation total, even when it is above the new
    // invoice total. The excess is intentional supplier credit/overpayment
    // and must be handled from the cash page rather than silently discarded.
    final paid =
        _money(_number(row.data['total'])).clamp(0, double.infinity).toDouble();
    final paymentStatus = paid + PaymentVoucherService._epsilon >= target.total && target.total > 0
        ? 'paid'
        : (paid > 0 ? 'partial' : 'unpaid');
    final now = DateTime.now().toUtc().toIso8601String();
    final table = isSale ? 'sales' : 'purchases';
    final current = await _db.customSelect(
      "SELECT paid_amount, payment_status FROM $table WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    if (current == null) {
      if (!isSale) throw StateError('Purchase $id was not found.');
      return;
    }
    final currentPaid = _number(current.data['paid_amount']);
    final currentStatus = current.data['payment_status']?.toString() ?? '';
    final needsUpdate =
        (currentPaid - paid).abs() > PaymentVoucherService._epsilon || currentStatus != paymentStatus;
    if (needsUpdate) {
      final updated = await _db.customUpdate(
        '''
        UPDATE $table
        SET paid_amount = ?, payment_status = ?, updated_at = ?,
            sync_status = 'pending', version = version + 1,
            last_modified_by_device_id = ?
        WHERE id = ? AND deleted_at = ''
        ''',
        variables: <Variable<Object>>[
          Variable<double>(paid),
          Variable<String>(paymentStatus),
          Variable<String>(now),
          Variable<String>(deviceId.trim()),
          Variable<String>(id),
        ],
      );
      if (!isSale && updated != 1) {
        throw StateError(
            'Purchase $id payment cache was not updated from allocations.');
      }
    }
    if (!isSale) {
      final verify = await _db.customSelect(
        "SELECT paid_amount, payment_status FROM purchases WHERE id = ? AND deleted_at = '' LIMIT 1",
        variables: <Variable<Object>>[Variable<String>(id)],
      ).getSingleOrNull();
      final storedPaid = _number(verify?.data['paid_amount']);
      final storedStatus = verify?.data['payment_status']?.toString() ?? '';
      if ((storedPaid - paid).abs() > PaymentVoucherService._epsilon ||
          storedStatus != paymentStatus) {
        throw StateError(
            'Purchase $id payment cache does not match its active allocations.');
      }
    }
  }

  Future<void> _repairSplitCompatibilityAccountMovements() async {
    Future<void> repair({required bool isReceipt}) async {
      final voucherTable = isReceipt ? 'receipt_vouchers' : 'payment_vouchers';
      final voucherType = isReceipt ? 'receipt' : 'payment';
      final partyIdColumn = isReceipt ? 'customer_id' : 'supplier_id';
      final partyNameColumn = isReceipt ? 'customer_name' : 'supplier_name';
      final primarySuffix = isReceipt ? 'customer-payment' : 'supplier-payment';
      final movementType = isReceipt ? 'paymentReceived' : 'paymentPaid';
      final amountColumn = isReceipt ? 'credit' : 'debit';

      final rows = await _db.customSelect(
        '''
        SELECT v.id, v.voucher_no, v.$partyIdColumn AS party_id,
               v.$partyNameColumn AS party_name, v.amount, v.currency,
               v.payment_method, v.notes, v.device_id, v.branch_id, v.store_id,
               v.voucher_date, v.unallocated_amount
        FROM $voucherTable v
        WHERE v.deleted_at = ''
          AND v.status = 'posted'
          AND v.version = 1
          AND EXISTS (
            SELECT 1 FROM payment_allocations pa
            WHERE pa.voucher_type = ?
              AND pa.voucher_id = v.id
              AND pa.deleted_at = ''
              AND pa.status = 'active'
          )
          AND (
            v.unallocated_amount > ?
            OR (
              SELECT COUNT(*) FROM payment_allocations pa
              WHERE pa.voucher_type = ?
                AND pa.voucher_id = v.id
                AND pa.deleted_at = ''
                AND pa.status = 'active'
            ) > 1
          )
          AND EXISTS (
            SELECT 1 FROM account_transactions at
            WHERE at.id = v.id || '-$primarySuffix'
              AND at.deleted_at = ''
              AND at.transaction_type = ?
              AND ABS(at.$amountColumn - v.amount) <= ?
          )
        ORDER BY v.voucher_date, v.created_at, v.id
        ''',
        variables: <Variable<Object>>[
          Variable<String>(voucherType),
          Variable<double>(PaymentVoucherService._epsilon),
          Variable<String>(voucherType),
          Variable<String>(movementType),
          Variable<double>(PaymentVoucherService._epsilon),
        ],
      ).get();

      for (final row in rows) {
        final voucherId = row.data['id']?.toString() ?? '';
        if (voucherId.isEmpty) continue;
        final allocations = await allocationsFor(voucherType, voucherId);
        if (allocations.isEmpty) continue;
        final first = allocations.first;
        final firstAmount = _money(first.amount);
        final firstReferenceNo = first.referenceNumber.trim().isNotEmpty
            ? first.referenceNumber.trim()
            : (row.data['voucher_no']?.toString() ?? '');
        final nowIso = DateTime.now().toUtc().toIso8601String();

        await _db.customUpdate(
          '''
          UPDATE account_transactions
          SET reference_id = ?, reference_no = ?,
              debit = ?, credit = ?, updated_at = ?,
              sync_status = 'pending', version = version + 1
          WHERE id = ? AND deleted_at = '' AND transaction_type = ?
          ''',
          variables: <Variable<Object>>[
            Variable<String>(first.referenceId),
            Variable<String>(firstReferenceNo),
            Variable<double>(isReceipt ? 0 : firstAmount),
            Variable<double>(isReceipt ? firstAmount : 0),
            Variable<String>(nowIso),
            Variable<String>('$voucherId-$primarySuffix'),
            Variable<String>(movementType),
          ],
        );

        final occurredAt = DateTime.tryParse(
              row.data['voucher_date']?.toString() ?? '',
            ) ??
            DateTime.now().toUtc();
        await _insertCompatibilityAccountMovement(
          voucherType: voucherType,
          voucherId: voucherId,
          voucherNo: row.data['voucher_no']?.toString() ?? '',
          partyId: row.data['party_id']?.toString() ?? '',
          partyName: row.data['party_name']?.toString() ?? '',
          amount: _number(row.data['amount']),
          currency: row.data['currency']?.toString() ?? 'USD',
          paymentMethod: row.data['payment_method']?.toString() ?? 'Cash',
          allocations: allocations,
          notes: row.data['notes']?.toString() ?? '',
          deviceId: row.data['device_id']?.toString() ?? '',
          branchId: row.data['branch_id']?.toString() ?? '',
          storeId: row.data['store_id']?.toString() ?? '',
          occurredAt: occurredAt,
        );
      }
    }

    await repair(isReceipt: true);
    await repair(isReceipt: false);
  }
}
