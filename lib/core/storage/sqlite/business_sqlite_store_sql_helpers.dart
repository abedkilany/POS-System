part of 'business_sqlite_store_impl.dart';

Future<void> deleteKey(VentioDriftDatabase db, String key) async {
  final table = _tableByKey[key];
  if (table != null) {
    await db.customStatement('DELETE FROM $table;');
    await db.customStatement(
        'DELETE FROM local_key_values WHERE key = ?;', <Object?>[key]);
    return;
  }
  await db
      .customStatement('DELETE FROM settings WHERE key = ?;', <Object?>[key]);
  await db.customStatement(
      'DELETE FROM local_key_values WHERE key = ?;', <Object?>[key]);
}

Future<void> clear(VentioDriftDatabase db) async {
  final now = DateTime.now().toUtc().toIso8601String();
  for (final table in _tableByKey.values) {
    if (await _tableHasColumn(db, table, 'deleted_at')) {
      await db.customUpdate(
        "UPDATE $table SET deleted_at = ? WHERE deleted_at = ''",
        variables: <Variable<Object>>[Variable<String>(now)],
      );
    } else {
      await db.customStatement('DELETE FROM $table;');
    }
  }
  await db.customStatement('DELETE FROM warehouse_inventory;');
  await db.customStatement('DELETE FROM stock_operations;');
  await db.customStatement('DELETE FROM inventory_reconciliations;');
  await db.customStatement('DELETE FROM inventory_migration_adjustments;');
  await db.customStatement('DELETE FROM settings;');
  await db.customStatement('DELETE FROM local_key_values;');
}

Future<BusinessSqliteValidationResult> validateAgainstLegacyJson(
  VentioDriftDatabase db, {
  required Map<String, String> legacyEntries,
}) async {
  final problems = <String>[];
  for (final key in _entityListKeys) {
    final legacyCount = _jsonListLength(legacyEntries[key]);
    final sqliteCount = await _entityCount(db, _tableByKey[key]!);
    if (legacyEntries.containsKey(key) && legacyCount != sqliteCount) {
      problems.add('$key legacy=$legacyCount sqlite=$sqliteCount');
    }
  }

  if (problems.isEmpty) {
    await _setMeta(db, phase3ValidatedMetaKey, 'true');
    return const BusinessSqliteValidationResult(
        ok: true,
        message:
            'Business entity counts match legacy JSON storage source data.');
  }

  await _setMeta(db, phase3ValidatedMetaKey, 'false');
  return BusinessSqliteValidationResult(
      ok: false, message: problems.join('; '));
}

StockMovement _stockMovementFromRow(QueryRow row) {
  final date = _parseDate(_rowText(row, 'movement_date')) ??
      _parseDate(_rowText(row, 'created_at')) ??
      DateTime.now();
  return StockMovement(
    id: _rowText(row, 'id'),
    productId: _rowText(row, 'product_id'),
    productName: _rowText(row, 'product_name'),
    type: _rowText(row, 'movement_type', fallback: 'adjustment'),
    quantity: _rowDouble(row, 'quantity'),
    date: date,
    referenceId: _rowText(row, 'reference_id'),
    referenceNo: _rowText(row, 'reference_no'),
    reason: _rowText(row, 'reason'),
    adjustmentCategory: _rowText(row, 'adjustment_category'),
    notes: _rowText(row, 'notes'),
    evidenceRef: _rowText(row, 'evidence_ref'),
    warehouseId: _rowText(row, 'warehouse_id', fallback: 'main'),
    warehouseName: _rowText(row, 'warehouse_name', fallback: 'Main warehouse'),
    batchId: _rowText(row, 'batch_id'),
    movementGroupId: _rowText(row, 'movement_group_id'),
    documentLineId: _rowText(row, 'document_line_id'),
    sourceMovementId: _rowText(row, 'source_movement_id'),
    reversalOfMovementId: _rowText(row, 'reversal_of_movement_id'),
    idempotencyKey: _rowText(row, 'idempotency_key'),
    unitCost: _rowDouble(row, 'unit_cost'),
    createdAt: _parseDate(_rowText(row, 'created_at')) ?? date,
    updatedAt: _parseDate(_rowText(row, 'updated_at')) ?? date,
    deviceId: _rowText(row, 'device_id'),
    syncStatus: _rowText(row, 'sync_status', fallback: 'synced'),
    storeId: _rowText(row, 'store_id'),
    branchId: _rowText(row, 'branch_id'),
    version: _rowInt(row, 'version', fallback: 1),
    lastModifiedByDeviceId: _rowText(
      row,
      'last_modified_by_device_id',
      fallback: _rowText(row, 'device_id'),
    ),
    reviewedAt: _parseDate(_rowText(row, 'reviewed_at')),
    reviewedBy: _rowText(row, 'reviewed_by'),
    reviewNote: _rowText(row, 'review_note'),
  );
}

AccountTransaction _accountTransactionFromRow(QueryRow row) {
  final date = _parseDate(_rowText(row, 'transaction_date')) ??
      _parseDate(_rowText(row, 'created_at')) ??
      DateTime.now();
  return AccountTransaction(
    id: _rowText(row, 'id'),
    accountType: _rowText(row, 'account_type'),
    accountId: _rowText(row, 'account_id'),
    accountName: _rowText(row, 'account_name'),
    date: date,
    type: _rowText(row, 'transaction_type'),
    referenceId: _rowText(row, 'reference_id'),
    referenceNo: _rowText(row, 'reference_no'),
    debit: _rowDouble(row, 'debit'),
    credit: _rowDouble(row, 'credit'),
    currency: _rowText(row, 'currency', fallback: 'USD'),
    paymentMethod: _rowText(row, 'payment_method'),
    note: _rowText(row, 'note'),
    createdAt: _parseDate(_rowText(row, 'created_at')) ?? date,
    updatedAt: _parseDate(_rowText(row, 'updated_at')) ?? date,
    deletedAt: _parseDate(_rowText(row, 'deleted_at')),
    deviceId: _rowText(row, 'device_id'),
    syncStatus: _rowText(row, 'sync_status', fallback: 'synced'),
    storeId: _rowText(row, 'store_id'),
    branchId: _rowText(row, 'branch_id'),
    version: _rowInt(row, 'version', fallback: 1),
    lastModifiedByDeviceId: _rowText(
      row,
      'last_modified_by_device_id',
      fallback: _rowText(row, 'device_id'),
    ),
  );
}

Product _productFromQueryRow(
  QueryRow row, {
  Map<String, double> stockByIdentity = const <String, double>{},
  Map<String, List<Map<String, dynamic>>> saleUnitsByProduct =
      const <String, List<Map<String, dynamic>>>{},
  Map<String, List<Map<String, dynamic>>> purchaseUnitsByProduct =
      const <String, List<Map<String, dynamic>>>{},
}) {
  final data = Map<String, dynamic>.from(row.data);
  final productId = data['id']?.toString() ?? '';
  data['trackStock'] = data['trackStock'] == 1 || data['trackStock'] == true;
  data['expiryTrackingEnabled'] = data['expiryTrackingEnabled'] == 1 ||
      data['expiryTrackingEnabled'] == true;
  data['expiryEntryRequired'] =
      data['expiryEntryRequired'] == 1 || data['expiryEntryRequired'] == true;
  data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
  final storeId = data['storeId']?.toString() ?? '';
  final derivedStock = stockByIdentity['$storeId::$productId'];
  data['inventoryStock'] = derivedStock ?? 0;
  data['saleUnits'] =
      saleUnitsByProduct[productId] ?? const <Map<String, dynamic>>[];
  data['purchaseUnits'] =
      purchaseUnitsByProduct[productId] ?? const <Map<String, dynamic>>[];
  return Product.fromJson(data);
}

Future<Map<String, double>> _warehouseInventoryStockByIdentity(
  VentioDriftDatabase db, {
  String storeId = '',
  Iterable<String> productIds = const <String>[],
}) async {
  final conditions = <String>[];
  final variables = <Variable<Object>>[];
  if (storeId.trim().isNotEmpty) {
    conditions.add('store_id = ?');
    variables.add(Variable<String>(storeId.trim()));
  }
  final normalizedProductIds = productIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (normalizedProductIds.isNotEmpty) {
    conditions.add(
      'product_id IN (${List.filled(normalizedProductIds.length, '?').join(', ')})',
    );
    variables.addAll(normalizedProductIds.map(Variable<String>.new));
  }
  final whereSql = conditions.isEmpty ? '1=1' : conditions.join(' AND ');
  final rows = await db.customSelect('''
      SELECT store_id AS storeId, product_id AS productId,
             COALESCE(SUM(quantity), 0) AS quantity
      FROM warehouse_inventory
      WHERE $whereSql
      GROUP BY store_id, product_id
    ''', variables: variables).get();
  return <String, double>{
    for (final row in rows)
      '${row.read<String>('storeId')}::${row.read<String>('productId')}':
          _doubleValue(row.data['quantity'], fallback: 0),
  };
}

String _rowText(
  QueryRow row,
  String column, {
  String fallback = '',
}) {
  final value = row.data[column];
  if (value == null) return fallback;
  final text = value.toString();
  if (text.isEmpty || text == 'null') return fallback;
  return text;
}

double _rowDouble(QueryRow row, String column, {double fallback = 0}) {
  return _doubleValue(row.data[column], fallback: fallback);
}

int _rowInt(QueryRow row, String column, {required int fallback}) {
  return _intValue(row.data[column], fallback: fallback);
}

DateTime? _parseDate(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed == 'null') return null;
  return DateTime.tryParse(trimmed);
}

Future<void> _mergeEntityList(
    VentioDriftDatabase db, String key, String jsonText) async {
  final table = _tableByKey[key]!;
  final entityType = _entityTypeByKey[key]!;
  final decoded = jsonDecode(jsonText);
  if (decoded is! List) {
    throw FormatException('Expected a JSON list for $key');
  }

  final seenIds = <String>{};
  final payloads = <Map<String, dynamic>>[];
  final sortIndices = <int?>[];
  for (var index = 0; index < decoded.length; index += 1) {
    final raw = decoded[index];
    if (raw is! Map) continue;
    final payload = Map<String, dynamic>.from(raw);
    final id = (payload['id']?.toString().isNotEmpty ?? false)
        ? payload['id'].toString()
        : '${entityType}_$index';
    seenIds.add(id);
    payloads.add(payload);
    sortIndices.add(index);
  }

  if (payloads.isNotEmpty) {
    await upsertEntityPayloads(
      db,
      key,
      payloads,
      sortIndices: sortIndices,
    );
  }

  final existingRows = await db.customSelect('SELECT id FROM $table').get();
  final supportsSoftDelete = await _tableHasColumn(db, table, 'deleted_at');
  final deletedAt = DateTime.now().toUtc().toIso8601String();
  for (final row in existingRows) {
    final id = row.read<String>('id');
    if (!seenIds.contains(id)) {
      // Business snapshots must never physically remove rows referenced by
      // stock, costing, accounting, or audit history. An empty in-memory
      // list can occur briefly during recovery before the backup payload is
      // imported; hard deletion here both loses history and violates FKs.
      if (supportsSoftDelete) {
        await db.customUpdate(
          "UPDATE $table SET deleted_at = ? WHERE id = ? AND deleted_at = ''",
          variables: <Variable<Object>>[
            Variable<String>(deletedAt),
            Variable<String>(id),
          ],
        );
      } else {
        await db
            .customStatement('DELETE FROM $table WHERE id = ?;', <Object?>[id]);
      }
    }
  }
}

Future<int> _entityCount(VentioDriftDatabase db, String table) async {
  final rows = await db.customSelect('SELECT COUNT(*) AS c FROM $table').get();
  return rows.first.read<int>('c');
}

Future<bool> _tableHasColumn(
  VentioDriftDatabase db,
  String table,
  String column,
) async {
  final columns = await _tableColumns(db, table);
  return columns.contains(column);
}

Future<Set<String>> _tableColumns(
  VentioDriftDatabase db,
  String table,
) {
  return _tableColumnFutures.putIfAbsent(table, () async {
    final rows = await db.customSelect('PRAGMA table_info($table);').get();
    return rows
        .map((row) => row.data['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
  });
}

int _jsonListLength(String? jsonText) {
  if (jsonText == null || jsonText.isEmpty) return 0;
  try {
    final decoded = jsonDecode(jsonText);
    return decoded is List ? decoded.length : 0;
  } catch (_) {
    return 0;
  }
}

int _intValue(Object? value, {required int fallback}) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _doubleValue(Object? value, {double fallback = 0}) {
  if (value is num) {
    final parsed = value.toDouble();
    return parsed.isFinite ? parsed : fallback;
  }
  if (value is String) {
    final parsed = double.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed : fallback;
  }
  return fallback;
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return fallback;
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'y';
  }
  if (value == null) return fallback;
  return fallback;
}

String _textValue(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  if (text.isEmpty || text == 'null') return fallback;
  return text;
}

Object _sqlValue(Object? value) {
  if (value == null) return '';
  if (value is DateTime) return value.toIso8601String();
  if (value is bool) return value ? 1 : 0;
  if (value is Iterable && value is! String) return jsonEncode(value);
  if (value is Map) return jsonEncode(value);
  return value;
}

String? _dateString(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty || text == 'null' ? null : text;
}

Future<void> _saveLocalMirrorValue(
    VentioDriftDatabase db, String key, String value) async {
  await db.customInsert(
    '''
      INSERT OR REPLACE INTO local_key_values (key, value, updated_at)
      VALUES (?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(key),
      Variable<String>(value),
      Variable<String>(DateTime.now().toUtc().toIso8601String()),
    ],
  );
}

Future<String?> _metaValue(VentioDriftDatabase db, String key) async {
  final rows = await db.customSelect(
    'SELECT value FROM migration_meta WHERE key = ?',
    variables: <Variable<Object>>[Variable<String>(key)],
  ).get();
  return rows.isEmpty ? null : rows.first.read<String>('value');
}

Future<void> _setMeta(VentioDriftDatabase db, String key, String value) async {
  await db.customInsert(
    'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
    variables: <Variable<Object>>[
      Variable<String>(key),
      Variable<String>(value),
      Variable<String>(DateTime.now().toUtc().toIso8601String()),
    ],
  );
}
