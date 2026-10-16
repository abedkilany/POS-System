part of 'app_store.dart';

extension _AppStoreSplitBackupRecoveryPart3 on AppStore {
  Future<void> importBackupJson(String rawJson,
      {Set<String>? selectedSectionIds}) async {
    requirePermission(AppPermission.backupRestore);
    _requireSensitiveActionAuthorization(SensitiveAction.backupRestore);
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
            await LocalDatabaseService.setString(
                AppStore._activeUserKey, user.id);
            await LocalDatabaseService.setString(
              AppStore._rememberLoginKey,
              rememberBeforeImport ? 'true' : 'false',
            );
            break;
          }
        }
      }
      await _reloadAllAfterDatabaseChange();
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
}
