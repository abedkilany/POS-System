part of 'app_store.dart';

extension _AppStoreSplitBackupRecovery on AppStore {
  dynamic _businessBackupValue(dynamic value) {
    if (value is Map) {
      final cleaned = <String, dynamic>{};
      value.forEach((key, item) {
        final textKey = key.toString();
        if (AppStore._businessBackupBlockedKeys.contains(textKey)) return;
        cleaned[textKey] = _businessBackupValue(item);
      });
      return cleaned;
    }
    if (value is List) {
      return value.map(_businessBackupValue).toList();
    }
    return value;
  }

  Map<String, dynamic> _businessBackupJson(dynamic item) {
    final raw = item.toJson() as Map<String, dynamic>;
    return Map<String, dynamic>.from(_businessBackupValue(raw) as Map);
  }

  Future<void> rebuildProductStockCache(String productId) async {
    await _refreshProductStockCompatibilityCache(<String>[productId]);
  }


  void _applyProductStockCompatibilityDeltas(
    Iterable<StockMovement> movements,
  ) {
    final deltasByProductId = <String, double>{};
    for (final movement in movements) {
      final productId = movement.productId.trim();
      if (productId.isEmpty) continue;
      deltasByProductId.update(
        productId,
        (value) => value + movement.quantity,
        ifAbsent: () => movement.quantity,
      );
    }
    if (deltasByProductId.isEmpty) return;
    final now = DateTime.now();
    for (final entry in deltasByProductId.entries) {
      final index = _productIndexById[entry.key];
      if (index == null) continue;
      final updated = _products[index].copyWith(
        stock: _products[index].stock + entry.value,
        updatedAt: now,
      );
      _products[index] = updated;
    }
  }

  Future<void> _refreshProductStockCompatibilityCache(
    Iterable<String> productIds,
  ) async {
    final uniqueIds =
        productIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (uniqueIds.isEmpty) return;
    for (final productId in uniqueIds) {
      final total = await _totalWarehouseStockFromSqlite(productId);
      final index = _productIndexById[productId];
      if (index == null) continue;
      final updated = _products[index].copyWith(stock: total);
      _products[index] = updated;
    }
    // The product list caches hold immutable Product snapshots. Whenever the
    // authoritative warehouse projection changes, invalidate those snapshots
    // so inventory totals/low-stock UI cannot keep displaying stale stock.
    _touchDataRevisions(products: true);
  }

  Map<String, String> _backupSafeLocalDatabaseEntries() {
    final entries = Map<String, String>.from(LocalDatabaseService.allEntries());
    const deviceBoundSecrets = <String>{
      'direct_api_token',
      'account_auth_admin_token_v1',
      'account_auth_account_token_v1',
      'account_auth_refresh_token_v1',
      'google_drive_backup_client_secret_v1',
      'google_drive_backup_refresh_token_v1',
      'google_drive_backup_access_token_v1',
    };
    for (final key in deviceBoundSecrets) {
      entries.remove(key);
    }

    final accountCache = entries[AccountAuthCache.key];
    if (accountCache != null && accountCache.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(accountCache);
        if (decoded is Map) {
          final clean = Map<String, dynamic>.from(decoded)
            ..remove('adminToken')
            ..remove('accountToken')
            ..remove('refreshToken')
            ..remove('admin_token')
            ..remove('account_token')
            ..remove('refresh_token');
          entries[AccountAuthCache.key] = jsonEncode(clean);
        }
      } catch (_) {
        // A malformed authentication cache is safer to omit from a backup.
        entries.remove(AccountAuthCache.key);
      }
    }
    return entries;
  }

  Future<Map<String, dynamic>> _backupPayload({
    List<SyncChange>? changes,
    bool includeDeviceAndSyncState = true,
  }) async {
    final warehouseInventory =
        await LocalDatabaseService.getWarehouseInventoriesFromSqlite();
    final inventoryBatches =
        await LocalDatabaseService.getInventoryBatchesFromSqlite();
    final inventoryBatchBalances =
        await LocalDatabaseService.getInventoryBatchBalancesFromSqlite();
    final stockOperations =
        await LocalDatabaseService.getStockOperationsFromSqlite();
    final inventoryReconciliations =
        await LocalDatabaseService.getInventoryReconciliationsFromSqlite();
    final inventoryMigrationAdjustments =
        await LocalDatabaseService.getInventoryMigrationAdjustmentsFromSqlite();
    final sqliteStockMovements =
        await LocalDatabaseService.getStockMovementsFromSqlite();
    final sqliteWarehouses =
        await LocalDatabaseService.getWarehousesFromSqlite();
    final productPriceHistory =
        await LocalDatabaseService.getProductPriceHistoryFromSqlite(
      limit: 100000,
    );
    final phase8AccountingRows =
        await LocalDatabaseService.getPhase8AccountingSnapshotRows();
    final exportWarehouses =
        sqliteWarehouses != null && sqliteWarehouses.isNotEmpty
            ? sqliteWarehouses
            : _warehouses;
    return {
      'version': 13,
      'generatedAt': DateTime.now().toIso8601String(),
      'schemaVersion': 17,
      'backupType':
          includeDeviceAndSyncState ? 'full_device_backup' : 'business_backup',
      'secretPolicy': 'device-secrets-excluded-v1',
      if (includeDeviceAndSyncState)
        'localDatabaseEntries': _backupSafeLocalDatabaseEntries(),
      if (!includeDeviceAndSyncState) 'storeId': appIdentity.storeId,
      if (!includeDeviceAndSyncState) 'branchId': appIdentity.branchId,
      if (!includeDeviceAndSyncState) 'appVersion': 'stage2',
      if (!includeDeviceAndSyncState) 'platform': appIdentity.platform.name,
      if (!includeDeviceAndSyncState)
        'themeMode':
            LocalDatabaseService.getString(AppStore._themeModeKey) ?? 'system',
      'invoiceCounter': _invoiceCounter,
      'purchaseCounter': _purchaseCounter,
      'storeProfile': _storeProfile.toJson(),
      'products': _products
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'productPriceHistory': productPriceHistory == null
          ? <dynamic>[]
          : productPriceHistory.map((item) => item.toJson()).toList(),
      'customers': _customers
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'sales': _sales
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'creditNotes': _creditNotes.map((item) => item.toJson()).toList(),
      'saleQuotations': _saleQuotations
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'deliveryNotes': _deliveryNotes
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'billsOfMaterials': _billsOfMaterials
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'manufacturingOrders': _manufacturingOrders
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'suppliers': _suppliers
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'supplierProductPrices': _supplierProductPrices
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'categories': _categories
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'brands': _brands
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'units': _units
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'expenses': _expenses
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'purchases': _purchases
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'stockMovements':
          sqliteStockMovements == null || sqliteStockMovements.isEmpty
              ? _stockMovements
                  .map(
                    (item) => includeDeviceAndSyncState
                        ? item.toJson()
                        : _businessBackupJson(item),
                  )
                  .toList()
              : sqliteStockMovements.map((item) => item.toJson()).toList(),
      'inventoryCounts': _inventoryCounts.map((item) => item.toJson()).toList(),
      'warehouseInventory': warehouseInventory == null
          ? <dynamic>[]
          : warehouseInventory.map((item) => item.toJson()).toList(),
      'inventoryBatches': inventoryBatches ?? <dynamic>[],
      'inventoryBatchBalances': inventoryBatchBalances ?? <dynamic>[],
      'stockOperations': stockOperations ?? <dynamic>[],
      'inventoryReconciliations': inventoryReconciliations == null
          ? <dynamic>[]
          : inventoryReconciliations.map((item) => item.toJson()).toList(),
      'inventoryMigrationAdjustments':
          inventoryMigrationAdjustments ?? <dynamic>[],
      'warehouses': exportWarehouses
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      'accountTransactions': _accountTransactions
          .map(
            (item) => includeDeviceAndSyncState
                ? item.toJson()
                : _businessBackupJson(item),
          )
          .toList(),
      for (final entry in phase8AccountingRows.entries) entry.key: entry.value,
      if (includeDeviceAndSyncState) 'deviceId': _deviceId,
      if (includeDeviceAndSyncState)
        'syncChanges':
            (changes ?? _syncChanges).map((item) => item.toJson()).toList(),
      if (includeDeviceAndSyncState)
        'syncQueue': _syncQueue.map((item) => item.toJson()).toList(),
      'roles': _roles.map((item) => item.toJson()).toList(),
      'users': _users.map((item) => item.toJson()).toList(),
      if (includeDeviceAndSyncState) 'appIdentity': appIdentity.toJson(),
      if (includeDeviceAndSyncState) 'storeEpoch': appIdentity.storeEpoch,
      'syncGeneratedAt': DateTime.now().toIso8601String(),
      'syncGeneratedSequence': _syncChanges.isEmpty
          ? 0
          : _syncChanges
              .map((item) => item.sequence)
              .reduce((a, b) => a > b ? a : b),
    };
  }

  Map<String, dynamic> _unifiedSnapshotManifestJson({
    required String jobId,
    required String generatedAt,
    required String kind,
    int totalChunks = 1,
    Iterable<String>? collections,
  }) {
    final identity = appIdentity;
    final sections = collections == null
        ? UnifiedSnapshotCatalog.sections
        : UnifiedSnapshotCatalog.sectionsForCollections(collections);
    return UnifiedSnapshotManifest(
      jobId: jobId,
      generatedAt: generatedAt,
      storeId: identity.storeId,
      branchId: identity.branchId,
      deviceId: _deviceId,
      storeEpoch: identity.storeEpoch.toString(),
      kind: kind,
      totalChunks: totalChunks,
      sections: sections,
    ).toJson();
  }

  void _attachUnifiedSnapshotChunkMetadata(
    List<Map<String, dynamic>> chunks, {
    required String kind,
    required String generatedAt,
  }) {
    final collectionTotals = <String, int>{};
    final collectionSeen = <String, int>{};
    final sectionTotals = <String, int>{};
    final sectionSeen = <String, int>{};
    final sectionIds = <String>{};
    for (final chunk in chunks) {
      final collection = (chunk['collection'] ?? '').toString();
      final section = UnifiedSnapshotCatalog.sectionForCollection(collection);
      chunk['snapshotFormat'] = UnifiedSnapshotManifest.format;
      chunk['snapshotVersion'] = UnifiedSnapshotManifest.version;
      chunk['snapshotKind'] = kind;
      chunk['sectionId'] = section.id;
      chunk['sectionLabelKey'] = section.labelKey;
      chunk['sectionOrder'] = section.order;
      sectionIds.add(section.id);
      collectionTotals[collection] = (collectionTotals[collection] ?? 0) + 1;
      sectionTotals[section.id] = (sectionTotals[section.id] ?? 0) + 1;
    }
    final manifest = _unifiedSnapshotManifestJson(
      jobId: chunks.isEmpty ? '' : (chunks.first['jobId'] ?? '').toString(),
      generatedAt: generatedAt,
      kind: kind,
      totalChunks: chunks.length,
      // Keep the manifest section model stable even when some collections are
      // empty and therefore omitted from the chunk stream.
      collections: null,
    );
    final allCollections = collectionTotals.keys.toList(growable: false);
    final unifiedSections = UnifiedSnapshotCatalog.sections
        .map((section) => section.id)
        .toList(growable: false);
    for (var i = 0; i < chunks.length; i += 1) {
      final collection = (chunks[i]['collection'] ?? '').toString();
      final section = UnifiedSnapshotCatalog.sectionForCollection(collection);
      final collectionIndex = collectionSeen[collection] ?? 0;
      final unifiedSectionIndex = sectionSeen[section.id] ?? 0;
      collectionSeen[collection] = collectionIndex + 1;
      sectionSeen[section.id] = unifiedSectionIndex + 1;
      chunks[i]['totalChunks'] = chunks.length;
      chunks[i]['ordinal'] = i;
      chunks[i]['syncGeneratedAt'] = generatedAt;
      chunks[i]['syncGeneratedSequence'] = _syncChanges.isEmpty
          ? 0
          : _syncChanges
              .map((item) => item.sequence)
              .reduce((a, b) => a > b ? a : b);
      chunks[i]['restoreCommandId'] = _currentHostRestoreCommandId();
      chunks[i]['hostRestoreCommandId'] = _currentHostRestoreCommandId();
      chunks[i]['rebuildCommandId'] = _currentHostRestoreCommandId();
      // Legacy progress fields remain collection-based so the current Direct
      // provisioning screen and server responses keep working during phase 1.
      chunks[i]['sectionChunkIndex'] = collectionIndex;
      chunks[i]['sectionTotalChunks'] = collectionTotals[collection] ?? 1;
      chunks[i]['allSections'] = allCollections;
      // New unified fields describe the business-level snapshot sections used
      // by both transports in the next phases.
      chunks[i]['unifiedSectionChunkIndex'] = unifiedSectionIndex;
      chunks[i]['unifiedSectionTotalChunks'] = sectionTotals[section.id] ?? 1;
      chunks[i]['allUnifiedSections'] = unifiedSections;
      chunks[i]['snapshotManifest'] = manifest;
    }
  }

  Future<Map<String, List<dynamic>>> _unifiedSnapshotCollectionPayloads({
    Set<String>? sectionIds,
  }) async {
    // Snapshots are DB-first. The in-memory user/role lists may still be
    // stale after a direct SQLite write or a lazy startup, so never export
    // login data from memory without refreshing it from the authoritative DB.
    final persistedRoles = await _loadRoles();
    final persistedUsers = await _loadUsers();
    _roles
      ..clear()
      ..addAll(persistedRoles);
    _users
      ..clear()
      ..addAll(persistedUsers);

    final warehouseInventory =
        await LocalDatabaseService.getWarehouseInventoriesFromSqlite();
    final inventoryBatches =
        await LocalDatabaseService.getInventoryBatchesFromSqlite();
    final inventoryBatchBalances =
        await LocalDatabaseService.getInventoryBatchBalancesFromSqlite();
    final stockOperations =
        await LocalDatabaseService.getStockOperationsFromSqlite();
    final inventoryReconciliations =
        await LocalDatabaseService.getInventoryReconciliationsFromSqlite();
    final inventoryMigrationAdjustments =
        await LocalDatabaseService.getInventoryMigrationAdjustmentsFromSqlite();
    final sqliteStockMovements =
        await LocalDatabaseService.getStockMovementsFromSqlite();
    final sqliteWarehouses =
        await LocalDatabaseService.getWarehousesFromSqlite();
    final phase8AccountingRows =
        await LocalDatabaseService.getPhase8AccountingSnapshotRows();
    final productPriceHistory =
        await LocalDatabaseService.getProductPriceHistoryFromSqlite(
            limit: 100000);
    final exportWarehouses =
        sqliteWarehouses != null && sqliteWarehouses.isNotEmpty
            ? sqliteWarehouses
            : _warehouses;
    final all = <String, List<dynamic>>{
      '_meta': <dynamic>[
        <String, dynamic>{
          'version': 15,
          'generatedAt': DateTime.now().toIso8601String(),
          'schemaVersion': 17,
          'invoiceCounter': _invoiceCounter,
          'purchaseCounter': _purchaseCounter,
          'storeProfile': _storeProfile.toJson(),
          'appIdentity': appIdentity.toJson(),
          'storeEpoch': appIdentity.storeEpoch,
          'syncGeneratedSequence': _syncChanges.isEmpty
              ? 0
              : _syncChanges
                  .map((item) => item.sequence)
                  .reduce((a, b) => a > b ? a : b),
        },
      ],
      'roles': _roles.map((item) => item.toJson()).toList(),
      'users': _users.map((item) => item.toJson()).toList(),
      'categories': _categories.map((item) => item.toJson()).toList(),
      'brands': _brands.map((item) => item.toJson()).toList(),
      'units': _units.map((item) => item.toJson()).toList(),
      'warehouses': exportWarehouses.map((item) => item.toJson()).toList(),
      'products': _products.map((item) => item.toJson()).toList(),
      'customers': _customers.map((item) => item.toJson()).toList(),
      'suppliers': _suppliers.map((item) => item.toJson()).toList(),
      'supplierProductPrices':
          _supplierProductPrices.map((item) => item.toJson()).toList(),
      'priceLists': _priceLists.map((item) => item.toJson()).toList(),
      'productPrices': _productPrices.map((item) => item.toJson()).toList(),
      'productPriceHistory': productPriceHistory == null
          ? <dynamic>[]
          : productPriceHistory.map((item) => item.toJson()).toList(),
      'productPriceOverrides':
          _productPriceOverrides.map((item) => item.toJson()).toList(),
      'productCosts': _productCosts.map((item) => item.toJson()).toList(),
      'costingMethodHistory':
          _costingMethodHistory.map((item) => item.toJson()).toList(),
      'inventoryCostingMethod': <dynamic>[_inventoryCostingMethod.code],
      'inventoryCostLayers':
          _inventoryCostLayers.map((item) => item.toJson()).toList(),
      'stockMovements':
          sqliteStockMovements == null || sqliteStockMovements.isEmpty
              ? _stockMovements.map((item) => item.toJson()).toList()
              : sqliteStockMovements.map((item) => item.toJson()).toList(),
      'inventoryCounts': _inventoryCounts.map((item) => item.toJson()).toList(),
      'warehouseInventory': warehouseInventory == null
          ? <dynamic>[]
          : warehouseInventory.map((item) => item.toJson()).toList(),
      'inventoryBatches': inventoryBatches ?? <dynamic>[],
      'inventoryBatchBalances': inventoryBatchBalances ?? <dynamic>[],
      'stockOperations': stockOperations ?? <dynamic>[],
      'inventoryReconciliations': inventoryReconciliations == null
          ? <dynamic>[]
          : inventoryReconciliations.map((item) => item.toJson()).toList(),
      'inventoryMigrationAdjustments':
          inventoryMigrationAdjustments ?? <dynamic>[],
      'sales': _sales.map((item) => item.toJson()).toList(),
      'creditNotes': _creditNotes.map((item) => item.toJson()).toList(),
      'saleQuotations': _saleQuotations.map((item) => item.toJson()).toList(),
      'deliveryNotes': _deliveryNotes.map((item) => item.toJson()).toList(),
      'purchases': _purchases.map((item) => item.toJson()).toList(),
      'expenses': _expenses.map((item) => item.toJson()).toList(),
      'accountTransactions':
          _accountTransactions.map((item) => item.toJson()).toList(),
      for (final entry in phase8AccountingRows.entries) entry.key: entry.value,
      'billsOfMaterials':
          _billsOfMaterials.map((item) => item.toJson()).toList(),
      'manufacturingOrders':
          _manufacturingOrders.map((item) => item.toJson()).toList(),
    };

    final ordered = <String, List<dynamic>>{};
    for (final section in UnifiedSnapshotCatalog.sections) {
      if (sectionIds != null && !sectionIds.contains(section.id)) continue;
      for (final collection in section.collections) {
        ordered[collection] = all[collection] ?? const <dynamic>[];
      }
    }
    return ordered;
  }

  String _encodeUnifiedSnapshotChunkPayload(Map<String, dynamic> payload) {
    final bytes = utf8.encode(jsonEncode(payload));
    final compressed = GZipEncoder().encode(bytes);
    return base64Encode(compressed);
  }

  Map<String, dynamic> _decodeUnifiedSnapshotChunkPayload(
    Map<String, dynamic> chunk,
  ) {
    final encoding = (chunk['encoding'] ?? '').toString();
    final rawPayload = chunk['payload'];
    if (encoding == 'gzip+base64+json' && rawPayload is String) {
      final compressed = base64Decode(rawPayload);
      final bytes = GZipDecoder().decodeBytes(compressed);
      final decoded = jsonDecode(utf8.decode(bytes));
      return Map<String, dynamic>.from(decoded as Map);
    }
    if (rawPayload is Map) return Map<String, dynamic>.from(rawPayload);
    return const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> exportUnifiedSnapshotChunks({
    String kind = 'full_store',
    Set<String>? sectionIds,
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) async {
    if (kind != 'login_bootstrap') {
      await _ensureHeavyDataLoaded(failOnError: true);
    }
    final identity = appIdentity;
    final generatedAt = DateTime.now().toIso8601String();
    final jobId = '${DateTime.now().microsecondsSinceEpoch}-$_deviceId-$kind';
    final collections = await _unifiedSnapshotCollectionPayloads(
      sectionIds: sectionIds,
    );

    final chunks = <Map<String, dynamic>>[];
    void addEncodedPayload(
      String collection,
      int index,
      Map<String, dynamic> payload,
      String encoded,
    ) {
      chunks.add({
        'jobId': jobId,
        'storeId': identity.storeId,
        'branchId': identity.branchId,
        'deviceId': _deviceId,
        'collection': collection,
        'chunkIndex': index,
        'encoding': 'gzip+base64+json',
        'payload': encoded,
        'generatedAt': generatedAt,
        'storeEpoch': identity.storeEpoch,
      });
    }

    collections.forEach((collection, list) {
      var chunkIndex = 0;
      if (collection == '_meta') {
        final meta = list.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(list.first as Map);
        addEncodedPayload(
          collection,
          chunkIndex,
          meta,
          _encodeUnifiedSnapshotChunkPayload(meta),
        );
        return;
      }
      if (list.isEmpty) {
        // Empty collections are represented by their absence from the chunk
        // stream. The unified importer already treats missing collections as
        // empty lists, so sending zero-item chunks only wastes requests and can
        // leave large restore publishes waiting on meaningless empty uploads.
        return;
      }

      void addRange(int start, int end) {
        final count = end - start;
        final payload = {'items': list.sublist(start, end)};
        final encoded = _encodeUnifiedSnapshotChunkPayload(payload);
        if (encoded.length <= maxEncodedPayloadBytes || count <= 1) {
          addEncodedPayload(collection, chunkIndex, payload, encoded);
          chunkIndex += 1;
          return;
        }
        final mid = start + (count ~/ 2);
        addRange(start, mid);
        addRange(mid, end);
      }

      for (var start = 0; start < list.length; start += maxItemsPerChunk) {
        final end = min(start + maxItemsPerChunk, list.length);
        addRange(start, end);
      }
    });

    _attachUnifiedSnapshotChunkMetadata(
      chunks,
      kind: kind,
      generatedAt: generatedAt,
    );
    return chunks;
  }

  Map<String, dynamic> unifiedSnapshotPayloadFromChunks(
    List<Map<String, dynamic>> chunks,
  ) {
    final payload = <String, dynamic>{};
    Map<String, dynamic>? manifest;
    var generatedAt = DateTime.now().toIso8601String();
    var generatedSequence = 0;

    for (final chunk in chunks) {
      manifest ??= chunk['snapshotManifest'] is Map
          ? Map<String, dynamic>.from(chunk['snapshotManifest'] as Map)
          : null;
      generatedAt = (chunk['generatedAt'] ?? generatedAt).toString();
      final collection = (chunk['collection'] ?? '').toString();
      if (collection.isEmpty) continue;
      final decoded = _decodeUnifiedSnapshotChunkPayload(chunk);
      if (collection == '_meta') {
        payload.addAll(decoded);
        generatedSequence =
            int.tryParse(decoded['syncGeneratedSequence']?.toString() ?? '') ??
                generatedSequence;
        continue;
      }
      final items = decoded['items'] is List
          ? List<dynamic>.from(decoded['items'] as List)
          : const <dynamic>[];
      final existing = payload[collection];
      if (existing is List) {
        existing.addAll(items);
      } else {
        payload[collection] = List<dynamic>.from(items);
      }
    }

    payload['snapshotManifest'] = manifest ??
        _unifiedSnapshotManifestJson(
          jobId: chunks.isEmpty ? '' : (chunks.first['jobId'] ?? '').toString(),
          generatedAt: generatedAt,
          kind: chunks.isEmpty
              ? 'full_store'
              : (chunks.first['snapshotKind'] ?? 'full_store').toString(),
          totalChunks: chunks.length,
          collections: chunks.map(
            (item) => (item['collection'] ?? '').toString(),
          ),
        );
    payload['syncGeneratedAt'] = generatedAt;
    payload['syncGeneratedSequence'] = generatedSequence;
    return payload;
  }

  Future<List<Map<String, dynamic>>>
      exportDirectLoginBootstrapSnapshotChunks() async {
    return await exportUnifiedSnapshotChunks(
      kind: 'login_bootstrap',
      sectionIds: {UnifiedSnapshotCatalog.loginSettingsAndUsers.id},
    );
  }
}
