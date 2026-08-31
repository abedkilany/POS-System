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

Future<void> rebuildAllProductStockCaches() async {
    await _refreshProductStockCompatibilityCache(
      _products.where((item) => !item.isDeleted).map((item) => item.id),
    );
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
      final total = await totalWarehouseStockFromSqlite(productId);
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
        'themeMode': LocalDatabaseService.getString(AppStore._themeModeKey) ?? 'system',
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
      chunks[i]['restoreCommandId'] = currentHostRestoreCommandId();
      chunks[i]['hostRestoreCommandId'] = currentHostRestoreCommandId();
      chunks[i]['rebuildCommandId'] = currentHostRestoreCommandId();
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
      await ensureHeavyDataLoaded(failOnError: true);
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

Future<List<Map<String, dynamic>>> exportDirectBootstrapSnapshotChunks({
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) async {
    return await exportUnifiedSnapshotChunks(
      kind: 'full_store',
      maxItemsPerChunk: maxItemsPerChunk,
      maxEncodedPayloadBytes: maxEncodedPayloadBytes,
    );
  }

String exportRecoveryFileJson({String controlPlaneApiUrl = ''}) {
    requirePermission(AppPermission.backupExport);
    final payload = <String, dynamic>{
      'format': 'ventio_store_recovery_file',
      'version': 2,
      'generatedAt': DateTime.now().toIso8601String(),
      'storeId': appIdentity.storeId,
      'branchId': appIdentity.branchId,
      'controlPlaneApiUrl': controlPlaneApiUrl.trim(),
      'recoveryKey': appIdentity.recoveryKey,
      'storeEpoch': appIdentity.storeEpoch,
    };
    payload['checksum'] = _recoveryChecksum(payload);
    payload['signature'] = _recoverySignature(payload);
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

Map<String, String> parseRecoveryFileJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw ArgumentError('Invalid recovery file.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['format']?.toString() != 'ventio_store_recovery_file') {
      throw ArgumentError('Invalid recovery file format.');
    }
    final version = (payload['version'] as num? ?? 0).toInt();
    if (version < 1 || version > 2) {
      throw ArgumentError('Unsupported recovery file version.');
    }
    final expected = payload['checksum']?.toString() ?? '';
    if (expected.isEmpty || expected != _recoveryChecksum(payload)) {
      throw ArgumentError('Recovery file checksum failed.');
    }
    if (version >= 2) {
      final signature = payload['signature']?.toString() ?? '';
      if (signature.isEmpty || signature != _recoverySignature(payload)) {
        throw ArgumentError('Recovery file signature failed.');
      }
    }
    final storeId = payload['storeId']?.toString().trim().toUpperCase() ?? '';
    final branchId = payload['branchId']?.toString().trim().toUpperCase() ?? '';
    final recoveryKey =
        payload['recoveryKey']?.toString().trim().toUpperCase() ?? '';
    if (!storeId.startsWith('ST-') ||
        branchId.isEmpty ||
        !recoveryKey.startsWith('RK-')) {
      throw ArgumentError(
        'Recovery file is missing required store identity fields.',
      );
    }
    return {
      'storeId': storeId,
      'branchId': branchId,
      'controlPlaneApiUrl':
          payload['controlPlaneApiUrl']?.toString().trim() ?? '',
      'recoveryKey': recoveryKey,
    };
  }

String _recoveryChecksum(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('checksum')
      ..remove('signature');
    final canonical = jsonEncode(
      Map.fromEntries(
        copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    var hash = 2166136261;
    for (final unit in canonical.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

Future<String> exportBackupJson() async {
    requirePermission(AppPermission.backupExport);
    final payload = await _backupPayload(includeDeviceAndSyncState: true);
    return compute(_encodePrettyBackupPayload, payload);
  }

String currentHostSnapshotGeneration() {
    if (!appIdentity.isHost) return '';
    final stored = LocalDatabaseService.getString(AppStore._hostSnapshotGenerationKey);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    final markers = _syncChanges.where(
      (item) =>
          item.entityType == 'system' &&
          item.operation == 'restore_snapshot_ready',
    );
    if (markers.isEmpty) return '';
    final latest = markers.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final payload = latest.payload;
    final generation = (payload['snapshotGeneration'] ??
            payload['restoreGeneration'] ??
            payload['restoredAt'] ??
            latest.createdAt.toIso8601String())
        .toString();
    return generation.trim();
  }

String currentHostRestoreCommandId() {
    if (!appIdentity.isHost) return '';
    final stored = LocalDatabaseService.getString(AppStore._hostRestoreCommandIdKey);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    final markers = _syncChanges.where(
      (item) =>
          item.entityType == 'system' &&
          item.operation == 'restore_snapshot_ready',
    );
    if (markers.isEmpty) return '';
    final latest = markers.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final payload = latest.payload;
    final commandId = (payload['commandId'] ??
            payload['restoreCommandId'] ??
            payload['rebuildCommandId'] ??
            payload['snapshotGeneration'] ??
            payload['restoreGeneration'] ??
            '')
        .toString();
    return commandId.trim();
  }

Future<Map<String, dynamic>> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) async {
    final chunks = await exportUnifiedSnapshotChunks(
      kind: kind,
      maxItemsPerChunk: maxItemsPerChunk,
      maxEncodedPayloadBytes: maxEncodedPayloadBytes,
    );
    final manifest =
        chunks.isNotEmpty && chunks.first['snapshotManifest'] is Map
            ? Map<String, dynamic>.from(chunks.first['snapshotManifest'] as Map)
            : _unifiedSnapshotManifestJson(
                jobId: '',
                generatedAt: DateTime.now().toIso8601String(),
                kind: kind,
                totalChunks: chunks.length,
              );
    final generatedAt = chunks.isEmpty
        ? DateTime.now().toIso8601String()
        : (chunks.first['generatedAt'] ?? DateTime.now().toIso8601String())
            .toString();
    final generatedSequence = _syncChanges.isEmpty
        ? 0
        : _syncChanges
            .map((item) => item.sequence)
            .reduce((a, b) => a > b ? a : b);
    return <String, dynamic>{
      'snapshotFormat': UnifiedSnapshotManifest.format,
      'snapshotVersion': UnifiedSnapshotManifest.version,
      'snapshotKind': kind,
      'snapshotManifest': manifest,
      'snapshotChunks': chunks,
      'totalChunks': chunks.length,
      'syncGeneratedAt': generatedAt,
      'syncGeneratedSequence': generatedSequence,
      'snapshotGeneration': currentHostSnapshotGeneration(),
      'hostSnapshotGeneration': currentHostSnapshotGeneration(),
      'restoreCommandId': currentHostRestoreCommandId(),
      'hostRestoreCommandId': currentHostRestoreCommandId(),
    };
  }

Future<String> exportSyncSnapshotJson() async {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(await exportUnifiedSnapshotEnvelope(kind: 'full_store'));
  }

DateTime syncSnapshotGeneratedAtFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      return DateTime.tryParse(decoded['syncGeneratedAt']?.toString() ?? '') ??
          DateTime.now();
    } catch (_) {
      return DateTime.now();
    }
  }

int syncSnapshotGeneratedSequenceFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      return int.tryParse(decoded['syncGeneratedSequence']?.toString() ?? '') ??
          0;
    } catch (_) {
      return 0;
    }
  }

String exportSyncChangesJson({
    DateTime? since,
    int? sinceSequence,
    int? maxEncodedPayloadBytes,
  }) {
    final sequenceFloor = sinceSequence ?? 0;
    final earliestSequence = _earliestStoredAuthoritativeSequence();
    final latestSequence = _latestStoredAuthoritativeSequence();
    final hasHostRestoreMarker = _syncChanges.any(
      (item) =>
          item.entityType == 'system' &&
          item.operation == 'restore_snapshot_ready',
    );

    // If a client asks for an old sequence that has already been compacted,
    // incremental delivery cannot be trusted. The client must rebuild from a
    // full Host snapshot instead of silently accepting a partial event stream.
    //
    // Restore-specific guard: a manual Host backup restore can replace the
    // local sync log with a fresh, shorter log while existing Clients still
    // remember a higher lastAppliedSequence from the previous dataset. In that
    // case the normal `sequence > sinceSequence` query returns nothing, so the
    // Client never sees the restore marker. Treat `client sequence > latest
    // Host sequence` as a snapshot-required condition whenever a Host restore
    // marker is present.
    final needsSnapshot = sequenceFloor > 0 &&
        ((latestSequence > sequenceFloor &&
                earliestSequence > 0 &&
                sequenceFloor < earliestSequence - 1) ||
            (hasHostRestoreMarker &&
                latestSequence > 0 &&
                sequenceFloor > latestSequence));

    final allChanges = needsSnapshot
        ? <SyncChange>[]
        : (_syncChanges.where((item) {
            if (sequenceFloor > 0) return item.sequence > sequenceFloor;
            if (since != null) return !item.createdAt.isBefore(since);
            return true;
          }).toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence)));
    var changes = allChanges;
    var hasMoreChanges = false;
    final maxPayloadBytes = maxEncodedPayloadBytes ?? 0;
    if (!needsSnapshot && maxPayloadBytes > 0 && allChanges.isNotEmpty) {
      final limited = <SyncChange>[];
      var encodedBytes = utf8.encode('{"changes":[').length;
      for (final change in allChanges) {
        final changeBytes = utf8.encode(jsonEncode(change.toJson())).length;
        final separatorBytes = limited.isEmpty ? 0 : 1;
        if (limited.isNotEmpty &&
            encodedBytes + separatorBytes + changeBytes + 2 > maxPayloadBytes) {
          hasMoreChanges = true;
          break;
        }
        limited.add(change);
        encodedBytes += separatorBytes + changeBytes;
        if (encodedBytes + 2 > maxPayloadBytes) {
          hasMoreChanges = limited.length < allChanges.length;
          break;
        }
      }
      changes = limited;
    }
    final cursor = changes.isEmpty
        ? (since ?? DateTime.fromMillisecondsSinceEpoch(0))
        : changes
            .map((item) => item.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final generatedSequence = needsSnapshot
        ? latestSequence
        : (changes.isEmpty
            ? sequenceFloor
            : changes
                .map((item) => item.sequence)
                .reduce((a, b) => a > b ? a : b));
    return jsonEncode({
      'ok': true,
      'deviceId': _deviceId,
      'generatedAt': cursor.toIso8601String(),
      'generatedSequence': generatedSequence,
      'earliestSequence': earliestSequence,
      'latestSequence': latestSequence,
      'requestedSinceSequence': sequenceFloor,
      'hostSnapshotGeneration': currentHostSnapshotGeneration(),
      'snapshotGeneration': currentHostSnapshotGeneration(),
      'restoreCommandId': currentHostRestoreCommandId(),
      'hostRestoreCommandId': currentHostRestoreCommandId(),
      'needsSnapshot': needsSnapshot,
      'hasMoreChanges': hasMoreChanges,
      'changes': changes.map((item) => item.toJson()).toList(),
    });
  }

String _recoverySignature(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('checksum')
      ..remove('signature');
    final canonical = jsonEncode(
      Map.fromEntries(
        copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    final storeSecret =
        "${copy['storeId'] ?? ''}|${copy['branchId'] ?? ''}|${copy['recoveryKey'] ?? ''}|${copy['storeEpoch'] ?? ''}";
    return Hmac(
      sha256,
      utf8.encode(storeSecret),
    ).convert(utf8.encode(canonical)).toString();
  }

List<int> _deriveBackupKey(String password, String salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(
      pc.Pbkdf2Parameters(Uint8List.fromList(utf8.encode(salt)), 200000, 32),
    );
    return derivator.process(
      Uint8List.fromList(utf8.encode('store_manager_pro|backup_v3|$password')),
    );
  }

List<int> _deriveBackupKeyV2(String password, String salt) {
    List<int> digest = utf8.encode(
      'store_manager_pro|backup_v2|$salt|$password',
    );
    for (var i = 0; i < 100000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest;
  }

String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

List<int> _aesGcmEncrypt(List<int> plain, List<int> key, List<int> nonce) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(Uint8List.fromList(key)),
          128,
          Uint8List.fromList(nonce),
          Uint8List(0),
        ),
      );
    return cipher.process(Uint8List.fromList(plain));
  }

List<int> _aesGcmDecrypt(
    List<int> encrypted,
    List<int> key,
    List<int> nonce,
  ) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        false,
        pc.AEADParameters(
          pc.KeyParameter(Uint8List.fromList(key)),
          128,
          Uint8List.fromList(nonce),
          Uint8List(0),
        ),
      );
    return cipher.process(Uint8List.fromList(encrypted));
  }

List<int> _deriveBackupKeyV1(String password, String salt) {
    List<int> digest = utf8.encode(
      'store_manager_pro|backup_v1|$salt|$password',
    );
    for (var i = 0; i < 25000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest;
  }

List<int> _xorWithSha256Stream(List<int> input, List<int> key, String nonce) {
    final output = <int>[];
    var counter = 0;
    while (output.length < input.length) {
      final block = sha256.convert([
        ...key,
        ...utf8.encode(nonce),
        ...utf8.encode(counter.toString()),
      ]).bytes;
      for (final byte in block) {
        if (output.length >= input.length) break;
        output.add(input[output.length] ^ byte);
      }
      counter += 1;
    }
    return output;
  }

bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

Future<void> importBackupJson(String rawJson,
      {Set<String>? selectedSectionIds}) async {
    requirePermission(AppPermission.backupRestore);
    requireSensitiveActionAuthorization(SensitiveAction.backupRestore);
    if (appIdentity.isClient) {
      throw StateError('Import Backup is only available on the Host device.');
    }
    final auditActorId = _activeUser?.id ?? '';
    final auditActorName = _activeUser?.username ?? '';
    var decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    bool wants(String id) =>
        selectedSectionIds == null || selectedSectionIds.contains(id);
    final customImport = selectedSectionIds != null;
    final currentIdentityBeforeImport = appIdentity;
    decoded = normalizeBackupInventoryForStore(
      decoded,
      storeId: currentIdentityBeforeImport.storeId,
      branchId: currentIdentityBeforeImport.branchId,
      deviceId: _deviceId,
    );
    final preservePairedHostIdentity = currentIdentityBeforeImport.isHost;
    final liveHostConnectionEntries = preservePairedHostIdentity
        ? Map<String, String>.fromEntries(
            LocalDatabaseService.allEntries().entries.where(
                  (entry) => _shouldPreserveLiveHostConnectionKey(entry.key),
                ),
          )
        : const <String, String>{};
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map(
          (item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ??
        (decoded['quotations'] as List<dynamic>?) ??
        const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map(
          (item) =>
              SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final billsOfMaterials =
        (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
            .map(
              (item) => BillOfMaterials.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final manufacturingOrders =
        (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
            .map(
              (item) => ManufacturingOrder.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map(
          (item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final supplierProductPrices =
        (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
            .map(
              (item) => SupplierProductPrice.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final priceLists = (decoded['priceLists'] as List<dynamic>? ?? [])
        .map((item) =>
            PriceList.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPrices = (decoded['productPrices'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPriceOverrides =
        (decoded['productPriceOverrides'] as List<dynamic>? ?? [])
            .map((item) => ProductPriceOverride.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
    final productCosts = (decoded['productCosts'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductCost.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.productId.isNotEmpty)
        .toList();
    final costingMethodHistory =
        (decoded['costingMethodHistory'] as List<dynamic>? ?? [])
            .map((item) => CostingMethodHistory.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .where((item) => item.id.isNotEmpty)
            .toList();
    final inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
      decoded['inventoryCostingMethod'] is List
          ? ((decoded['inventoryCostingMethod'] as List).isEmpty
              ? null
              : (decoded['inventoryCostingMethod'] as List).first as String?)
          : decoded['inventoryCostingMethod'] as String?,
    );
    final inventoryCostLayers = (decoded['inventoryCostLayers']
                as List<dynamic>? ??
            [])
        .map((item) =>
            InventoryCostLayer.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.id.isNotEmpty && item.productId.isNotEmpty)
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map(
          (item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              StockMovement.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    List<Map<String, dynamic>> decodeEntityList(
      String key, {
      List<String> aliases = const <String>[],
    }) {
      Object? raw = decoded[key];
      for (final alias in aliases) {
        raw ??= decoded[alias];
      }
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }

    final warehouseInventoryRows = decodeEntityList(
      'warehouseInventory',
      aliases: <String>['warehouse_inventory'],
    );
    final stockOperationsRows = decodeEntityList(
      'stockOperations',
      aliases: <String>['stock_operations'],
    );
    final inventoryReconciliationRows = decodeEntityList(
      'inventoryReconciliations',
      aliases: <String>['inventory_reconciliations'],
    );
    final inventoryMigrationAdjustmentRows = decodeEntityList(
      'inventoryMigrationAdjustments',
      aliases: <String>['inventory_migration_adjustments'],
    );
    final phase8AccountingSnapshotRows = <String, List<Map<String, dynamic>>>{
      for (final key
          in LocalDatabaseService.phase8AccountingSnapshotTables.keys)
        if (decoded.containsKey(key)) key: decodeEntityList(key),
    };
    final inventoryCounts = (decoded['inventoryCounts'] as List<dynamic>? ?? [])
        .map(
          (item) => InventoryCountSession.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map(
          (item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final accountTransactions =
        (decoded['accountTransactions'] as List<dynamic>? ?? [])
            .map(
              (item) => AccountTransaction.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map(
          (item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final profile = decoded['storeProfile'] == null
        ? StoreProfile.defaults
        : StoreProfile.fromJson(
            Map<String, dynamic>.from(decoded['storeProfile'] as Map),
          );

    if (wants('products')) {
      _products
        ..clear()
        ..addAll(products);
    }
    if (wants('customers')) {
      _customers
        ..clear()
        ..addAll(customers);
    }
    if (wants('sales')) {
      _sales
        ..clear()
        ..addAll(sales);
    }
    if (wants('deliveryNotes')) {
      _deliveryNotes
        ..clear()
        ..addAll(deliveryNotes);
    }
    if (wants('manufacturing')) {
      _billsOfMaterials
        ..clear()
        ..addAll(billsOfMaterials);
      _manufacturingOrders
        ..clear()
        ..addAll(manufacturingOrders);
    }
    if (wants('saleQuotations')) {
      _saleQuotations
        ..clear()
        ..addAll(saleQuotations);
    }
    if (wants('suppliers')) {
      _suppliers
        ..clear()
        ..addAll(suppliers);
    }
    if (wants('supplierProductPrices')) {
      _supplierProductPrices
        ..clear()
        ..addAll(supplierProductPrices);
    }
    if (wants('priceLists')) {
      _priceLists
        ..clear()
        ..addAll(priceLists);
    }
    if (wants('productPrices')) {
      _productPrices
        ..clear()
        ..addAll(productPrices);
    }
    if (wants('productPriceOverrides')) {
      _productPriceOverrides
        ..clear()
        ..addAll(productPriceOverrides);
    }
    if (wants('productCosts')) {
      _productCosts
        ..clear()
        ..addAll(productCosts);
      _rebuildProductCostLookupCache();
    }
    if (wants('costingMethodHistory')) {
      _costingMethodHistory
        ..clear()
        ..addAll(costingMethodHistory);
    }
    if (wants('inventoryCostingMethod')) {
      _inventoryCostingMethod =
        _runtimeInventoryCostingMethod(inventoryCostingMethod);
    }
    if (wants('inventoryCostLayers')) {
      _inventoryCostLayers
        ..clear()
        ..addAll(inventoryCostLayers);
      _rebuildInventoryCostLayerLookupCache();
    }
    if (wants('categories')) {
      _categories
        ..clear()
        ..addAll(categories);
    }
    if (wants('brands')) {
      _brands
        ..clear()
        ..addAll(brands);
    }
    if (wants('units')) {
      _units
        ..clear()
        ..addAll(units);
    }
    _ensureCatalogDefaults();
    if (wants('expenses')) {
      _expenses
        ..clear()
        ..addAll(expenses);
    }
    if (wants('purchases')) {
      _purchases
        ..clear()
        ..addAll(purchases);
    }
    if (wants('stockMovements')) {
      _stockMovements
        ..clear()
        ..addAll(stockMovements);
    }
    if (wants('inventoryCounts')) {
      _inventoryCounts
        ..clear()
        ..addAll(inventoryCounts);
    }
    if (wants('warehouses')) {
      _warehouses
        ..clear()
        ..addAll(warehouses);
    }
    _ensureDefaultWarehouse();
    if (wants('accountTransactions')) {
      _accountTransactions
        ..clear()
        ..addAll(accountTransactions);
    }
    _invalidateAccountLedgerCache();
    final restoreFullDeviceBackup =
        decoded['backupType']?.toString() == 'full_device_backup';
    final sessionBeforeImport = _activeUser;
    final rememberBeforeImport = _rememberLogin;
    final localDatabaseEntries =
        restoreFullDeviceBackup && decoded['localDatabaseEntries'] is Map
            ? Map<String, dynamic>.from(decoded['localDatabaseEntries'] as Map)
            : const <String, dynamic>{};
    final importedSyncChanges = restoreFullDeviceBackup
        ? (decoded['syncChanges'] as List<dynamic>? ?? const <dynamic>[])
            .map(
              (item) =>
                  SyncChange.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList()
        : const <SyncChange>[];
    final importedSyncQueue = restoreFullDeviceBackup
        ? (decoded['syncQueue'] as List<dynamic>? ?? const <dynamic>[])
            .map(
              (item) => SyncQueueItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList()
        : const <SyncQueueItem>[];
    if (wants('syncChanges')) {
      _syncChanges
        ..clear()
        ..addAll(
          preservePairedHostIdentity
              ? const <SyncChange>[]
              : importedSyncChanges,
        );
    }
    if (wants('syncQueue')) {
      _syncQueue
        ..clear()
        ..addAll(
          preservePairedHostIdentity
              ? const <SyncQueueItem>[]
              : importedSyncQueue,
        );
    }
    if (wants('deviceId') &&
        restoreFullDeviceBackup &&
        !preservePairedHostIdentity &&
        decoded['deviceId']?.toString().trim().isNotEmpty == true) {
      _deviceId = decoded['deviceId'].toString().trim();
      await LocalDatabaseService.setString(AppStore._deviceIdKey, _deviceId);
    }
    if (wants('storeProfile')) {
      _storeProfile = profile;
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    // Business Backup may contain an old Store/Branch identity. When this
    // device is already a paired Host, keep the current sync identity so
    // existing Clients remain attached to the same store after Restore. The
    // restored file replaces business data only; it must not move the Host to a
    // different direct/LAN store namespace and make Clients miss the rebuild
    // marker.
    if (wants('appIdentity')) {
      final importedStoreId = decoded['storeId']?.toString().trim() ?? '';
      final importedBranchId = decoded['branchId']?.toString().trim() ?? '';
      if (restoreFullDeviceBackup &&
          decoded['appIdentity'] is Map &&
          !preservePairedHostIdentity) {
        _appIdentity = AppIdentity.fromJson(
          Map<String, dynamic>.from(decoded['appIdentity'] as Map),
        );
      } else {
        _appIdentity = currentIdentityBeforeImport.copyWith(
          storeId: preservePairedHostIdentity
              ? currentIdentityBeforeImport.storeId
              : (importedStoreId.isNotEmpty
                  ? importedStoreId.toUpperCase()
                  : currentIdentityBeforeImport.storeId),
          branchId: preservePairedHostIdentity
              ? currentIdentityBeforeImport.branchId
              : (importedBranchId.isNotEmpty
                  ? importedBranchId.toUpperCase()
                  : currentIdentityBeforeImport.branchId),
          deviceId: _deviceId,
          platform: _detectPlatform(),
          updatedAt: DateTime.now(),
        );
      }
    } else {
      _appIdentity = currentIdentityBeforeImport.copyWith(
        deviceId: _deviceId,
        platform: _detectPlatform(),
        updatedAt: DateTime.now(),
      );
    }
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    if (wants('themeMode') && decoded['themeMode'] is String) {
      await LocalDatabaseService.setString(
        AppStore._themeModeKey,
        decoded['themeMode'].toString(),
      );
    }
    if (wants('syncChanges') ||
        wants('syncQueue') ||
        wants('localDatabaseEntries')) {
      await LocalDatabaseService.deleteString('direct_last_pull_cursor');
    }
    if (wants('usersAndRoles')) {
      if (roles.isNotEmpty) {
        _roles
          ..clear()
          ..addAll(roles);
      }
      if (users.isNotEmpty) {
        _replaceUsersWithoutDuplicates(users);
      }
      await _ensureDefaultAdminUser();
    }
    if (wants('counters')) {
      final importedCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
      _invoiceCounter =
          importedCounter > 0 ? importedCounter : _loadInvoiceCounter();
      final importedPurchaseCounter =
          (decoded['purchaseCounter'] as num?)?.toInt() ?? 0;
      _purchaseCounter = importedPurchaseCounter > 0
          ? importedPurchaseCounter
          : _loadPurchaseCounter();
    }
    _normalizeCustomers();

    // Full-device backups are expected to restore the whole local database, not
    // only the typed business collections above. Clear the current local store
    // first so stale keys from the previous installation cannot survive, then
    // save the typed collections and finally re-apply the raw exported entries
    // (settings, identity, cursors, login/session flags, feature preferences,
    // and any future keys not represented by AppStore fields yet).
    if (!customImport &&
        restoreFullDeviceBackup &&
        localDatabaseEntries.isNotEmpty) {
      await LocalDatabaseService.clearAll();
    }

    await _saveAll();
    // Users and roles are persisted in their own typed tables and are not part
    // of the generic business save batch. Re-save them after a full-device
    // clear so the following runtime reload keeps the live session intact.
    await _saveRolesAndUsers();

    if (restoreFullDeviceBackup) {
      await LocalDatabaseService.runSqliteAuthoritativeTransaction(() async {
        await LocalDatabaseService.replaceWarehouseInventoryRowsImmediate(
          warehouseInventoryRows,
          allowNegativeStock: _storeProfile.allowNegativeStock,
        );
        await LocalDatabaseService.replaceStockOperationsRowsImmediate(
          stockOperationsRows,
        );
        await LocalDatabaseService.replaceInventoryReconciliationsRowsImmediate(
          inventoryReconciliationRows,
        );
        await LocalDatabaseService
            .replaceInventoryMigrationAdjustmentsRowsImmediate(
          inventoryMigrationAdjustmentRows,
        );
        if (phase8AccountingSnapshotRows.isNotEmpty) {
          await LocalDatabaseService
              .replacePhase8AccountingSnapshotRowsImmediate(
            phase8AccountingSnapshotRows,
          );
        }
      });
    }

    if (wants('localDatabaseEntries') &&
        restoreFullDeviceBackup &&
        localDatabaseEntries.isNotEmpty) {
      // Restore raw exported keys, but keep the current paired Host connection
      // keys. The import remains a full data restore; the live Host/client link
      // is intentionally device-local and must keep using the current tokens,
      // settings, and registries so existing Clients can receive the rebuild
      // command generated below.
      final keysToSkip = <String>{
        AppStore._hostSnapshotGenerationKey,
        AppStore._hostRestoreCommandIdKey,
        AppStore._syncChangesKey,
        AppStore._syncQueueKey,
        AppStore._syncSequenceKey,
        'direct_last_pull_cursor',
      };
      for (final entry in localDatabaseEntries.entries) {
        final key = entry.key.toString();
        if (keysToSkip.contains(key)) continue;
        if (BusinessSqliteStore.isTypedEntityKey(key)) continue;
        if (preservePairedHostIdentity &&
            _shouldPreserveLiveHostConnectionKey(key)) {
          continue;
        }
        if (preservePairedHostIdentity &&
            _isHostRebuildRuntimeKeyForAnotherImport(key)) {
          continue;
        }
        await LocalDatabaseService.setString(
          key,
          entry.value?.toString() ?? '',
        );
      }
      for (final entry in liveHostConnectionEntries.entries) {
        await LocalDatabaseService.setString(entry.key, entry.value);
      }
      if (sessionBeforeImport != null) {
        for (final user in _users) {
          if (user.id == sessionBeforeImport.id && user.isActive) {
            _activeUser = user;
            _rememberLogin = rememberBeforeImport;
            await LocalDatabaseService.setString(AppStore._activeUserKey, user.id);
            await LocalDatabaseService.setString(
              AppStore._rememberLoginKey,
              rememberBeforeImport ? 'true' : 'false',
            );
            break;
          }
        }
      }
      await reloadAllAfterDatabaseChange();
    }

    if (appIdentity.isHost) {
      final restoreGeneration =
          DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      final restoreCommandId = 'host_restore_rebuild_$restoreGeneration';
      await LocalDatabaseService.setString(
        AppStore._hostSnapshotGenerationKey,
        restoreGeneration,
      );
      await LocalDatabaseService.setString(
        AppStore._hostRestoreCommandIdKey,
        restoreCommandId,
      );
      _recordSyncChange(
        entityType: 'system',
        entityId: 'store',
        operation: 'restore_snapshot_ready',
        payload: {
          'commandId': restoreCommandId,
          'restoreCommandId': restoreCommandId,
          'rebuildCommandId': restoreCommandId,
          'restoredAt': DateTime.now().toIso8601String(),
          'snapshotGeneration': restoreGeneration,
          'restoreGeneration': restoreGeneration,
          'reason': restoreFullDeviceBackup
              ? 'manual_full_device_backup_import'
              : 'manual_backup_import',
          'storeId': appIdentity.storeId,
          'branchId': appIdentity.branchId,
        },
      );
      await _saveSyncStateOnly();
    }

    await AuditLogger.record(
      entityType: 'backup',
      entityId: appIdentity.storeId,
      action: 'restore_success',
      summary: 'Backup restore completed',
      details: jsonEncode(<String, Object?>{
        'fullDeviceBackup': restoreFullDeviceBackup,
        'customImport': customImport,
        'selectedSections': selectedSectionIds == null
            ? null
            : (selectedSectionIds.toList()..sort()),
      }),
      userId: auditActorId,
      userName: auditActorName,
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'backup',
      isImportant: true,
    );
    notifyListeners();
  }

bool _shouldPreserveLiveHostConnectionKey(String key) {
    return key == AppStore._appIdentityKey ||
        key == AppStore._deviceIdKey ||
        key == 'lan_sync_settings_v2' ||
        key == 'vps_api_base_url' ||
        key == 'direct_control_auto_sync_enabled' ||
        key == 'direct_control_auto_sync_interval_seconds' ||
        key == 'host_authoritative_sync_device_state_v1' ||
        key == 'host_authoritative_sync_peer_states_v1' ||
        key == 'sync_monitoring_suspended_devices_v1' ||
        key == 'sync_monitoring_deleted_devices_v1' ||
        key == 'sync_monitoring_deleted_device_tokens_v1' ||
        key == 'sync_monitoring_wipe_pending_devices_v1' ||
        key == 'sync_monitoring_wipe_pending_device_tokens_v1';
  }

bool _isHostRebuildRuntimeKeyForAnotherImport(String key) {
    return key.startsWith('applied_host_snapshot_generation_') ||
        key.startsWith('in_progress_host_snapshot_generation_') ||
        key.startsWith('failed_host_snapshot_generation_') ||
        key.startsWith('in_progress_host_snapshot_generation_at_') ||
        key.startsWith('failed_host_snapshot_generation_at_') ||
        key.startsWith('requested_host_snapshot_generation_') ||
        key.startsWith('requested_host_snapshot_generation_at_') ||
        key.startsWith('executed_host_restore_command_') ||
        key.startsWith('in_progress_host_restore_command_');
  }

int _readVersion(dynamic item) {
    try {
      return item.version as int;
    } catch (_) {
      return 1;
    }
  }

DateTime _readUpdatedAt(dynamic item) {
    try {
      final updatedAt = item.updatedAt as DateTime;
      return updatedAt;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

List<AppUser> _dedupeUsersByUsername(List<AppUser> input) {
    final byUsername = <String, AppUser>{};
    for (final user in input) {
      final key = user.username.trim().toLowerCase();
      if (key.isEmpty) continue;
      final current = byUsername[key];
      if (current == null ||
          (user.updatedAt ??
                  user.createdAt ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .isAfter(
            current.updatedAt ??
                current.createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0),
          )) {
        byUsername[key] = user.copyWith(username: key);
      }
    }
    return byUsername.values.toList();
  }

void _replaceUsersWithoutDuplicates(List<AppUser> incoming) {
    final activeBeforeReplace = _activeUser;
    final normalizedIncoming = List<AppUser>.from(incoming);
    // A business-data reset does not log the operator out. Keep the active
    // session when a transient empty reload reaches the save path before the
    // users table has been rehydrated.
    if (normalizedIncoming.isEmpty && activeBeforeReplace != null) {
      normalizedIncoming.add(activeBeforeReplace);
    }
    _users
      ..clear()
      ..addAll(_dedupeUsersByUsername(normalizedIncoming));
    if (_activeUser != null &&
        !_users.any((user) => user.id == _activeUser!.id && user.isActive)) {
      _activeUser = null;
      unawaited(LocalDatabaseService.setString(AppStore._activeUserKey, ''));
    }
  }

void _mergeUsersWithoutUsernameDuplicates(List<AppUser> incoming) {
    final merged = <AppUser>[..._users];
    for (final remote in incoming) {
      final remoteName = remote.username.trim().toLowerCase();
      if (remoteName.isEmpty) continue;
      final sameIdIndex = merged.indexWhere((user) => user.id == remote.id);
      final sameNameIndex = merged.indexWhere(
        (user) => user.username.trim().toLowerCase() == remoteName,
      );
      final index = sameIdIndex != -1 ? sameIdIndex : sameNameIndex;
      final normalizedRemote = remote.copyWith(username: remoteName);
      if (index == -1) {
        merged.add(normalizedRemote);
      } else if ((normalizedRemote.updatedAt ??
              normalizedRemote.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0))
          .isAfter(
        merged[index].updatedAt ??
            merged[index].createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0),
      )) {
        merged[index] = normalizedRemote;
      }
    }
    _replaceUsersWithoutDuplicates(merged);
  }

void _mergeByUpdatedAt<T>(
    List<T> local,
    List<T> incoming,
    String Function(T item) idOf,
  ) {
    for (final remote in incoming) {
      final index = local.indexWhere((item) => idOf(item) == idOf(remote));
      if (index == -1) {
        local.add(remote);
        continue;
      }
      if (_readUpdatedAt(remote).isAfter(_readUpdatedAt(local[index]))) {
        local[index] = remote;
      }
    }
  }

void _mergeSyncChanges(List<SyncChange> incoming) {
    final existingIds = _syncChanges.map((item) => item.id).toSet();
    for (final change in incoming) {
      if (!existingIds.contains(change.id)) {
        _syncChanges.add(change);
        existingIds.add(change.id);
      }
    }
  }

Future<void> mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  }) async {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final products = (decoded['products'] as List<dynamic>? ?? [])
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final customers = (decoded['customers'] as List<dynamic>? ?? [])
        .map(
          (item) => Customer.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final sales = (decoded['sales'] as List<dynamic>? ?? [])
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final rawSaleQuotations = (decoded['saleQuotations'] as List<dynamic>?) ??
        (decoded['quotations'] as List<dynamic>?) ??
        const <dynamic>[];
    final saleQuotations = rawSaleQuotations
        .map(
          (item) =>
              SaleQuotation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final deliveryNotes = (decoded['deliveryNotes'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              DeliveryNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final billsOfMaterials =
        (decoded['billsOfMaterials'] as List<dynamic>? ?? [])
            .map(
              (item) => BillOfMaterials.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final manufacturingOrders =
        (decoded['manufacturingOrders'] as List<dynamic>? ?? [])
            .map(
              (item) => ManufacturingOrder.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final suppliers = (decoded['suppliers'] as List<dynamic>? ?? [])
        .map(
          (item) => Supplier.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final supplierProductPrices =
        (decoded['supplierProductPrices'] as List<dynamic>? ?? [])
            .map(
              (item) => SupplierProductPrice.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final priceLists = (decoded['priceLists'] as List<dynamic>? ?? [])
        .map((item) =>
            PriceList.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPrices = (decoded['productPrices'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductPrice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final productPriceOverrides =
        (decoded['productPriceOverrides'] as List<dynamic>? ?? [])
            .map((item) => ProductPriceOverride.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
    final productCosts = (decoded['productCosts'] as List<dynamic>? ?? [])
        .map((item) =>
            ProductCost.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.productId.isNotEmpty)
        .toList();
    final costingMethodHistory =
        (decoded['costingMethodHistory'] as List<dynamic>? ?? [])
            .map((item) => CostingMethodHistory.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .where((item) => item.id.isNotEmpty)
            .toList();
    final inventoryCostingMethod = InventoryCostingMethodJson.fromCode(
      decoded['inventoryCostingMethod'] is List
          ? ((decoded['inventoryCostingMethod'] as List).isEmpty
              ? null
              : (decoded['inventoryCostingMethod'] as List).first as String?)
          : decoded['inventoryCostingMethod'] as String?,
    );
    final inventoryCostLayers = (decoded['inventoryCostLayers']
                as List<dynamic>? ??
            [])
        .map((item) =>
            InventoryCostLayer.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((item) => item.id.isNotEmpty && item.productId.isNotEmpty)
        .toList();
    final categories = (decoded['categories'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final brands = (decoded['brands'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final units = (decoded['units'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final expenses = (decoded['expenses'] as List<dynamic>? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final purchases = (decoded['purchases'] as List<dynamic>? ?? [])
        .map(
          (item) => Purchase.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final stockMovements = (decoded['stockMovements'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              StockMovement.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final warehouses = (decoded['warehouses'] as List<dynamic>? ?? [])
        .map(
          (item) => Warehouse.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final accountTransactions =
        (decoded['accountTransactions'] as List<dynamic>? ?? [])
            .map(
              (item) => AccountTransaction.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final roles = (decoded['roles'] as List<dynamic>? ?? [])
        .map(
          (item) => UserRole.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final users = (decoded['users'] as List<dynamic>? ?? [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();

    _mergeByUpdatedAt<Product>(_products, products, (item) => item.id);
    _mergeByUpdatedAt<Customer>(_customers, customers, (item) => item.id);
    _mergeByUpdatedAt<Sale>(_sales, sales, (item) => item.id);
    _mergeByUpdatedAt<SaleQuotation>(
      _saleQuotations,
      saleQuotations,
      (item) => item.id,
    );
    _mergeByUpdatedAt<DeliveryNote>(
      _deliveryNotes,
      deliveryNotes,
      (item) => item.id,
    );
    _mergeByUpdatedAt<BillOfMaterials>(
      _billsOfMaterials,
      billsOfMaterials,
      (item) => item.id,
    );
    _mergeByUpdatedAt<ManufacturingOrder>(
      _manufacturingOrders,
      manufacturingOrders,
      (item) => item.id,
    );
    _mergeByUpdatedAt<Supplier>(_suppliers, suppliers, (item) => item.id);
    _mergeByUpdatedAt<SupplierProductPrice>(
      _supplierProductPrices,
      supplierProductPrices,
      (item) => item.id,
    );
    _mergeByUpdatedAt<PriceList>(_priceLists, priceLists, (item) => item.id);
    _mergeByUpdatedAt<ProductPrice>(
        _productPrices, productPrices, (item) => item.id);
    _mergeByUpdatedAt<ProductPriceOverride>(
        _productPriceOverrides, productPriceOverrides, (item) => item.id);
    _mergeByUpdatedAt<ProductCost>(
        _productCosts, productCosts, (item) => item.productId);
    _mergeByUpdatedAt<CostingMethodHistory>(
        _costingMethodHistory, costingMethodHistory, (item) => item.id);
    _inventoryCostingMethod =
        _runtimeInventoryCostingMethod(inventoryCostingMethod);
    _mergeByUpdatedAt<InventoryCostLayer>(
        _inventoryCostLayers, inventoryCostLayers, (item) => item.id);
    _rebuildProductCostLookupCache();
    _rebuildInventoryCostLayerLookupCache();
    _mergeByUpdatedAt<CatalogItem>(_categories, categories, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_brands, brands, (item) => item.id);
    _mergeByUpdatedAt<CatalogItem>(_units, units, (item) => item.id);
    _mergeByUpdatedAt<Expense>(_expenses, expenses, (item) => item.id);
    _mergeByUpdatedAt<Purchase>(_purchases, purchases, (item) => item.id);
    _mergeByUpdatedAt<StockMovement>(
      _stockMovements,
      stockMovements,
      (item) => item.id,
    );
    _mergeByUpdatedAt<Warehouse>(_warehouses, warehouses, (item) => item.id);
    _ensureDefaultWarehouse();
    _mergeByUpdatedAt<AccountTransaction>(
      _accountTransactions,
      accountTransactions,
      (item) => item.id,
    );
    _invalidateAccountLedgerCache();
    if (decoded['storeProfile'] != null) {
      _storeProfile = StoreProfile.fromJson(
        Map<String, dynamic>.from(decoded['storeProfile'] as Map),
      );
      AccountingService.configureMoneyPolicy(_storeProfile);
    }
    // Never overwrite the local device identity during LAN pull/merge.
    // The remote snapshot belongs to the Host, while this device must keep
    // its own deviceId/deviceName/role so new local changes are queued
    // correctly toward the Host.
    _appIdentity = appIdentity.copyWith(
      deviceId: _deviceId,
      platform: _detectPlatform(),
    );
    await LocalDatabaseService.setString(
      AppStore._appIdentityKey,
      jsonEncode(_appIdentity!.toJson()),
    );
    _mergeByUpdatedAt<UserRole>(_roles, roles, (item) => item.id);
    _mergeUsersWithoutUsernameDuplicates(users);
    final nowForMergedRemoteChanges = DateTime.now();
    _mergeSyncChanges(
      markSynced
          ? syncChanges
          : syncChanges.map((change) {
              if (change.deviceId == _deviceId || change.isSynced) {
                return change;
              }
              return change.copyWith(
                isSynced: true,
                syncedAt: nowForMergedRemoteChanges,
              );
            }).toList(),
    );

    final importedCounter = (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
    if (importedCounter > _invoiceCounter) _invoiceCounter = importedCounter;
    final importedPurchaseCounter =
        (decoded['purchaseCounter'] as num?)?.toInt() ?? 0;
    if (importedPurchaseCounter > _purchaseCounter) {
      _purchaseCounter = importedPurchaseCounter;
    }

    if (markSynced) {
      final now = DateTime.now();
      for (var i = 0; i < _syncChanges.length; i++) {
        _syncChanges[i] = _syncChanges[i].copyWith(
          isSynced: true,
          syncedAt: now,
        );
      }
    }

    _ensureCatalogDefaults();
    _normalizeCustomers();
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    notifyListeners();
  }

}
