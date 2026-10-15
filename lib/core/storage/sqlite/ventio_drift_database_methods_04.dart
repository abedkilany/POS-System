part of 'ventio_drift_database.dart';

extension VentioDriftDatabaseMethods4 on VentioDriftDatabase {
  Future<void> _backfillSimpleBusinessColumnsIfNeeded() async {
    final done =
        await _metaValue('sqlite_operational_columns_v2_backfilled') == 'true';
    if (done) return;
    await _migratePayloadJsonRows('customers', (payload, row) {
      return <String, Object?>{
        'name': _stringOrNull(payload['name']) ?? _stringValue(row['name']),
        'phone': _stringOrNull(payload['phone']) ?? _stringValue(row['phone']),
        'address':
            _stringOrNull(payload['address']) ?? _stringValue(row['address']),
      };
    });

    await _migratePayloadJsonRows('suppliers', (payload, row) {
      return <String, Object?>{
        'name': _stringOrNull(payload['name']) ?? _stringValue(row['name']),
        'name_en':
            _stringOrNull(payload['nameEn']) ?? _stringValue(row['name_en']),
        'name_ar':
            _stringOrNull(payload['nameAr']) ?? _stringValue(row['name_ar']),
        'phone': _stringOrNull(payload['phone']) ?? _stringValue(row['phone']),
        'address':
            _stringOrNull(payload['address']) ?? _stringValue(row['address']),
        'notes': _stringOrNull(payload['notes']) ?? _stringValue(row['notes']),
      };
    });

    await _migratePayloadJsonRows('expenses', (payload, row) {
      return <String, Object?>{
        'title': _stringOrNull(payload['title']) ?? _stringValue(row['title']),
        'category':
            _stringOrNull(payload['category']) ?? _stringValue(row['category']),
        'amount':
            _doubleOrNull(payload['amount']) ?? _doubleValue(row['amount']),
        'original_amount': _doubleOrNull(payload['originalAmount']) ??
            _doubleOrNull(payload['amount']) ??
            _doubleValue(row['original_amount']),
        'original_currency': _stringOrNull(payload['originalCurrency']) ??
            _stringValue(row['original_currency'], fallback: 'USD'),
        'exchange_rate_at_entry':
            _doubleOrNull(payload['exchangeRateAtEntry']) ??
                _doubleValue(row['exchange_rate_at_entry']),
        'expense_date': _stringOrNull(payload['date']) ??
            _stringValue(row['expense_date'],
                fallback: _stringValue(row['created_at'])),
        'notes': _stringOrNull(payload['notes']) ?? _stringValue(row['notes']),
        'expense_status': _stringOrNull(payload['status']) ??
            _stringValue(row['expense_status']),
        'cancel_reason': _stringOrNull(payload['cancelReason']) ??
            _stringValue(row['cancel_reason']),
        'cancelled_by_device_id':
            _stringOrNull(payload['cancelledByDeviceId']) ??
                _stringValue(row['cancelled_by_device_id']),
        'cancelled_at': _stringOrNull(payload['cancelledAt']) ??
            _stringValue(row['cancelled_at']),
      };
    });

    await _migratePayloadJsonRows('warehouses', (payload, row) {
      return <String, Object?>{
        'name': _stringOrNull(payload['name']) ?? _stringValue(row['name']),
        'code': _stringOrNull(payload['code']) ?? _stringValue(row['code']),
        'location':
            _stringOrNull(payload['location']) ?? _stringValue(row['location']),
        'is_default': _boolTrueOrNull(payload['isDefault']) == true
            ? 1
            : _intValue(row['is_default'], fallback: 0),
        'is_active': _boolTrueOrNull(payload['isActive']) == true
            ? 1
            : _intValue(row['is_active'], fallback: 1),
      };
    });

    for (final table in <String>{
      'catalog_categories',
      'catalog_brands',
      'catalog_units'
    }) {
      await _migratePayloadJsonRows(table, (payload, row) {
        return <String, Object?>{
          'name_en':
              _stringOrNull(payload['nameEn']) ?? _stringValue(row['name_en']),
          'name_ar':
              _stringOrNull(payload['nameAr']) ?? _stringValue(row['name_ar']),
          'code': _stringOrNull(payload['code']) ?? _stringValue(row['code']),
        };
      });
    }

    await _migratePayloadJsonRows('price_lists', (payload, row) {
      return <String, Object?>{
        'name': _stringOrNull(payload['name']) ?? _stringValue(row['name']),
        'code': _stringOrNull(payload['code']) ?? _stringValue(row['code']),
        'is_default': _boolTrueOrNull(payload['isDefault']) == true
            ? 1
            : _intValue(row['is_default'], fallback: 0),
        'is_active': _boolTrueOrNull(payload['isActive']) == true
            ? 1
            : _intValue(row['is_active'], fallback: 1),
      };
    });

    await _migratePayloadJsonRows('product_prices', (payload, row) {
      return <String, Object?>{
        'product_id': _stringOrNull(payload['productId']) ??
            _stringValue(row['product_id']),
        'price_list_id': _stringOrNull(payload['priceListId']) ??
            _stringValue(row['price_list_id']),
        'unit_id': _stringOrNull(payload['unitId']) ??
            _stringValue(row['unit_id'], fallback: 'base'),
        'base_currency_code': _stringOrNull(payload['baseCurrencyCode']) ??
            _stringValue(row['base_currency_code'], fallback: 'USD'),
        'base_amount': _doubleOrNull(payload['baseAmount']) ??
            _doubleValue(row['base_amount']),
        'is_active': _boolTrueOrNull(payload['isActive']) == true
            ? 1
            : _intValue(row['is_active'], fallback: 1),
      };
    });

    await _migratePayloadJsonRows('product_price_overrides', (payload, row) {
      return <String, Object?>{
        'product_price_id': _stringOrNull(payload['productPriceId']) ??
            _stringValue(row['product_price_id']),
        'currency_code': _stringOrNull(payload['currencyCode']) ??
            _stringValue(row['currency_code'], fallback: 'USD'),
        'amount':
            _doubleOrNull(payload['amount']) ?? _doubleValue(row['amount']),
        'mode': _stringOrNull(payload['mode']) ??
            _stringValue(row['mode'], fallback: 'fixed'),
        'is_active': _boolTrueOrNull(payload['isActive']) == true
            ? 1
            : _intValue(row['is_active'], fallback: 1),
      };
    });

    await _migratePayloadJsonRows('product_costs', (payload, row) {
      return <String, Object?>{
        'product_id': _stringOrNull(payload['productId']) ??
            _stringValue(row['product_id']),
        'average_cost': _doubleOrNull(payload['averageCost']) ??
            _doubleValue(row['average_cost']),
        'last_cost': _doubleOrNull(payload['lastCost']) ??
            _doubleValue(row['last_cost']),
        'currency_code': _stringOrNull(payload['currencyCode']) ??
            _stringValue(row['currency_code'], fallback: 'USD'),
      };
    });

    await _migratePayloadJsonRows('costing_method_history', (payload, row) {
      return <String, Object?>{
        'method': _stringOrNull(payload['method']) ??
            _stringValue(row['method'], fallback: 'weighted_average'),
        'effective_from': _stringOrNull(payload['effectiveFrom']) ??
            _stringValue(row['effective_from']),
        'effective_to': _stringOrNull(payload['effectiveTo']) ??
            _stringValue(row['effective_to']),
        'reason':
            _stringOrNull(payload['reason']) ?? _stringValue(row['reason']),
      };
    });

    await _migratePayloadJsonRows('inventory_cost_layers', (payload, row) {
      return <String, Object?>{
        'product_id': _stringOrNull(payload['productId']) ??
            _stringValue(row['product_id']),
        'product_name': _stringOrNull(payload['productName']) ??
            _stringValue(row['product_name']),
        'quantity_received': _doubleOrNull(payload['quantityReceived']) ??
            _doubleValue(row['quantity_received']),
        'quantity_remaining': _doubleOrNull(payload['quantityRemaining']) ??
            _doubleValue(row['quantity_remaining']),
        'unit_cost': _doubleOrNull(payload['unitCost']) ??
            _doubleValue(row['unit_cost']),
        'currency_code': _stringOrNull(payload['currencyCode']) ??
            _stringValue(row['currency_code'], fallback: 'USD'),
        'exchange_rate': _doubleOrNull(payload['exchangeRate']) ??
            _doubleValue(row['exchange_rate'], fallback: 1),
        'purchase_id': _stringOrNull(payload['purchaseId']) ??
            _stringValue(row['purchase_id']),
        'purchase_item_id': _stringOrNull(payload['purchaseItemId']) ??
            _stringValue(row['purchase_item_id']),
        'source_type': _stringOrNull(payload['sourceType']) ??
            _stringValue(row['source_type'], fallback: 'purchase'),
        'source_id': _stringOrNull(payload['sourceId']) ??
            _stringValue(row['source_id']),
        'is_closed': _boolTrueOrNull(payload['isClosed']) == true
            ? 1
            : _intValue(row['is_closed'], fallback: 0),
      };
    });

    await _migratePayloadJsonRows('supplier_product_prices', (payload, row) {
      return <String, Object?>{
        'product_id': _stringOrNull(payload['productId']) ??
            _stringValue(row['product_id']),
        'supplier_id': _stringOrNull(payload['supplierId']) ??
            _stringValue(row['supplier_id']),
        'cost': _doubleOrNull(payload['cost']) ??
            _doubleOrNull(payload['unitCost']) ??
            _doubleValue(row['cost']),
        'currency': _stringOrNull(payload['currency']) ??
            _stringValue(row['currency'], fallback: 'USD'),
        'is_preferred': _boolTrueOrNull(payload['isPreferred']) == true
            ? 1
            : _intValue(row['is_preferred'], fallback: 0),
        'supplier_sku': _stringOrNull(payload['supplierSku']) ??
            _stringOrNull(payload['supplierSKU']) ??
            _stringOrNull(payload['supplierCode']) ??
            _stringValue(row['supplier_sku']),
        'min_order_qty': _doubleOrNull(payload['minOrderQty']) ??
            _doubleOrNull(payload['minimumOrderQty']) ??
            _doubleValue(row['min_order_qty']),
        'lead_time_days': _intOrNull(payload['leadTimeDays']) ??
            _intOrNull(payload['lead_time_days']) ??
            _intValue(row['lead_time_days']),
        'notes': _stringOrNull(payload['notes']) ?? _stringValue(row['notes']),
        'price_history_json': _jsonStringValue(
          payload['priceHistory'],
          fallback: _stringValue(row['price_history_json'], fallback: '[]'),
        ),
      };
    });

    await _setMeta('sqlite_operational_columns_v2_backfilled', 'true');
  }

  Future<String?> _metaValue(String key) async {
    final rows = await customSelect(
      'SELECT value FROM migration_meta WHERE key = ?',
      variables: <Variable<Object>>[Variable<String>(key)],
    ).get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  Future<void> _setMeta(String key, String value) async {
    await customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        Variable<String>(key),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }
}
