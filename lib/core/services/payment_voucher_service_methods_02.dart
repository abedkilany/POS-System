part of 'payment_voucher_service.dart';

extension PaymentVoucherServiceSplitPart2 on PaymentVoucherService {

  /// Safe posted-edit counterpart for supplier payment vouchers.
  Future<PaymentVoucher> editPayment({
    required String voucherId,
    required int expectedVersion,
    String? supplierId,
    String? supplierName,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? cashLocationId,
    String? cashDrawerSessionId,
    List<PaymentAllocationDraft>? allocations,
    String? notes,
    DateTime? date,
    String editedBy = '',
    String editedByUserId = '',
    String deviceId = '',
  }) async {
    final id = voucherId.trim();
    if (id.isEmpty) throw ArgumentError('voucherId is required.');
    final preflight = await findPaymentById(id);
    if (preflight == null) throw StateError('Payment voucher does not exist.');
    if (_isCash(preflight.paymentMethod)) {
      await _ensureVoucherCashHistoryAvailable(
        voucherType: 'payment',
        voucherId: id,
      );
    }

    late List<PaymentAllocationDraft> requestedAllocations;
    late String requestedSupplierId;
    late String requestedSupplierName;
    late double requestedAmount;
    late String requestedCurrency;
    late String requestedPaymentMethod;
    late String requestedCashLocationId;
    late String requestedCashDrawerSessionId;
    late String requestedNotes;
    late DateTime requestedDate;
    var prepared = <PaymentAllocation>[];
    final editReason = 'Payment edited from version $expectedVersion';

    final result = await _db.transaction(() async {
      final pipeline = PostedDocumentEditPipeline<PaymentVoucher>(
        loadAuthoritative: () async {
          final current = await findPaymentById(id);
          if (current == null) throw StateError('Payment voucher disappeared.');
          return current;
        },
        validatePermission: (current) async {
          if (current.status != 'posted' || current.isDeleted) {
            throw StateError(
                'Only active posted payment vouchers can be edited.');
          }
        },
        validateVersion: (current) async {
          if (current.version != expectedVersion) {
            throw StateError(
              'Payment voucher changed by another user. Reload before editing.',
            );
          }
        },
        validateDependencies: (current) async {
          await _assertVoucherHasNoDownstreamRefunds(
            voucherType: 'payment',
            voucherId: current.id,
          );
          requestedSupplierId = supplierId?.trim().isNotEmpty == true
              ? supplierId!.trim()
              : current.supplierId;
          requestedSupplierName = supplierName ?? current.supplierName;
          requestedAmount = amount ?? current.amount;
          requestedCurrency = _currency(currency ?? current.currency);
          requestedPaymentMethod = paymentMethod?.trim().isNotEmpty == true
              ? paymentMethod!.trim()
              : current.paymentMethod;
          requestedCashLocationId = cashLocationId ?? current.cashLocationId;
          requestedCashDrawerSessionId =
              cashDrawerSessionId ?? current.cashDrawerSessionId;
          requestedAllocations = allocations ??
              <PaymentAllocationDraft>[
                for (final item in current.allocations)
                  PaymentAllocationDraft(
                    referenceId: item.referenceId,
                    referenceNumber: item.referenceNumber,
                    amount: item.amount,
                    referenceAmount: item.referenceAmount,
                    referenceCurrency: item.referenceCurrency,
                    exchangeRate: item.exchangeRate,
                  ),
              ];
          requestedNotes = notes ?? current.notes;
          requestedDate = (date ?? current.date).toUtc();
          _validateCommon(
            partyId: requestedSupplierId,
            amount: requestedAmount,
            paymentMethod: requestedPaymentMethod,
            cashLocationId: requestedCashLocationId,
            cashDrawerSessionId: requestedCashDrawerSessionId,
          );
          final allocated = requestedAllocations.fold<double>(
            0,
            (sum, item) => sum + item.amount,
          );
          if (allocated - requestedAmount > PaymentVoucherService._epsilon) {
            throw StateError('Allocated amount cannot exceed payment amount.');
          }
        },
        reverseOperationalEffects: (current) async {
          if (_isCash(current.paymentMethod)) {
            await _reverseActiveVoucherCashMovementsInTransaction(
              voucherType: 'payment',
              voucherId: current.id,
              reason: editReason,
              createdBy: editedBy,
              createdByUserId: editedByUserId,
              deviceId: deviceId,
            );
          }
          await _reverseActiveAllocationsForEdit(
            voucherType: 'payment',
            voucherId: current.id,
            reason: editReason,
            createdBy: editedBy,
            createdByUserId: editedByUserId,
            deviceId: deviceId,
          );
        },
        reverseAccountingEffects: (current) async {
          await AccountingService.reverseEntryForReference(
            referenceType: 'payment_voucher',
            referenceId: current.id,
            reason: editReason,
            createdBy: editedBy,
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
          await _reverseCompatibilityAccountMovements(
            voucherType: 'payment',
            voucherId: current.id,
            reason: editReason,
            deviceId: deviceId,
            occurredAt: DateTime.now().toUtc(),
          );
        },
        applyChanges: (current) async {
          final allocated = requestedAllocations.fold<double>(
            0,
            (sum, item) => sum + item.amount,
          );
          final nextVersion = current.version + 1;
          final now = DateTime.now().toUtc();
          final updatedRows = await _db.customUpdate(
            '''
            UPDATE payment_vouchers
            SET supplier_id = ?, supplier_name = ?, voucher_date = ?, amount = ?,
                unallocated_amount = ?, currency = ?, payment_method = ?,
                cash_location_id = ?, cash_drawer_session_id = ?, notes = ?,
                updated_at = ?, sync_status = 'pending', version = version + 1,
                last_modified_by_device_id = ?
            WHERE id = ? AND deleted_at = '' AND status = 'posted' AND version = ?
            ''',
            variables: <Variable<Object>>[
              Variable<String>(requestedSupplierId),
              Variable<String>(requestedSupplierName.trim()),
              Variable<String>(requestedDate.toIso8601String()),
              Variable<double>(_money(requestedAmount)),
              Variable<double>(_money(requestedAmount - allocated)),
              Variable<String>(requestedCurrency),
              Variable<String>(requestedPaymentMethod),
              Variable<String>(requestedCashLocationId.trim()),
              Variable<String>(requestedCashDrawerSessionId.trim()),
              Variable<String>(requestedNotes.trim()),
              Variable<String>(now.toIso8601String()),
              Variable<String>(deviceId.trim()),
              Variable<String>(current.id),
              Variable<int>(expectedVersion),
            ],
          );
          if (updatedRows != 1) {
            throw StateError('Payment voucher changed before edit commit.');
          }
          final staged = await findPaymentById(current.id);
          if (staged == null || staged.version != nextVersion) {
            throw StateError('Payment voucher edit version was not persisted.');
          }
          return staged;
        },
        rebuildOperationalEffects: (updated) async {
          prepared = await _prepareAllocations(
            voucherType: 'payment',
            voucherId: updated.id,
            expectedReferenceType: 'purchase',
            partyId: requestedSupplierId,
            voucherAmount: requestedAmount,
            voucherCurrency: requestedCurrency,
            drafts: requestedAllocations,
            deviceId: deviceId,
          );
          await _insertAllocations(prepared);
          await _applyAllocationCaches(prepared, deviceId: deviceId);
          if (_isCash(requestedPaymentMethod) && requestedAmount > PaymentVoucherService._epsilon) {
            final technicalReferenceId =
                '${updated.id}:payment_edit:v${updated.version}';
            await _appendVoucherCashMovement(
              type: 'payment',
              direction: 'out',
              voucherId: updated.id,
              voucherNo: updated.voucherNo,
              amount: requestedAmount,
              currency: requestedCurrency,
              cashLocationId: requestedCashLocationId,
              sessionId: requestedCashDrawerSessionId,
              partyType: 'supplier',
              partyId: requestedSupplierId,
              partyName: requestedSupplierName,
              paymentMethod: requestedPaymentMethod,
              createdBy: editedBy,
              createdByUserId: editedByUserId,
              deviceId: deviceId,
              branchId: updated.branchId,
              storeId: updated.storeId,
              notes: requestedNotes,
              occurredAt: requestedDate,
              technicalReferenceId: technicalReferenceId,
            );
            await _moveCashLocation(
              requestedCashLocationId,
              -requestedAmount,
              DateTime.now().toUtc(),
            );
          }
          final fresh = await findPaymentById(updated.id);
          if (fresh == null) {
            throw StateError('Edited payment could not be reloaded.');
          }
          return fresh;
        },
        buildPostedSnapshot: (updated) async => updated,
        repostAccounting: (updated) async {
          await _postPaymentAccounting(
            updated,
            accountingReferenceId:
                '${updated.id}:payment_edit:v${updated.version}',
          );
        },
        rebuildDerivedState: (updated) async {
          await _insertCompatibilityAccountMovement(
            voucherType: 'payment',
            voucherId: updated.id,
            voucherNo: updated.voucherNo,
            partyId: updated.supplierId,
            partyName: updated.supplierName,
            amount: _money(updated.amount + updated.discount),
            currency: updated.currency,
            paymentMethod: updated.paymentMethod,
            allocations: prepared,
            notes: updated.notes,
            deviceId: deviceId,
            branchId: updated.branchId,
            storeId: updated.storeId,
            occurredAt: updated.date,
            movementVersionSuffix: 'edit-v${updated.version}',
          );
        },
        verifyIntegrity: (updated) => _verifyVoucherEditIntegrity(
          voucherType: 'payment',
          voucherId: updated.id,
          expectedVersion: updated.version,
          expectedAmount: updated.amount,
          expectedUnallocated: updated.unallocatedAmount,
          paymentMethod: updated.paymentMethod,
        ),
      );
      return pipeline.execute();
    });
    AccountingService.notifyCommittedMutation();
    return result;
  }

  Future<void> _assertVoucherHasNoDownstreamRefunds({
    required String voucherType,
    required String voucherId,
  }) async {
    final refund = await _db.customSelect(
      '''
      SELECT id
      FROM cash_refund_allocations
      WHERE voucher_type = ? AND voucher_id = ? AND deleted_at = ''
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(voucherType),
        Variable<String>(voucherId),
      ],
    ).getSingleOrNull();
    if (refund != null) {
      throw StateError(
        'Voucher cannot be edited after a downstream refund. Reverse the refund first.',
      );
    }
    final allocationReversal = await _db.customSelect(
      '''
      SELECT id
      FROM payment_allocations
      WHERE voucher_type = ? AND voucher_id = ? AND deleted_at = ''
        AND allocation_kind = 'reversal'
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(voucherType),
        Variable<String>(voucherId),
      ],
    ).getSingleOrNull();
    if (allocationReversal != null) {
      throw StateError(
        'Voucher allocations have downstream reversals and cannot be edited safely.',
      );
    }
  }

  Future<void> _ensureVoucherCashHistoryAvailable({
    required String voucherType,
    required String voucherId,
  }) async {
    if (await _hasActiveVoucherCashMovement(voucherType, voucherId)) return;
    await backfillLegacyCashLedger();
    if (!await _hasActiveVoucherCashMovement(voucherType, voucherId)) {
      throw StateError(
        'Cash voucher cannot be edited because its active Cash Ledger movement is missing.',
      );
    }
  }

  Future<bool> _hasActiveVoucherCashMovement(
    String voucherType,
    String voucherId,
  ) async {
    final referenceType =
        voucherType == 'receipt' ? 'receipt_voucher' : 'payment_voucher';
    final editPrefix = '$voucherId:${voucherType}_edit:';
    final row = await _db.customSelect(
      '''
      SELECT tx.id
      FROM cash_ledger_transactions tx
      WHERE tx.reference_type = ?
        AND (tx.reference_id = ? OR instr(tx.reference_id, ?) = 1)
        AND tx.reversal_of_id = '' AND tx.deleted_at = ''
        AND NOT EXISTS (
          SELECT 1 FROM cash_ledger_transactions rev
          WHERE rev.reversal_of_id = tx.id AND rev.deleted_at = ''
        )
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(referenceType),
        Variable<String>(voucherId),
        Variable<String>(editPrefix),
      ],
    ).getSingleOrNull();
    return row != null;
  }

  Future<void> _reverseActiveVoucherCashMovementsInTransaction({
    required String voucherType,
    required String voucherId,
    required String reason,
    required String createdBy,
    required String createdByUserId,
    required String deviceId,
  }) async {
    final referenceType =
        voucherType == 'receipt' ? 'receipt_voucher' : 'payment_voucher';
    final editPrefix = '$voucherId:${voucherType}_edit:';
    final rows = await _db.customSelect(
      '''
      SELECT tx.id
      FROM cash_ledger_transactions tx
      WHERE tx.reference_type = ?
        AND (tx.reference_id = ? OR instr(tx.reference_id, ?) = 1)
        AND tx.reversal_of_id = '' AND tx.deleted_at = ''
        AND NOT EXISTS (
          SELECT 1 FROM cash_ledger_transactions rev
          WHERE rev.reversal_of_id = tx.id AND rev.deleted_at = ''
        )
      ORDER BY tx.occurred_at DESC, tx.created_at DESC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(referenceType),
        Variable<String>(voucherId),
        Variable<String>(editPrefix),
      ],
    ).get();
    if (rows.isEmpty) {
      throw StateError('Active Cash Ledger movement for voucher is missing.');
    }
    for (final row in rows) {
      final transactionId = row.data['id']?.toString() ?? '';
      final original = await _cashLedger.findById(transactionId);
      if (original == null) {
        throw StateError('Voucher Cash Ledger movement disappeared.');
      }
      await _cashLedger.reverseTransactionInExistingTransaction(
        original,
        reason: reason,
        createdBy: createdBy,
        createdByUserId: createdByUserId,
        deviceId: deviceId,
        occurredAt: DateTime.now().toUtc(),
      );
    }
  }

  Future<void> _reverseActiveAllocationsForEdit({
    required String voucherType,
    required String voucherId,
    required String reason,
    required String createdBy,
    required String createdByUserId,
    required String deviceId,
  }) async {
    final active = await _db.customSelect(
      '''
      SELECT DISTINCT reference_type, reference_id
      FROM payment_allocations
      WHERE voucher_type = ? AND voucher_id = ?
        AND deleted_at = '' AND status = 'active'
      ''',
      variables: <Variable<Object>>[
        Variable<String>(voucherType),
        Variable<String>(voucherId),
      ],
    ).get();
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      '''
      UPDATE payment_allocations
      SET status = 'reversed', reversed_at = ?, reversal_reason = ?,
          reversed_by = ?, reversed_by_user_id = ?, updated_at = ?,
          sync_status = 'pending', version = version + 1,
          last_modified_by_device_id = ?
      WHERE voucher_type = ? AND voucher_id = ?
        AND deleted_at = '' AND status = 'active'
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(reason),
        Variable<String>(createdBy.trim()),
        Variable<String>(createdByUserId.trim()),
        Variable<String>(now),
        Variable<String>(deviceId.trim()),
        Variable<String>(voucherType),
        Variable<String>(voucherId),
      ],
    );
    for (final row in active) {
      final referenceType = row.data['reference_type']?.toString() ?? '';
      final referenceId = row.data['reference_id']?.toString() ?? '';
      if (referenceType.isEmpty || referenceId.isEmpty) continue;
      await _rebuildAllocationCache(
        referenceType: referenceType,
        referenceId: referenceId,
        deviceId: deviceId,
      );
    }
  }

  Future<void> _verifyVoucherEditIntegrity({
    required String voucherType,
    required String voucherId,
    required int expectedVersion,
    required double expectedAmount,
    required double expectedUnallocated,
    required String paymentMethod,
  }) async {
    final table =
        voucherType == 'receipt' ? 'receipt_vouchers' : 'payment_vouchers';
    final referenceType =
        voucherType == 'receipt' ? 'receipt_voucher' : 'payment_voucher';
    final technicalReferenceId =
        '$voucherId:${voucherType}_edit:v$expectedVersion';
    final voucher = await _db.customSelect(
      "SELECT version, amount, unallocated_amount, status FROM $table WHERE id = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(voucherId)],
    ).getSingleOrNull();
    if (voucher == null ||
        (voucher.data['version'] as num?)?.toInt() != expectedVersion ||
        voucher.data['status']?.toString() != 'posted' ||
        (_number(voucher.data['amount']) - expectedAmount).abs() > PaymentVoucherService._epsilon ||
        (_number(voucher.data['unallocated_amount']) - expectedUnallocated)
                .abs() >
            PaymentVoucherService._epsilon) {
      throw StateError('Voucher edit integrity verification failed.');
    }
    final allocationTotals = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS allocated
      FROM payment_allocations
      WHERE voucher_type = ? AND voucher_id = ?
        AND deleted_at = '' AND status = 'active'
        AND allocation_kind = 'allocation'
      ''',
      variables: <Variable<Object>>[
        Variable<String>(voucherType),
        Variable<String>(voucherId),
      ],
    ).getSingle();
    final allocated = _number(allocationTotals.data['allocated']);
    if ((expectedAmount - allocated - expectedUnallocated).abs() > 0.00001) {
      throw StateError(
          'Voucher allocation totals do not reconcile after edit.');
    }
    final journal = await _db.customSelect(
      '''
      SELECT id FROM journal_entries
      WHERE reference_type = ? AND reference_id = ?
        AND deleted_at = '' AND status = 'posted'
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(referenceType),
        Variable<String>(technicalReferenceId),
      ],
    ).getSingleOrNull();
    if (journal == null) {
      throw StateError('Voucher edit accounting journal is missing.');
    }
    if (_isCash(paymentMethod)) {
      final cash = await _db.customSelect(
        '''
        SELECT tx.id FROM cash_ledger_transactions tx
        WHERE tx.reference_type = ? AND tx.reference_id = ?
          AND tx.reversal_of_id = '' AND tx.deleted_at = ''
          AND NOT EXISTS (
            SELECT 1 FROM cash_ledger_transactions rev
            WHERE rev.reversal_of_id = tx.id AND rev.deleted_at = ''
          )
        LIMIT 1
        ''',
        variables: <Variable<Object>>[
          Variable<String>(referenceType),
          Variable<String>(technicalReferenceId),
        ],
      ).getSingleOrNull();
      if (cash == null) {
        throw StateError('Voucher edit Cash Ledger movement is missing.');
      }
    }
  }

  Future<void> _postReceiptAccounting(ReceiptVoucher voucher,
      {String accountingReferenceId = ''}) async {
    await AccountingService.postVoucherPayment(
      database: _db,
      voucherType: 'receipt',
      voucherId: voucher.id,
      voucherNo: voucher.voucherNo,
      date: voucher.date,
      amount: voucher.amount,
      discount: voucher.discount,
      paymentMethod: voucher.paymentMethod,
      partyId: voucher.customerId,
      partyName: voucher.customerName,
      cashLocationId: voucher.cashLocationId,
      createdBy: voucher.createdByUserId.isNotEmpty
          ? voucher.createdByUserId
          : (voucher.createdBy.isNotEmpty
              ? voucher.createdBy
              : voucher.deviceId),
      storeId: voucher.storeId,
      branchId: voucher.branchId,
      accountingReferenceId: accountingReferenceId,
      withinExistingTransaction: true,
    );
  }

  Future<void> _postPaymentAccounting(PaymentVoucher voucher,
      {String accountingReferenceId = ''}) async {
    await AccountingService.postVoucherPayment(
      database: _db,
      voucherType: 'payment',
      voucherId: voucher.id,
      voucherNo: voucher.voucherNo,
      date: voucher.date,
      amount: voucher.amount,
      discount: voucher.discount,
      paymentMethod: voucher.paymentMethod,
      partyId: voucher.supplierId,
      partyName: voucher.supplierName,
      cashLocationId: voucher.cashLocationId,
      createdBy: voucher.createdByUserId.isNotEmpty
          ? voucher.createdByUserId
          : (voucher.createdBy.isNotEmpty
              ? voucher.createdBy
              : voucher.deviceId),
      storeId: voucher.storeId,
      branchId: voucher.branchId,
      accountingReferenceId: accountingReferenceId,
      withinExistingTransaction: true,
    );
  }

  Future<double> refundableCashForSale(String saleId,
      {double? maxRefundAmount}) async {
    final totalRow = await _db.customSelect(
      '''
       SELECT COALESCE(SUM(pa.reference_amount), 0) AS total
      FROM payment_allocations pa
      INNER JOIN receipt_vouchers rv ON rv.id = pa.voucher_id
      WHERE pa.voucher_type = 'receipt'
        AND pa.reference_type = 'sale'
        AND pa.reference_id = ?
        AND pa.deleted_at = ''
         AND pa.status = 'active'
         AND pa.allocation_kind = 'allocation'
        AND rv.deleted_at = ''
        AND rv.status = 'posted'
        AND LOWER(rv.payment_method) = 'cash'
      ''',
      variables: <Variable<Object>>[Variable<String>(saleId.trim())],
    ).getSingle();
    final refundedRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM cash_ledger_transactions refund_tx
      WHERE refund_tx.type = 'refund'
        AND refund_tx.direction = 'out'
        AND refund_tx.reference_type = 'sale_refund'
        AND refund_tx.reference_id LIKE ?
        AND refund_tx.deleted_at = ''
        AND NOT EXISTS (
          SELECT 1
          FROM cash_ledger_transactions reversal_tx
          WHERE reversal_tx.reversal_of_id = refund_tx.id
            AND reversal_tx.deleted_at = ''
        )
      ''',
      variables: <Variable<Object>>[Variable<String>('${saleId.trim()}:%')],
    ).getSingle();
    final refunded = _number(refundedRow.data['total']);
    final unallocated = await unallocatedCashForSale(saleId);
    final cashRemaining =
        _money(_number(totalRow.data['total']) + unallocated - refunded)
            .clamp(0, double.infinity)
            .toDouble();
    if (maxRefundAmount == null || !maxRefundAmount.isFinite) {
      return cashRemaining;
    }
    final entitlementRemaining =
        _money(maxRefundAmount - refunded).clamp(0, double.infinity).toDouble();
    return min(cashRemaining, entitlementRemaining);
  }

  Future<double> unallocatedCashForSale(String saleId) async {
    final row = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(rv.unallocated_amount), 0) AS total
      FROM receipt_vouchers rv
      INNER JOIN sales s ON s.customer_id = rv.customer_id
      WHERE s.id = ? AND rv.deleted_at = '' AND rv.status = 'posted'
        AND LOWER(rv.payment_method) = 'cash'
        AND rv.unallocated_amount > 0
        AND EXISTS (
          SELECT 1
          FROM payment_allocations pa
          WHERE pa.voucher_type = 'receipt'
            AND pa.voucher_id = rv.id
            AND pa.reference_type = 'sale'
            AND pa.reference_id = s.id
            AND pa.allocation_kind = 'allocation'
            AND pa.status = 'active'
            AND pa.deleted_at = ''
        )
      ''',
      variables: <Variable<Object>>[Variable<String>(saleId.trim())],
    ).getSingle();
    return _money(_number(row.data['total']));
  }
}
