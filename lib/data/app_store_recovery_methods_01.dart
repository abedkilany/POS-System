part of 'app_store.dart';

extension AppStoreRecoveryServiceSplitPart1 on AppStoreRecoveryService {
  Future<void> importBackupJson(
    String rawJson, {
    Set<String>? selectedSectionIds,
  }) async {
    store.requirePermission(AppPermission.backupRestore);
    store._requireSensitiveActionAuthorization(SensitiveAction.backupRestore);
    if (store.appIdentity.isClient) {
      throw StateError('Import Backup is only available on the Host device.');
    }
    if (!LocalDatabaseService.isSqliteAuthoritative) {
      // Keep the non-SQLite storage adapter behavior available for web/test
      // stores until that backend has a transactional restore implementation.
      await _AppStoreSplitBackupRecoveryPart3(store).importBackupJson(
        rawJson,
        selectedSectionIds: selectedSectionIds,
      );
      return;
    }
    final auditActorId = store._activeUser?.id ?? '';
    final auditActorName = store._activeUser?.username ?? '';

    var decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final customImport = selectedSectionIds != null;
    bool wants(String id) =>
        selectedSectionIds == null || selectedSectionIds.contains(id);

    final currentIdentityBeforeImport = store.appIdentity;
    decoded = normalizeBackupInventoryForStore(
      decoded,
      storeId: currentIdentityBeforeImport.storeId,
      branchId: currentIdentityBeforeImport.branchId,
      deviceId: store.deviceId,
    );
    final effectiveStoreProfile = _effectiveStoreProfile(
      decoded,
      useIncomingStoreProfile: wants('storeProfile'),
    );
    _assertNegativeStockPolicy(
      decoded,
      allowNegativeStock: effectiveStoreProfile.allowNegativeStock,
    );
    final preservePairedHostIdentity = currentIdentityBeforeImport.isHost;
    final liveHostConnectionEntries = preservePairedHostIdentity
        ? Map<String, String>.fromEntries(
            LocalDatabaseService.allEntries().entries.where(
                  (entry) => _shouldPreserveLiveHostConnectionKey(entry.key),
                ),
          )
        : const <String, String>{};
    final restoreFullDeviceBackup =
        decoded['backupType']?.toString() == 'full_device_backup';
    final localDatabaseEntries =
        restoreFullDeviceBackup && decoded['localDatabaseEntries'] is Map
            ? Map<String, dynamic>.from(
                decoded['localDatabaseEntries'] as Map,
              )
            : const <String, dynamic>{};

    final importedSyncChanges = restoreFullDeviceBackup
        ? (decoded['syncChanges'] as List<dynamic>? ?? const <dynamic>[])
            .map(
              (item) =>
                  SyncChange.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(growable: false)
        : const <SyncChange>[];
    final importedSyncQueue = restoreFullDeviceBackup
        ? (decoded['syncQueue'] as List<dynamic>? ?? const <dynamic>[])
            .map(
              (item) => SyncQueueItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false)
        : const <SyncQueueItem>[];

    await StartupTimingService.measure(
      'backup_import.direct_to_sqlite',
      () async {
        await LocalDatabaseService.runSqliteAuthoritativeTransaction(() async {
          if (!customImport &&
              restoreFullDeviceBackup &&
              localDatabaseEntries.isNotEmpty) {
            await LocalDatabaseService.clearAll();
          }

          Future<void> replaceRows(
            String storageKey,
            List<Map<String, dynamic>> rows,
          ) async {
            if (storageKey == AppStore._stockMovementsKey) {
              await BusinessSqliteStore.saveKeyJson(
                SqliteMigrationManager.database!,
                storageKey,
                jsonEncode(rows),
              );
              return;
            }
            await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
              storageKey,
              rows,
              sortIndices: List<int?>.generate(rows.length, (index) => index),
            );
          }

          Future<void> replaceSection(
            String sectionId,
            String storageKey,
            String decodedKey, {
            List<String> aliases = const <String>[],
          }) async {
            if (!wants(sectionId)) return;
            await replaceRows(
              storageKey,
              _snapshotListMaps(decoded, decodedKey, aliases: aliases),
            );
          }

          await replaceSection('products', AppStore._productsKey, 'products');
          await LocalDatabaseService.replaceInventoryBatchRowsImmediate(
            batches: _snapshotListMaps(decoded, 'inventoryBatches'),
            balances: _snapshotListMaps(decoded, 'inventoryBatchBalances'),
          );
          await replaceSection(
              'customers', AppStore._customersKey, 'customers');
          await replaceSection('sales', AppStore._salesKey, 'sales');
          await replaceSection(
            'saleQuotations',
            AppStore._saleQuotationsKey,
            'saleQuotations',
            aliases: <String>['quotations'],
          );
          await replaceSection(
            'deliveryNotes',
            AppStore._deliveryNotesKey,
            'deliveryNotes',
          );
          if (wants('manufacturing')) {
            await replaceRows(
              AppStore._billsOfMaterialsKey,
              _snapshotListMaps(decoded, 'billsOfMaterials'),
            );
            await replaceRows(
              AppStore._manufacturingOrdersKey,
              _snapshotListMaps(decoded, 'manufacturingOrders'),
            );
          }
          await replaceSection(
              'suppliers', AppStore._suppliersKey, 'suppliers');
          await replaceSection(
            'supplierProductPrices',
            AppStore._supplierProductPricesKey,
            'supplierProductPrices',
          );
          await replaceSection(
              'priceLists', AppStore._priceListsKey, 'priceLists');
          await replaceSection(
            'productPrices',
            AppStore._productPricesKey,
            'productPrices',
          );
          await replaceSection(
            'productPriceHistory',
            AppStore._productPriceHistoryKey,
            'productPriceHistory',
          );
          await replaceSection(
            'productPriceOverrides',
            AppStore._productPriceOverridesKey,
            'productPriceOverrides',
          );
          await replaceSection(
            'productCosts',
            AppStore._productCostsKey,
            'productCosts',
          );
          await replaceSection(
            'costingMethodHistory',
            AppStore._costingMethodHistoryKey,
            'costingMethodHistory',
          );
          await replaceSection(
            'inventoryCostLayers',
            AppStore._inventoryCostLayersKey,
            'inventoryCostLayers',
          );
          await replaceSection(
              'categories', AppStore._categoriesKey, 'categories');
          await replaceSection('brands', AppStore._brandsKey, 'brands');
          await replaceSection('units', AppStore._unitsKey, 'units');
          await replaceSection('expenses', AppStore._expensesKey, 'expenses');
          await replaceSection(
              'purchases', AppStore._purchasesKey, 'purchases');
          await replaceSection(
            'stockMovements',
            AppStore._stockMovementsKey,
            'stockMovements',
          );
          await LocalDatabaseService.replaceWarehouseInventoryRowsImmediate(
            _snapshotListMaps(decoded, 'warehouseInventory',
                aliases: <String>['warehouse_inventory']),
            allowNegativeStock: effectiveStoreProfile.allowNegativeStock,
          );
          await LocalDatabaseService.replaceStockOperationsRowsImmediate(
            _snapshotListMaps(decoded, 'stockOperations',
                aliases: <String>['stock_operations']),
          );
          await LocalDatabaseService
              .replaceInventoryReconciliationsRowsImmediate(
            _snapshotListMaps(decoded, 'inventoryReconciliations',
                aliases: <String>['inventory_reconciliations']),
          );
          await LocalDatabaseService
              .replaceInventoryMigrationAdjustmentsRowsImmediate(
            _snapshotListMaps(decoded, 'inventoryMigrationAdjustments',
                aliases: <String>['inventory_migration_adjustments']),
          );
          await replaceSection(
            'inventoryCounts',
            AppStore._inventoryCountsKey,
            'inventoryCounts',
          );
          await replaceSection(
              'warehouses', AppStore._warehousesKey, 'warehouses');
          await replaceSection(
            'accountTransactions',
            AppStore._accountTransactionsKey,
            'accountTransactions',
          );
          if (wants('usersAndRoles')) {
            await replaceRows(
              AppStore._rolesKey,
              _snapshotListMaps(decoded, 'roles'),
            );
            await replaceRows(
              AppStore._usersKey,
              _snapshotListMaps(decoded, 'users'),
            );
          }

          if (wants('inventoryCostingMethod')) {
            await LocalDatabaseService.setString(
              AppStore._inventoryCostingMethodKey,
              _snapshotScalarString(
                decoded,
                'inventoryCostingMethod',
                fallback: store._inventoryCostingMethod.code,
              ),
            );
          }

          if (wants('storeProfile')) {
            final profileMap = decoded['storeProfile'] is Map
                ? Map<String, dynamic>.from(decoded['storeProfile'] as Map)
                : store._storeProfile.toJson();
            await LocalDatabaseService.setString(
              AppStore._storeProfileKey,
              jsonEncode(profileMap),
            );
          }

          if (wants('counters')) {
            final importedCounter =
                (decoded['invoiceCounter'] as num?)?.toInt() ??
                    store._invoiceCounter;
            final importedPurchaseCounter =
                (decoded['purchaseCounter'] as num?)?.toInt() ??
                    store._purchaseCounter;
            await LocalDatabaseService.setString(
              AppStore._invoiceCounterKey,
              importedCounter.toString(),
            );
            await LocalDatabaseService.setString(
              AppStore._purchaseCounterKey,
              importedPurchaseCounter.toString(),
            );
          }

          if (wants('deviceId') &&
              restoreFullDeviceBackup &&
              !preservePairedHostIdentity &&
              decoded['deviceId']?.toString().trim().isNotEmpty == true) {
            store._deviceId = decoded['deviceId'].toString().trim();
            await LocalDatabaseService.setString(
              AppStore._deviceIdKey,
              store._deviceId,
            );
          }

          if (wants('themeMode') && decoded['themeMode'] is String) {
            await LocalDatabaseService.setString(
              AppStore._themeModeKey,
              decoded['themeMode'].toString(),
            );
          }

          if (wants('appIdentity')) {
            final importedStoreId = decoded['storeId']?.toString().trim() ?? '';
            final importedBranchId =
                decoded['branchId']?.toString().trim() ?? '';
            if (restoreFullDeviceBackup &&
                decoded['appIdentity'] is Map &&
                !preservePairedHostIdentity) {
              store._appIdentity = AppIdentity.fromJson(
                Map<String, dynamic>.from(decoded['appIdentity'] as Map),
              ).copyWith(
                  deviceId: store._deviceId, platform: store._detectPlatform());
            } else {
              store._appIdentity = currentIdentityBeforeImport.copyWith(
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
                deviceId: store._deviceId,
                platform: store._detectPlatform(),
                updatedAt: DateTime.now(),
              );
            }
          } else {
            store._appIdentity = currentIdentityBeforeImport.copyWith(
              deviceId: store._deviceId,
              platform: store._detectPlatform(),
              updatedAt: DateTime.now(),
            );
          }
          await LocalDatabaseService.setString(
            AppStore._appIdentityKey,
            jsonEncode(store._appIdentity!.toJson()),
          );

          if (wants('syncChanges') ||
              wants('syncQueue') ||
              wants('localDatabaseEntries')) {
            await LocalDatabaseService.deleteString('direct_last_pull_cursor');
          }

          if (wants('syncChanges')) {
            store._syncChanges
              ..clear()
              ..addAll(importedSyncChanges);
            await LocalDatabaseService.setString(
              AppStore._syncChangesKey,
              jsonEncode(
                importedSyncChanges.map((item) => item.toJson()).toList(),
              ),
            );
          }
          if (wants('syncQueue')) {
            store._syncQueue
              ..clear()
              ..addAll(importedSyncQueue);
            await LocalDatabaseService.setString(
              AppStore._syncQueueKey,
              jsonEncode(
                  importedSyncQueue.map((item) => item.toJson()).toList()),
            );
          }

          if (!customImport &&
              restoreFullDeviceBackup &&
              localDatabaseEntries.isNotEmpty) {
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
          }
        });
        await LocalDatabaseService.flushPendingWrites();
      },
      category: 'backup',
    );

    if (!customImport &&
        restoreFullDeviceBackup &&
        localDatabaseEntries.isNotEmpty) {
      final snapshotPayload = Map<String, dynamic>.from(decoded);
      if (preservePairedHostIdentity) {
        snapshotPayload['appIdentity'] = store.appIdentity.toJson();
      }
      await replaceFromSnapshotPayloadDirectToSqlite(
        snapshotPayload,
      );
    }

    await _refreshRuntimeAfterRecovery(loadStoreProfile: true);
    await store._reloadAllAfterDatabaseChange();
    await _refreshSummaryTables();

    if (store.appIdentity.isHost) {
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
      store._recordSyncChange(
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
          'storeId': store.appIdentity.storeId,
          'branchId': store.appIdentity.branchId,
        },
      );
      await store._saveSyncStateOnly();
    }

    await AuditLogger.record(
      entityType: 'backup',
      entityId: store.appIdentity.storeId,
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
      storeId: store.appIdentity.storeId,
      branchId: store.appIdentity.branchId,
      sessionId: store.deviceId,
      traceId: store.deviceId,
      deviceId: store.deviceId,
      sourceModule: 'backup',
      isImportant: true,
    );

    store._refreshUi();
  }

  Future<void> mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  }) async {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final effectiveStoreProfile = _effectiveStoreProfile(decoded);
    _assertNegativeStockPolicy(
      decoded,
      allowNegativeStock: effectiveStoreProfile.allowNegativeStock,
    );
    final now = DateTime.now();
    await StartupTimingService.measure(
      'backup_merge.direct_to_sqlite',
      () async {
        await LocalDatabaseService.runSqliteAuthoritativeTransaction(() async {
          Future<void> mergeRows(
            String storageKey,
            List<Map<String, dynamic>> incoming, {
            String Function(Map<String, dynamic>)? idOf,
          }) async {
            final merged = await _mergeRowsByUpdatedAt(
              storageKey,
              incoming,
              idOf: idOf,
            );
            await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
              storageKey,
              merged,
              sortIndices: List<int?>.generate(merged.length, (index) => index),
            );
          }

          await mergeRows(
              AppStore._productsKey, _snapshotListMaps(decoded, 'products'));
          await LocalDatabaseService.replaceInventoryBatchRowsImmediate(
            batches: _snapshotListMaps(decoded, 'inventoryBatches'),
            balances: _snapshotListMaps(decoded, 'inventoryBatchBalances'),
          );
          await mergeRows(
              AppStore._customersKey, _snapshotListMaps(decoded, 'customers'));
          await mergeRows(
              AppStore._salesKey, _snapshotListMaps(decoded, 'sales'));
          await mergeRows(
            AppStore._saleQuotationsKey,
            _snapshotListMaps(decoded, 'saleQuotations',
                aliases: <String>['quotations']),
          );
          await mergeRows(AppStore._deliveryNotesKey,
              _snapshotListMaps(decoded, 'deliveryNotes'));
          await mergeRows(AppStore._billsOfMaterialsKey,
              _snapshotListMaps(decoded, 'billsOfMaterials'));
          await mergeRows(AppStore._manufacturingOrdersKey,
              _snapshotListMaps(decoded, 'manufacturingOrders'));
          await mergeRows(
              AppStore._suppliersKey, _snapshotListMaps(decoded, 'suppliers'));
          await mergeRows(
            AppStore._supplierProductPricesKey,
            _snapshotListMaps(decoded, 'supplierProductPrices'),
          );
          await mergeRows(AppStore._priceListsKey,
              _snapshotListMaps(decoded, 'priceLists'));
          await mergeRows(AppStore._productPricesKey,
              _snapshotListMaps(decoded, 'productPrices'));
          await mergeRows(
            AppStore._productPriceHistoryKey,
            _snapshotListMaps(decoded, 'productPriceHistory'),
          );
          await mergeRows(
            AppStore._productPriceOverridesKey,
            _snapshotListMaps(decoded, 'productPriceOverrides'),
          );
          await mergeRows(AppStore._productCostsKey,
              _snapshotListMaps(decoded, 'productCosts'));
          await mergeRows(
            AppStore._costingMethodHistoryKey,
            _snapshotListMaps(decoded, 'costingMethodHistory'),
          );
          await mergeRows(
            AppStore._inventoryCostLayersKey,
            _snapshotListMaps(decoded, 'inventoryCostLayers'),
          );
          await mergeRows(AppStore._categoriesKey,
              _snapshotListMaps(decoded, 'categories'));
          await mergeRows(
              AppStore._brandsKey, _snapshotListMaps(decoded, 'brands'));
          await mergeRows(
              AppStore._unitsKey, _snapshotListMaps(decoded, 'units'));
          await mergeRows(
              AppStore._expensesKey, _snapshotListMaps(decoded, 'expenses'));
          await mergeRows(
              AppStore._purchasesKey, _snapshotListMaps(decoded, 'purchases'));
          await mergeRows(AppStore._stockMovementsKey,
              _snapshotListMaps(decoded, 'stockMovements'));
          await LocalDatabaseService.replaceWarehouseInventoryRowsImmediate(
            _snapshotListMaps(decoded, 'warehouseInventory',
                aliases: <String>['warehouse_inventory']),
            allowNegativeStock: effectiveStoreProfile.allowNegativeStock,
          );
          await LocalDatabaseService.replaceStockOperationsRowsImmediate(
            _snapshotListMaps(decoded, 'stockOperations',
                aliases: <String>['stock_operations']),
          );
          await LocalDatabaseService
              .replaceInventoryReconciliationsRowsImmediate(
            _snapshotListMaps(decoded, 'inventoryReconciliations',
                aliases: <String>['inventory_reconciliations']),
          );
          await LocalDatabaseService
              .replaceInventoryMigrationAdjustmentsRowsImmediate(
            _snapshotListMaps(decoded, 'inventoryMigrationAdjustments',
                aliases: <String>['inventory_migration_adjustments']),
          );
          await mergeRows(AppStore._warehousesKey,
              _snapshotListMaps(decoded, 'warehouses'));
          await mergeRows(
            AppStore._accountTransactionsKey,
            _snapshotListMaps(decoded, 'accountTransactions'),
          );
          await mergeRows(
              AppStore._rolesKey, _snapshotListMaps(decoded, 'roles'));
          await mergeRows(
              AppStore._usersKey, _snapshotListMaps(decoded, 'users'));

          if (decoded['storeProfile'] is Map) {
            await LocalDatabaseService.setString(
              AppStore._storeProfileKey,
              jsonEncode(
                  Map<String, dynamic>.from(decoded['storeProfile'] as Map)),
            );
          }
          if (decoded['inventoryCostingMethod'] != null) {
            await LocalDatabaseService.setString(
              AppStore._inventoryCostingMethodKey,
              _snapshotScalarString(
                decoded,
                'inventoryCostingMethod',
                fallback: store._inventoryCostingMethod.code,
              ),
            );
          }

          final importedCounter =
              (decoded['invoiceCounter'] as num?)?.toInt() ?? 0;
          if (importedCounter > store._invoiceCounter) {
            await LocalDatabaseService.setString(
              AppStore._invoiceCounterKey,
              importedCounter.toString(),
            );
          }
          final importedPurchaseCounter =
              (decoded['purchaseCounter'] as num?)?.toInt() ?? 0;
          if (importedPurchaseCounter > store._purchaseCounter) {
            await LocalDatabaseService.setString(
              AppStore._purchaseCounterKey,
              importedPurchaseCounter.toString(),
            );
          }

          final mergedSyncChanges = <SyncChange>[...store._syncChanges];
          final incomingSyncChanges =
              (decoded['syncChanges'] as List<dynamic>? ?? const <dynamic>[])
                  .map(
                    (item) => SyncChange.fromJson(
                      Map<String, dynamic>.from(item as Map),
                    ),
                  )
                  .toList(growable: false);
          for (final incoming in incomingSyncChanges) {
            final normalized = markSynced
                ? incoming.copyWith(isSynced: true, syncedAt: now)
                : incoming.deviceId == store.deviceId || incoming.isSynced
                    ? incoming
                    : incoming.copyWith(isSynced: true, syncedAt: now);
            final index = mergedSyncChanges
                .indexWhere((item) => item.id == normalized.id);
            if (index == -1) {
              mergedSyncChanges.add(normalized);
            } else if (_syncChangeUpdatedAt(normalized)
                .isAfter(_syncChangeUpdatedAt(mergedSyncChanges[index]))) {
              mergedSyncChanges[index] = normalized;
            }
          }
          if (markSynced) {
            for (var i = 0; i < mergedSyncChanges.length; i++) {
              mergedSyncChanges[i] = mergedSyncChanges[i].copyWith(
                isSynced: true,
                syncedAt: now,
              );
            }
          }
          store._syncChanges
            ..clear()
            ..addAll(mergedSyncChanges);
          await store._saveSyncStateOnly();

          if (decoded['appIdentity'] is Map) {
            store._appIdentity = AppIdentity.fromJson(
              Map<String, dynamic>.from(decoded['appIdentity'] as Map),
            ).copyWith(
                deviceId: store._deviceId, platform: store._detectPlatform());
            await LocalDatabaseService.setString(
              AppStore._appIdentityKey,
              jsonEncode(store._appIdentity!.toJson()),
            );
          }

          final incomingSyncQueue =
              (decoded['syncQueue'] as List<dynamic>? ?? const <dynamic>[])
                  .map(
                    (item) => SyncQueueItem.fromJson(
                      Map<String, dynamic>.from(item as Map),
                    ),
                  )
                  .toList(growable: false);
          if (incomingSyncQueue.isNotEmpty) {
            store._syncQueue
              ..clear()
              ..addAll(incomingSyncQueue);
            await LocalDatabaseService.setString(
              AppStore._syncQueueKey,
              jsonEncode(
                  incomingSyncQueue.map((item) => item.toJson()).toList()),
            );
          }
        });
        await LocalDatabaseService.flushPendingWrites();
      },
      category: 'backup',
    );

    await _refreshRuntimeAfterRecovery(loadStoreProfile: true);
    await _refreshSummaryTables();
    store._refreshUi();
  }

  Future<void> importSyncSnapshotJson(String rawJson) async {
    if (store.appIdentity.isHost) {
      throw StateError(
        'Host devices cannot be converted to Clients by importing a sync snapshot.',
      );
    }
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final unifiedChunks = decoded['snapshotChunks'];
    final payload = unifiedChunks is List
        ? store._unifiedSnapshotPayloadFromChunks(
            unifiedChunks
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false),
          )
        : decoded;
    await replaceFromSnapshotPayloadDirectToSqlite(
      payload,
      preserveLocalIdentityForLanClient: true,
    );
  }
}
