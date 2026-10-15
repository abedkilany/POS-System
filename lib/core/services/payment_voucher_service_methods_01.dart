part of 'payment_voucher_service.dart';

extension PaymentVoucherServiceSplitPart1 on PaymentVoucherService {

  String _newId(String prefix) {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return '${prefix}_${micros}_${PaymentVoucherService._random.nextInt(1 << 32).toRadixString(16)}';
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
    double discount = 0,
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
    if (!discount.isFinite || discount < 0) {
      throw ArgumentError('Discount must be zero or greater.');
    }
    _validateCommon(
      partyId: customerId,
      amount: amount,
      allowZeroAmount: discount > PaymentVoucherService._epsilon,
      paymentMethod: paymentMethod,
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
    );
    final cleanDiscount = _money(discount);
    final when = (date ?? DateTime.now()).toUtc();
    final cleanId = id.trim().isEmpty ? _newId('receipt') : id.trim();
    final cleanCurrency = _currency(currency);
    final cleanPaymentMethod =
        paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();

    final result = await _db.transaction(() async {
      final existing = await _findReceiptByIdentity(cleanId, idempotencyKey);
      if (existing != null) {
        if (existing.status == 'posted') {
          await _postReceiptAccounting(existing);
        }
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
      final allocated =
          prepared.fold<double>(0, (sum, item) => sum + item.amount);
      final unallocated = _money(amount - allocated);

      final now = DateTime.now().toUtc();
      final voucher = ReceiptVoucher(
        id: cleanId,
        voucherNo: voucherNo.trim().isEmpty
            ? _newVoucherNo('RC', when)
            : voucherNo.trim(),
        customerId: customerId.trim(),
        customerName: customerName.trim(),
        date: when,
        amount: _money(amount),
        discount: cleanDiscount,
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
      if (_isCash(cleanPaymentMethod) && amount > PaymentVoucherService._epsilon) {
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
      await _insertCompatibilityAccountMovement(
        voucherType: 'receipt',
        voucherId: voucher.id,
        voucherNo: voucher.voucherNo,
        partyId: voucher.customerId,
        partyName: voucher.customerName,
        amount: _money(voucher.amount + voucher.discount),
        currency: voucher.currency,
        paymentMethod: voucher.paymentMethod,
        allocations: prepared,
        notes: voucher.notes,
        deviceId: voucher.deviceId,
        branchId: voucher.branchId,
        storeId: voucher.storeId,
        occurredAt: voucher.date,
      );
      return voucher;
    });
    AccountingService.notifyCommittedMutation();
    return result;
  }

  Future<PaymentVoucher> createPayment({
    String id = '',
    String voucherNo = '',
    required String supplierId,
    required String supplierName,
    required double amount,
    double discount = 0,
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
    if (!discount.isFinite || discount < 0) {
      throw ArgumentError('Discount must be zero or greater.');
    }
    _validateCommon(
      partyId: supplierId,
      amount: amount,
      allowZeroAmount: discount > PaymentVoucherService._epsilon,
      paymentMethod: paymentMethod,
      cashLocationId: cashLocationId,
      cashDrawerSessionId: cashDrawerSessionId,
    );
    final cleanDiscount = _money(discount);
    final when = (date ?? DateTime.now()).toUtc();
    final cleanId = id.trim().isEmpty ? _newId('payment') : id.trim();
    final cleanCurrency = _currency(currency);
    final cleanPaymentMethod =
        paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();

    final result = await _db.transaction(() async {
      final existing = await _findPaymentByIdentity(cleanId, idempotencyKey);
      if (existing != null) {
        if (existing.status == 'posted') {
          await _postPaymentAccounting(existing);
        }
        return existing;
      }

      if (_isCash(cleanPaymentMethod) && amount > PaymentVoucherService._epsilon) {
        await AccountingService.ensureCashOutflowAllowed(
          cashLocationId: cashLocationId,
          amount: amount,
          database: _db,
        );
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
      final allocated =
          prepared.fold<double>(0, (sum, item) => sum + item.amount);
      final unallocated = _money(amount - allocated);

      final now = DateTime.now().toUtc();
      final voucher = PaymentVoucher(
        id: cleanId,
        voucherNo: voucherNo.trim().isEmpty
            ? _newVoucherNo('PV', when)
            : voucherNo.trim(),
        supplierId: supplierId.trim(),
        supplierName: supplierName.trim(),
        date: when,
        amount: _money(amount),
        discount: cleanDiscount,
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
      if (_isCash(cleanPaymentMethod) && voucher.amount > PaymentVoucherService._epsilon) {
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
      await _insertCompatibilityAccountMovement(
        voucherType: 'payment',
        voucherId: voucher.id,
        voucherNo: voucher.voucherNo,
        partyId: voucher.supplierId,
        partyName: voucher.supplierName,
        amount: _money(voucher.amount + voucher.discount),
        currency: voucher.currency,
        paymentMethod: voucher.paymentMethod,
        allocations: prepared,
        notes: voucher.notes,
        deviceId: voucher.deviceId,
        branchId: voucher.branchId,
        storeId: voucher.storeId,
        occurredAt: voucher.date,
      );
      return voucher;
    });
    AccountingService.notifyCommittedMutation();
    return result;
  }

  /// Safely edits a posted customer receipt using the shared posted-document
  /// edit contract. Historical allocations, journal rows, Cash Ledger rows and
  /// compatibility account movements are preserved and reversed; the new
  /// version is then rebuilt from authoritative data in the same transaction.
  Future<ReceiptVoucher> editReceipt({
    required String voucherId,
    required int expectedVersion,
    String? customerId,
    String? customerName,
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
    final preflight = await findReceiptById(id);
    if (preflight == null) throw StateError('Receipt voucher does not exist.');
    if (_isCash(preflight.paymentMethod)) {
      await _ensureVoucherCashHistoryAvailable(
        voucherType: 'receipt',
        voucherId: id,
      );
    }

    late List<PaymentAllocationDraft> requestedAllocations;
    late String requestedCustomerId;
    late String requestedCustomerName;
    late double requestedAmount;
    late String requestedCurrency;
    late String requestedPaymentMethod;
    late String requestedCashLocationId;
    late String requestedCashDrawerSessionId;
    late String requestedNotes;
    late DateTime requestedDate;
    var prepared = <PaymentAllocation>[];
    final editReason = 'Receipt edited from version $expectedVersion';

    final result = await _db.transaction(() async {
      final pipeline = PostedDocumentEditPipeline<ReceiptVoucher>(
        loadAuthoritative: () async {
          final current = await findReceiptById(id);
          if (current == null) throw StateError('Receipt voucher disappeared.');
          return current;
        },
        validatePermission: (current) async {
          if (current.status != 'posted' || current.isDeleted) {
            throw StateError(
                'Only active posted receipt vouchers can be edited.');
          }
        },
        validateVersion: (current) async {
          if (current.version != expectedVersion) {
            throw StateError(
              'Receipt voucher changed by another user. Reload before editing.',
            );
          }
        },
        validateDependencies: (current) async {
          await _assertVoucherHasNoDownstreamRefunds(
            voucherType: 'receipt',
            voucherId: current.id,
          );
          requestedCustomerId = customerId?.trim().isNotEmpty == true
              ? customerId!.trim()
              : current.customerId;
          requestedCustomerName = customerName ?? current.customerName;
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
            partyId: requestedCustomerId,
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
            throw StateError('Allocated amount cannot exceed receipt amount.');
          }
        },
        reverseOperationalEffects: (current) async {
          if (_isCash(current.paymentMethod)) {
            await _reverseActiveVoucherCashMovementsInTransaction(
              voucherType: 'receipt',
              voucherId: current.id,
              reason: editReason,
              createdBy: editedBy,
              createdByUserId: editedByUserId,
              deviceId: deviceId,
            );
          }
          await _reverseActiveAllocationsForEdit(
            voucherType: 'receipt',
            voucherId: current.id,
            reason: editReason,
            createdBy: editedBy,
            createdByUserId: editedByUserId,
            deviceId: deviceId,
          );
        },
        reverseAccountingEffects: (current) async {
          await AccountingService.reverseEntryForReference(
            referenceType: 'receipt_voucher',
            referenceId: current.id,
            reason: editReason,
            createdBy: editedBy,
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
          await _reverseCompatibilityAccountMovements(
            voucherType: 'receipt',
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
            UPDATE receipt_vouchers
            SET customer_id = ?, customer_name = ?, voucher_date = ?, amount = ?,
                unallocated_amount = ?, currency = ?, payment_method = ?,
                cash_location_id = ?, cash_drawer_session_id = ?, notes = ?,
                updated_at = ?, sync_status = 'pending', version = version + 1,
                last_modified_by_device_id = ?
            WHERE id = ? AND deleted_at = '' AND status = 'posted' AND version = ?
            ''',
            variables: <Variable<Object>>[
              Variable<String>(requestedCustomerId),
              Variable<String>(requestedCustomerName.trim()),
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
            throw StateError('Receipt voucher changed before edit commit.');
          }
          final staged = await findReceiptById(current.id);
          if (staged == null || staged.version != nextVersion) {
            throw StateError('Receipt voucher edit version was not persisted.');
          }
          return staged;
        },
        rebuildOperationalEffects: (updated) async {
          prepared = await _prepareAllocations(
            voucherType: 'receipt',
            voucherId: updated.id,
            expectedReferenceType: 'sale',
            partyId: requestedCustomerId,
            voucherAmount: requestedAmount,
            voucherCurrency: requestedCurrency,
            drafts: requestedAllocations,
            deviceId: deviceId,
          );
          await _insertAllocations(prepared);
          await _applyAllocationCaches(prepared, deviceId: deviceId);
          if (_isCash(requestedPaymentMethod) && requestedAmount > PaymentVoucherService._epsilon) {
            final technicalReferenceId =
                '${updated.id}:receipt_edit:v${updated.version}';
            await _appendVoucherCashMovement(
              type: 'receipt',
              direction: 'in',
              voucherId: updated.id,
              voucherNo: updated.voucherNo,
              amount: requestedAmount,
              currency: requestedCurrency,
              cashLocationId: requestedCashLocationId,
              sessionId: requestedCashDrawerSessionId,
              partyType: 'customer',
              partyId: requestedCustomerId,
              partyName: requestedCustomerName,
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
              requestedAmount,
              DateTime.now().toUtc(),
            );
          }
          final fresh = await findReceiptById(updated.id);
          if (fresh == null) {
            throw StateError('Edited receipt could not be reloaded.');
          }
          return fresh;
        },
        buildPostedSnapshot: (updated) async {
          // Voucher rows are themselves immutable-version authoritative event
          // records; allocation/journal/cash history remains append-only.
          return updated;
        },
        repostAccounting: (updated) async {
          await _postReceiptAccounting(
            updated,
            accountingReferenceId:
                '${updated.id}:receipt_edit:v${updated.version}',
          );
        },
        rebuildDerivedState: (updated) async {
          await _insertCompatibilityAccountMovement(
            voucherType: 'receipt',
            voucherId: updated.id,
            voucherNo: updated.voucherNo,
            partyId: updated.customerId,
            partyName: updated.customerName,
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
          voucherType: 'receipt',
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
}
