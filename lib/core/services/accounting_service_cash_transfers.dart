part of 'accounting_service_impl.dart';

Future<void> createCashLocation({
  required String name,
  required String type,
  String code = '',
  String accountId = '',
  String paymentAccountId = '',
  bool isDefault = false,
  String notes = '',
  String storeId = '',
  String branchId = '',
  String deviceId = '',
  String createdBy = '',
}) async {
  if (!isAvailable) return;
  final normalizedName = name.trim();
  if (normalizedName.isEmpty) throw ArgumentError('اسم موقع النقدية مطلوب.');
  final normalizedType = _normalizeCashLocationType(type);
  final now = DateTime.now().toUtc().toIso8601String();
  final locationId = _newId('cashloc');
  final normalizedCode = code.trim().isEmpty
      ? 'CASH-${DateTime.now().millisecondsSinceEpoch}'
      : code.trim().toUpperCase();
  final resolvedAccountId = accountId.trim().isEmpty
      ? await _createCashLocationAccount(
          locationId: locationId,
          name: normalizedName,
          type: normalizedType,
          code: normalizedCode,
          storeId: storeId,
          branchId: branchId,
        )
      : accountId.trim();
  await _accountSnapshot(_db, resolvedAccountId);
  await _db.transaction(() async {
    if (isDefault) {
      await _db.customUpdate(
        "UPDATE cash_locations SET is_default = 0, updated_at = ? WHERE type = ? AND deleted_at = ''",
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(normalizedType)
        ],
      );
    }
    await _db.customInsert(
      '''
        INSERT INTO cash_locations
          (id, code, name, type, account_id, parent_id, payment_account_id, is_default, is_active,
           allow_negative, current_balance, notes, created_at, updated_at, store_id, branch_id, device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, 0, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(locationId),
        Variable<String>(normalizedCode),
        Variable<String>(normalizedName),
        Variable<String>(normalizedType),
        Variable<String>(resolvedAccountId),
        Variable<String>(''),
        Variable<String>(paymentAccountId.trim()),
        Variable<int>(isDefault ? 1 : 0),
        Variable<int>(0),
        Variable<String>(notes.trim()),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(storeId),
        Variable<String>(branchId),
        Variable<String>(deviceId.trim()),
      ],
    );
  });
  _notifyMutation();
  await _writeAuditLog(
    action: 'create_cash_location',
    entityType: 'cash_location',
    entityId: locationId,
    details: normalizedName,
    createdBy: createdBy,
    storeId: storeId,
    branchId: branchId,
  );
}

Future<void> linkCashDrawerToDevice({
  required String cashLocationId,
  required String deviceId,
  String branchId = '',
}) async {
  if (!isAvailable) return;
  final cleanLocationId = cashLocationId.trim();
  final cleanDeviceId = deviceId.trim();
  final cleanBranchId = branchId.trim();
  if (cleanLocationId.isEmpty) {
    throw ArgumentError('درج النقدية مطلوب.');
  }
  if (cleanDeviceId.isEmpty) {
    throw ArgumentError('معرّف الجهاز مطلوب.');
  }
  final now = DateTime.now().toUtc().toIso8601String();
  final row = await _db.customSelect(
    """
      SELECT id, type, name
      FROM cash_locations
      WHERE id = ? AND deleted_at = '' AND is_active = 1
      LIMIT 1
      """,
    variables: <Variable<Object>>[Variable<String>(cleanLocationId)],
  ).getSingleOrNull();
  if (row == null) throw StateError('درج النقدية غير موجود.');
  if ((row.data['type']?.toString() ?? '') != 'cash_drawer') {
    throw StateError('يمكن ربط أدراج النقد فقط بالأجهزة.');
  }
  await _db.transaction(() async {
    await _db.customUpdate(
      """
        UPDATE cash_locations
        SET device_id = '', updated_at = ?
        WHERE device_id = ? AND id <> ? AND type = 'cash_drawer' AND deleted_at = ''
        """,
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(cleanDeviceId),
        Variable<String>(cleanLocationId),
      ],
    );
    await _db.customUpdate(
      """
        UPDATE cash_locations
        SET device_id = ?,
            branch_id = CASE WHEN ? <> '' THEN ? ELSE branch_id END,
            updated_at = ?
        WHERE id = ?
        """,
      variables: <Variable<Object>>[
        Variable<String>(cleanDeviceId),
        Variable<String>(cleanBranchId),
        Variable<String>(cleanBranchId),
        Variable<String>(now),
        Variable<String>(cleanLocationId),
      ],
    );
  });
  _notifyMutation();
}

Future<void> unlinkCashDrawerFromDevice({required String deviceId}) async {
  if (!isAvailable) return;
  final cleanDeviceId = deviceId.trim();
  if (cleanDeviceId.isEmpty) return;
  await _db.customUpdate(
    "UPDATE cash_locations SET device_id = '', updated_at = ? WHERE device_id = ? AND type = 'cash_drawer' AND deleted_at = ''",
    variables: <Variable<Object>>[
      Variable<String>(DateTime.now().toUtc().toIso8601String()),
      Variable<String>(cleanDeviceId),
    ],
  );
  _notifyMutation();
}

Future<String> createCashTransfer({
  required BusinessSessionContext authorization,
  required String fromLocationId,
  required String toLocationId,
  required double amount,
  DateTime? transferDate,
  String notes = '',
  String createdBy = '',
  String createdByUserId = '',
  String storeId = '',
  String branchId = '',
  String deviceId = '',
  String fromSessionId = '',
  String toSessionId = '',
  String transferKind = 'vault_transfer',
  String idempotencyKey = '',
  bool notifyChange = true,
  bool withinExistingTransaction = false,
}) async {
  authorization.requirePermission(AppPermission.cashBoxManage);
  if (!isAvailable) return '';
  final cleanAmount = _roundMoney(amount);
  if (cleanAmount <= 0) {
    throw ArgumentError('مبلغ التحويل يجب أن يكون أكبر من صفر.');
  }
  final normalizedKind = transferKind.trim() == 'shift_transfer'
      ? 'shift_transfer'
      : 'vault_transfer';
  final cleanKey = idempotencyKey.trim();
  if (cleanKey.isNotEmpty) {
    final existing = await _db.customSelect(
      "SELECT id FROM cash_transfers WHERE idempotency_key = ? AND deleted_at = '' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(cleanKey)],
    ).getSingleOrNull();
    if (existing != null) return existing.data['id']?.toString() ?? '';
  }

  final fromLocation = await _cashLocationSnapshot(fromLocationId);
  final toLocation = await _cashLocationSnapshot(toLocationId);
  if (fromLocation.id == toLocation.id) {
    throw ArgumentError('لا يمكن التحويل إلى نفس موقع النقدية.');
  }

  if (normalizedKind == 'shift_transfer') {
    final cleanFromSessionId = fromSessionId.trim();
    final cleanToSessionId = toSessionId.trim();
    if (fromLocation.type != 'cash_drawer' ||
        toLocation.type != 'cash_drawer') {
      throw StateError('تحويل الوردية يجب أن يكون بين درجَي نقدية.');
    }
    if (cleanFromSessionId.isEmpty || cleanToSessionId.isEmpty) {
      throw StateError('تحويل الوردية يتطلب وردية مفتوحة للمصدر والوجهة.');
    }
    final sessions = await _db.customSelect(
      '''
        SELECT id, cash_location_id
        FROM cash_drawer_sessions
        WHERE id IN (?, ?) AND status = 'open'
        ''',
      variables: <Variable<Object>>[
        Variable<String>(cleanFromSessionId),
        Variable<String>(cleanToSessionId),
      ],
    ).get();
    final openById = <String, String>{
      for (final row in sessions)
        row.data['id']?.toString() ?? '':
            row.data['cash_location_id']?.toString() ?? '',
    };
    if (openById[cleanFromSessionId] != fromLocation.id ||
        openById[cleanToSessionId] != toLocation.id) {
      throw StateError(
          'تحويل الوردية يتطلب ورديتين مفتوحتين ومطابقتين لدرجَي المصدر والوجهة.');
    }
  }
  await ensureCashOutflowAllowed(
    cashLocationId: fromLocation.id,
    amount: cleanAmount,
    database: _db,
  );

  final id = _newId('cashtx');
  final date = transferDate ?? DateTime.now();
  final nowDate = DateTime.now().toUtc();
  final now = nowDate.toIso8601String();
  final transferNo = await _nextCashTransferNo(date);
  final ledger = CashLedgerService(_db);
  String entryId = '';

  Future<void> persistTransfer() async {
    entryId = await createPostedEntry(
      JournalEntryDraft(
        entryDate: date,
        referenceType: 'cash_transfer',
        referenceId: id,
        referenceNo: transferNo,
        description:
            'تحويل نقدية من ${fromLocation.name} إلى ${toLocation.name}',
        source: 'system',
        createdBy: createdBy,
        storeId: storeId,
        branchId: branchId,
        lines: <JournalLineDraft>[
          JournalLineDraft(
              accountId: toLocation.accountId,
              debit: cleanAmount,
              credit: 0,
              memo: 'استلام تحويل نقدية'),
          JournalLineDraft(
              accountId: fromLocation.accountId,
              debit: 0,
              credit: cleanAmount,
              memo: 'إرسال تحويل نقدية'),
        ],
      ),
      database: _db,
      withinExistingTransaction: true,
    );
    if (entryId.isEmpty) {
      throw StateError('تعذر إنشاء القيد المحاسبي لتحويل النقدية.');
    }

    await _db.customInsert(
      '''
        INSERT INTO cash_transfers
          (id, transfer_no, transfer_date, from_location_id, to_location_id, amount, status, journal_entry_id,
           reference_type, reference_id, notes, created_by, approved_by, created_at, updated_at, store_id, branch_id,
           transfer_kind, from_session_id, to_session_id, created_by_user_id, device_id, idempotency_key)
        VALUES (?, ?, ?, ?, ?, ?, 'posted', ?, 'cash_transfer', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(id),
        Variable<String>(transferNo),
        Variable<String>(date.toUtc().toIso8601String()),
        Variable<String>(fromLocation.id),
        Variable<String>(toLocation.id),
        Variable<double>(cleanAmount),
        Variable<String>(entryId),
        Variable<String>(id),
        Variable<String>(notes.trim()),
        Variable<String>(createdBy),
        Variable<String>(createdBy),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(storeId),
        Variable<String>(branchId),
        Variable<String>(normalizedKind),
        Variable<String>(fromSessionId.trim()),
        Variable<String>(toSessionId.trim()),
        Variable<String>(createdByUserId.trim()),
        Variable<String>(deviceId.trim()),
        Variable<String>(cleanKey),
      ],
    );

    await ledger.appendInExistingTransaction(CashLedgerTransaction(
      id: '${id}_out',
      type: normalizedKind,
      direction: 'out',
      amount: cleanAmount,
      cashLocationId: fromLocation.id,
      cashDrawerSessionId: fromSessionId.trim(),
      referenceType: 'cash_transfer',
      referenceId: id,
      referenceNumber: transferNo,
      paymentMethod: 'Cash',
      createdBy: createdBy.trim(),
      createdByUserId: createdByUserId.trim(),
      deviceId: deviceId.trim(),
      branchId: branchId.trim(),
      storeId: storeId.trim(),
      notes: notes.trim(),
      idempotencyKey: cleanKey.isEmpty ? '' : '$cleanKey:out',
      occurredAt: date.toUtc(),
      createdAt: nowDate,
      updatedAt: nowDate,
      lastModifiedByDeviceId: deviceId.trim(),
    ));
    await ledger.appendInExistingTransaction(CashLedgerTransaction(
      id: '${id}_in',
      type: normalizedKind,
      direction: 'in',
      amount: cleanAmount,
      cashLocationId: toLocation.id,
      cashDrawerSessionId: toSessionId.trim(),
      referenceType: 'cash_transfer',
      referenceId: id,
      referenceNumber: transferNo,
      paymentMethod: 'Cash',
      createdBy: createdBy.trim(),
      createdByUserId: createdByUserId.trim(),
      deviceId: deviceId.trim(),
      branchId: branchId.trim(),
      storeId: storeId.trim(),
      notes: notes.trim(),
      idempotencyKey: cleanKey.isEmpty ? '' : '$cleanKey:in',
      occurredAt: date.toUtc(),
      createdAt: nowDate,
      updatedAt: nowDate,
      lastModifiedByDeviceId: deviceId.trim(),
    ));

    await applyCashLocationDelta(
      cashLocationId: fromLocation.id,
      delta: -cleanAmount,
      updatedAt: now,
      database: _db,
    );
    await applyCashLocationDelta(
      cashLocationId: toLocation.id,
      delta: cleanAmount,
      updatedAt: now,
      database: _db,
    );
  }

  if (withinExistingTransaction) {
    await persistTransfer();
  } else {
    await _db.transaction(persistTransfer);
  }
  if (notifyChange) _notifyMutation();
  await _writeAuditLog(
    action: normalizedKind == 'shift_transfer'
        ? 'create_shift_transfer'
        : 'create_vault_transfer',
    entityType: 'cash_transfer',
    entityId: id,
    details:
        '$transferNo: ${fromLocation.name} -> ${toLocation.name}: $cleanAmount',
    createdBy: createdBy,
    storeId: storeId,
    branchId: branchId,
  );
  return id;
}

Future<void> createPaymentAccount({
  required String name,
  required String type,
  required String accountId,
  bool isDefault = false,
  String notes = '',
  String storeId = '',
  String branchId = '',
}) async {
  if (!isAvailable) return;
  await _accountSnapshot(_db, accountId);
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.transaction(() async {
    if (isDefault) {
      await _db.customUpdate(
        "UPDATE payment_accounts SET is_default = 0, updated_at = ? WHERE type = ? AND deleted_at = ''",
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(type)
        ],
      );
    }
    await _db.customInsert(
      '''
        INSERT INTO payment_accounts
          (id, name, type, account_id, is_default, is_active, notes, created_at, updated_at, store_id, branch_id)
        VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(_newId('payacc')),
        Variable<String>(name.trim().isEmpty ? type : name.trim()),
        Variable<String>(type.trim().isEmpty ? 'other' : type.trim()),
        Variable<String>(accountId),
        Variable<int>(isDefault ? 1 : 0),
        Variable<String>(notes),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(storeId),
        Variable<String>(branchId),
      ],
    );
  });
  _notifyMutation();
  await _writeAuditLog(
      action: 'create_payment_account',
      entityType: 'payment_account',
      details: name,
      storeId: storeId,
      branchId: branchId);
}

Future<void> createCheque({
  required String chequeNo,
  required String direction,
  required String partyType,
  required String partyId,
  required String partyName,
  required String bankName,
  required DateTime dueDate,
  required double amount,
  String notes = '',
  String storeId = '',
  String branchId = '',
}) async {
  if (!isAvailable) return;
  if (_cleanAmount(amount) <= 0) throw ArgumentError('قيمة الشيك مطلوبة.');
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customInsert(
    '''
      INSERT INTO cheques
        (id, cheque_no, direction, party_type, party_id, party_name, bank_name, due_date,
         amount, status, notes, created_at, updated_at, store_id, branch_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(_newId('chq')),
      Variable<String>(chequeNo.trim()),
      Variable<String>(direction == 'issued' ? 'issued' : 'received'),
      Variable<String>(partyType),
      Variable<String>(partyId),
      Variable<String>(partyName),
      Variable<String>(bankName),
      Variable<String>(dueDate.toUtc().toIso8601String()),
      Variable<double>(_roundMoney(amount)),
      Variable<String>(notes),
      Variable<String>(now),
      Variable<String>(now),
      Variable<String>(storeId),
      Variable<String>(branchId),
    ],
  );
  _notifyMutation();
  await _writeAuditLog(
      action: 'create_cheque',
      entityType: 'cheque',
      details: chequeNo,
      storeId: storeId,
      branchId: branchId);
}

Future<void> settleCheque(
    {required String chequeId, String settledBy = ''}) async {
  if (!isAvailable) return;
  final row = await _db.customSelect(
    "SELECT * FROM cheques WHERE id = ? AND status = 'pending' LIMIT 1",
    variables: <Variable<Object>>[Variable<String>(chequeId)],
  ).getSingleOrNull();
  if (row == null) return;
  final data = row.data;
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customUpdate(
    "UPDATE cheques SET status = 'cleared', updated_at = ? WHERE id = ?",
    variables: <Variable<Object>>[
      Variable<String>(now),
      Variable<String>(chequeId)
    ],
  );
  _notifyMutation();
  await _writeAuditLog(
      action: 'clear_cheque',
      entityType: 'cheque',
      entityId: chequeId,
      details: data['cheque_no']?.toString() ?? '',
      createdBy: settledBy,
      storeId: data['store_id']?.toString() ?? '',
      branchId: data['branch_id']?.toString() ?? '');
}

Future<void> bounceCheque(
    {required String chequeId, String reason = '', String actor = ''}) async {
  if (!isAvailable) return;
  final row = await _db.customSelect(
    "SELECT cheque_no, store_id, branch_id FROM cheques WHERE id = ? AND status = 'pending' LIMIT 1",
    variables: <Variable<Object>>[Variable<String>(chequeId)],
  ).getSingleOrNull();
  if (row == null) return;
  final now = DateTime.now().toUtc().toIso8601String();
  await _db.customUpdate(
    "UPDATE cheques SET status = 'bounced', notes = notes || ?, updated_at = ? WHERE id = ?",
    variables: <Variable<Object>>[
      Variable<String>('\nBounced: $reason'),
      Variable<String>(now),
      Variable<String>(chequeId)
    ],
  );
  _notifyMutation();
  await _writeAuditLog(
      action: 'bounce_cheque',
      entityType: 'cheque',
      entityId: chequeId,
      details: reason,
      createdBy: actor,
      storeId: row.data['store_id']?.toString() ?? '',
      branchId: row.data['branch_id']?.toString() ?? '');
}
