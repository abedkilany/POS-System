part of 'business_sqlite_store_impl.dart';

Future<List<Sale>> readSales(VentioDriftDatabase db) async {
  final hasWarehouseColumns =
      await _tableHasColumn(db, 'sales', 'warehouse_id') &&
          await _tableHasColumn(db, 'sales', 'warehouse_name');
  final warehouseSelect = hasWarehouseColumns
      ? 'note, warehouse_id AS warehouseId,\n             warehouse_name AS warehouseName'
      : 'note';
  final saleRows = await db.customSelect('''
      SELECT id, invoice_no AS invoiceNo, customer_name AS customerName,
             customer_id AS customerId, document_date AS date,
             status, discount, original_discount AS originalDiscount,
             discount_currency AS discountCurrency,
             discount_exchange_rate_at_entry AS discountExchangeRateAtEntry,
             payment_method AS paymentMethod,
             payment_status AS paymentStatus,
             invoice_currency AS invoiceCurrency,
             payment_currency AS paymentCurrency,
             exchange_rate_at_payment AS exchangeRateAtPayment,
             base_currency AS baseCurrency,
             exchange_rate_at_invoice AS exchangeRateAtInvoice,
             transaction_amount AS transactionAmount,
             base_amount AS baseAmount,
             paid_base_amount AS paidBaseAmount,
             exchange_difference_amount AS exchangeDifferenceAmount,
             paid_amount AS paidAmount,
             cash_received_amount AS cashReceivedAmount,
             paid_amount_in_payment_currency AS paidAmountInPaymentCurrency,
             cash_received_amount_in_payment_currency
               AS cashReceivedAmountInPaymentCurrency,
             posted_snapshot_json AS postedSnapshotJson,
             $warehouseSelect,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM sales
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
  final itemRows = await db.customSelect('''
      SELECT id, sale_id AS saleId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             unit_price AS unitPrice, quantity, unit_name AS unitName,
             base_quantity AS baseQuantity,
             conversion_to_base AS conversionToBase,
             unit_cost AS unitCost,
             costing_method_at_sale AS costingMethodAtSale,
             cost_currency AS costCurrency,
             cost_exchange_rate AS costExchangeRate
      FROM sale_items
      ORDER BY sale_id ASC, line_no ASC
    ''').get();
  final consumptionRows = await db.customSelect('''
      SELECT id, sale_item_id AS saleItemId, line_no AS lineNo,
             layer_id AS layerId, quantity, unit_cost AS unitCost,
             currency_code AS currencyCode
      FROM sale_item_cost_layer_consumptions
      ORDER BY sale_item_id ASC, line_no ASC
    ''').get();
  final batchAllocationRows = await db.customSelect('''
      SELECT sale_item_id AS saleItemId, line_no AS lineNo,
             batch_id AS batchId, quantity, unit_cost AS unitCost,
             expiration_date AS expirationDate
      FROM sale_item_batch_allocations
      ORDER BY sale_item_id ASC, line_no ASC
    ''').get();

  final consumptionsByItem = <String, List<Map<String, dynamic>>>{};
  for (final row in consumptionRows) {
    final data = Map<String, dynamic>.from(row.data);
    final saleItemId = data['saleItemId']?.toString() ?? '';
    if (saleItemId.isEmpty) continue;
    consumptionsByItem
        .putIfAbsent(
          saleItemId,
          () => <Map<String, dynamic>>[],
        )
        .add(data);
  }
  final batchAllocationsByItem = <String, List<Map<String, dynamic>>>{};
  for (final row in batchAllocationRows) {
    final data = Map<String, dynamic>.from(row.data);
    final saleItemId = data['saleItemId']?.toString() ?? '';
    if (saleItemId.isEmpty) continue;
    batchAllocationsByItem
        .putIfAbsent(saleItemId, () => <Map<String, dynamic>>[])
        .add(data);
  }

  final itemsBySale = <String, List<Map<String, dynamic>>>{};
  for (final row in itemRows) {
    final data = Map<String, dynamic>.from(row.data);
    final saleId = data['saleId']?.toString() ?? '';
    if (saleId.isEmpty) continue;
    final itemId = data['id']?.toString() ?? '';
    data['costLayerConsumptions'] =
        consumptionsByItem[itemId] ?? const <Map<String, dynamic>>[];
    data['batchAllocations'] =
        batchAllocationsByItem[itemId] ?? const <Map<String, dynamic>>[];
    itemsBySale.putIfAbsent(saleId, () => <Map<String, dynamic>>[]).add(data);
  }

  return saleRows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    final postedSnapshotRaw =
        data.remove('postedSnapshotJson')?.toString() ?? '';
    if (postedSnapshotRaw.trim().isNotEmpty) {
      try {
        final decodedSnapshot = jsonDecode(postedSnapshotRaw);
        if (decodedSnapshot is Map) {
          data['postedSnapshot'] = Map<String, dynamic>.from(decodedSnapshot);
        }
      } catch (_) {}
    }
    data['items'] = itemsBySale[data['id']?.toString() ?? ''] ??
        const <Map<String, dynamic>>[];
    return Sale.fromJson(data);
  }).toList(growable: false);
}

Future<List<Sale>> readSalesByIds(
  VentioDriftDatabase db,
  List<String> ids,
) {
  if (ids.isEmpty) return Future.value(const <Sale>[]);
  return _readSalesByIds(db, ids);
}

Future<List<Sale>> queryEligibleDeliveryNoteSales(
  VentioDriftDatabase db, {
  int limit = 100,
}) async {
  final safeLimit = _safeLimit(limit);
  final rows = await db.customSelect('''
      SELECT s.id
      FROM sales s
      WHERE s.deleted_at = ''
        AND lower(s.status) NOT IN ('cancelled', 'canceled')
        AND NOT EXISTS (
          SELECT 1
          FROM delivery_notes dn
          WHERE dn.sale_id = s.id AND dn.deleted_at = ''
        )
      ORDER BY s.document_date DESC, s.updated_at DESC, s.id DESC
      LIMIT ?
    ''', variables: <Variable<Object>>[
    Variable<int>(safeLimit),
  ]).get();
  final ids = rows
      .map((row) => row.read<String>('id'))
      .where((id) => id.trim().isNotEmpty)
      .toList(growable: false);
  if (ids.isEmpty) return const <Sale>[];
  final sales = await _readSalesByIds(db, ids);
  final byId = <String, Sale>{for (final sale in sales) sale.id: sale};
  return ids.map((id) => byId[id]).whereType<Sale>().toList(growable: false);
}

Future<List<Sale>> _readSalesByIds(
  VentioDriftDatabase db,
  List<String> ids,
) async {
  final placeholders = _inPlaceholders(ids.length);
  final variables = ids.map((id) => Variable<String>(id)).toList();
  final hasWarehouseColumns =
      await _tableHasColumn(db, 'sales', 'warehouse_id') &&
          await _tableHasColumn(db, 'sales', 'warehouse_name');
  final warehouseSelect = hasWarehouseColumns
      ? 'note, warehouse_id AS warehouseId,\n             warehouse_name AS warehouseName'
      : 'note';
  final saleRows = await db.customSelect('''
      SELECT id, invoice_no AS invoiceNo, customer_name AS customerName,
             customer_id AS customerId, document_date AS date,
             status, discount, original_discount AS originalDiscount,
             discount_currency AS discountCurrency,
             discount_exchange_rate_at_entry AS discountExchangeRateAtEntry,
             payment_method AS paymentMethod,
             payment_status AS paymentStatus,
             invoice_currency AS invoiceCurrency,
             payment_currency AS paymentCurrency,
             exchange_rate_at_payment AS exchangeRateAtPayment,
             base_currency AS baseCurrency,
             exchange_rate_at_invoice AS exchangeRateAtInvoice,
             transaction_amount AS transactionAmount,
             base_amount AS baseAmount,
             paid_base_amount AS paidBaseAmount,
             exchange_difference_amount AS exchangeDifferenceAmount,
             paid_amount AS paidAmount,
             cash_received_amount AS cashReceivedAmount,
             paid_amount_in_payment_currency
               AS paidAmountInPaymentCurrency,
             cash_received_amount_in_payment_currency
               AS cashReceivedAmountInPaymentCurrency,
             posted_snapshot_json AS postedSnapshotJson,
             $warehouseSelect,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM sales
      WHERE id IN ($placeholders)
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''', variables: variables).get();
  final itemRows = await db.customSelect('''
      SELECT id, sale_id AS saleId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             unit_price AS unitPrice, quantity, unit_name AS unitName,
             base_quantity AS baseQuantity,
             conversion_to_base AS conversionToBase,
             unit_cost AS unitCost,
             costing_method_at_sale AS costingMethodAtSale,
             cost_currency AS costCurrency,
             cost_exchange_rate AS costExchangeRate
      FROM sale_items
      WHERE sale_id IN ($placeholders)
      ORDER BY sale_id ASC, line_no ASC
    ''', variables: variables).get();
  final consumptionRows = await db.customSelect('''
      SELECT id, sale_item_id AS saleItemId, line_no AS lineNo,
             layer_id AS layerId, quantity, unit_cost AS unitCost,
             currency_code AS currencyCode
      FROM sale_item_cost_layer_consumptions
      WHERE sale_item_id IN (
        SELECT id FROM sale_items WHERE sale_id IN ($placeholders)
      )
      ORDER BY sale_item_id ASC, line_no ASC
    ''', variables: variables).get();

  final batchAllocationRows = await db.customSelect('''
      SELECT sale_item_id AS saleItemId, line_no AS lineNo,
             batch_id AS batchId, quantity, unit_cost AS unitCost,
             expiration_date AS expirationDate
      FROM sale_item_batch_allocations
      WHERE sale_item_id IN (
        SELECT id FROM sale_items WHERE sale_id IN ($placeholders)
      )
      ORDER BY sale_item_id ASC, line_no ASC
    ''', variables: variables).get();

  final consumptionsByItem = <String, List<Map<String, dynamic>>>{};
  for (final row in consumptionRows) {
    final data = Map<String, dynamic>.from(row.data);
    final saleItemId = data['saleItemId']?.toString() ?? '';
    if (saleItemId.isEmpty) continue;
    consumptionsByItem
        .putIfAbsent(saleItemId, () => <Map<String, dynamic>>[])
        .add(data);
  }

  final batchAllocationsByItem = <String, List<Map<String, dynamic>>>{};
  for (final row in batchAllocationRows) {
    final data = Map<String, dynamic>.from(row.data);
    final saleItemId = data['saleItemId']?.toString() ?? '';
    if (saleItemId.isEmpty) continue;
    batchAllocationsByItem
        .putIfAbsent(saleItemId, () => <Map<String, dynamic>>[])
        .add(data);
  }

  final itemsBySale = <String, List<Map<String, dynamic>>>{};
  for (final row in itemRows) {
    final data = Map<String, dynamic>.from(row.data);
    final saleId = data['saleId']?.toString() ?? '';
    if (saleId.isEmpty) continue;
    final itemId = data['id']?.toString() ?? '';
    data['costLayerConsumptions'] =
        consumptionsByItem[itemId] ?? const <Map<String, dynamic>>[];
    data['batchAllocations'] =
        batchAllocationsByItem[itemId] ?? const <Map<String, dynamic>>[];
    itemsBySale.putIfAbsent(saleId, () => <Map<String, dynamic>>[]).add(data);
  }

  final salesById = <String, Sale>{};
  for (final row in saleRows) {
    final data = Map<String, dynamic>.from(row.data);
    final postedSnapshotRaw =
        data.remove('postedSnapshotJson')?.toString() ?? '';
    if (postedSnapshotRaw.trim().isNotEmpty) {
      try {
        final decodedSnapshot = jsonDecode(postedSnapshotRaw);
        if (decodedSnapshot is Map) {
          data['postedSnapshot'] = Map<String, dynamic>.from(decodedSnapshot);
        }
      } catch (_) {}
    }
    data['items'] = itemsBySale[data['id']?.toString() ?? ''] ??
        const <Map<String, dynamic>>[];
    final sale = Sale.fromJson(data);
    salesById[sale.id] = sale;
  }
  return [
    for (final id in ids)
      if (salesById[id] != null) salesById[id]!,
  ];
}

_SqlFilter _saleFilter({
  String query = '',
  String status = 'all',
  String customerId = '',
  DateTime? from,
  DateTime? to,
}) {
  final conditions = <String>["deleted_at = ''"];
  final variables = <Variable<Object>>[];
  final normalizedStatus = status.trim().toLowerCase();
  if (normalizedStatus.isNotEmpty && normalizedStatus != 'all') {
    conditions.add('lower(status) = ?');
    variables.add(Variable<String>(normalizedStatus));
  }
  final normalizedCustomerId = customerId.trim();
  if (normalizedCustomerId.isNotEmpty) {
    conditions.add('customer_id = ?');
    variables.add(Variable<String>(normalizedCustomerId));
  }
  if (from != null) {
    conditions.add('document_date >= ?');
    variables.add(Variable<String>(_iso(from.toLocal())));
  }
  if (to != null) {
    conditions.add('document_date < ?');
    variables.add(
      Variable<String>(_iso(to.toLocal().add(const Duration(days: 1)))),
    );
  }
  final normalized = query.trim().toLowerCase();
  if (normalized.isNotEmpty) {
    conditions.add(
      "id IN (SELECT entity_id FROM search_index WHERE entity_type = 'sale' AND search_text LIKE ?)",
    );
    variables.add(Variable<String>(_likePattern(normalized)));
  }
  return _SqlFilter(
    whereSql: conditions.join(' AND '),
    variables: variables,
  );
}

String _saleOrderBy(String sortMode) {
  switch (sortMode.trim().toLowerCase()) {
    case 'oldest':
      return 'document_date ASC, updated_at ASC, id ASC';
    case 'highest':
      return 'CASE WHEN lower(status) IN (\'cancelled\', \'returned\') THEN 0 ELSE transaction_amount END DESC, document_date DESC, updated_at DESC, id DESC';
    case 'lowest':
      return 'CASE WHEN lower(status) IN (\'cancelled\', \'returned\') THEN 0 ELSE transaction_amount END ASC, document_date DESC, updated_at DESC, id DESC';
    case 'customer':
      return 'lower(customer_name) ASC, document_date DESC, updated_at DESC, id DESC';
    case 'newest':
    default:
      return 'document_date DESC, updated_at DESC, id DESC';
  }
}

String _saleSummaryOrderBy(String sortMode) {
  switch (sortMode.trim().toLowerCase()) {
    case 'oldest':
      return 'date ASC, id ASC';
    case 'highest':
      return 'total DESC, date DESC, id DESC';
    case 'lowest':
      return 'total ASC, date DESC, id DESC';
    case 'customer':
      return 'lower(customerName) ASC, date DESC, id DESC';
    case 'newest':
    default:
      return 'date DESC, id DESC';
  }
}

Future<BusinessQueryPage<Sale>> querySales(
  VentioDriftDatabase db, {
  String query = '',
  String status = 'all',
  String customerId = '',
  DateTime? from,
  DateTime? to,
  int limit = 50,
  int offset = 0,
  String sortMode = 'newest',
}) async {
  final filter = _saleFilter(
    query: query,
    status: status,
    customerId: customerId,
    from: from,
    to: to,
  );
  final safeLimit = _safeLimit(limit);
  final safeOffset = _safeOffset(offset);
  final usesTextSearch = query.trim().isNotEmpty;
  final queryLimit = usesTextSearch ? safeLimit + 1 : safeLimit;
  final totalFuture = usesTextSearch
      ? null
      : _countWhere(db, 'sales', filter.whereSql, filter.variables);
  final orderBy = _saleOrderBy(sortMode);
  final rows = await db.customSelect('''
      SELECT id
      FROM sales
      WHERE ${filter.whereSql}
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''', variables: <Variable<Object>>[
    ...filter.variables,
    Variable<int>(queryLimit),
    Variable<int>(safeOffset),
  ]).get();
  final hasMoreSearchRows = usesTextSearch && rows.length > safeLimit;
  final pageRows =
      hasMoreSearchRows ? rows.take(safeLimit).toList(growable: false) : rows;
  final ids = pageRows
      .map((row) => row.read<String>('id'))
      .where((value) => value.trim().isNotEmpty)
      .toList(growable: false);
  final items = await readSalesByIds(db, ids);
  return BusinessQueryPage<Sale>(
    items: items,
    totalCount: usesTextSearch
        ? safeOffset + pageRows.length + (hasMoreSearchRows ? 1 : 0)
        : await totalFuture!,
    limit: safeLimit,
    offset: safeOffset,
  );
}

Future<List<SaleQuotation>> readSaleQuotations(VentioDriftDatabase db) async {
  final quotationRows = await db.customSelect('''
      SELECT id, quotation_no AS quotationNo,
             customer_name AS customerName,
             customer_id AS customerId,
             document_date AS date,
             valid_until AS validUntil,
             status, discount, invoice_currency AS invoiceCurrency,
             note, converted_sale_id AS convertedSaleId,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM sale_quotations
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
  final itemRows = await db.customSelect('''
      SELECT id, sale_quotation_id AS saleQuotationId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             unit_price AS unitPrice, quantity, unit_name AS unitName,
             base_quantity AS baseQuantity,
             conversion_to_base AS conversionToBase,
             unit_cost AS unitCost,
             costing_method_at_sale AS costingMethodAtSale,
             cost_currency AS costCurrency,
             cost_exchange_rate AS costExchangeRate
      FROM sale_quotation_items
      ORDER BY sale_quotation_id ASC, line_no ASC
    ''').get();
  final itemsByQuotation = <String, List<Map<String, dynamic>>>{};
  for (final row in itemRows) {
    final data = Map<String, dynamic>.from(row.data);
    final quotationId = data['saleQuotationId']?.toString() ?? '';
    if (quotationId.isEmpty) continue;
    itemsByQuotation
        .putIfAbsent(
          quotationId,
          () => <Map<String, dynamic>>[],
        )
        .add(data);
  }

  return quotationRows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    data['items'] = itemsByQuotation[data['id']?.toString() ?? ''] ??
        const <Map<String, dynamic>>[];
    return SaleQuotation.fromJson(data);
  }).toList(growable: false);
}

Future<List<DeliveryNote>> readDeliveryNotes(VentioDriftDatabase db) async {
  final deliveryRows = await db.customSelect('''
      SELECT id, delivery_no AS deliveryNo,
             sale_id AS saleId,
             invoice_no AS invoiceNo,
             customer_name AS customerName,
             customer_id AS customerId,
             document_date AS date,
             status, note, delivered_at AS deliveredAt,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM delivery_notes
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
  final itemRows = await db.customSelect('''
      SELECT id, delivery_note_id AS deliveryNoteId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             unit_price AS unitPrice, quantity, unit_name AS unitName,
             base_quantity AS baseQuantity,
             conversion_to_base AS conversionToBase,
             unit_cost AS unitCost,
             costing_method_at_sale AS costingMethodAtSale,
             cost_currency AS costCurrency,
             cost_exchange_rate AS costExchangeRate
      FROM delivery_note_items
      ORDER BY delivery_note_id ASC, line_no ASC
    ''').get();
  final itemsByDelivery = <String, List<Map<String, dynamic>>>{};
  for (final row in itemRows) {
    final data = Map<String, dynamic>.from(row.data);
    final deliveryId = data['deliveryNoteId']?.toString() ?? '';
    if (deliveryId.isEmpty) continue;
    itemsByDelivery
        .putIfAbsent(
          deliveryId,
          () => <Map<String, dynamic>>[],
        )
        .add(data);
  }

  return deliveryRows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    data['items'] = itemsByDelivery[data['id']?.toString() ?? ''] ??
        const <Map<String, dynamic>>[];
    return DeliveryNote.fromJson(data);
  }).toList(growable: false);
}
