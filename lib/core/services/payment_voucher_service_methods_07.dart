part of 'payment_voucher_service.dart';

extension PaymentVoucherServiceSplitPart7 on PaymentVoucherService {

  Future<void> _allocateRefundCoverage({
    required String refundId,
    required String voucherType,
    required String referenceType,
    required String referenceId,
    required double amount,
    required String deviceId,
  }) async {
    var remaining = _money(amount);
    if (remaining <= PaymentVoucherService._epsilon) return;
    final voucherTable =
        voucherType == 'receipt' ? 'receipt_vouchers' : 'payment_vouchers';
    // Purchase refunds unwind the newest supplier payment first. Keep the
    // existing receipt ordering unchanged to avoid altering sale-refund policy.
    final refundOrder = voucherType == 'payment' ? 'DESC' : 'ASC';
    final vouchers = await _db.customSelect(
      '''
      SELECT v.id, v.unallocated_amount
      FROM $voucherTable v
      WHERE v.status = 'posted' AND v.deleted_at = ''
        AND LOWER(v.payment_method) = 'cash'
        AND EXISTS (
          SELECT 1 FROM payment_allocations pa
          WHERE pa.voucher_type = ? AND pa.voucher_id = v.id
            AND pa.reference_type = ? AND pa.reference_id = ?
            AND pa.status = 'active' AND pa.deleted_at = ''
            AND pa.allocation_kind = 'allocation'
        )
      ORDER BY v.voucher_date $refundOrder, v.created_at $refundOrder, v.id $refundOrder
      ''',
      variables: <Variable<Object>>[
        Variable<String>(voucherType),
        Variable<String>(referenceType),
        Variable<String>(referenceId),
      ],
    ).get();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final voucher in vouchers) {
      if (remaining <= PaymentVoucherService._epsilon) break;
      final voucherId = voucher.data['id']?.toString() ?? '';
      var unallocated = _number(voucher.data['unallocated_amount']);
      final fromUnallocated = min(remaining, unallocated);
      if (fromUnallocated > PaymentVoucherService._epsilon) {
        unallocated = _money(unallocated - fromUnallocated);
        await _db.customUpdate(
          'UPDATE $voucherTable SET unallocated_amount = ?, updated_at = ?, sync_status = \'pending\', version = version + 1, last_modified_by_device_id = ? WHERE id = ? AND deleted_at = \'\'',
          variables: <Variable<Object>>[
            Variable<double>(unallocated),
            Variable<String>(now),
            Variable<String>(deviceId.trim()),
            Variable<String>(voucherId),
          ],
        );
        await _insertRefundCoverage(
          refundId: refundId,
          voucherType: voucherType,
          voucherId: voucherId,
          allocationKind: 'unallocated',
          amount: fromUnallocated,
          referenceType: referenceType,
          referenceId: referenceId,
          deviceId: deviceId,
        );
        remaining = _money(remaining - fromUnallocated);
      }
      if (remaining <= PaymentVoucherService._epsilon) break;

      final allocations = await _db.customSelect(
        '''
        SELECT pa.*,
               pa.reference_amount - COALESCE((
                 SELECT SUM(r.reference_amount)
                 FROM payment_allocations r
                 WHERE r.allocation_kind = 'reversal'
                   AND r.reversal_of_id = pa.id
                   AND r.status = 'active' AND r.deleted_at = ''
               ), 0) AS net_reference_amount
        FROM payment_allocations pa
        WHERE pa.voucher_type = ? AND pa.voucher_id = ?
          AND pa.reference_type = ? AND pa.reference_id = ?
          AND pa.allocation_kind = 'allocation'
          AND pa.status = 'active' AND pa.deleted_at = ''
        ORDER BY pa.created_at $refundOrder, pa.id $refundOrder
        ''',
        variables: <Variable<Object>>[
          Variable<String>(voucherType),
          Variable<String>(voucherId),
          Variable<String>(referenceType),
          Variable<String>(referenceId),
        ],
      ).get();
      for (final original in allocations) {
        if (remaining <= PaymentVoucherService._epsilon) break;
        final available = _number(original.data['net_reference_amount']);
        final reversalAmount = min(remaining, available);
        if (reversalAmount <= PaymentVoucherService._epsilon) continue;
        final originalId = original.data['id']?.toString() ?? '';
        if (originalId.isEmpty) continue;
        final existingReversal = await _db.customSelect(
          '''
          SELECT id
          FROM payment_allocations
          WHERE voucher_type = ? AND voucher_id = ?
            AND reference_type = ? AND reference_id = ?
            AND allocation_kind = 'reversal' AND reversal_of_id = ?
            AND status = 'active' AND deleted_at = ''
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable<String>(voucherType),
            Variable<String>(voucherId),
            Variable<String>(referenceType),
            Variable<String>(referenceId),
            Variable<String>(originalId),
          ],
        ).getSingleOrNull();

        // The unique index permits one reversal row per original allocation.
        // Refunds can consume the same original allocation more than once over
        // time, so grow the existing reversal instead of inserting a duplicate.
        late final String reversalId;
        if (existingReversal != null) {
          reversalId = existingReversal.data['id']?.toString() ?? '';
          if (reversalId.isEmpty) {
            throw StateError('Existing allocation reversal is invalid.');
          }
          await _db.customUpdate(
            '''
            UPDATE payment_allocations
            SET amount = amount + ?, reference_amount = reference_amount + ?,
                updated_at = ?, sync_status = 'pending', version = version + 1,
                last_modified_by_device_id = ?
            WHERE id = ? AND status = 'active' AND deleted_at = ''
            ''',
            variables: <Variable<Object>>[
              Variable<double>(reversalAmount),
              Variable<double>(reversalAmount),
              Variable<String>(now),
              Variable<String>(deviceId.trim()),
              Variable<String>(reversalId),
            ],
          );
        } else {
          reversalId = _newId('alloc-reversal');
          await _db.customInsert(
            '''
            INSERT INTO payment_allocations
              (id, voucher_type, voucher_id, reference_type, reference_id,
               reference_number, amount, reference_amount, currency,
               reference_currency, exchange_rate, allocation_kind, reversal_of_id,
               created_at, updated_at, deleted_at, sync_status, version,
               last_modified_by_device_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'reversal', ?, ?, ?, '',
                    'pending', 1, ?)
            ''',
            variables: <Variable<Object>>[
              Variable<String>(reversalId),
              Variable<String>(voucherType),
              Variable<String>(voucherId),
              Variable<String>(referenceType),
              Variable<String>(referenceId),
              Variable<String>(
                  original.data['reference_number']?.toString() ?? ''),
              Variable<double>(reversalAmount),
              Variable<double>(reversalAmount),
              Variable<String>(original.data['currency']?.toString() ?? 'USD'),
              Variable<String>(
                  original.data['reference_currency']?.toString() ?? 'USD'),
              Variable<double>(_number(original.data['exchange_rate'])),
              Variable<String>(originalId),
              Variable<String>(now),
              Variable<String>(now),
              Variable<String>(deviceId.trim()),
            ],
          );
        }
        await _insertRefundCoverage(
          refundId: refundId,
          voucherType: voucherType,
          voucherId: voucherId,
          allocationKind: 'allocated',
          allocationId: reversalId,
          amount: reversalAmount,
          referenceType: referenceType,
          referenceId: referenceId,
          deviceId: deviceId,
        );
        remaining = _money(remaining - reversalAmount);
      }
    }
    if (remaining > PaymentVoucherService._epsilon) {
      throw StateError(
          'Refund could not be matched to the original voucher balance.');
    }
  }

  Future<void> _insertRefundCoverage({
    required String refundId,
    required String voucherType,
    required String voucherId,
    required String allocationKind,
    String allocationId = '',
    required double amount,
    required String referenceType,
    required String referenceId,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customInsert(
      '''
      INSERT INTO cash_refund_allocations
        (id, refund_id, voucher_type, voucher_id, allocation_kind,
         allocation_id, reference_type, reference_id, amount, reference_amount,
         created_at, updated_at, deleted_at, sync_status, version,
         last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 'pending', 1, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(_newId('refund-coverage')),
        Variable<String>(refundId),
        Variable<String>(voucherType),
        Variable<String>(voucherId),
        Variable<String>(allocationKind),
        Variable<String>(allocationId),
        Variable<String>(referenceType),
        Variable<String>(referenceId),
        Variable<double>(amount),
        Variable<double>(amount),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(deviceId.trim()),
      ],
    );
  }

  /// Repairs legacy vouchers that allocated more than the target document.
  /// The excess becomes unallocated and is represented by an append-only
  /// allocation reversal.
  Future<void> normalizeOverAllocatedVouchers({String deviceId = ''}) async {
    await _db.transaction(() async {
      for (final spec in <(String, String)>[
        ('receipt', 'receipt_vouchers'),
        ('payment', 'payment_vouchers'),
      ]) {
        final voucherType = spec.$1;
        final table = spec.$2;
        final vouchers = await _db
            .customSelect(
              "SELECT id FROM $table WHERE status = 'posted' AND deleted_at = ''",
            )
            .get();
        for (final voucher in vouchers) {
          final voucherId = voucher.data['id']?.toString() ?? '';
          final groups = await _db.customSelect(
            '''
            SELECT reference_type, reference_id,
                   COALESCE(SUM(CASE WHEN allocation_kind = 'reversal'
                                     THEN -reference_amount
                                     ELSE reference_amount END), 0) AS net_amount
            FROM payment_allocations
            WHERE voucher_type = ? AND voucher_id = ?
              AND status = 'active' AND deleted_at = ''
            GROUP BY reference_type, reference_id
            ''',
            variables: <Variable<Object>>[
              Variable<String>(voucherType),
              Variable<String>(voucherId),
            ],
          ).get();
          for (final group in groups) {
            final referenceType =
                group.data['reference_type']?.toString() ?? '';
            final referenceId = group.data['reference_id']?.toString() ?? '';
            final target = referenceType == 'sale'
                ? await _saleTarget(referenceId)
                : await _purchaseTarget(referenceId, 'USD');
            if (target == null) continue;
            final excess = _money(
              _number(group.data['net_amount']) - target.total,
            );
            if (excess <= PaymentVoucherService._epsilon) {
              // paid_amount/payment_status are derived compatibility caches.
              // Rebuild even when allocations already match the invoice so
              // a cache left stale by an earlier refund self-heals.
              await _rebuildAllocationCache(
                referenceType: referenceType,
                referenceId: referenceId,
                deviceId: deviceId,
              );
              continue;
            }
            var remaining = excess;
            final originals = await _db.customSelect(
              '''
              SELECT * FROM payment_allocations
              WHERE voucher_type = ? AND voucher_id = ?
                AND reference_type = ? AND reference_id = ?
                AND allocation_kind = 'allocation'
                AND status = 'active' AND deleted_at = ''
              ORDER BY created_at DESC, id DESC
              ''',
              variables: <Variable<Object>>[
                Variable<String>(voucherType),
                Variable<String>(voucherId),
                Variable<String>(referenceType),
                Variable<String>(referenceId),
              ],
            ).get();
            for (final original in originals) {
              if (remaining <= PaymentVoucherService._epsilon) break;
              final alreadyReversed = _number((await _db.customSelect(
                '''
                SELECT COALESCE(SUM(reference_amount), 0) AS total
                FROM payment_allocations
                WHERE allocation_kind = 'reversal' AND reversal_of_id = ?
                  AND status = 'active' AND deleted_at = ''
                ''',
                variables: <Variable<Object>>[
                  Variable<String>(original.data['id']?.toString() ?? ''),
                ],
              ).getSingle())
                  .data['total']);
              final available =
                  _number(original.data['reference_amount']) - alreadyReversed;
              final reversalAmount = min(remaining, available);
              if (reversalAmount <= PaymentVoucherService._epsilon) continue;
              final now = DateTime.now().toUtc().toIso8601String();
              final originalId = original.data['id']?.toString() ?? '';
              final existingReversal = await _db.customSelect(
                '''
                SELECT id
                FROM payment_allocations
                WHERE allocation_kind = 'reversal' AND reversal_of_id = ?
                  AND status = 'active' AND deleted_at = ''
                LIMIT 1
                ''',
                variables: <Variable<Object>>[
                  Variable<String>(originalId),
                ],
              ).getSingleOrNull();

              // The unique index allows one cumulative reversal per original
              // allocation. If the invoice is reduced again, grow that row
              // instead of attempting a second insert for the same original.
              if (existingReversal != null) {
                await _db.customUpdate(
                  '''
                  UPDATE payment_allocations
                  SET amount = amount + ?, reference_amount = reference_amount + ?,
                      updated_at = ?, sync_status = 'pending', version = version + 1,
                      last_modified_by_device_id = ?
                  WHERE id = ? AND status = 'active' AND deleted_at = ''
                  ''',
                  variables: <Variable<Object>>[
                    Variable<double>(reversalAmount),
                    Variable<double>(reversalAmount),
                    Variable<String>(now),
                    Variable<String>(deviceId.trim()),
                    Variable<String>(
                        existingReversal.data['id']?.toString() ?? ''),
                  ],
                );
              } else {
                await _db.customInsert(
                  '''
                INSERT INTO payment_allocations
                  (id, voucher_type, voucher_id, reference_type, reference_id,
                   reference_number, amount, reference_amount, currency,
                   reference_currency, exchange_rate, allocation_kind,
                   reversal_of_id, created_at, updated_at, deleted_at,
                   sync_status, version, last_modified_by_device_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'reversal', ?, ?, ?,
                        '', 'pending', 1, ?)
                ''',
                  variables: <Variable<Object>>[
                    Variable<String>(_newId('alloc-reversal')),
                    Variable<String>(voucherType),
                    Variable<String>(voucherId),
                    Variable<String>(referenceType),
                    Variable<String>(referenceId),
                    Variable<String>(
                        original.data['reference_number']?.toString() ?? ''),
                    Variable<double>(reversalAmount),
                    Variable<double>(reversalAmount),
                    Variable<String>(
                        original.data['currency']?.toString() ?? 'USD'),
                    Variable<String>(
                        original.data['reference_currency']?.toString() ??
                            'USD'),
                    Variable<double>(_number(original.data['exchange_rate'])),
                    Variable<String>(originalId),
                    Variable<String>(now),
                    Variable<String>(now),
                    Variable<String>(deviceId.trim()),
                  ],
                );
              }
              remaining = _money(remaining - reversalAmount);
            }
            final priorRefundRow = await _db.customSelect(
              '''
              SELECT COALESCE(SUM(amount), 0) AS total
              FROM cash_ledger_transactions
              WHERE type = ? AND direction = ? AND reference_type = ?
                AND reference_id LIKE ? AND deleted_at = ''
                AND reversal_of_id = ''
              ''',
              variables: <Variable<Object>>[
                Variable<String>(
                    voucherType == 'receipt' ? 'refund' : 'supplier_refund'),
                Variable<String>(voucherType == 'receipt' ? 'out' : 'in'),
                Variable<String>(voucherType == 'receipt'
                    ? 'sale_refund'
                    : 'purchase_refund'),
                Variable<String>('$referenceId:%'),
              ],
            ).getSingle();
            final priorRefunded = _number(priorRefundRow.data['total']);
            final unallocatedToAdd =
                max(0.0, excess - priorRefunded).toDouble();
            if (unallocatedToAdd > PaymentVoucherService._epsilon) {
              final now = DateTime.now().toUtc().toIso8601String();
              await _db.customUpdate(
                'UPDATE $table SET unallocated_amount = unallocated_amount + ?, updated_at = ?, sync_status = \'pending\', version = version + 1, last_modified_by_device_id = ? WHERE id = ? AND deleted_at = \'\'',
                variables: <Variable<Object>>[
                  Variable<double>(unallocatedToAdd),
                  Variable<String>(now),
                  Variable<String>(deviceId.trim()),
                  Variable<String>(voucherId),
                ],
              );
            }
            await _rebuildAllocationCache(
              referenceType: referenceType,
              referenceId: referenceId,
              deviceId: deviceId,
            );
          }

          // Reconcile the voucher-level unallocated balance from the active
          // allocations. This is important for an interrupted or previously
          // retried normalization: the reversal may already exist while the
          // corresponding unallocated amount was never persisted. Deriving it
          // from the ledger makes the repair idempotent and prevents both
          // missing refunds and double credits.
          await _reconcileVoucherUnallocatedAmount(
            voucherType: voucherType,
            voucherId: voucherId,
            table: table,
            deviceId: deviceId,
          );
        }
      }
    });
  }

  Future<void> _reconcileVoucherUnallocatedAmount({
    required String voucherType,
    required String voucherId,
    required String table,
    required String deviceId,
  }) async {
    final voucher = await _db.customSelect(
      'SELECT amount FROM $table WHERE id = ? AND status = \'posted\' AND deleted_at = \'\' LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(voucherId)],
    ).getSingleOrNull();
    if (voucher == null) return;

    final allocated = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(CASE WHEN allocation_kind = 'reversal'
                               THEN -amount ELSE amount END), 0) AS total
      FROM payment_allocations
      WHERE voucher_type = ? AND voucher_id = ?
        AND status = 'active' AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[
        Variable<String>(voucherType),
        Variable<String>(voucherId),
      ],
    ).getSingle();
    final voucherAmount = _number(voucher.data['amount']);
    final allocatedAmount = _number(allocated.data['total']);
    final coverage = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM cash_refund_allocations
      WHERE voucher_type = ? AND voucher_id = ? AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[
        Variable<String>(voucherType),
        Variable<String>(voucherId),
      ],
    ).getSingle();
    final coveredByRefunds = _number(coverage.data['total']);
    final expectedUnallocated =
        _money(voucherAmount - allocatedAmount - coveredByRefunds)
            .clamp(0, double.infinity)
            .toDouble();
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      '''
      UPDATE $table
      SET unallocated_amount = ?, updated_at = ?, sync_status = 'pending',
          version = version + 1, last_modified_by_device_id = ?
      WHERE id = ? AND status = 'posted' AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[
        Variable<double>(expectedUnallocated),
        Variable<String>(now),
        Variable<String>(deviceId.trim()),
        Variable<String>(voucherId),
      ],
    );
  }

  Future<void> _applyAllocationCaches(List<PaymentAllocation> items,
      {required String deviceId}) async {
    final grouped = <String, double>{};
    final types = <String, String>{};
    for (final item in items) {
      grouped[item.referenceId] =
          (grouped[item.referenceId] ?? 0) + item.effectiveReferenceAmount;
      types[item.referenceId] = item.referenceType;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    for (final entry in grouped.entries) {
      if (types[entry.key] == 'sale') {
        final target = await _saleTarget(entry.key);
        if (target == null) {
          throw StateError('Sale ${entry.key} disappeared during allocation.');
        }
        final newPaid =
            _money(target.paid + entry.value).clamp(0, target.total).toDouble();
        final paymentStatus = newPaid + PaymentVoucherService._epsilon >= target.total
            ? 'paid'
            : (newPaid > 0 ? 'partial' : 'unpaid');
        await _db.customUpdate(
          '''
          UPDATE sales
          SET paid_amount = ?, payment_status = ?, updated_at = ?, sync_status = 'pending',
              version = version + 1, last_modified_by_device_id = ?
          WHERE id = ? AND deleted_at = ''
          ''',
          variables: <Variable<Object>>[
            Variable<double>(newPaid),
            Variable<String>(paymentStatus),
            Variable<String>(now),
            Variable<String>(deviceId.trim()),
            Variable<String>(entry.key),
          ],
        );
      } else {
        final target = await _purchaseTarget(entry.key, 'USD');
        if (target == null) {
          throw StateError(
              'Purchase ${entry.key} disappeared during allocation.');
        }
        final newPaid =
            _money(target.paid + entry.value).clamp(0, target.total).toDouble();
        final paymentStatus = newPaid + PaymentVoucherService._epsilon >= target.total
            ? 'paid'
            : (newPaid > 0 ? 'partial' : 'unpaid');
        await _db.customUpdate(
          '''
          UPDATE purchases
          SET paid_amount = ?, payment_status = ?, updated_at = ?, sync_status = 'pending',
              version = version + 1, last_modified_by_device_id = ?
          WHERE id = ? AND deleted_at = ''
          ''',
          variables: <Variable<Object>>[
            Variable<double>(newPaid),
            Variable<String>(paymentStatus),
            Variable<String>(now),
            Variable<String>(deviceId.trim()),
            Variable<String>(entry.key),
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
    String technicalReferenceId = '',
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
      referenceId: technicalReferenceId.trim().isEmpty
          ? voucherId
          : technicalReferenceId.trim(),
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
      idempotencyKey: technicalReferenceId.trim().isEmpty
          ? '$type:$voucherId'
          : '$type:${technicalReferenceId.trim()}',
      occurredAt: occurredAt,
      createdAt: now,
      updatedAt: now,
      lastModifiedByDeviceId: deviceId,
    ));
  }

  Future<void> _moveCashLocation(
      String locationId, double delta, DateTime now) async {
    if (delta < 0) {
      await AccountingService.ensureCashOutflowAllowed(
        cashLocationId: locationId,
        amount: -delta,
        database: _db,
      );
    }
    await AccountingService.applyCashLocationDelta(
      cashLocationId: locationId,
      delta: delta,
      updatedAt: now.toIso8601String(),
      database: _db,
    );
  }

  Future<ReceiptVoucher?> _findReceiptByIdentity(
      String id, String idempotencyKey) async {
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
    return _receiptFromRow(
        row.data, await allocationsFor('receipt', existingId));
  }

  Future<PaymentVoucher?> _findPaymentByIdentity(
      String id, String idempotencyKey) async {
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
    return _paymentFromRow(
        row.data, await allocationsFor('payment', existingId));
  }
}
