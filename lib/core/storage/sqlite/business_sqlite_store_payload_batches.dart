part of 'business_sqlite_store_impl.dart';

Future<void> upsertEntityPayloads(
  VentioDriftDatabase db,
  String key,
  List<Map<String, dynamic>> payloads, {
  List<int?>? sortIndices,
}) async {
  final table = _tableByKey[key];
  final entityType = _entityTypeByKey[key];
  if (table == null || entityType == null) {
    throw ArgumentError('Key $key is not a typed SQLite entity key.');
  }
  if (key == productsKey && payloads.length > 1) {
    await _upsertProductPayloads(
      db,
      table,
      entityType,
      payloads,
      sortIndices: sortIndices,
    );
    return;
  }
  await db.transaction(() async {
    for (var index = 0; index < payloads.length; index += 1) {
      final payload = payloads[index];
      final sortIndex = sortIndices != null && index < sortIndices.length
          ? sortIndices[index]
          : null;
      final now = DateTime.now().toUtc().toIso8601String();
      final explicitId = payload['id']?.toString().trim() ?? '';
      final productCostProductId =
          key == productCostsKey ? _textValue(payload['productId']) : '';
      final id = explicitId.isNotEmpty
          ? explicitId
          : productCostProductId.isNotEmpty
              ? 'product_cost_$productCostProductId'
              : '${entityType}_${now.hashCode}';
      final payloadJson = jsonEncode(payload);
      final createdAt = _dateString(payload['createdAt']) ??
          _dateString(payload['date']) ??
          now;
      final updatedAt = _dateString(payload['updatedAt']) ?? createdAt;
      final deletedAt = _dateString(payload['deletedAt']) ?? '';
      if (key == stockMovementsKey) {
        await _upsertStockMovementPayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == accountTransactionsKey) {
        await _upsertAccountTransactionPayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == customersKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'name': _textValue(payload['name']),
            'phone': _textValue(payload['phone']),
            'address': _textValue(payload['address']),
          },
        );
        continue;
      }
      if (key == suppliersKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'name': _textValue(payload['name']),
            'name_en': _textValue(payload['nameEn']),
            'name_ar': _textValue(payload['nameAr']),
            'phone': _textValue(payload['phone']),
            'address': _textValue(payload['address']),
            'notes': _textValue(payload['notes']),
          },
        );
        continue;
      }
      if (key == expensesKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'title': _textValue(payload['title']),
            'category': _textValue(payload['category']),
            'amount': _doubleValue(payload['amount']),
            'original_amount': _doubleValue(
              payload['originalAmount'],
              fallback: _doubleValue(payload['amount']),
            ),
            'original_currency':
                _textValue(payload['originalCurrency'], fallback: 'USD'),
            'exchange_rate_at_entry':
                _doubleValue(payload['exchangeRateAtEntry']),
            'expense_date': _dateString(payload['date']) ?? createdAt,
            'notes': _textValue(payload['notes']),
            'expense_status': _textValue(payload['status'], fallback: 'Draft'),
            'cancel_reason': _textValue(payload['cancelReason']),
            'cancelled_by_device_id':
                _textValue(payload['cancelledByDeviceId']),
            'cancelled_at': _dateString(payload['cancelledAt']) ?? '',
          },
        );
        continue;
      }
      if (key == warehouseTransferOrdersKey) {
        final rawItems =
            payload['items'] as List<dynamic>? ?? const <dynamic>[];
        final totalUnits = rawItems.fold<double>(0, (sum, raw) {
          if (raw is! Map) return sum;
          final item = Map<String, dynamic>.from(raw);
          return sum +
              (item['baseQuantity'] as num? ??
                      ((item['quantity'] as num? ?? 0).toDouble() *
                          (item['conversionToBase'] as num? ?? 1).toDouble()))
                  .toDouble();
        });
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'order_no': _textValue(payload['orderNo']),
            'from_warehouse_id': _textValue(payload['fromWarehouseId']),
            'from_warehouse_name': _textValue(payload['fromWarehouseName']),
            'to_warehouse_id': _textValue(payload['toWarehouseId']),
            'to_warehouse_name': _textValue(payload['toWarehouseName']),
            'document_date': _dateString(payload['date']) ?? createdAt,
            'status': _textValue(payload['status'], fallback: 'completed'),
            'notes': _textValue(payload['notes']),
            'created_by_user_id': _textValue(payload['createdByUserId']),
            'created_by_user_name': _textValue(payload['createdByUserName']),
            'items_json': jsonEncode(rawItems),
            'total_units': totalUnits,
          },
        );
        continue;
      }
      if (key == warehousesKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'name': _textValue(payload['name']),
            'code': _textValue(payload['code']),
            'location': _textValue(payload['location']),
            'is_default': _boolValue(payload['isDefault']),
            'is_active': _boolValue(payload['isActive'], fallback: true),
          },
        );
        continue;
      }
      if (key == categoriesKey || key == brandsKey || key == unitsKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'name_en': _textValue(payload['nameEn']),
            'name_ar': _textValue(payload['nameAr']),
            'code': _textValue(payload['code']),
          },
        );
        continue;
      }
      if (key == rolesKey) {
        await _upsertRolePayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == usersKey) {
        await _upsertUserPayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == supplierProductPricesKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'product_id': _textValue(payload['productId']),
            'supplier_id': _textValue(payload['supplierId']),
            'cost': _doubleValue(payload['cost'] ?? payload['unitCost']),
            'currency': _textValue(payload['currency'], fallback: 'USD'),
            'is_preferred': _boolValue(
              payload['isPreferred'] ?? payload['preferredSupplier'],
            ),
            'supplier_sku': _textValue(
              payload['supplierSku'] ??
                  payload['supplierSKU'] ??
                  payload['supplierCode'],
            ),
            'min_order_qty': _doubleValue(
              payload['minOrderQty'] ?? payload['minimumOrderQty'],
            ),
            'lead_time_days': _intValue(
              payload['leadTimeDays'] ?? payload['lead_time_days'],
              fallback: 0,
            ),
            'notes': _textValue(payload['notes']),
            'price_history_json':
                jsonEncode(payload['priceHistory'] ?? const []),
          },
        );
        continue;
      }
      if (key == priceListsKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'name': _textValue(payload['name']),
            'code': _textValue(payload['code']),
            'is_default': _boolValue(payload['isDefault']),
            'is_active': _boolValue(payload['isActive'], fallback: true),
          },
        );
        continue;
      }
      if (key == productPricesKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'product_id': _textValue(payload['productId']),
            'price_list_id': _textValue(payload['priceListId']),
            'unit_id': _textValue(payload['unitId'], fallback: 'base'),
            'base_currency_code':
                _textValue(payload['baseCurrencyCode'], fallback: 'USD'),
            'base_amount': _doubleValue(payload['baseAmount']),
            'is_active': _boolValue(payload['isActive'], fallback: true),
          },
        );
        continue;
      }
      if (key == productPriceHistoryKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'product_id': _textValue(payload['productId']),
            'price_list_id': _textValue(payload['priceListId']),
            'unit_id': _textValue(payload['unitId'], fallback: 'base'),
            'currency_code':
                _textValue(payload['currencyCode'], fallback: 'USD'),
            'old_amount': _doubleValue(payload['oldAmount']),
            'new_amount': _doubleValue(payload['newAmount']),
            'change_percent': _doubleValue(payload['changePercent']),
            'change_type':
                _textValue(payload['changeType'], fallback: 'manual'),
            'source': _textValue(payload['source'], fallback: 'manual'),
            'batch_id': _textValue(payload['batchId']),
            'user_id': _textValue(payload['userId']),
            'user_name': _textValue(payload['userName']),
            'changed_at': _dateString(payload['changedAt']) ?? createdAt,
          },
        );
        continue;
      }
      if (key == productPriceOverridesKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'product_price_id': _textValue(payload['productPriceId']),
            'currency_code':
                _textValue(payload['currencyCode'], fallback: 'USD'),
            'amount': _doubleValue(payload['amount']),
            'mode': _textValue(payload['mode'], fallback: 'fixed'),
            'is_active': _boolValue(payload['isActive'], fallback: true),
          },
        );
        continue;
      }
      if (key == productCostsKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'product_id': _textValue(payload['productId']),
            'average_cost': _doubleValue(payload['averageCost']),
            'last_cost': _doubleValue(payload['lastCost']),
            'currency_code':
                _textValue(payload['currencyCode'], fallback: 'USD'),
          },
        );
        continue;
      }
      if (key == costingMethodHistoryKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'method': _textValue(
              payload['method'],
              fallback: InventoryCostingMethod.weightedAverage.code,
            ),
            'effective_from':
                _dateString(payload['effectiveFrom']) ?? createdAt,
            'effective_to': _dateString(payload['effectiveTo']) ?? '',
            'reason': _textValue(payload['reason']),
          },
        );
        continue;
      }
      if (key == inventoryCostLayersKey) {
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
          sortIndex: sortIndex ?? 0,
          typedColumns: <String, Object?>{
            'product_id': _textValue(payload['productId']),
            'product_name': _textValue(payload['productName']),
            'quantity_received': _doubleValue(payload['quantityReceived']),
            'quantity_remaining': _doubleValue(payload['quantityRemaining']),
            'unit_cost': _doubleValue(payload['unitCost']),
            'currency_code':
                _textValue(payload['currencyCode'], fallback: 'USD'),
            'exchange_rate': _doubleValue(payload['exchangeRate'], fallback: 1),
            'purchase_id': _textValue(payload['purchaseId']),
            'purchase_item_id': _textValue(payload['purchaseItemId']),
            'source_type':
                _textValue(payload['sourceType'], fallback: 'purchase'),
            'source_id': _textValue(payload['sourceId']),
            'is_closed': _boolValue(payload['isClosed']),
          },
        );
        continue;
      }
      if (key == productsKey) {
        await _upsertProductPayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == salesKey) {
        await _upsertSalePayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == saleQuotationsKey) {
        await _upsertSaleQuotationPayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == deliveryNotesKey) {
        await _upsertDeliveryNotePayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == purchasesKey) {
        await _upsertPurchasePayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == inventoryCountsKey) {
        await _upsertInventoryCountPayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == billsOfMaterialsKey) {
        await _upsertBillOfMaterialsPayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      if (key == manufacturingOrdersKey) {
        await _upsertManufacturingOrderPayload(
          db,
          table,
          entityType,
          payload,
          id: id,
          payloadJson: payloadJson,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          sortIndex: sortIndex ?? 0,
        );
        continue;
      }
      await db.customInsert(
        """
          INSERT OR REPLACE INTO $table
            (id, entity_type, created_at, updated_at, deleted_at, device_id, sync_status, store_id, branch_id, version, sort_index)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        variables: <Variable<Object>>[
          Variable<String>(id),
          Variable<String>(entityType),
          Variable<String>(createdAt),
          Variable<String>(updatedAt),
          Variable<String>(deletedAt),
          Variable<String>(payload['deviceId']?.toString() ?? ''),
          Variable<String>(payload['syncStatus']?.toString() ?? ''),
          Variable<String>(payload['storeId']?.toString() ?? ''),
          Variable<String>(payload['branchId']?.toString() ?? ''),
          Variable<int>(_intValue(payload['version'], fallback: 1)),
          Variable<int>(sortIndex ?? 0),
        ],
      );
    }
  });
}
