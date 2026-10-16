part of 'app_store.dart';

extension _AppStoreRecoveryReset on AppStoreRecoveryService {
  Future<void> replaceFromSnapshotPayloadDirectToSqlite(
    Map<String, dynamic> decoded, {
    bool preserveLocalIdentityForLanClient = false,
  }) async {
    final unifiedChunks = decoded['snapshotChunks'];
    if (unifiedChunks is List) {
      decoded = store._unifiedSnapshotPayloadFromChunks(
        unifiedChunks
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false),
      );
    }
    final effectiveStoreProfile = _effectiveStoreProfile(decoded);
    _assertNegativeStockPolicy(
      decoded,
      allowNegativeStock: effectiveStoreProfile.allowNegativeStock,
    );
    final importedStockMovements = _snapshotListMaps(decoded, 'stockMovements');
    final AppIdentity? importedIdentity = preserveLocalIdentityForLanClient
        ? _identityForLanSnapshotImport(decoded)
        : decoded['appIdentity'] is Map
            ? AppIdentity.fromJson(
                Map<String, dynamic>.from(decoded['appIdentity'] as Map),
              ).copyWith(
                deviceId: store._deviceId,
                platform: store._detectPlatform(),
              )
            : null;
    try {
      await StartupTimingService.measure(
        'snapshot_import.direct_payload_to_sqlite',
        () async {
          await LocalDatabaseService.runSqliteAuthoritativeTransaction(
              () async {
            Future<void> replaceRows(
              String storageKey,
              List<Map<String, dynamic>> rows,
            ) async {
              await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
                storageKey,
                rows,
                sortIndices: List<int?>.generate(rows.length, (index) => index),
              );
            }

            final now = DateTime.now();
            final rawSyncChanges = _snapshotListMaps(decoded, 'syncChanges');
            final syncChangesForClient = preserveLocalIdentityForLanClient
                ? rawSyncChanges.map((item) {
                    final copy = Map<String, dynamic>.from(item);
                    copy['isSynced'] = true;
                    copy['syncedAt'] = now.toIso8601String();
                    return copy;
                  }).toList(growable: false)
                : rawSyncChanges;
            final rawSyncQueue = preserveLocalIdentityForLanClient
                ? const <Map<String, dynamic>>[]
                : _snapshotListMaps(decoded, 'syncQueue');

            await replaceRows(
                AppStore._productsKey, _snapshotListMaps(decoded, 'products'));
            await LocalDatabaseService.replaceInventoryBatchRowsImmediate(
              batches: _snapshotListMaps(decoded, 'inventoryBatches'),
              balances: _snapshotListMaps(decoded, 'inventoryBatchBalances'),
            );
            final writes = <Future<void>>[
              replaceRows(AppStore._productsKey,
                  _snapshotListMaps(decoded, 'products')),
              replaceRows(AppStore._customersKey,
                  _snapshotListMaps(decoded, 'customers')),
              replaceRows(
                  AppStore._salesKey, _snapshotListMaps(decoded, 'sales')),
              replaceRows(
                AppStore._saleQuotationsKey,
                _snapshotListMaps(decoded, 'saleQuotations',
                    aliases: <String>['quotations']),
              ),
              replaceRows(AppStore._deliveryNotesKey,
                  _snapshotListMaps(decoded, 'deliveryNotes')),
              replaceRows(AppStore._billsOfMaterialsKey,
                  _snapshotListMaps(decoded, 'billsOfMaterials')),
              replaceRows(AppStore._manufacturingOrdersKey,
                  _snapshotListMaps(decoded, 'manufacturingOrders')),
              replaceRows(AppStore._suppliersKey,
                  _snapshotListMaps(decoded, 'suppliers')),
              replaceRows(
                AppStore._supplierProductPricesKey,
                _snapshotListMaps(decoded, 'supplierProductPrices'),
              ),
              replaceRows(AppStore._priceListsKey,
                  _snapshotListMaps(decoded, 'priceLists')),
              replaceRows(AppStore._productPricesKey,
                  _snapshotListMaps(decoded, 'productPrices')),
              replaceRows(
                AppStore._productPriceHistoryKey,
                _snapshotListMaps(decoded, 'productPriceHistory'),
              ),
              replaceRows(
                AppStore._productPriceOverridesKey,
                _snapshotListMaps(decoded, 'productPriceOverrides'),
              ),
              replaceRows(AppStore._productCostsKey,
                  _snapshotListMaps(decoded, 'productCosts')),
              replaceRows(
                AppStore._costingMethodHistoryKey,
                _snapshotListMaps(decoded, 'costingMethodHistory'),
              ),
              replaceRows(
                AppStore._inventoryCostLayersKey,
                _snapshotListMaps(decoded, 'inventoryCostLayers'),
              ),
              replaceRows(AppStore._categoriesKey,
                  _snapshotListMaps(decoded, 'categories')),
              replaceRows(
                  AppStore._brandsKey, _snapshotListMaps(decoded, 'brands')),
              replaceRows(
                  AppStore._unitsKey, _snapshotListMaps(decoded, 'units')),
              replaceRows(AppStore._expensesKey,
                  _snapshotListMaps(decoded, 'expenses')),
              replaceRows(AppStore._purchasesKey,
                  _snapshotListMaps(decoded, 'purchases')),
              replaceRows(AppStore._stockMovementsKey, importedStockMovements),
              LocalDatabaseService.replaceWarehouseInventoryRowsImmediate(
                _snapshotListMaps(
                  decoded,
                  'warehouseInventory',
                  aliases: <String>['warehouse_inventory'],
                ),
                allowNegativeStock: effectiveStoreProfile.allowNegativeStock,
              ),
              LocalDatabaseService.replaceStockOperationsRowsImmediate(
                _snapshotListMaps(
                  decoded,
                  'stockOperations',
                  aliases: <String>['stock_operations'],
                ),
              ),
              LocalDatabaseService.replaceInventoryReconciliationsRowsImmediate(
                _snapshotListMaps(
                  decoded,
                  'inventoryReconciliations',
                  aliases: <String>['inventory_reconciliations'],
                ),
              ),
              LocalDatabaseService
                  .replaceInventoryMigrationAdjustmentsRowsImmediate(
                _snapshotListMaps(
                  decoded,
                  'inventoryMigrationAdjustments',
                  aliases: <String>['inventory_migration_adjustments'],
                ),
              ),
              if (LocalDatabaseService.phase8AccountingSnapshotTables.keys
                  .any(decoded.containsKey))
                LocalDatabaseService
                    .replacePhase8AccountingSnapshotRowsImmediate(
                  <String, List<Map<String, dynamic>>>{
                    for (final key in LocalDatabaseService
                        .phase8AccountingSnapshotTables.keys)
                      if (decoded.containsKey(key))
                        key: _snapshotListMaps(decoded, key),
                  },
                ),
              replaceRows(AppStore._inventoryCountsKey,
                  _snapshotListMaps(decoded, 'inventoryCounts')),
              replaceRows(AppStore._warehousesKey,
                  _snapshotListMaps(decoded, 'warehouses')),
              replaceRows(
                AppStore._accountTransactionsKey,
                _snapshotListMaps(decoded, 'accountTransactions'),
              ),
              replaceRows(
                  AppStore._rolesKey, _snapshotListMaps(decoded, 'roles')),
              replaceRows(
                  AppStore._usersKey, _snapshotListMaps(decoded, 'users')),
              LocalDatabaseService.setString(
                AppStore._inventoryCostingMethodKey,
                _snapshotScalarString(
                  decoded,
                  'inventoryCostingMethod',
                  fallback: store._inventoryCostingMethod.code,
                ),
              ),
              LocalDatabaseService.setString(
                AppStore._storeProfileKey,
                jsonEncode(
                  decoded['storeProfile'] is Map
                      ? Map<String, dynamic>.from(
                          decoded['storeProfile'] as Map)
                      : store._storeProfile.toJson(),
                ),
              ),
              LocalDatabaseService.setString(
                AppStore._invoiceCounterKey,
                ((decoded['invoiceCounter'] as num?)?.toInt() ??
                        store._invoiceCounter)
                    .toString(),
              ),
              LocalDatabaseService.setString(
                AppStore._purchaseCounterKey,
                ((decoded['purchaseCounter'] as num?)?.toInt() ??
                        store._purchaseCounter)
                    .toString(),
              ),
              LocalDatabaseService.setString(
                AppStore._syncChangesKey,
                jsonEncode(syncChangesForClient),
              ),
              LocalDatabaseService.setString(
                AppStore._syncQueueKey,
                jsonEncode(rawSyncQueue),
              ),
              LocalDatabaseService.setString(
                AppStore._syncSequenceKey,
                _snapshotScalarString(
                  decoded,
                  'syncSequence',
                  fallback: _snapshotScalarString(
                    decoded,
                    'generatedSequence',
                    fallback: store._syncSequence.toString(),
                  ),
                ),
              ),
              LocalDatabaseService.setString(AppStore._schemaVersionKey, '17'),
            ];

            if (importedIdentity != null) {
              writes.add(
                LocalDatabaseService.setString(
                  AppStore._appIdentityKey,
                  jsonEncode(importedIdentity.toJson()),
                ),
              );
            }

            await Future.wait(writes);
            // Re-run document materialization after batch rows exist so the
            // allocation child tables can satisfy their foreign keys.
            await replaceRows(
                AppStore._salesKey, _snapshotListMaps(decoded, 'sales'));
            await replaceRows(AppStore._purchasesKey,
                _snapshotListMaps(decoded, 'purchases'));
          });
          await LocalDatabaseService.flushPendingWrites();
        },
        category: 'snapshot',
      );
    } catch (_) {
      await LocalDatabaseService.refreshSqliteMirrorAfterRollback();
      rethrow;
    }

    store._stockMovements
      ..clear()
      ..addAll(
        importedStockMovements
            .map((item) => StockMovement.fromJson(item))
            .toList(growable: false),
      );
    if (importedIdentity != null) {
      store._appIdentity = importedIdentity;
    }

    await _refreshRuntimeAfterRecovery(
      loadStoreProfile: true,
      runUnifiedBatchClosure: false,
    );
    await _refreshSummaryTables();
    store._refreshUi();
  }

  List<Map<String, dynamic>> _snapshotListMaps(
    Map<String, dynamic> decoded,
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

  String _snapshotScalarString(
    Map<String, dynamic> decoded,
    String key, {
    String fallback = '',
  }) {
    final raw = decoded[key];
    if (raw is List) {
      return raw.isEmpty ? fallback : (raw.first?.toString() ?? fallback);
    }
    return raw?.toString() ?? fallback;
  }

  AppIdentity _identityForLanSnapshotImport(Map<String, dynamic> decoded) {
    final local = store.appIdentity;
    final raw = decoded['appIdentity'];
    if (raw is! Map) {
      return local.copyWith(
        deviceId: store._deviceId,
        platform: store._detectPlatform(),
      );
    }

    final imported = AppIdentity.fromJson(Map<String, dynamic>.from(raw));

    // A LAN snapshot contains the Host identity. It must never replace the
    // live Client identity, otherwise the Client can inherit the Host's role,
    // sync mode, or active Direct transport immediately after pairing.
    return local.copyWith(
      storeId: imported.storeId.isNotEmpty ? imported.storeId : local.storeId,
      branchId:
          imported.branchId.isNotEmpty ? imported.branchId : local.branchId,
      deviceId: store._deviceId,
      platform: store._detectPlatform(),
      deviceRole: DeviceRole.client,
      appRole: imported.appRole,
      syncMode: local.syncMode == SyncMode.localOnly
          ? SyncMode.lanOnly
          : local.syncMode,
      hostDeviceId:
          imported.deviceId.isNotEmpty ? imported.deviceId : local.hostDeviceId,
      controlPlaneTenantId: imported.controlPlaneTenantId.isNotEmpty
          ? imported.controlPlaneTenantId
          : local.controlPlaneTenantId,
      deviceToken: local.deviceToken.trim().isNotEmpty
          ? local.deviceToken
          : imported.deviceToken,
      // Deliberately preserve local.activeSyncTransport. The transport was
      // selected by the pairing flow and is not part of Host snapshot data.
    );
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

  Future<void> _refreshRuntimeAfterRecovery({
    bool loadStoreProfile = false,
    bool runUnifiedBatchClosure = true,
  }) async {
    if (loadStoreProfile) {
      store._storeProfile = store._loadStoreProfile();
      AccountingService.configureMoneyPolicy(store._storeProfile);
    }
    store._rememberLogin =
        LocalDatabaseService.getString(AppStore._rememberLoginKey) == 'true';
    // Snapshot imports write the authoritative users/roles directly to
    // SQLite. Reload them before restoring the session; otherwise Login
    // continues to validate against the pre-import in-memory list (usually
    // the default local admin) and the synced user appears to be missing.
    store._roles
      ..clear()
      ..addAll(await store._loadRoles());
    store._users
      ..clear()
      ..addAll(await store._loadUsers());
    await store._loadSessionPermissionsFromStorage();
    await store._restoreActiveUserFromStorage();
    await store._refreshAuthFlags();
    store._inventoryCostingMethod = store._runtimeInventoryCostingMethod(
      InventoryCostingMethodJson.fromCode(
        LocalDatabaseService.getString(AppStore._inventoryCostingMethodKey),
      ),
    );
    store._invoiceCounter = store._loadInvoiceCounter();
    store._purchaseCounter = store._loadPurchaseCounter();
    store._syncSequence = store._loadSyncSequence();

    if (runUnifiedBatchClosure &&
        !kIsWeb &&
        LocalDatabaseService.isSqliteAuthoritative &&
        !LocalDatabaseService.isSqliteDatabaseForTesting) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        await UnifiedBatchPhase4ClosureService(db).close(
          storeId: store.appIdentity.storeId,
          branchId: store.appIdentity.branchId,
          deviceId: store.deviceId,
          allowNegativeStock: store._storeProfile.allowNegativeStock,
        );
        await LocalDatabaseService.setString(
          AppStore._inventoryCostingMethodKey,
          InventoryCostingMethod.batch.code,
        );
        store._inventoryCostingMethod = InventoryCostingMethod.batch;
      }
    }
  }

  Future<void> _refreshSummaryTables() async {
    final db = SqliteMigrationManager.database;
    if (db == null) return;
    await BusinessSqliteStore.refreshSummaryTables(
      db,
      reference: DateTime.now(),
      force: true,
    );
  }

  StoreProfile _effectiveStoreProfile(
    Map<String, dynamic> decoded, {
    bool useIncomingStoreProfile = true,
  }) {
    if (!useIncomingStoreProfile) return store._storeProfile;
    final raw = decoded['storeProfile'];
    if (raw is! Map) return store._storeProfile;
    try {
      return StoreProfile.fromJson(Map<String, dynamic>.from(raw));
    } catch (error) {
      throw StateError('Snapshot contains an invalid Store profile: $error');
    }
  }

  void _assertNegativeStockPolicy(
    Map<String, dynamic> decoded, {
    required bool allowNegativeStock,
  }) {
    if (allowNegativeStock) return;

    double valueOf(Map<String, dynamic> row, String key) {
      final value = row[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final warehouseRows = _snapshotListMaps(
      decoded,
      'warehouseInventory',
      aliases: <String>['warehouse_inventory'],
    );
    if (warehouseRows.any((row) => valueOf(row, 'quantity') < -0.000001)) {
      throw StateError(
        'Backup contains negative warehouse inventory while negative stock is disabled.',
      );
    }

    final batchBalances = _snapshotListMaps(decoded, 'inventoryBatchBalances');
    if (batchBalances.any((row) => valueOf(row, 'quantity') < -0.000001)) {
      throw StateError(
        'Backup contains negative batch inventory while negative stock is disabled.',
      );
    }
  }
}
