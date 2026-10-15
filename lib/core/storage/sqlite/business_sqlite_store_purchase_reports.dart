part of 'business_sqlite_store_impl.dart';

Future<List<Purchase>> readPurchases(VentioDriftDatabase db) async {
  final hasWarehouseColumns =
      await _tableHasColumn(db, 'purchases', 'warehouse_id') &&
          await _tableHasColumn(db, 'purchases', 'warehouse_name');
  final hasPayloadJson = await _tableHasColumn(db, 'purchases', 'payload_json');
  final payloadJsonColumn =
      hasPayloadJson ? 'payload_json AS payloadJson,' : '';
  final purchaseRows = await db.customSelect('''
      SELECT id, purchase_no AS purchaseNo,
             supplier_id AS supplierId,
             supplier_name AS supplierName,
             $payloadJsonColumn
             document_date AS date,
             status, note, payment_status AS paymentStatus,
             payment_method AS paymentMethod,
             paid_amount AS paidAmount,
             document_type AS documentType,
             source_purchase_id AS sourcePurchaseId,
             source_purchase_no AS sourcePurchaseNo,
             cancel_reason AS cancelReason,
             cancelled_by_device_id AS cancelledByDeviceId,
             CASE WHEN reversal_applied = 1 THEN 1 ELSE 0 END AS reversalApplied,
             cancelled_at AS cancelledAt,
             posted_snapshot_json AS postedSnapshotJson,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId${hasWarehouseColumns ? ', warehouse_id AS warehouseId, warehouse_name AS warehouseName' : ''}
      FROM purchases
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
  final itemRows = await db.customSelect('''
      SELECT id, purchase_id AS purchaseId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             source_line_id AS sourceLineId,
             quantity, unit_cost AS unitCost,
             purchase_unit_id AS purchaseUnitId,
             purchase_unit_name AS purchaseUnitName,
             conversion_to_base AS conversionToBase,
             original_unit_cost AS originalUnitCost,
             unit_cost_currency AS unitCostCurrency,
             exchange_rate_at_entry AS exchangeRateAtEntry,
             requested_supplier_batch_number AS requestedSupplierBatchNumber,
             requested_manufacturing_date AS requestedManufacturingDate,
             requested_expiration_date AS requestedExpirationDate
      FROM purchase_items
      ORDER BY purchase_id ASC, line_no ASC
    ''').get();
  final batchAllocationRows = await db.customSelect('''
      SELECT purchase_item_id AS purchaseItemId, line_no AS lineNo,
             batch_id AS batchId, quantity,
             supplier_batch_number AS supplierBatchNumber,
             manufacturing_date AS manufacturingDate,
             expiration_date AS expirationDate
      FROM purchase_item_batch_allocations
      ORDER BY purchase_item_id ASC, line_no ASC
    ''').get();
  final batchAllocationsByItem = <String, List<Map<String, dynamic>>>{};
  for (final row in batchAllocationRows) {
    final data = Map<String, dynamic>.from(row.data);
    final purchaseItemId = data['purchaseItemId']?.toString() ?? '';
    if (purchaseItemId.isEmpty) continue;
    batchAllocationsByItem
        .putIfAbsent(purchaseItemId, () => <Map<String, dynamic>>[])
        .add(data);
  }

  final itemsByPurchase = <String, List<Map<String, dynamic>>>{};
  for (final row in itemRows) {
    final data = Map<String, dynamic>.from(row.data);
    final purchaseId = data['purchaseId']?.toString() ?? '';
    if (purchaseId.isEmpty) continue;
    final itemId = data['id']?.toString() ?? '';
    data['lineId'] = itemId;
    final persistedBatches =
        batchAllocationsByItem[itemId] ?? const <Map<String, dynamic>>[];
    if (persistedBatches.isNotEmpty) {
      data['batchAllocations'] = persistedBatches;
    } else if ((data['requestedExpirationDate']?.toString().trim().isNotEmpty ??
            false) ||
        (data['requestedSupplierBatchNumber']?.toString().trim().isNotEmpty ??
            false) ||
        (data['requestedManufacturingDate']?.toString().trim().isNotEmpty ??
            false)) {
      data['batchAllocations'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'batchId': '',
          'quantity': ((data['quantity'] as num? ?? 0).toDouble()) *
              ((data['conversionToBase'] as num? ?? 1).toDouble()),
          'supplierBatchNumber': data['requestedSupplierBatchNumber'] ?? '',
          'manufacturingDate': data['requestedManufacturingDate'] ?? '',
          'expirationDate': data['requestedExpirationDate'] ?? '',
        }
      ];
    } else {
      data['batchAllocations'] = const <Map<String, dynamic>>[];
    }
    itemsByPurchase
        .putIfAbsent(
          purchaseId,
          () => <Map<String, dynamic>>[],
        )
        .add(data);
  }

  return purchaseRows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    data['reversalApplied'] =
        data['reversalApplied'] == 1 || data['reversalApplied'] == true;
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
    if (hasPayloadJson &&
        (data['warehouseId'] == null ||
            data['warehouseId'].toString().isEmpty) &&
        data['payloadJson']?.toString().isNotEmpty == true) {
      try {
        final payload = Map<String, dynamic>.from(
            jsonDecode(data['payloadJson'].toString()));
        data['warehouseId'] =
            payload['warehouseId']?.toString().isNotEmpty == true
                ? payload['warehouseId']
                : 'main';
        data['warehouseName'] =
            payload['warehouseName']?.toString().isNotEmpty == true
                ? payload['warehouseName']
                : 'Main warehouse';
      } catch (_) {}
    }
    data['items'] = itemsByPurchase[data['id']?.toString() ?? ''] ??
        const <Map<String, dynamic>>[];
    return Purchase.fromJson(data);
  }).toList(growable: false);
}

Future<List<Purchase>> readPurchasesByIds(
  VentioDriftDatabase db,
  List<String> ids,
) {
  if (ids.isEmpty) return Future.value(const <Purchase>[]);
  return _readPurchasesByIds(db, ids);
}

Future<List<Purchase>> _readPurchasesByIds(
  VentioDriftDatabase db,
  List<String> ids,
) async {
  final hasWarehouseColumns =
      await _tableHasColumn(db, 'purchases', 'warehouse_id') &&
          await _tableHasColumn(db, 'purchases', 'warehouse_name');
  final hasPayloadJson = await _tableHasColumn(db, 'purchases', 'payload_json');
  final payloadJsonColumn =
      hasPayloadJson ? 'payload_json AS payloadJson,' : '';
  final placeholders = _inPlaceholders(ids.length);
  final variables = ids.map((id) => Variable<String>(id)).toList();
  final purchaseRows = await db.customSelect('''
      SELECT id, purchase_no AS purchaseNo,
             supplier_id AS supplierId,
             supplier_name AS supplierName,
             $payloadJsonColumn
             document_date AS date,
             status, note, payment_status AS paymentStatus,
             payment_method AS paymentMethod,
             paid_amount AS paidAmount,
             document_type AS documentType,
             source_purchase_id AS sourcePurchaseId,
             source_purchase_no AS sourcePurchaseNo,
             cancel_reason AS cancelReason,
             cancelled_by_device_id AS cancelledByDeviceId,
             CASE WHEN reversal_applied = 1 THEN 1 ELSE 0 END AS reversalApplied,
             cancelled_at AS cancelledAt,
             posted_snapshot_json AS postedSnapshotJson,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId${hasWarehouseColumns ? ', warehouse_id AS warehouseId, warehouse_name AS warehouseName' : ''}
       FROM purchases
       WHERE id IN ($placeholders)
       ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''', variables: variables).get();
  final itemRows = await db.customSelect('''
      SELECT id, purchase_id AS purchaseId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             source_line_id AS sourceLineId,
             quantity, unit_cost AS unitCost,
             purchase_unit_id AS purchaseUnitId,
             purchase_unit_name AS purchaseUnitName,
             conversion_to_base AS conversionToBase,
             original_unit_cost AS originalUnitCost,
             unit_cost_currency AS unitCostCurrency,
             exchange_rate_at_entry AS exchangeRateAtEntry,
             requested_supplier_batch_number AS requestedSupplierBatchNumber,
             requested_manufacturing_date AS requestedManufacturingDate,
             requested_expiration_date AS requestedExpirationDate
      FROM purchase_items
      WHERE purchase_id IN ($placeholders)
      ORDER BY purchase_id ASC, line_no ASC
    ''', variables: variables).get();
  final batchAllocationRows = await db.customSelect('''
      SELECT purchase_item_id AS purchaseItemId, line_no AS lineNo,
             batch_id AS batchId, quantity,
             supplier_batch_number AS supplierBatchNumber,
             manufacturing_date AS manufacturingDate,
             expiration_date AS expirationDate
      FROM purchase_item_batch_allocations
      WHERE purchase_item_id IN (
        SELECT id FROM purchase_items WHERE purchase_id IN ($placeholders)
      )
      ORDER BY purchase_item_id ASC, line_no ASC
    ''', variables: variables).get();
  final batchAllocationsByItem = <String, List<Map<String, dynamic>>>{};
  for (final row in batchAllocationRows) {
    final data = Map<String, dynamic>.from(row.data);
    final purchaseItemId = data['purchaseItemId']?.toString() ?? '';
    if (purchaseItemId.isEmpty) continue;
    batchAllocationsByItem
        .putIfAbsent(purchaseItemId, () => <Map<String, dynamic>>[])
        .add(data);
  }
  final itemsByPurchase = <String, List<Map<String, dynamic>>>{};
  for (final row in itemRows) {
    final data = Map<String, dynamic>.from(row.data);
    final purchaseId = data['purchaseId']?.toString() ?? '';
    if (purchaseId.isEmpty) continue;
    final itemId = data['id']?.toString() ?? '';
    data['lineId'] = itemId;
    final persistedBatches =
        batchAllocationsByItem[itemId] ?? const <Map<String, dynamic>>[];
    if (persistedBatches.isNotEmpty) {
      data['batchAllocations'] = persistedBatches;
    } else if ((data['requestedExpirationDate']?.toString().trim().isNotEmpty ??
            false) ||
        (data['requestedSupplierBatchNumber']?.toString().trim().isNotEmpty ??
            false) ||
        (data['requestedManufacturingDate']?.toString().trim().isNotEmpty ??
            false)) {
      data['batchAllocations'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'batchId': '',
          'quantity': ((data['quantity'] as num? ?? 0).toDouble()) *
              ((data['conversionToBase'] as num? ?? 1).toDouble()),
          'supplierBatchNumber': data['requestedSupplierBatchNumber'] ?? '',
          'manufacturingDate': data['requestedManufacturingDate'] ?? '',
          'expirationDate': data['requestedExpirationDate'] ?? '',
        }
      ];
    } else {
      data['batchAllocations'] = const <Map<String, dynamic>>[];
    }
    itemsByPurchase
        .putIfAbsent(purchaseId, () => <Map<String, dynamic>>[])
        .add(data);
  }

  final purchasesById = <String, Purchase>{};
  for (final row in purchaseRows) {
    final data = Map<String, dynamic>.from(row.data);
    data['reversalApplied'] =
        data['reversalApplied'] == 1 || data['reversalApplied'] == true;
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
    if (hasPayloadJson &&
        (data['warehouseId'] == null ||
            data['warehouseId'].toString().isEmpty) &&
        data['payloadJson']?.toString().isNotEmpty == true) {
      try {
        final payload = Map<String, dynamic>.from(
            jsonDecode(data['payloadJson'].toString()));
        data['warehouseId'] =
            payload['warehouseId']?.toString().isNotEmpty == true
                ? payload['warehouseId']
                : 'main';
        data['warehouseName'] =
            payload['warehouseName']?.toString().isNotEmpty == true
                ? payload['warehouseName']
                : 'Main warehouse';
      } catch (_) {}
    }
    data['items'] = itemsByPurchase[data['id']?.toString() ?? ''] ??
        const <Map<String, dynamic>>[];
    final purchase = Purchase.fromJson(data);
    purchasesById[purchase.id] = purchase;
  }
  return [
    for (final id in ids)
      if (purchasesById[id] != null) purchasesById[id]!,
  ];
}

_SqlFilter _purchaseFilter({
  String query = '',
  String status = 'all',
  String supplierId = '',
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
  final normalizedSupplierId = supplierId.trim();
  if (normalizedSupplierId.isNotEmpty) {
    conditions.add('supplier_id = ?');
    variables.add(Variable<String>(normalizedSupplierId));
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
      '''(
          lower(purchase_no) LIKE ? OR lower(supplier_name) LIKE ? OR
          lower(payment_method) LIKE ? OR lower(payment_status) LIKE ? OR
          lower(status) LIKE ? OR lower(source_purchase_no) LIKE ? OR
          EXISTS (
            SELECT 1 FROM purchase_items
            WHERE purchase_items.purchase_id = purchases.id
              AND lower(product_name) LIKE ?
          )
        )''',
    );
    final pattern = _likePattern(normalized);
    for (var i = 0; i < 7; i += 1) {
      variables.add(Variable<String>(pattern));
    }
  }
  return _SqlFilter(
    whereSql: conditions.join(' AND '),
    variables: variables,
  );
}

String _purchaseOrderBy(String sortMode) {
  switch (sortMode.trim().toLowerCase()) {
    case 'oldest':
      return 'document_date ASC, updated_at ASC, id ASC';
    case 'highest':
      return 'CASE WHEN lower(status) IN (\'cancelled\', \'returned\') THEN 0 ELSE (SELECT COALESCE(SUM(quantity * unit_cost), 0) FROM purchase_items WHERE purchase_items.purchase_id = purchases.id) END DESC, document_date DESC, updated_at DESC, id DESC';
    case 'lowest':
      return 'CASE WHEN lower(status) IN (\'cancelled\', \'returned\') THEN 0 ELSE (SELECT COALESCE(SUM(quantity * unit_cost), 0) FROM purchase_items WHERE purchase_items.purchase_id = purchases.id) END ASC, document_date DESC, updated_at DESC, id DESC';
    case 'supplier':
      return 'lower(supplier_name) ASC, document_date DESC, updated_at DESC, id DESC';
    case 'newest':
    default:
      return 'document_date DESC, updated_at DESC, id DESC';
  }
}

Future<BusinessQueryPage<Purchase>> queryPurchases(
  VentioDriftDatabase db, {
  String query = '',
  String status = 'all',
  String supplierId = '',
  DateTime? from,
  DateTime? to,
  int limit = 50,
  int offset = 0,
  String sortMode = 'newest',
}) async {
  final filter = _purchaseFilter(
    query: query,
    status: status,
    supplierId: supplierId,
    from: from,
    to: to,
  );
  final total =
      await _countWhere(db, 'purchases', filter.whereSql, filter.variables);
  final safeLimit = _safeLimit(limit);
  final safeOffset = _safeOffset(offset);
  final orderBy = _purchaseOrderBy(sortMode);
  final rows = await db.customSelect('''
      SELECT id
      FROM purchases
      WHERE ${filter.whereSql}
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''', variables: <Variable<Object>>[
    ...filter.variables,
    Variable<int>(safeLimit),
    Variable<int>(safeOffset),
  ]).get();
  final ids = rows
      .map((row) => row.read<String>('id'))
      .where((value) => value.trim().isNotEmpty)
      .toList(growable: false);
  final items = await readPurchasesByIds(db, ids);
  return BusinessQueryPage<Purchase>(
    items: items,
    totalCount: total,
    limit: safeLimit,
    offset: safeOffset,
  );
}

Future<BusinessQueryPage<SaleSummary>> querySaleSummaries(
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
  final total =
      await _countWhere(db, 'sales', filter.whereSql, filter.variables);
  final safeLimit = _safeLimit(limit);
  final safeOffset = _safeOffset(offset);
  final orderBy = _saleSummaryOrderBy(sortMode);
  final rows = await db.customSelect('''
      SELECT sales.id AS id,
             invoice_no AS invoiceNo,
             customer_name AS customerName,
             customer_id AS customerId,
             document_date AS date,
             status,
             payment_status AS paymentStatus,
             CASE
               WHEN lower(status) IN ('cancelled', 'returned') THEN 0
               ELSE max(COALESCE(SUM(si.unit_price * si.quantity), 0) - discount, 0)
             END AS total,
             COUNT(DISTINCT CASE
               WHEN trim(si.product_id) <> '' THEN si.product_id
             END) AS productCount
      FROM sales
      LEFT JOIN sale_items si ON si.sale_id = sales.id
      WHERE ${filter.whereSql}
      GROUP BY sales.id
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''', variables: <Variable<Object>>[
    ...filter.variables,
    Variable<int>(safeLimit),
    Variable<int>(safeOffset),
  ]).get();
  return BusinessQueryPage<SaleSummary>(
    items: rows
        .map((row) => SaleSummary.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false),
    totalCount: total,
    limit: safeLimit,
    offset: safeOffset,
  );
}

Future<Map<String, Object?>> assistantSalesSummary(
  VentioDriftDatabase db, {
  required DateTime from,
  required DateTime to,
}) async {
  final filter = _saleFilter(from: from, to: to);
  final rows = await db.customSelect('''
      SELECT COALESCE(NULLIF(upper(trim(base_currency)), ''), 'USD')
               AS base_currency,
             COUNT(*) AS invoice_count,
             COALESCE(SUM(CASE WHEN base_amount > 0 THEN base_amount ELSE 0 END), 0)
               AS gross_base_amount,
             SUM(CASE WHEN base_amount <= 0 THEN 1 ELSE 0 END)
               AS missing_base_amount_count
      FROM sales
      WHERE ${filter.whereSql}
        AND lower(status) NOT IN ('cancelled', 'returned')
      GROUP BY COALESCE(NULLIF(upper(trim(base_currency)), ''), 'USD')
      ORDER BY base_currency ASC
    ''', variables: filter.variables).get();
  final totals = await db.customSelect('''
      SELECT COUNT(*) AS invoice_count,
             SUM(CASE WHEN base_amount <= 0 THEN 1 ELSE 0 END)
               AS missing_base_amount_count
      FROM sales
      WHERE ${filter.whereSql}
        AND lower(status) NOT IN ('cancelled', 'returned')
    ''', variables: filter.variables).getSingle();
  return <String, Object?>{
    'invoiceCount': (totals.data['invoice_count'] as num?)?.toInt() ?? 0,
    'missingRecordedBaseAmountCount':
        (totals.data['missing_base_amount_count'] as num?)?.toInt() ?? 0,
    'grossBaseAmountsByCurrency': rows.map((row) {
      return <String, Object?>{
        'currency': row.data['base_currency']?.toString() ?? 'USD',
        'invoiceCount': (row.data['invoice_count'] as num?)?.toInt() ?? 0,
        'grossAmount': (row.data['gross_base_amount'] as num?)?.toDouble() ?? 0,
        'missingRecordedBaseAmountCount':
            (row.data['missing_base_amount_count'] as num?)?.toInt() ?? 0,
      };
    }).toList(growable: false),
  };
}

Future<Map<String, Object?>> assistantPurchaseSummary(
  VentioDriftDatabase db, {
  required DateTime from,
  required DateTime to,
}) async {
  final filter = _purchaseFilter(
    status: 'received',
    from: from,
    to: to,
  );
  final rows = await db.customSelect('''
      SELECT lower(purchases.document_type) AS document_type,
             COUNT(DISTINCT purchases.id) AS document_count,
             COALESCE(SUM(purchase_items.quantity * purchase_items.unit_cost), 0)
               AS amount_usd_reference
      FROM purchases
      LEFT JOIN purchase_items ON purchase_items.purchase_id = purchases.id
      WHERE ${filter.whereSql}
      GROUP BY lower(purchases.document_type)
      ORDER BY document_type ASC
    ''', variables: filter.variables).get();
  final documents = rows.map((row) {
    final documentType = row.data['document_type']?.toString() ?? 'purchase';
    final amountUsdReference =
        (row.data['amount_usd_reference'] as num?)?.toDouble() ?? 0;
    return <String, Object?>{
      'documentType': documentType,
      'documentCount': (row.data['document_count'] as num?)?.toInt() ?? 0,
      'amountUsdReference': amountUsdReference,
      'signedAmountUsdReference': documentType == 'purchase_return'
          ? -amountUsdReference
          : amountUsdReference,
    };
  }).toList(growable: false);
  final purchaseAmount =
      documents.where((row) => row['documentType'] == 'purchase').fold<double>(
            0,
            (sum, row) => sum + (row['amountUsdReference'] as double),
          );
  final purchaseReturnAmount = documents
      .where((row) => row['documentType'] == 'purchase_return')
      .fold<double>(
        0,
        (sum, row) => sum + (row['amountUsdReference'] as double),
      );
  return <String, Object?>{
    'purchaseAmountUsdReference': purchaseAmount,
    'purchaseReturnAmountUsdReference': purchaseReturnAmount,
    'netPurchaseAmountUsdReference': purchaseAmount - purchaseReturnAmount,
    'documents': documents,
  };
}

Future<Map<String, Object?>> buildPurchasesOverview(
  VentioDriftDatabase db, {
  required DateTime reference,
}) async {
  final monthStart = DateTime(reference.year, reference.month);
  final nextMonth = DateTime(reference.year, reference.month + 1);
  final row = await db.customSelect('''
      $_purchaseTotalsCte
      SELECT
        (SELECT COUNT(*) FROM purchases WHERE deleted_at = '') AS totalCount,
        COALESCE(SUM(subtotal), 0) AS totalPurchasesAmount,
        COALESCE(
          SUM(
            CASE
              WHEN document_date >= ? AND document_date < ? THEN subtotal
              ELSE 0
            END
          ),
          0
        ) AS monthlyTotal,
        COALESCE(
          SUM(
            CASE
              WHEN document_date >= ? AND document_date < ?
                   AND document_type <> 'purchase_return' THEN 1
              ELSE 0
            END
          ),
          0
        ) AS monthlyCount,
        COALESCE(
          SUM(
            CASE
              WHEN lower(status) = 'draft' THEN subtotal
              ELSE 0
            END
          ),
          0
        ) AS draftTotal,
        (SELECT COUNT(*) FROM purchases WHERE deleted_at = '' AND lower(status) = 'draft')
          AS draftCount,
        (SELECT COUNT(*) FROM purchases WHERE deleted_at = '' AND lower(status) = 'received'
          AND document_type <> 'purchase_return')
          AS receivedCount,
        (SELECT COUNT(*) FROM purchases WHERE deleted_at = '' AND lower(status) = 'returned')
          AS returnedCount,
        (SELECT COUNT(*) FROM purchases WHERE deleted_at = '' AND lower(status) = 'cancelled')
          AS cancelledCount
      FROM purchase_totals
    ''', variables: <Variable<Object>>[
    Variable<String>(_iso(monthStart)),
    Variable<String>(_iso(nextMonth)),
    Variable<String>(_iso(monthStart)),
    Variable<String>(_iso(nextMonth)),
  ]).getSingle();
  return <String, Object?>{
    'totalCount': _rowInt(row, 'totalCount', fallback: 0),
    'totalPurchasesAmount': _rowDouble(row, 'totalPurchasesAmount'),
    'monthlyTotal': _rowDouble(row, 'monthlyTotal'),
    'monthlyCount': _rowInt(row, 'monthlyCount', fallback: 0),
    'draftTotal': _rowDouble(row, 'draftTotal'),
    'draftCount': _rowInt(row, 'draftCount', fallback: 0),
    'receivedCount': _rowInt(row, 'receivedCount', fallback: 0),
    'returnedCount': _rowInt(row, 'returnedCount', fallback: 0),
    'cancelledCount': _rowInt(row, 'cancelledCount', fallback: 0),
    'pendingPurchaseCount': _rowInt(row, 'draftCount', fallback: 0),
  };
}

Future<List<InventoryCountSession>> readInventoryCounts(
    VentioDriftDatabase db) async {
  final sessionRows = await db.customSelect('''
      SELECT id, count_no AS countNo, created_at AS createdAt,
             created_by AS createdBy, warehouse_id AS warehouseId,
             warehouse_name AS warehouseName, status, notes,
             approved_at AS approvedAt, approved_by AS approvedBy,
             journal_entry_id AS journalEntryId,
             reversal_journal_entry_id AS reversalJournalEntryId,
             reversed_at AS reversedAt, reversed_by AS reversedBy,
             reversal_reason AS reversalReason, updated_at AS updatedAt
      FROM inventory_counts
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
  final lineRows = await db.customSelect('''
      SELECT id, inventory_count_id AS inventoryCountId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             product_code AS productCode, snapshot_stock AS snapshotStock,
             counted_qty AS countedQty, counted_at AS countedAt,
             counted_by AS countedBy, note,
             system_qty_at_approval AS systemQtyAtApproval,
             difference_qty AS differenceQty, unit_cost AS unitCost,
             difference_value AS differenceValue,
             stock_movement_id AS stockMovementId
      FROM inventory_count_lines
      ORDER BY inventory_count_id ASC, line_no ASC
    ''').get();
  final linesByCount = <String, List<Map<String, dynamic>>>{};
  for (final row in lineRows) {
    final data = Map<String, dynamic>.from(row.data);
    final countId = data['inventoryCountId']?.toString() ?? '';
    if (countId.isEmpty) continue;
    linesByCount.putIfAbsent(countId, () => <Map<String, dynamic>>[]).add(data);
  }

  return sessionRows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    data['lines'] = linesByCount[data['id']?.toString() ?? ''] ??
        const <Map<String, dynamic>>[];
    return InventoryCountSession.fromJson(data);
  }).toList(growable: false);
}

Future<List<BillOfMaterials>> readBillOfMaterials(
    VentioDriftDatabase db) async {
  final bomRows = await db.customSelect('''
      SELECT id, name, output_product_id AS outputProductId,
             output_product_name AS outputProductName,
             output_quantity AS outputQuantity,
             notes, CASE WHEN is_active = 1 THEN 1 ELSE 0 END AS isActive,
             created_at AS createdAt, updated_at AS updatedAt,
             deleted_at AS deletedAt, device_id AS deviceId,
             sync_status AS syncStatus, store_id AS storeId,
             branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM bill_of_materials
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
  final lineRows = await db.customSelect('''
      SELECT id, bill_of_material_id AS billOfMaterialId, line_no AS lineNo,
             product_id AS productId, product_name AS productName,
             quantity, unit_cost AS unitCost
      FROM bill_of_materials_lines
      ORDER BY bill_of_material_id ASC, line_no ASC
    ''').get();
  final linesByBom = <String, List<Map<String, dynamic>>>{};
  for (final row in lineRows) {
    final data = Map<String, dynamic>.from(row.data);
    final bomId = data['billOfMaterialId']?.toString() ?? '';
    if (bomId.isEmpty) continue;
    linesByBom.putIfAbsent(bomId, () => <Map<String, dynamic>>[]).add(data);
  }

  return bomRows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    data['isActive'] = data['isActive'] == 1 || data['isActive'] == true;
    data['components'] = linesByBom[data['id']?.toString() ?? ''] ??
        const <Map<String, dynamic>>[];
    return BillOfMaterials.fromJson(data);
  }).toList(growable: false);
}

Future<List<ManufacturingOrder>> readManufacturingOrders(
    VentioDriftDatabase db) async {
  final hasPayloadJson =
      await _tableHasColumn(db, 'manufacturing_orders', 'payload_json');
  final hasWarehouseColumns = await _tableHasColumn(
          db, 'manufacturing_orders', 'raw_materials_warehouse_id') &&
      await _tableHasColumn(
          db, 'manufacturing_orders', 'finished_goods_warehouse_id');
  final payloadJsonColumn =
      hasPayloadJson ? 'payload_json AS payloadJson,' : '';
  final rows = await db.customSelect('''
      SELECT id, order_no AS orderNo, bom_id AS bomId, bom_name AS bomName,
             output_product_id AS outputProductId,
             output_product_name AS outputProductName,
              quantity, ${hasWarehouseColumns ? 'raw_materials_warehouse_id AS rawMaterialsWarehouseId, raw_materials_warehouse_name AS rawMaterialsWarehouseName, finished_goods_warehouse_id AS finishedGoodsWarehouseId, finished_goods_warehouse_name AS finishedGoodsWarehouseName,' : ''} status, notes,
              actual_output_quantity AS actualOutputQuantity,
              total_material_cost AS totalMaterialCost,
              total_waste_cost AS totalWasteCost,
              total_eligible_cost AS totalEligibleCost,
              actual_unit_cost AS actualUnitCost,
              material_costs_json AS materialCostsJson,
              waste_lines_json AS wasteLinesJson,
              journal_entry_id AS journalEntryId,
              reversal_journal_entry_id AS reversalJournalEntryId,
              completed_at AS completedAt, completed_by AS completedBy,
              reversed_at AS reversedAt, reversed_by AS reversedBy,
              reversal_reason AS reversalReason,
             document_date AS date, created_at AS createdAt,
             updated_at AS updatedAt, deleted_at AS deletedAt,
             device_id AS deviceId, sync_status AS syncStatus,
             store_id AS storeId, branch_id AS branchId, version,
             last_modified_by_device_id AS lastModifiedByDeviceId$payloadJsonColumn
      FROM manufacturing_orders
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
  return rows.map((row) {
    final data = Map<String, dynamic>.from(row.data);
    for (final field in <String>['materialCosts', 'wasteLines']) {
      final jsonField = '${field}Json';
      final encoded = data[jsonField]?.toString() ?? '';
      if (encoded.isNotEmpty) {
        try {
          data[field] = jsonDecode(encoded);
        } catch (_) {
          data[field] = const <Map<String, dynamic>>[];
        }
      }
    }
    if (hasPayloadJson &&
        data['rawMaterialsWarehouseId']?.toString().isEmpty != false &&
        data['payloadJson']?.toString().isNotEmpty == true) {
      try {
        final payload = Map<String, dynamic>.from(
            jsonDecode(data['payloadJson'].toString()));
        data['rawMaterialsWarehouseId'] =
            payload['rawMaterialsWarehouseId']?.toString().isNotEmpty == true
                ? payload['rawMaterialsWarehouseId']
                : 'main';
        data['rawMaterialsWarehouseName'] =
            payload['rawMaterialsWarehouseName']?.toString().isNotEmpty == true
                ? payload['rawMaterialsWarehouseName']
                : 'Main warehouse';
        data['finishedGoodsWarehouseId'] =
            payload['finishedGoodsWarehouseId']?.toString().isNotEmpty == true
                ? payload['finishedGoodsWarehouseId']
                : 'main';
        data['finishedGoodsWarehouseName'] =
            payload['finishedGoodsWarehouseName']?.toString().isNotEmpty == true
                ? payload['finishedGoodsWarehouseName']
                : 'Main warehouse';
      } catch (_) {}
    }
    return ManufacturingOrder.fromJson(data);
  }).toList(growable: false);
}

Future<void> saveKeyJson(
    VentioDriftDatabase db, String key, String value) async {
  if (isTypedEntityKey(key)) {
    // Performance fix: normal app saves must be incremental. The old Phase 3B
    // compatibility path deleted the whole entity table and re-inserted every
    // row on every product/customer/sale change, which preserved legacy JSON storage's slow
    // "rewrite the whole list" behavior inside SQLite. Keep local_key_values
    // out of the hot path as well; hydrateKeyMirror rebuilds the JSON mirror
    // from the typed tables on startup.
    await _mergeEntityList(db, key, value);
    return;
  }

  // Settings and scalar app state get their own typed table. local_key_values
  // remains as a compatibility mirror for older diagnostics/exports.
  await db.customInsert(
    '''
      INSERT OR REPLACE INTO settings (key, value, updated_at)
      VALUES (?, ?, ?)
      ''',
    variables: <Variable<Object>>[
      Variable<String>(key),
      Variable<String>(value),
      Variable<String>(DateTime.now().toUtc().toIso8601String()),
    ],
  );
  await _saveLocalMirrorValue(db, key, value);
}

Future<void> upsertEntityPayload(
  VentioDriftDatabase db,
  String key,
  Map<String, dynamic> payload, {
  int? sortIndex,
}) async {
  await upsertEntityPayloads(
    db,
    key,
    <Map<String, dynamic>>[payload],
    sortIndices: <int?>[sortIndex],
  );
}
