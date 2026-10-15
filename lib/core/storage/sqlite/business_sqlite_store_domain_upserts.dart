part of 'business_sqlite_store_impl.dart';

void _insertProductUnitsIntoBatch(
  Batch batch,
  String table,
  String productId,
  Object? unitsValue,
) {
  final units = _payloadMapList(unitsValue);
  for (var index = 0; index < units.length; index += 1) {
    final unit = units[index];
    final unitId = _textValue(unit['id'], fallback: '$table-$index');
    batch.customStatement(
      '''
        INSERT OR REPLACE INTO $table
          (id, product_id, line_no, unit_id, name, conversion_to_base, price,
           original_price, original_currency, barcode, is_default)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      <Object?>[
        '${productId}_${table}_$index',
        productId,
        index,
        unitId,
        _textValue(unit['name']),
        _doubleValue(unit['conversionToBase'], fallback: 1),
        _doubleValue(unit['price']),
        _doubleValue(
          unit['originalPrice'],
          fallback: _doubleValue(unit['price']),
        ),
        _textValue(unit['originalCurrency'], fallback: 'USD'),
        _textValue(unit['barcode']),
        _boolValue(unit['isDefault']) ? 1 : 0,
      ],
    );
  }
}

Future<void> _insertProductUnits(
  VentioDriftDatabase db,
  String table,
  String productId,
  Object? unitsValue,
) async {
  await db.batch((batch) {
    _insertProductUnitsIntoBatch(batch, table, productId, unitsValue);
  });
}

Future<void> _upsertSalePayload(
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
  final hasWarehouseColumns =
      await _tableHasColumn(db, table, 'warehouse_id') &&
          await _tableHasColumn(db, table, 'warehouse_name');
  var postedSnapshotJson = payload['postedSnapshot'] is Map
      ? jsonEncode(payload['postedSnapshot'])
      : '';
  final existingSnapshotRow = await db.customSelect(
    'SELECT posted_snapshot_json FROM $table WHERE id = ? LIMIT 1',
    variables: <Variable<Object>>[Variable<String>(id)],
  ).getSingleOrNull();
  final existingSnapshot =
      existingSnapshotRow?.data['posted_snapshot_json']?.toString() ?? '';
  if (existingSnapshot.trim().isNotEmpty) {
    // Posted document snapshots are append-once. Older sync clients may send
    // no snapshot at all; cancellations/payments may update the live row;
    // neither case is allowed to rewrite the historical document image.
    postedSnapshotJson = existingSnapshot;
  }
  final typedColumns = <String, Object?>{
    'invoice_no': _textValue(payload['invoiceNo']),
    'customer_id': _textValue(payload['customerId']),
    'customer_name': _textValue(payload['customerName']),
    'document_date': _dateString(payload['date']) ?? createdAt,
    'status': _textValue(payload['status'], fallback: 'Paid'),
    'discount': _doubleValue(payload['discount']),
    'original_discount': _doubleValue(
      payload['originalDiscount'],
      fallback: _doubleValue(payload['discount']),
    ),
    'discount_currency':
        _textValue(payload['discountCurrency'], fallback: 'USD'),
    'discount_exchange_rate_at_entry':
        _doubleValue(payload['discountExchangeRateAtEntry']),
    'payment_method': _textValue(payload['paymentMethod'], fallback: 'Cash'),
    'payment_status': _textValue(payload['paymentStatus'], fallback: 'paid'),
    'invoice_currency': _textValue(payload['invoiceCurrency'], fallback: 'USD'),
    'payment_currency': _textValue(payload['paymentCurrency'], fallback: 'USD'),
    'exchange_rate_at_payment': _doubleValue(payload['exchangeRateAtPayment']),
    'base_currency': _textValue(payload['baseCurrency'], fallback: 'USD'),
    'exchange_rate_at_invoice':
        _doubleValue(payload['exchangeRateAtInvoice'], fallback: 1),
    'transaction_amount': _doubleValue(payload['transactionAmount']),
    'base_amount': _doubleValue(payload['baseAmount']),
    'paid_base_amount': _doubleValue(payload['paidBaseAmount']),
    'exchange_difference_amount':
        _doubleValue(payload['exchangeDifferenceAmount']),
    'paid_amount': _doubleValue(payload['paidAmount']),
    'cash_received_amount': _doubleValue(payload['cashReceivedAmount']),
    'paid_amount_in_payment_currency':
        _doubleValue(payload['paidAmountInPaymentCurrency']),
    'cash_received_amount_in_payment_currency':
        _doubleValue(payload['cashReceivedAmountInPaymentCurrency']),
    'note': _textValue(payload['note']),
    'posted_snapshot_json': postedSnapshotJson,
  };
  if (hasWarehouseColumns) {
    typedColumns['warehouse_id'] =
        _textValue(payload['warehouseId'], fallback: 'main');
    typedColumns['warehouse_name'] = _textValue(
      payload['warehouseName'],
      fallback: 'Main warehouse',
    );
  }
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
    typedColumns: typedColumns,
  );

  await db.customStatement(
    'DELETE FROM sale_items WHERE sale_id = ?;',
    <Object?>[id],
  );
  await db.customStatement(
    'DELETE FROM sale_item_cost_layer_consumptions '
    'WHERE sale_item_id IN (SELECT id FROM sale_items WHERE sale_id = ?);',
    <Object?>[id],
  );
  await _insertSaleLikeItems(
    db,
    itemTable: 'sale_items',
    parentColumn: 'sale_id',
    parentId: id,
    itemsValue: payload['items'],
    includeConsumptions: true,
    consumptionTable: 'sale_item_cost_layer_consumptions',
    consumptionParentColumn: 'sale_item_id',
  );
  await _upsertSearchIndex(
    db,
    entityType: 'sale',
    entityId: id,
    searchText: <Object?>[
      payload['invoiceNo'],
      payload['customerName'],
      payload['paymentMethod'],
      payload['paymentStatus'],
      payload['status'],
      payload['note'],
      ..._payloadMapList(payload['items']).expand(
        (item) => <Object?>[item['productName'], item['unitName']],
      ),
    ].join(' '),
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

Future<void> _upsertSaleQuotationPayload(
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
      'quotation_no': _textValue(payload['quotationNo']),
      'customer_id': _textValue(payload['customerId']),
      'customer_name': _textValue(payload['customerName']),
      'document_date': _dateString(payload['date']) ?? createdAt,
      'valid_until': _dateString(payload['validUntil']) ?? '',
      'status': _textValue(payload['status'], fallback: 'Draft'),
      'discount': _doubleValue(payload['discount']),
      'invoice_currency':
          _textValue(payload['invoiceCurrency'], fallback: 'USD'),
      'note': _textValue(payload['note']),
      'converted_sale_id': _textValue(payload['convertedSaleId']),
    },
  );

  await db.customStatement(
    'DELETE FROM sale_quotation_items WHERE sale_quotation_id = ?;',
    <Object?>[id],
  );
  await _insertSaleLikeItems(
    db,
    itemTable: 'sale_quotation_items',
    parentColumn: 'sale_quotation_id',
    parentId: id,
    itemsValue: payload['items'],
  );
}

Future<void> _upsertDeliveryNotePayload(
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
      'delivery_no': _textValue(payload['deliveryNo']),
      'sale_id': _textValue(payload['saleId']),
      'invoice_no': _textValue(payload['invoiceNo']),
      'customer_id': _textValue(payload['customerId']),
      'customer_name': _textValue(payload['customerName']),
      'document_date': _dateString(payload['date']) ?? createdAt,
      'status': _textValue(payload['status'], fallback: 'Draft'),
      'note': _textValue(payload['note']),
      'delivered_at': _dateString(payload['deliveredAt']) ?? '',
    },
  );

  await db.customStatement(
    'DELETE FROM delivery_note_items WHERE delivery_note_id = ?;',
    <Object?>[id],
  );
  await _insertSaleLikeItems(
    db,
    itemTable: 'delivery_note_items',
    parentColumn: 'delivery_note_id',
    parentId: id,
    itemsValue: payload['items'],
  );
}

Future<void> _upsertPurchasePayload(
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
  final hasWarehouseColumns =
      await _tableHasColumn(db, table, 'warehouse_id') &&
          await _tableHasColumn(db, table, 'warehouse_name');
  var postedSnapshotJson = payload['postedSnapshot'] is Map
      ? jsonEncode(payload['postedSnapshot'])
      : '';
  final existingSnapshotRow = await db.customSelect(
    'SELECT posted_snapshot_json FROM $table WHERE id = ? LIMIT 1',
    variables: <Variable<Object>>[Variable<String>(id)],
  ).getSingleOrNull();
  final existingSnapshot =
      existingSnapshotRow?.data['posted_snapshot_json']?.toString() ?? '';
  if (existingSnapshot.trim().isNotEmpty) {
    postedSnapshotJson = existingSnapshot;
  }
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
      'purchase_no': _textValue(payload['purchaseNo']),
      'supplier_id': _textValue(payload['supplierId']),
      'supplier_name': _textValue(payload['supplierName']),
      'document_date': _dateString(payload['date']) ?? createdAt,
      'status': _textValue(payload['status'], fallback: 'Draft'),
      'note': _textValue(payload['note']),
      'payment_status': _textValue(payload['paymentStatus'], fallback: 'paid'),
      'payment_method': _textValue(payload['paymentMethod'], fallback: 'Cash'),
      'paid_amount': _doubleValue(payload['paidAmount']),
      'document_type':
          _textValue(payload['documentType'], fallback: 'purchase'),
      'source_purchase_id': _textValue(payload['sourcePurchaseId']),
      'source_purchase_no': _textValue(payload['sourcePurchaseNo']),
      if (hasWarehouseColumns) ...{
        'warehouse_id': _textValue(payload['warehouseId'], fallback: 'main'),
        'warehouse_name': _textValue(
          payload['warehouseName'],
          fallback: 'Main warehouse',
        ),
      },
      'cancel_reason': _textValue(payload['cancelReason']),
      'cancelled_by_device_id': _textValue(payload['cancelledByDeviceId']),
      'reversal_applied': _boolValue(payload['reversalApplied']),
      'cancelled_at': _dateString(payload['cancelledAt']) ?? '',
      'posted_snapshot_json': postedSnapshotJson,
    },
  );

  await db.customStatement(
    'DELETE FROM purchase_items WHERE purchase_id = ?;',
    <Object?>[id],
  );
  await _insertPurchaseItems(
    db,
    purchaseId: id,
    itemsValue: payload['items'],
  );
}

/// Persists one inventory-count session inside the caller-owned SQLite
/// transaction. Phase 3 uses this so stock movements, accounting and the
/// count status commit or roll back as one unit.
Future<void> upsertInventoryCountInTransaction(
  VentioDriftDatabase db,
  InventoryCountSession session,
) async {
  final payload = session.toJson();
  final existing = await db.customSelect(
    'SELECT sort_index FROM inventory_counts WHERE id = ? LIMIT 1',
    variables: <Variable<Object>>[Variable<String>(session.id)],
  ).getSingleOrNull();
  late final int sortIndex;
  if (existing != null) {
    sortIndex = (existing.data['sort_index'] as num?)?.toInt() ?? 0;
  } else {
    final next = await db
        .customSelect(
          'SELECT COALESCE(MAX(sort_index), 0) + 1 AS next_sort FROM inventory_counts',
        )
        .getSingle();
    sortIndex = (next.data['next_sort'] as num?)?.toInt() ?? 1;
  }
  await _upsertInventoryCountPayload(
    db,
    _tableByKey[inventoryCountsKey]!,
    _entityTypeByKey[inventoryCountsKey]!,
    payload,
    id: session.id,
    payloadJson: jsonEncode(payload),
    createdAt: session.createdAt.toUtc().toIso8601String(),
    updatedAt: session.updatedAt.toUtc().toIso8601String(),
    deletedAt: '',
    sortIndex: sortIndex,
  );
}

Future<void> _upsertInventoryCountPayload(
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
      'count_no': _textValue(payload['countNo']),
      'created_by': _textValue(payload['createdBy']),
      'warehouse_id': _textValue(payload['warehouseId'], fallback: 'main'),
      'warehouse_name': _textValue(
        payload['warehouseName'],
        fallback: 'Main warehouse',
      ),
      'status': _textValue(payload['status'], fallback: 'open'),
      'notes': _textValue(payload['notes']),
      'approved_at': _dateString(payload['approvedAt']) ?? '',
      'approved_by': _textValue(payload['approvedBy']),
      'journal_entry_id': _textValue(payload['journalEntryId']),
      'reversal_journal_entry_id':
          _textValue(payload['reversalJournalEntryId']),
      'reversed_at': _dateString(payload['reversedAt']) ?? '',
      'reversed_by': _textValue(payload['reversedBy']),
      'reversal_reason': _textValue(payload['reversalReason']),
    },
  );

  await db.customStatement(
    'DELETE FROM inventory_count_lines WHERE inventory_count_id = ?;',
    <Object?>[id],
  );
  await _insertInventoryCountLines(
    db,
    inventoryCountId: id,
    linesValue: payload['lines'],
  );
}

Future<void> _upsertBillOfMaterialsPayload(
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
      'output_product_id': _textValue(payload['outputProductId']),
      'output_product_name': _textValue(payload['outputProductName']),
      'output_quantity': _doubleValue(payload['outputQuantity'], fallback: 1),
      'notes': _textValue(payload['notes']),
      'is_active': _boolValue(payload['isActive'], fallback: true),
    },
  );

  await db.customStatement(
    'DELETE FROM bill_of_materials_lines WHERE bill_of_material_id = ?;',
    <Object?>[id],
  );
  await _insertBillOfMaterialsLines(
    db,
    billOfMaterialId: id,
    linesValue: payload['components'],
  );
}

Future<void> _upsertManufacturingOrderPayload(
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
      'order_no': _textValue(payload['orderNo']),
      'bom_id': _textValue(payload['bomId']),
      'bom_name': _textValue(payload['bomName']),
      'output_product_id': _textValue(payload['outputProductId']),
      'output_product_name': _textValue(payload['outputProductName']),
      'quantity': _doubleValue(payload['quantity']),
      'raw_materials_warehouse_id':
          _textValue(payload['rawMaterialsWarehouseId'], fallback: 'main'),
      'raw_materials_warehouse_name': _textValue(
        payload['rawMaterialsWarehouseName'],
        fallback: 'Main warehouse',
      ),
      'finished_goods_warehouse_id':
          _textValue(payload['finishedGoodsWarehouseId'], fallback: 'main'),
      'finished_goods_warehouse_name': _textValue(
        payload['finishedGoodsWarehouseName'],
        fallback: 'Main warehouse',
      ),
      'status': _textValue(payload['status'], fallback: 'completed'),
      'notes': _textValue(payload['notes']),
      'document_date': _dateString(payload['date']) ?? createdAt,
      'actual_output_quantity': _doubleValue(payload['actualOutputQuantity']),
      'total_material_cost': _doubleValue(payload['totalMaterialCost']),
      'total_waste_cost': _doubleValue(payload['totalWasteCost']),
      'total_eligible_cost': _doubleValue(payload['totalEligibleCost']),
      'actual_unit_cost': _doubleValue(payload['actualUnitCost']),
      'material_costs_json': jsonEncode(payload['materialCosts'] ?? const []),
      'waste_lines_json': jsonEncode(payload['wasteLines'] ?? const []),
      'journal_entry_id': _textValue(payload['journalEntryId']),
      'reversal_journal_entry_id':
          _textValue(payload['reversalJournalEntryId']),
      'completed_at': _dateString(payload['completedAt']) ?? '',
      'completed_by': _textValue(payload['completedBy']),
      'reversed_at': _dateString(payload['reversedAt']) ?? '',
      'reversed_by': _textValue(payload['reversedBy']),
      'reversal_reason': _textValue(payload['reversalReason']),
    },
  );
}

Future<void> upsertManufacturingOrderPayloadInTransaction(
  VentioDriftDatabase db,
  Map<String, dynamic> payload, {
  required String id,
  required String payloadJson,
  required String createdAt,
  required String updatedAt,
  required String deletedAt,
  required int sortIndex,
}) async {
  await _upsertManufacturingOrderPayload(
    db,
    _tableByKey[manufacturingOrdersKey]!,
    _entityTypeByKey[manufacturingOrdersKey]!,
    payload,
    id: id,
    payloadJson: payloadJson,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    sortIndex: sortIndex,
  );
}

Future<void> upsertBillOfMaterialsPayloadInTransaction(
  VentioDriftDatabase db,
  Map<String, dynamic> payload, {
  required String id,
  required String payloadJson,
  required String createdAt,
  required String updatedAt,
  required String deletedAt,
  required int sortIndex,
}) async {
  await _upsertBillOfMaterialsPayload(
    db,
    _tableByKey[billsOfMaterialsKey]!,
    _entityTypeByKey[billsOfMaterialsKey]!,
    payload,
    id: id,
    payloadJson: payloadJson,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    sortIndex: sortIndex,
  );
}

Future<void> _upsertRolePayload(
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
      'permissions_json': jsonEncode(payload['permissions'] ?? const []),
      'is_system': _boolValue(payload['isSystem']),
    },
  );
}

Future<void> _upsertUserPayload(
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
      'full_name': _textValue(payload['fullName']),
      'username': _textValue(payload['username']),
      'password_hash': _textValue(payload['passwordHash']),
      'role_id': _textValue(payload['roleId']),
      'extra_permissions_json':
          jsonEncode(payload['extraPermissions'] ?? const []),
      'denied_permissions_json':
          jsonEncode(payload['deniedPermissions'] ?? const []),
      'is_active': _boolValue(payload['isActive'], fallback: true),
      'is_system': _boolValue(payload['isSystem']),
      'last_login_at': _dateString(payload['lastLoginAt']) ?? '',
    },
  );
}
