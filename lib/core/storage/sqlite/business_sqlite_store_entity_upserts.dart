part of 'business_sqlite_store_impl.dart';

Future<void> _upsertTypedEntityRow(
  VentioDriftDatabase db,
  String table,
  String entityType,
  Map<String, dynamic> payload, {
  required String id,
  required String payloadJson,
  required String createdAt,
  required String updatedAt,
  required String deletedAt,
  required int sortIndex,
  required Map<String, Object?> typedColumns,
}) async {
  final columns = <String>[
    'id',
    'entity_type',
    'created_at',
    'updated_at',
    'deleted_at',
    'device_id',
    'sync_status',
    'store_id',
    'branch_id',
    'version',
    'last_modified_by_device_id',
    'sort_index',
    ...typedColumns.keys,
  ];
  final placeholders =
      List<String>.filled(columns.length, '?', growable: false).join(', ');
  final values = <Variable<Object>>[
    Variable<String>(id),
    Variable<String>(entityType),
    Variable<String>(createdAt),
    Variable<String>(updatedAt),
    Variable<String>(deletedAt),
    Variable<String>(_textValue(payload['deviceId'])),
    Variable<String>(_textValue(payload['syncStatus'])),
    Variable<String>(_textValue(payload['storeId'])),
    Variable<String>(_textValue(payload['branchId'])),
    Variable<int>(_intValue(payload['version'], fallback: 1)),
    Variable<String>(
      _textValue(payload['lastModifiedByDeviceId'] ?? payload['deviceId']),
    ),
    Variable<int>(sortIndex),
    for (final value in typedColumns.values) Variable<Object>(_sqlValue(value)),
  ];

  await db.customInsert(
    'INSERT OR REPLACE INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
    variables: values,
  );
}

Future<void> _upsertStockMovementPayload(
  VentioDriftDatabase db,
  String table,
  String entityType,
  Map<String, dynamic> payload, {
  required String id,
  required String payloadJson,
  required String createdAt,
  required String updatedAt,
  required String deletedAt,
  required int sortIndex,
}) async {
  await db.customInsert(
    """
      INSERT OR REPLACE INTO $table
        (id, entity_type, created_at, updated_at, deleted_at,
         device_id, sync_status, store_id, branch_id, version, sort_index,
         product_id, product_name, movement_type, quantity, movement_date,
         reference_id, reference_no, reason, adjustment_category, notes,
         evidence_ref, warehouse_id, warehouse_name, batch_id, movement_group_id,
         document_line_id, source_movement_id, reversal_of_movement_id,
         idempotency_key, unit_cost,
         last_modified_by_device_id, reviewed_at, reviewed_by, review_note)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
    variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(entityType),
      Variable<String>(createdAt),
      Variable<String>(updatedAt),
      Variable<String>(deletedAt),
      Variable<String>(_textValue(payload['deviceId'])),
      Variable<String>(_textValue(payload['syncStatus'])),
      Variable<String>(_textValue(payload['storeId'])),
      Variable<String>(_textValue(payload['branchId'])),
      Variable<int>(_intValue(payload['version'], fallback: 1)),
      Variable<int>(sortIndex),
      Variable<String>(_textValue(payload['productId'])),
      Variable<String>(_textValue(payload['productName'])),
      Variable<String>(_textValue(payload['type'], fallback: 'adjustment')),
      Variable<double>(_doubleValue(payload['quantity'])),
      Variable<String>(
        _dateString(payload['date']) ??
            _dateString(payload['createdAt']) ??
            createdAt,
      ),
      Variable<String>(
        _textValue(
          payload['referenceId'] ?? payload['saleId'] ?? payload['purchaseId'],
        ),
      ),
      Variable<String>(_textValue(payload['referenceNo'])),
      Variable<String>(_textValue(payload['reason'])),
      Variable<String>(
        _textValue(
          payload['adjustmentCategory'] ?? payload['category'],
        ),
      ),
      Variable<String>(_textValue(payload['notes'])),
      Variable<String>(_textValue(payload['evidenceRef'])),
      Variable<String>(_textValue(payload['warehouseId'], fallback: 'main')),
      Variable<String>(
        _textValue(payload['warehouseName'], fallback: 'Main warehouse'),
      ),
      Variable<String>(_textValue(payload['batchId'])),
      Variable<String>(_textValue(payload['movementGroupId'])),
      Variable<String>(_textValue(payload['documentLineId'])),
      Variable<String>(_textValue(payload['sourceMovementId'])),
      Variable<String>(_textValue(payload['reversalOfMovementId'])),
      Variable<String>(_textValue(payload['idempotencyKey'])),
      Variable<double>(_doubleValue(payload['unitCost'])),
      Variable<String>(
        _textValue(
          payload['lastModifiedByDeviceId'] ?? payload['deviceId'],
        ),
      ),
      Variable<String>(_dateString(payload['reviewedAt']) ?? ''),
      Variable<String>(_textValue(payload['reviewedBy'])),
      Variable<String>(_textValue(payload['reviewNote'])),
    ],
  );
  await _upsertSearchIndex(
    db,
    entityType: 'stock_movement',
    entityId: id,
    searchText: <Object?>[
      payload['productName'],
      payload['referenceNo'],
      payload['type'],
      payload['warehouseName'],
      payload['reason'],
      payload['notes'],
    ].join(' '),
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

Future<void> _upsertAccountTransactionPayload(
  VentioDriftDatabase db,
  String table,
  String entityType,
  Map<String, dynamic> payload, {
  required String id,
  required String payloadJson,
  required String createdAt,
  required String updatedAt,
  required String deletedAt,
  required int sortIndex,
}) async {
  await db.customInsert(
    """
      INSERT OR REPLACE INTO $table
        (id, entity_type, created_at, updated_at, deleted_at,
         device_id, sync_status, store_id, branch_id, version, sort_index,
         account_type, account_id, account_name, transaction_date,
         transaction_type, reference_id, reference_no, debit, credit,
         currency, payment_method, note, last_modified_by_device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
    variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(entityType),
      Variable<String>(createdAt),
      Variable<String>(updatedAt),
      Variable<String>(deletedAt),
      Variable<String>(_textValue(payload['deviceId'])),
      Variable<String>(_textValue(payload['syncStatus'])),
      Variable<String>(_textValue(payload['storeId'])),
      Variable<String>(_textValue(payload['branchId'])),
      Variable<int>(_intValue(payload['version'], fallback: 1)),
      Variable<int>(sortIndex),
      Variable<String>(_textValue(payload['accountType'])),
      Variable<String>(_textValue(payload['accountId'])),
      Variable<String>(_textValue(payload['accountName'])),
      Variable<String>(
        _dateString(payload['date']) ??
            _dateString(payload['createdAt']) ??
            createdAt,
      ),
      Variable<String>(_textValue(payload['type'])),
      Variable<String>(_textValue(payload['referenceId'])),
      Variable<String>(_textValue(payload['referenceNo'])),
      Variable<double>(_doubleValue(payload['debit'])),
      Variable<double>(_doubleValue(payload['credit'])),
      Variable<String>(_textValue(payload['currency'], fallback: 'USD')),
      Variable<String>(_textValue(payload['paymentMethod'])),
      Variable<String>(_textValue(payload['note'])),
      Variable<String>(
        _textValue(
          payload['lastModifiedByDeviceId'] ?? payload['deviceId'],
        ),
      ),
    ],
  );
}

Future<void> _upsertProductPayload(
  VentioDriftDatabase db,
  String table,
  String entityType,
  Map<String, dynamic> payload, {
  required String id,
  required String payloadJson,
  required String createdAt,
  required String updatedAt,
  required String deletedAt,
  required int sortIndex,
}) async {
  await _upsertTypedEntityRow(
    db,
    table,
    entityType,
    payload,
    id: id,
    payloadJson: payloadJson,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    sortIndex: sortIndex,
    typedColumns: <String, Object?>{
      'name': _textValue(payload['name']),
      'code': _textValue(payload['code']),
      'name_en': _textValue(payload['nameEn']),
      'name_ar': _textValue(payload['nameAr']),
      'price': _doubleValue(payload['price'] ?? payload['usdPrice']),
      'cost': _doubleValue(payload['cost'] ?? payload['usdCost']),
      'original_cost': _doubleValue(
        payload['originalCost'] ?? payload['cost'] ?? payload['usdCost'],
      ),
      'cost_currency': _textValue(payload['costCurrency'], fallback: 'USD'),
      'usd_cost': _doubleValue(payload['usdCost'] ?? payload['cost']),
      'cost_exchange_rate_at_entry':
          _doubleValue(payload['costExchangeRateAtEntry']),
      'original_price': _doubleValue(
        payload['originalPrice'] ?? payload['price'],
      ),
      'original_currency':
          _textValue(payload['originalCurrency'], fallback: 'USD'),
      'usd_price': _doubleValue(payload['usdPrice'] ?? payload['price']),
      'exchange_rate_at_entry': _doubleValue(payload['exchangeRateAtEntry']),
      'category': _textValue(payload['category'], fallback: 'General'),
      'barcode': _textValue(payload['barcode']),
      'brand': _textValue(payload['brand']),
      'supplier': _textValue(payload['supplier']),
      'description': _textValue(payload['description']),
      'unit': _textValue(payload['unit'], fallback: 'pcs'),
      'quantity_type': _textValue(
        payload['quantityType'],
        fallback: ProductQuantityType.countable.code,
      ),
      'low_stock_threshold':
          _intValue(payload['lowStockThreshold'], fallback: 5),
      'track_stock': _boolValue(payload['trackStock'], fallback: true),
      'expiry_tracking_enabled':
          _boolValue(payload['expiryTrackingEnabled'], fallback: false),
      'expiry_entry_required':
          _boolValue(payload['expiryTrackingEnabled'], fallback: false)
              ? true
              : _boolValue(payload['expiryEntryRequired'], fallback: true),
      'expiry_alert_days': _intValue(payload['expiryAlertDays'], fallback: 30),
      'default_shelf_life_days':
          _intValue(payload['defaultShelfLifeDays'], fallback: 0),
      'minimum_receipt_shelf_life_days':
          _intValue(payload['minimumReceiptShelfLifeDays'], fallback: 0),
      'is_active': _boolValue(payload['isActive'], fallback: true),
      'image_path': _textValue(payload['imagePath']),
      'tax_profile_id': _textValue(payload['taxProfileId']),
    },
  );

  await db.customStatement(
    'DELETE FROM product_sale_units WHERE product_id = ?;',
    <Object?>[id],
  );
  await db.customStatement(
    'DELETE FROM product_purchase_units WHERE product_id = ?;',
    <Object?>[id],
  );

  await _insertProductUnits(
    db,
    'product_sale_units',
    id,
    payload['saleUnits'],
  );
  await _insertProductUnits(
    db,
    'product_purchase_units',
    id,
    payload['purchaseUnits'],
  );
  await _upsertSearchIndex(
    db,
    entityType: 'product',
    entityId: id,
    searchText: <Object?>[
      payload['name'],
      payload['nameEn'],
      payload['nameAr'],
      payload['code'],
      payload['barcode'],
      payload['category'],
      payload['brand'],
      payload['supplier'],
      payload['unit'],
      payload['description'],
      ..._payloadMapList(payload['saleUnits']).expand(
        (unit) => <Object?>[unit['name'], unit['barcode']],
      ),
      ..._payloadMapList(payload['purchaseUnits']).expand(
        (unit) => <Object?>[unit['name'], unit['barcode']],
      ),
    ].join(' '),
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

Future<void> _upsertProductPayloads(
  VentioDriftDatabase db,
  String table,
  String entityType,
  List<Map<String, dynamic>> payloads, {
  List<int?>? sortIndices,
}) async {
  await db.batch((batch) {
    for (var index = 0; index < payloads.length; index += 1) {
      final payload = payloads[index];
      final sortIndex = sortIndices != null && index < sortIndices.length
          ? sortIndices[index]
          : null;
      final now = DateTime.now().toUtc().toIso8601String();
      final id = (payload['id']?.toString().isNotEmpty ?? false)
          ? payload['id'].toString()
          : '${entityType}_${now.hashCode}';
      final createdAt = _dateString(payload['createdAt']) ??
          _dateString(payload['date']) ??
          now;
      final updatedAt = _dateString(payload['updatedAt']) ?? createdAt;
      final deletedAt = _dateString(payload['deletedAt']) ?? '';

      batch.customStatement(
        'INSERT OR REPLACE INTO $table '
        '(id, entity_type, created_at, updated_at, deleted_at, device_id, '
        'sync_status, store_id, branch_id, version, last_modified_by_device_id, '
        'sort_index, name, code, name_en, name_ar, price, cost, original_cost, '
        'cost_currency, usd_cost, cost_exchange_rate_at_entry, original_price, '
        'original_currency, usd_price, exchange_rate_at_entry, category, '
        'barcode, brand, supplier, description, unit, quantity_type, '
        'low_stock_threshold, track_stock, expiry_tracking_enabled, '
        'expiry_entry_required, expiry_alert_days, default_shelf_life_days, '
        'minimum_receipt_shelf_life_days, is_active, image_path, tax_profile_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          id,
          entityType,
          createdAt,
          updatedAt,
          deletedAt,
          _textValue(payload['deviceId']),
          _textValue(payload['syncStatus']),
          _textValue(payload['storeId']),
          _textValue(payload['branchId']),
          _intValue(payload['version'], fallback: 1),
          _textValue(payload['lastModifiedByDeviceId'] ?? payload['deviceId']),
          sortIndex ?? 0,
          _textValue(payload['name']),
          _textValue(payload['code']),
          _textValue(payload['nameEn']),
          _textValue(payload['nameAr']),
          _doubleValue(payload['price'] ?? payload['usdPrice']),
          _doubleValue(payload['cost'] ?? payload['usdCost']),
          _doubleValue(
              payload['originalCost'] ?? payload['cost'] ?? payload['usdCost']),
          _textValue(payload['costCurrency'], fallback: 'USD'),
          _doubleValue(payload['usdCost'] ?? payload['cost']),
          _doubleValue(payload['costExchangeRateAtEntry']),
          _doubleValue(payload['originalPrice'] ?? payload['price']),
          _textValue(payload['originalCurrency'], fallback: 'USD'),
          _doubleValue(payload['usdPrice'] ?? payload['price']),
          _doubleValue(payload['exchangeRateAtEntry']),
          _textValue(payload['category'], fallback: 'General'),
          _textValue(payload['barcode']),
          _textValue(payload['brand']),
          _textValue(payload['supplier']),
          _textValue(payload['description']),
          _textValue(payload['unit'], fallback: 'pcs'),
          _textValue(
            payload['quantityType'],
            fallback: ProductQuantityType.countable.code,
          ),
          _intValue(payload['lowStockThreshold'], fallback: 5),
          _boolValue(payload['trackStock'], fallback: true) ? 1 : 0,
          _boolValue(payload['expiryTrackingEnabled'], fallback: false) ? 1 : 0,
          (_boolValue(payload['expiryTrackingEnabled'], fallback: false) ||
                  _boolValue(payload['expiryEntryRequired'], fallback: true))
              ? 1
              : 0,
          _intValue(payload['expiryAlertDays'], fallback: 30),
          _intValue(payload['defaultShelfLifeDays'], fallback: 0),
          _intValue(payload['minimumReceiptShelfLifeDays'], fallback: 0),
          _boolValue(payload['isActive'], fallback: true) ? 1 : 0,
          _textValue(payload['imagePath']),
          _textValue(payload['taxProfileId']),
        ],
      );

      batch.customStatement(
        'DELETE FROM product_sale_units WHERE product_id = ?;',
        <Object?>[id],
      );
      batch.customStatement(
        'DELETE FROM product_purchase_units WHERE product_id = ?;',
        <Object?>[id],
      );

      _insertProductUnitsIntoBatch(
        batch,
        'product_sale_units',
        id,
        payload['saleUnits'],
      );
      _insertProductUnitsIntoBatch(
        batch,
        'product_purchase_units',
        id,
        payload['purchaseUnits'],
      );
      _upsertSearchIndexIntoBatch(
        batch,
        entityType: 'product',
        entityId: id,
        searchText: <Object?>[
          payload['name'],
          payload['nameEn'],
          payload['nameAr'],
          payload['code'],
          payload['barcode'],
          payload['category'],
          payload['brand'],
          payload['supplier'],
          payload['unit'],
          payload['description'],
          ..._payloadMapList(payload['saleUnits']).expand(
            (unit) => <Object?>[unit['name'], unit['barcode']],
          ),
          ..._payloadMapList(payload['purchaseUnits']).expand(
            (unit) => <Object?>[unit['name'], unit['barcode']],
          ),
        ].join(' '),
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );
    }
  });
}
