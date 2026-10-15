part of 'business_sqlite_store_impl.dart';

Future<void> migrateFromLegacyJsonIfNeeded(
  VentioDriftDatabase db, {
  required Map<String, String> legacyEntries,
}) async {
  final typedDone = await _metaValue(db, phase3TypedTablesMetaKey) == 'true';
  if (typedDone) return;

  for (final entry in legacyEntries.entries) {
    if (!isBusinessKey(entry.key)) continue;
    await saveKeyJson(db, entry.key, entry.value);
  }
  await _setMeta(db, phase3MigratedMetaKey, 'true');
  await _setMeta(db, phase3TypedTablesMetaKey, 'true');
}

Future<void> markFreshInstallValidated(VentioDriftDatabase db) async {
  await _setMeta(db, phase3MigratedMetaKey, 'true');
  await _setMeta(db, phase3TypedTablesMetaKey, 'true');
  await _setMeta(db, phase3ValidatedMetaKey, 'true');
}

Future<void> migrateComplexTablesFromPayloadJson(
  VentioDriftDatabase db,
) async {
  if (await _metaValue(db, phase3ComplexTablesMetaKey) == 'true') return;
  final needsMigration = await _tableHasColumn(
          db, _tableByKey[productsKey]!, 'payload_json') ||
      await _tableHasColumn(db, _tableByKey[salesKey]!, 'payload_json') ||
      await _tableHasColumn(
        db,
        _tableByKey[saleQuotationsKey]!,
        'payload_json',
      ) ||
      await _tableHasColumn(
        db,
        _tableByKey[deliveryNotesKey]!,
        'payload_json',
      ) ||
      await _tableHasColumn(db, _tableByKey[purchasesKey]!, 'payload_json') ||
      await _tableHasColumn(
        db,
        _tableByKey[inventoryCountsKey]!,
        'payload_json',
      ) ||
      await _tableHasColumn(
        db,
        _tableByKey[billsOfMaterialsKey]!,
        'payload_json',
      ) ||
      await _tableHasColumn(
        db,
        _tableByKey[manufacturingOrdersKey]!,
        'payload_json',
      );
  if (!needsMigration) {
    await _setMeta(db, phase3ComplexTablesMetaKey, 'true');
    return;
  }
  await _migrateComplexTables(db);
  await _setMeta(db, phase3ComplexTablesMetaKey, 'true');
}

Future<bool> isValidationPassed(VentioDriftDatabase db) async {
  return await _metaValue(db, phase3ValidatedMetaKey) == 'true';
}

Future<Map<String, String>> hydrateKeyMirror(VentioDriftDatabase db) async {
  final mirror = await hydrateScalarKeyMirror(db);

  for (final entry in _tableByKey.entries) {
    mirror[entry.key] = await readEntityListJsonByKey(db, entry.key) ?? '[]';
  }

  return mirror;
}

/// Startup-fast mirror hydration.
///
/// Phase 3 used to rebuild JSON strings for every typed table during
/// LocalDatabaseService.initialize(), then AppStore decoded the same JSON
/// again immediately after. With large datasets this made app launch pay for
/// products/sales/stock/accounting even before the user opened a page.
///
/// Keep only scalar/settings keys in the startup mirror. Typed entity lists
/// are loaded by AppStore in two stages: small catalog/login-critical lists
/// during initialize(), and large transactional lists shortly after startup.
Future<Map<String, String>> hydrateScalarKeyMirror(
    VentioDriftDatabase db) async {
  final rows = await db.customSelect('''
      SELECT key, value
      FROM local_key_values
      ORDER BY key ASC
    ''').get();
  final mirror = <String, String>{
    for (final row in rows) row.read<String>('key'): row.read<String>('value'),
  };

  for (final key in _entityListKeys) {
    mirror.remove(key);
  }

  // These lists are small and needed for login/catalog initialization. Keep
  // them available synchronously to AppStore without loading transactional
  // tables such as sales, purchases, stock movements, and accounting ledger.
  for (final key in <String>{
    categoriesKey,
    brandsKey,
    unitsKey,
    rolesKey,
    usersKey
  }) {
    mirror[key] = await readEntityListJsonByKey(db, key) ?? '[]';
  }

  final settingsRows = await db.customSelect('''
      SELECT key, value
      FROM settings
      ORDER BY key ASC
    ''').get();
  for (final row in settingsRows) {
    mirror[row.read<String>('key')] = row.read<String>('value');
  }
  return mirror;
}

Future<String?> readEntityListJsonByKey(
    VentioDriftDatabase db, String key) async {
  final table = _tableByKey[key];
  if (table == null) return null;
  final payloads = await _readEntityListPayloadsByKey(db, key);
  return jsonEncode(payloads);
}

Future<List<String>> readEntityListJsonBatches(
  VentioDriftDatabase db,
  String key, {
  int batchSize = 100,
}) async {
  final table = _tableByKey[key];
  if (table == null) return const <String>[];
  final size = batchSize.clamp(1, 1000).toInt();
  final payloads = await _readEntityListPayloadsByKey(db, key);
  final batches = <String>[];
  for (var index = 0; index < payloads.length; index += size) {
    final end =
        (index + size < payloads.length) ? index + size : payloads.length;
    batches.add(jsonEncode(payloads.sublist(index, end)));
  }
  return batches;
}

Future<List<Map<String, dynamic>>> _readEntityListPayloadsByKey(
  VentioDriftDatabase db,
  String key,
) async {
  switch (key) {
    case productsKey:
      return (await readProducts(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case customersKey:
      return (await readCustomers(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case suppliersKey:
      return (await readSuppliers(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case salesKey:
      return (await readSales(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case saleQuotationsKey:
      return (await readSaleQuotations(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case deliveryNotesKey:
      return (await readDeliveryNotes(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case billsOfMaterialsKey:
      return (await readBillOfMaterials(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case manufacturingOrdersKey:
      return (await readManufacturingOrders(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case inventoryCountsKey:
      return (await readInventoryCounts(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case warehousesKey:
      return (await readWarehouses(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case warehouseTransferOrdersKey:
      return (await readWarehouseTransferOrders(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case stockMovementsKey:
      return (await readStockMovements(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case accountTransactionsKey:
      return (await readAccountTransactions(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case categoriesKey:
      return (await readCatalogItems(db, _tableByKey[categoriesKey]!))
          .map((item) => item.toJson())
          .toList(growable: false);
    case brandsKey:
      return (await readCatalogItems(db, _tableByKey[brandsKey]!))
          .map((item) => item.toJson())
          .toList(growable: false);
    case unitsKey:
      return (await readCatalogItems(db, _tableByKey[unitsKey]!))
          .map((item) => item.toJson())
          .toList(growable: false);
    case priceListsKey:
      return (await readPriceLists(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case productPricesKey:
      return (await readProductPrices(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case productPriceHistoryKey:
      return (await readProductPriceHistory(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case productPriceOverridesKey:
      return (await readProductPriceOverrides(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case productCostsKey:
      return (await readProductCosts(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case costingMethodHistoryKey:
      return (await readCostingMethodHistory(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case inventoryCostLayersKey:
      return (await readInventoryCostLayers(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case supplierProductPricesKey:
      return (await readSupplierProductPrices(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case rolesKey:
      return (await readRoles(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    case usersKey:
      return (await readUsers(db))
          .map((item) => item.toJson())
          .toList(growable: false);
    default:
      return const <Map<String, dynamic>>[];
  }
}
