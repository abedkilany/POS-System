part of 'business_sqlite_store_impl.dart';

Future<void> _insertSaleLikeItems(
  VentioDriftDatabase db, {
  required String itemTable,
  required String parentColumn,
  required String parentId,
  required Object? itemsValue,
  bool includeConsumptions = false,
  String? consumptionTable,
  String? consumptionParentColumn,
}) async {
  final items = _payloadMapList(itemsValue);
  for (var index = 0; index < items.length; index += 1) {
    final item = items[index];
    final itemId = '$parentId:$index';
    await db.customInsert(
      '''
        INSERT OR REPLACE INTO $itemTable
          (id, $parentColumn, line_no, product_id, product_name,
           unit_price, quantity, unit_name, base_quantity,
           conversion_to_base, unit_cost, costing_method_at_sale,
           cost_currency, cost_exchange_rate)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(itemId),
        Variable<String>(parentId),
        Variable<int>(index),
        Variable<String>(_textValue(item['productId'])),
        Variable<String>(_textValue(item['productName'])),
        Variable<double>(_doubleValue(item['unitPrice'])),
        Variable<double>(_doubleValue(item['quantity'])),
        Variable<String>(_textValue(item['unitName'])),
        Variable<double>(_doubleValue(item['baseQuantity'])),
        Variable<double>(_doubleValue(item['conversionToBase'], fallback: 1)),
        Variable<double>(_doubleValue(item['unitCost'])),
        Variable<String>(
          _textValue(
            item['costingMethodAtSale'],
            fallback: InventoryCostingMethod.weightedAverage.code,
          ),
        ),
        Variable<String>(_textValue(item['costCurrency'], fallback: 'USD')),
        Variable<double>(_doubleValue(item['costExchangeRate'], fallback: 1)),
      ],
    );

    if (itemTable == 'sale_items') {
      final batchAllocations = _payloadMapList(item['batchAllocations']);
      for (var batchIndex = 0;
          batchIndex < batchAllocations.length;
          batchIndex += 1) {
        final allocation = batchAllocations[batchIndex];
        await db.customInsert(
          '''
            INSERT OR REPLACE INTO sale_item_batch_allocations
              (id, sale_item_id, line_no, batch_id, quantity, unit_cost, expiration_date)
            SELECT ?, ?, ?, ?, ?, ?, ?
            WHERE EXISTS (SELECT 1 FROM inventory_batches WHERE id = ?)
            ''',
          variables: <Variable<Object>>[
            Variable<String>('$itemId:batch:$batchIndex'),
            Variable<String>(itemId),
            Variable<int>(batchIndex),
            Variable<String>(_textValue(allocation['batchId'])),
            Variable<double>(_doubleValue(allocation['quantity'])),
            Variable<double>(_doubleValue(allocation['unitCost'])),
            Variable<String>(_dateString(allocation['expirationDate']) ?? ''),
            Variable<String>(_textValue(allocation['batchId'])),
          ],
        );
      }
    }

    if (!includeConsumptions || consumptionTable == null) continue;
    final consumptions = _payloadMapList(item['costLayerConsumptions']);
    final parentColumnName = consumptionParentColumn ?? 'sale_item_id';
    for (var consumptionIndex = 0;
        consumptionIndex < consumptions.length;
        consumptionIndex += 1) {
      final consumption = consumptions[consumptionIndex];
      await db.customInsert(
        '''
          INSERT OR REPLACE INTO $consumptionTable
            (id, $parentColumnName, line_no, layer_id, quantity, unit_cost, currency_code)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
        variables: <Variable<Object>>[
          Variable<String>('$itemId:$consumptionIndex'),
          Variable<String>(itemId),
          Variable<int>(consumptionIndex),
          Variable<String>(_textValue(consumption['layerId'])),
          Variable<double>(_doubleValue(consumption['quantity'])),
          Variable<double>(_doubleValue(consumption['unitCost'])),
          Variable<String>(
            _textValue(consumption['currencyCode'], fallback: 'USD'),
          ),
        ],
      );
    }
  }
}

Future<void> _insertPurchaseItems(
  VentioDriftDatabase db, {
  required String purchaseId,
  required Object? itemsValue,
}) async {
  final items = _payloadMapList(itemsValue);
  for (var index = 0; index < items.length; index += 1) {
    final item = items[index];
    final stableLineId = _textValue(item['lineId']).trim().isEmpty
        ? '$purchaseId:$index'
        : _textValue(item['lineId']).trim();
    final batchAllocations = _payloadMapList(item['batchAllocations']);
    final requestedAllocation =
        batchAllocations.isEmpty ? null : batchAllocations.first;
    await db.customInsert(
      '''
        INSERT OR REPLACE INTO purchase_items
          (id, purchase_id, line_no, product_id, product_name, quantity,
           unit_cost, purchase_unit_id, purchase_unit_name, conversion_to_base,
           original_unit_cost, unit_cost_currency, exchange_rate_at_entry,
           source_line_id,
           requested_supplier_batch_number, requested_manufacturing_date,
           requested_expiration_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>(stableLineId),
        Variable<String>(purchaseId),
        Variable<int>(index),
        Variable<String>(_textValue(item['productId'])),
        Variable<String>(_textValue(item['productName'])),
        Variable<double>(_doubleValue(item['quantity'])),
        Variable<double>(_doubleValue(item['unitCost'])),
        Variable<String>(_textValue(item['purchaseUnitId'], fallback: 'base')),
        Variable<String>(_textValue(item['purchaseUnitName'])),
        Variable<double>(_doubleValue(item['conversionToBase'], fallback: 1)),
        Variable<double>(_doubleValue(
          item['originalUnitCost'],
          fallback: _doubleValue(item['unitCost']),
        )),
        Variable<String>(
          _textValue(item['unitCostCurrency'], fallback: 'USD'),
        ),
        Variable<double>(_doubleValue(item['exchangeRateAtEntry'])),
        Variable<String>(_textValue(item['sourceLineId'])),
        Variable<String>(
            _textValue(requestedAllocation?['supplierBatchNumber'])),
        Variable<String>(
            _dateString(requestedAllocation?['manufacturingDate']) ?? ''),
        Variable<String>(
            _dateString(requestedAllocation?['expirationDate']) ?? ''),
      ],
    );
    for (var batchIndex = 0;
        batchIndex < batchAllocations.length;
        batchIndex += 1) {
      final allocation = batchAllocations[batchIndex];
      final batchId = _textValue(allocation['batchId']);
      if (batchId.isEmpty) continue;
      await db.customInsert(
        '''
          INSERT OR REPLACE INTO purchase_item_batch_allocations
            (id, purchase_item_id, line_no, batch_id, quantity,
             supplier_batch_number, manufacturing_date, expiration_date)
          SELECT ?, ?, ?, ?, ?, ?, ?, ?
          WHERE EXISTS (SELECT 1 FROM inventory_batches WHERE id = ?)
          ''',
        variables: <Variable<Object>>[
          Variable<String>('$stableLineId:batch:$batchIndex'),
          Variable<String>(stableLineId),
          Variable<int>(batchIndex),
          Variable<String>(batchId),
          Variable<double>(_doubleValue(allocation['quantity'])),
          Variable<String>(_textValue(allocation['supplierBatchNumber'])),
          Variable<String>(_dateString(allocation['manufacturingDate']) ?? ''),
          Variable<String>(_dateString(allocation['expirationDate']) ?? ''),
          Variable<String>(batchId),
        ],
      );
    }
  }
}

Future<void> _insertInventoryCountLines(
  VentioDriftDatabase db, {
  required String inventoryCountId,
  required Object? linesValue,
}) async {
  final lines = _payloadMapList(linesValue);
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    await db.customInsert(
      '''
        INSERT OR REPLACE INTO inventory_count_lines
          (id, inventory_count_id, line_no, product_id, product_name,
           product_code, snapshot_stock, counted_qty, counted_at, counted_by,
           note, system_qty_at_approval, difference_qty, unit_cost,
           difference_value, stock_movement_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>('$inventoryCountId:$index'),
        Variable<String>(inventoryCountId),
        Variable<int>(index),
        Variable<String>(_textValue(line['productId'])),
        Variable<String>(_textValue(line['productName'])),
        Variable<String>(_textValue(line['productCode'])),
        Variable<double>(_doubleValue(line['snapshotStock'])),
        Variable<double>(_doubleValue(line['countedQty'])),
        Variable<String>(_dateString(line['countedAt']) ?? ''),
        Variable<String>(_textValue(line['countedBy'])),
        Variable<String>(_textValue(line['note'])),
        Variable<double>(_doubleValue(line['systemQtyAtApproval'])),
        Variable<double>(_doubleValue(line['differenceQty'])),
        Variable<double>(_doubleValue(line['unitCost'])),
        Variable<double>(_doubleValue(line['differenceValue'])),
        Variable<String>(_textValue(line['stockMovementId'])),
      ],
    );
  }
}

Future<void> _insertBillOfMaterialsLines(
  VentioDriftDatabase db, {
  required String billOfMaterialId,
  required Object? linesValue,
}) async {
  final lines = _payloadMapList(linesValue);
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    await db.customInsert(
      '''
        INSERT OR REPLACE INTO bill_of_materials_lines
          (id, bill_of_material_id, line_no, product_id, product_name,
           quantity, unit_cost)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
      variables: <Variable<Object>>[
        Variable<String>('$billOfMaterialId:$index'),
        Variable<String>(billOfMaterialId),
        Variable<int>(index),
        Variable<String>(_textValue(line['productId'])),
        Variable<String>(_textValue(line['productName'])),
        Variable<double>(_doubleValue(line['quantity'])),
        Variable<double>(_doubleValue(line['unitCost'])),
      ],
    );
  }
}

List<Map<String, dynamic>> _payloadMapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

Future<void> _migrateComplexTables(VentioDriftDatabase db) async {
  final tables = <String,
      Future<void> Function(Map<String, dynamic> payload, int sortIndex)>{
    productsKey: (payload, sortIndex) async {
      await _upsertProductPayload(
        db,
        _tableByKey[productsKey]!,
        _entityTypeByKey[productsKey]!,
        payload,
        id: payload['id']?.toString() ?? '',
        payloadJson: jsonEncode(payload),
        createdAt: _dateString(payload['createdAt']) ??
            _dateString(payload['date']) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: _dateString(payload['updatedAt']) ??
            _dateString(payload['createdAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        deletedAt: _dateString(payload['deletedAt']) ?? '',
        sortIndex: sortIndex,
      );
    },
    salesKey: (payload, sortIndex) async {
      await _upsertSalePayload(
        db,
        _tableByKey[salesKey]!,
        _entityTypeByKey[salesKey]!,
        payload,
        id: payload['id']?.toString() ?? '',
        payloadJson: jsonEncode(payload),
        createdAt: _dateString(payload['createdAt']) ??
            _dateString(payload['date']) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: _dateString(payload['updatedAt']) ??
            _dateString(payload['createdAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        deletedAt: _dateString(payload['deletedAt']) ?? '',
        sortIndex: sortIndex,
      );
    },
    saleQuotationsKey: (payload, sortIndex) async {
      await _upsertSaleQuotationPayload(
        db,
        _tableByKey[saleQuotationsKey]!,
        _entityTypeByKey[saleQuotationsKey]!,
        payload,
        id: payload['id']?.toString() ?? '',
        payloadJson: jsonEncode(payload),
        createdAt: _dateString(payload['createdAt']) ??
            _dateString(payload['date']) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: _dateString(payload['updatedAt']) ??
            _dateString(payload['createdAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        deletedAt: _dateString(payload['deletedAt']) ?? '',
        sortIndex: sortIndex,
      );
    },
    deliveryNotesKey: (payload, sortIndex) async {
      await _upsertDeliveryNotePayload(
        db,
        _tableByKey[deliveryNotesKey]!,
        _entityTypeByKey[deliveryNotesKey]!,
        payload,
        id: payload['id']?.toString() ?? '',
        payloadJson: jsonEncode(payload),
        createdAt: _dateString(payload['createdAt']) ??
            _dateString(payload['date']) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: _dateString(payload['updatedAt']) ??
            _dateString(payload['createdAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        deletedAt: _dateString(payload['deletedAt']) ?? '',
        sortIndex: sortIndex,
      );
    },
    purchasesKey: (payload, sortIndex) async {
      await _upsertPurchasePayload(
        db,
        _tableByKey[purchasesKey]!,
        _entityTypeByKey[purchasesKey]!,
        payload,
        id: payload['id']?.toString() ?? '',
        payloadJson: jsonEncode(payload),
        createdAt: _dateString(payload['createdAt']) ??
            _dateString(payload['date']) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: _dateString(payload['updatedAt']) ??
            _dateString(payload['createdAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        deletedAt: _dateString(payload['deletedAt']) ?? '',
        sortIndex: sortIndex,
      );
    },
    inventoryCountsKey: (payload, sortIndex) async {
      await _upsertInventoryCountPayload(
        db,
        _tableByKey[inventoryCountsKey]!,
        _entityTypeByKey[inventoryCountsKey]!,
        payload,
        id: payload['id']?.toString() ?? '',
        payloadJson: jsonEncode(payload),
        createdAt: _dateString(payload['createdAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: _dateString(payload['updatedAt']) ??
            _dateString(payload['createdAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        deletedAt: _dateString(payload['deletedAt']) ?? '',
        sortIndex: sortIndex,
      );
    },
    billsOfMaterialsKey: (payload, sortIndex) async {
      await _upsertBillOfMaterialsPayload(
        db,
        _tableByKey[billsOfMaterialsKey]!,
        _entityTypeByKey[billsOfMaterialsKey]!,
        payload,
        id: payload['id']?.toString() ?? '',
        payloadJson: jsonEncode(payload),
        createdAt: _dateString(payload['createdAt']) ??
            _dateString(payload['updatedAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: _dateString(payload['updatedAt']) ??
            _dateString(payload['createdAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        deletedAt: _dateString(payload['deletedAt']) ?? '',
        sortIndex: sortIndex,
      );
    },
    manufacturingOrdersKey: (payload, sortIndex) async {
      await _upsertManufacturingOrderPayload(
        db,
        _tableByKey[manufacturingOrdersKey]!,
        _entityTypeByKey[manufacturingOrdersKey]!,
        payload,
        id: payload['id']?.toString() ?? '',
        payloadJson: jsonEncode(payload),
        createdAt: _dateString(payload['createdAt']) ??
            _dateString(payload['date']) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: _dateString(payload['updatedAt']) ??
            _dateString(payload['createdAt']) ??
            DateTime.now().toUtc().toIso8601String(),
        deletedAt: _dateString(payload['deletedAt']) ?? '',
        sortIndex: sortIndex,
      );
    },
  };

  for (final entry in tables.entries) {
    final table = _tableByKey[entry.key]!;
    final rows = await db.customSelect('''
        SELECT payload_json, sort_index
        FROM $table
        ORDER BY sort_index ASC, updated_at ASC, id ASC
      ''').get();
    for (final row in rows) {
      final raw = row.read<String>('payload_json');
      if (raw.trim().isEmpty) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      await entry.value(
        Map<String, dynamic>.from(decoded),
        row.read<int>('sort_index'),
      );
    }
  }
}
