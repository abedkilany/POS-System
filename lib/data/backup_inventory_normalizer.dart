Map<String, dynamic> normalizeBackupInventoryForStore(
  Map<String, dynamic> decoded, {
  required String storeId,
  required String branchId,
  required String deviceId,
}) {
  final normalized = Map<String, dynamic>.from(decoded);
  final now = DateTime.now().toUtc().toIso8601String();

  List<Map<String, dynamic>> list(String key) {
    final value = normalized[key];
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  final warehouses = list('warehouses');
  if (warehouses.isEmpty) {
    warehouses.add(<String, dynamic>{
      'id': 'main',
      'name': 'Main warehouse',
      'code': 'MAIN',
      'location': '',
      'isDefault': true,
      'isActive': true,
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
      'deviceId': deviceId,
      'syncStatus': 'pending',
      'storeId': storeId,
      'branchId': branchId,
      'version': 1,
      'lastModifiedByDeviceId': deviceId,
    });
  } else {
    for (final warehouse in warehouses) {
      warehouse['storeId'] = storeId;
      warehouse['branchId'] = branchId;
    }
  }
  normalized['warehouses'] = warehouses;

  for (final key in <String>[
    'warehouseInventory',
    'inventoryBatches',
    'inventoryBatchBalances',
  ]) {
    final rows = list(key);
    for (final row in rows) {
      row['storeId'] = storeId;
      row['branchId'] = branchId;
      if (row['warehouseId']?.toString().trim().isEmpty ?? true) {
        row['warehouseId'] = 'main';
      }
    }
    normalized[key] = rows;
  }

  final products = list('products');
  for (final product in products) {
    product['storeId'] = storeId;
    product['branchId'] = branchId;
  }
  normalized['products'] = products;
  return normalized;
}
