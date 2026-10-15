part of 'sqlite_sync_state_service.dart';

extension SqliteSyncStateServiceSplitPart3 on SqliteSyncStateService {

  Future<void> _applyRemoteSyncChanges(
    BusinessSessionContext context,
    VentioDriftDatabase db,
    List<SyncChange> incoming, {
    required bool markAppliedAsSynced,
    required bool mirrorToDirect,
  }) async {
    final sorted = [...incoming]..sort((a, b) {
        final epochCompare = a.storeEpoch.compareTo(b.storeEpoch);
        if (epochCompare != 0) return epochCompare;
        if (a.sequence != 0 || b.sequence != 0) {
          return a.sequence.compareTo(b.sequence);
        }
        return a.createdAt.compareTo(b.createdAt);
      });

    final latestSequence = await latestStoredAuthoritativeSequence(context);
    final currentEpoch = context.appIdentity.storeEpoch;
    final refreshKeys = <String>{};
    final storedChanges = <SyncChange>[];
    final queueItems = <SyncQueueItem>[];
    var nextSequence = await currentSyncSequence(context);
    var changed = false;
    var businessChanged = false;

    for (final change in sorted) {
      if (change.sequence > 0 && change.sequence <= latestSequence) {
        continue;
      }
      if (change.storeEpoch < currentEpoch &&
          !(change.entityType == 'system' &&
              change.operation == 'reset_store_data')) {
        continue;
      }

      final acceptedAt = DateTime.now();
      final shouldRestampAsHostAuthority =
          context.appIdentity.isHost && change.deviceId != context.deviceId;
      final incomingMeta = _decodeMap(
        change.payload['_syncV2'] is Map
            ? jsonEncode(change.payload['_syncV2'])
            : '{}',
      );
      final requestId = (incomingMeta['requestId'] ?? change.id).toString();
      final authoritativeEventId = shouldRestampAsHostAuthority
          ? 'evt_${acceptedAt.microsecondsSinceEpoch}'
          : change.id;
      final authoritativePayload = shouldRestampAsHostAuthority
          ? <String, dynamic>{
              ...change.payload,
              '_syncV2': <String, dynamic>{
                ...incomingMeta,
                'kind': 'authoritativeEvent',
                'requestId': requestId,
                'eventId': authoritativeEventId,
                'acceptedByHostDeviceId': context.deviceId,
                'acceptedAt': acceptedAt.toIso8601String(),
                'sourceCommandId': requestId,
                'sourceCommandDeviceId': change.deviceId,
              },
            }
          : change.payload;
      final authoritativeChange = shouldRestampAsHostAuthority
          ? change.copyWith(
              id: authoritativeEventId,
              createdAt: acceptedAt,
              deviceId: context.deviceId,
              storeId: context.appIdentity.storeId,
              branchId: context.appIdentity.branchId,
              payload: authoritativePayload,
              storeEpoch: context.appIdentity.storeEpoch,
              sequence: nextSequence = nextSequence + 1,
            )
          : change;
      final storedChange = markAppliedAsSynced && !mirrorToDirect
          ? authoritativeChange.copyWith(
              isSynced: true,
              syncedAt: acceptedAt,
            )
          : authoritativeChange.copyWith(
              isSynced: false,
              syncedAt: null,
            );
      storedChanges.add(storedChange);
      changed = true;

      final key = _businessKeyForEntityType(change.entityType);
      if (key != null) {
        refreshKeys.add(key);
      }

      switch (change.entityType) {
        case 'system':
          if (change.operation == 'reset_store_data') {
            await _applySystemReset(
              context,
              keepStoreProfile:
                  change.payload['keepStoreProfile'] as bool? ?? true,
            );
            businessChanged = true;
          } else if (change.operation == 'request_snapshot') {
            if (context.appIdentity.isHost &&
                context.appIdentity.isDirectEnabled) {
              await LocalDatabaseService.setString(
                '$_directHostBootstrapMarkerPrefix${context.appIdentity.storeId}',
                'direct_chunked',
              );
            }
          }
          break;
        case 'host_transfer':
          if (change.operation == 'request') {
            if (context.appIdentity.isHost) {
              await LocalDatabaseService.setString(
                _hostTransferRequestKey,
                _encodePayloadJson(change.payload),
              );
            }
          } else if (change.operation == 'approve') {
            final approvedDeviceId =
                change.payload['approvedDeviceId']?.toString().trim() ?? '';
            if (approvedDeviceId == context.deviceId) {
              await LocalDatabaseService.setString(
                _hostTransferApprovedDeviceKey,
                approvedDeviceId,
              );
            }
          }
          break;
        case 'store_profile':
          await BusinessSqliteStore.saveKeyJson(
            db,
            _storeProfileKey,
            _encodePayloadJson(change.payload),
          );
          refreshKeys.add(_storeProfileKey);
          businessChanged = true;
          break;
        case 'app_identity':
          if (change.entityId == context.deviceId) {
            final incomingIdentity = AppIdentity.fromJson(change.payload);
            // The device role is local authority. It must never be changed by
            // a replayed/remote app_identity event: a stale Host payload could
            // otherwise turn a Client into a Host during sync. Official Host
            // transfer is handled separately through the host_transfer flow.
            final safeIdentity = incomingIdentity.copyWith(
              deviceId: context.deviceId,
              platform: context.appIdentity.platform,
              deviceRole: context.appIdentity.deviceRole,
              hostDeviceId: context.appIdentity.hostDeviceId,
              updatedAt: DateTime.now(),
            );
            await BusinessSqliteStore.saveKeyJson(
              db,
              _appIdentityKey,
              _encodePayloadJson(safeIdentity.toJson()),
            );
            refreshKeys.add(_appIdentityKey);
          }
          break;
        case 'role':
        case 'user':
        case 'product':
        case 'customer':
        case 'supplier':
        case 'expense':
        case 'category':
        case 'brand':
        case 'unit':
        case 'sale':
        case 'sale_quotation':
        case 'delivery_note':
        case 'bill_of_materials':
        case 'manufacturing_order':
        case 'purchase':
        case 'warehouse_transfer_order':
        case 'account_transaction':
        case 'inventory_count':
          await _applyBusinessEntityChange(
            db,
            change,
            refreshKeys: refreshKeys,
          );
          businessChanged = true;
          break;
        case 'supplier_product_price':
          await _applySupplierPriceChange(
            db,
            change,
            refreshKeys: refreshKeys,
          );
          businessChanged = true;
          break;
        case 'stock_movement':
          await _applyStockMovementChange(
            context,
            db,
            change,
            refreshKeys: refreshKeys,
          );
          businessChanged = true;
          break;
        case 'inventory_batch':
          await _applyInventoryBatchChange(db, context, change);
          businessChanged = true;
          break;
        case 'cash_accounting_delta':
          await _applyCashAccountingDelta(change);
          businessChanged = true;
          break;
      }

      if (mirrorToDirect &&
          context.appIdentity.isHost &&
          change.deviceId != context.deviceId &&
          change.deviceId != 'direct-snapshot') {
        queueItems.add(
          SyncQueueItem(
            id: '${storedChange.id}-direct',
            changeId: storedChange.id,
            target: 'host',
            status: 'pending',
            attempts: 0,
            createdAt: acceptedAt,
            updatedAt: acceptedAt,
          ),
        );
      }
    }

    if (storedChanges.isNotEmpty) {
      await SyncSqliteStore.upsertSyncChanges(db, storedChanges);
    }
    if (queueItems.isNotEmpty) {
      await SyncSqliteStore.upsertSyncQueueItems(db, queueItems);
    }

    if (businessChanged) {
      await _refreshSummaryTables();
      await _refreshKeys(context, refreshKeys);
    }
    if (changed) {
      await _refreshSyncKeys(context);
    }
  }

  Future<void> _applyCashAccountingDelta(SyncChange change) async {
    final rawCollections = change.payload['collections'];
    if (rawCollections is! Map) return;
    final collections = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawCollections.entries) {
      final key = entry.key.toString();
      if (!LocalDatabaseService.phase8AccountingSnapshotTables
          .containsKey(key)) {
        continue;
      }
      final value = entry.value;
      if (value is! List) continue;
      collections[key] = value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    if (collections.isEmpty) return;
    await LocalDatabaseService.upsertPhase8AccountingSnapshotRowsImmediate(
      collections,
    );
  }

  Future<void> _applyBusinessEntityChange(
    VentioDriftDatabase db,
    SyncChange change, {
    required Set<String> refreshKeys,
  }) async {
    final key = _businessKeyForEntityType(change.entityType);
    if (key == null) return;
    final table = _sqliteTableForKey(key);
    final isDelete = change.operation == 'delete' && change.payload.isEmpty;
    if (isDelete) {
      await db.customStatement(
        'DELETE FROM $table WHERE id = ?',
        <Object?>[change.entityId],
      );
      return;
    }

    await BusinessSqliteStore.upsertEntityPayload(
      db,
      key,
      change.payload,
    );
    refreshKeys.add(key);

    if (change.entityType == 'sale') {
      final invoice = _sequenceFromDocumentNo(
        change.payload['invoiceNo']?.toString() ?? '',
      );
      if (invoice > 0) {
        final current = await _currentCounterValue(db, _invoiceCounterKey);
        if (invoice > current) {
          await BusinessSqliteStore.saveKeyJson(
            db,
            _invoiceCounterKey,
            invoice.toString(),
          );
        }
      }
    }
    if (change.entityType == 'purchase') {
      await _materializePurchaseBatches(db, change);
      final purchase = _sequenceFromDocumentNo(
        change.payload['purchaseNo']?.toString() ?? '',
      );
      if (purchase > 0) {
        final current = await _currentCounterValue(db, _purchaseCounterKey);
        if (purchase > current) {
          await BusinessSqliteStore.saveKeyJson(
            db,
            _purchaseCounterKey,
            purchase.toString(),
          );
        }
      }
    }
  }

  Future<void> _materializePurchaseBatches(
    VentioDriftDatabase db,
    SyncChange change,
  ) async {
    final items = change.payload['items'];
    if (items is! List) return;
    final nowText = change.createdAt.toUtc().toIso8601String();
    for (final rawItem in items.whereType<Map>()) {
      final item = Map<String, dynamic>.from(rawItem);
      final productId = item['productId']?.toString() ?? '';
      final productName = item['productName']?.toString() ?? '';
      final allocations = item['batchAllocations'];
      final unitCost = (item['unitCostPerBase'] as num? ??
              item['unitCost'] as num? ??
              0)
          .toDouble();
      if (productId.isEmpty || allocations is! List) continue;
      for (final rawAllocation in allocations.whereType<Map>()) {
        final allocation = Map<String, dynamic>.from(rawAllocation);
        final batchId = allocation['batchId']?.toString().trim() ?? '';
        if (batchId.isEmpty) continue;
        await db.customStatement('''
          INSERT INTO inventory_batches
            (id, product_id, product_name, supplier_batch_number,
             manufacturing_date, expiration_date, status, source_type,
             source_id, source_line_id, unit_cost, initial_quantity,
             cost_currency, exchange_rate, received_at, store_id, branch_id,
             created_at, updated_at, device_id,
             last_modified_by_device_id, sync_status, version)
          VALUES (?, ?, ?, ?, ?, ?, 'active', 'purchase', ?, '', ?, ?, 'USD', 1, ?, ?, ?, ?, ?, ?, ?, 'synced', 1)
          ON CONFLICT(id) DO UPDATE SET
            product_name = excluded.product_name,
            supplier_batch_number = excluded.supplier_batch_number,
            manufacturing_date = excluded.manufacturing_date,
            expiration_date = excluded.expiration_date,
            unit_cost = CASE
              WHEN inventory_batches.unit_cost <= 0 THEN excluded.unit_cost
              ELSE inventory_batches.unit_cost
            END,
            initial_quantity = CASE
              WHEN inventory_batches.initial_quantity <= 0 THEN excluded.initial_quantity
              ELSE inventory_batches.initial_quantity
            END,
            received_at = CASE
              WHEN trim(inventory_batches.received_at) = '' THEN excluded.received_at
              ELSE inventory_batches.received_at
            END,
            updated_at = excluded.updated_at,
            sync_status = 'synced'
        ''', <Object?>[
          batchId,
          productId,
          productName,
          allocation['supplierBatchNumber']?.toString() ?? '',
          allocation['manufacturingDate']?.toString() ?? '',
          allocation['expirationDate']?.toString() ?? '',
          change.entityId,
          (allocation['unitCost'] as num? ?? unitCost).toDouble(),
          (allocation['quantity'] as num? ?? 0).toDouble(),
          nowText,
          change.storeId,
          change.branchId,
          nowText,
          nowText,
          change.deviceId,
          change.deviceId,
        ]);
      }
    }
  }

  Future<void> _applySupplierPriceChange(
    VentioDriftDatabase db,
    SyncChange change, {
    required Set<String> refreshKeys,
  }) async {
    final key = BusinessSqliteStore.supplierProductPricesKey;
    final table = _sqliteTableForKey(key);
    final isDelete = change.operation == 'delete' && change.payload.isEmpty;
    if (isDelete) {
      await db.customStatement(
        'DELETE FROM $table WHERE id = ?',
        <Object?>[change.entityId],
      );
      return;
    }
    await BusinessSqliteStore.upsertEntityPayload(
      db,
      key,
      change.payload,
    );
    refreshKeys.add(key);
    final isPreferred = change.payload['isPreferred'] == true ||
        change.payload['isPreferred'] == 1;
    if (isPreferred) {
      final productId = change.payload['productId']?.toString() ?? '';
      final supplierId = change.payload['supplierId']?.toString() ?? '';
      if (productId.isNotEmpty && supplierId.isNotEmpty) {
        await db.customUpdate(
          """
          UPDATE supplier_product_prices
          SET is_preferred = 0, updated_at = ?
          WHERE product_id = ? AND supplier_id = ? AND id <> ? AND deleted_at = ''
          """,
          variables: <Variable<Object>>[
            Variable<String>(DateTime.now().toIso8601String()),
            Variable<String>(productId),
            Variable<String>(supplierId),
            Variable<String>(change.entityId),
          ],
        );
      }
    }
  }

  Future<void> _applyInventoryBatchChange(
    VentioDriftDatabase db,
    BusinessSessionContext context,
    SyncChange change,
  ) async {
    final payload = change.payload;
    final status = payload['status']?.toString() ?? 'active';
    if (payload['productId'] == null) {
      await db.customStatement(
        '''UPDATE inventory_batches
           SET status = ?, updated_at = ?, sync_status = 'synced'
           WHERE id = ? AND store_id = ?''',
        <Object?>[
          status,
          payload['updatedAt']?.toString() ??
              change.createdAt.toIso8601String(),
          change.entityId,
          change.storeId.isEmpty ? context.appIdentity.storeId : change.storeId,
        ],
      );
      return;
    }
    final storeId = payload['storeId']?.toString().trim().isNotEmpty == true
        ? payload['storeId'].toString()
        : (change.storeId.isEmpty
            ? context.appIdentity.storeId
            : change.storeId);
    final branchId = payload['branchId']?.toString().trim().isNotEmpty == true
        ? payload['branchId'].toString()
        : context.appIdentity.branchId;
    await db.customStatement('''
      INSERT INTO inventory_batches
        (id, product_id, product_name, supplier_batch_number,
         manufacturing_date, expiration_date, status, source_type, source_id,
         source_line_id, unit_cost, initial_quantity, cost_currency,
         exchange_rate, received_at, store_id, branch_id, created_at,
         updated_at, device_id,
         last_modified_by_device_id, sync_status, version)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?)
      ON CONFLICT(id) DO UPDATE SET
        product_name = excluded.product_name,
        supplier_batch_number = excluded.supplier_batch_number,
        manufacturing_date = excluded.manufacturing_date,
        expiration_date = excluded.expiration_date,
        status = excluded.status,
        source_line_id = CASE
          WHEN trim(inventory_batches.source_line_id) = '' THEN excluded.source_line_id
          ELSE inventory_batches.source_line_id
        END,
        unit_cost = CASE
          WHEN inventory_batches.unit_cost <= 0 THEN excluded.unit_cost
          ELSE inventory_batches.unit_cost
        END,
        initial_quantity = CASE
          WHEN inventory_batches.initial_quantity <= 0 THEN excluded.initial_quantity
          ELSE inventory_batches.initial_quantity
        END,
        cost_currency = CASE
          WHEN inventory_batches.unit_cost <= 0 THEN excluded.cost_currency
          ELSE inventory_batches.cost_currency
        END,
        exchange_rate = CASE
          WHEN inventory_batches.unit_cost <= 0 THEN excluded.exchange_rate
          ELSE inventory_batches.exchange_rate
        END,
        received_at = CASE
          WHEN trim(inventory_batches.received_at) = '' THEN excluded.received_at
          ELSE inventory_batches.received_at
        END,
        updated_at = excluded.updated_at,
        sync_status = 'synced',
        version = MAX(inventory_batches.version, excluded.version)
    ''', <Object?>[
      change.entityId,
      payload['productId']?.toString() ?? '',
      payload['productName']?.toString() ?? '',
      payload['supplierBatchNumber']?.toString() ?? '',
      payload['manufacturingDate']?.toString() ?? '',
      payload['expirationDate']?.toString() ?? '',
      status,
      payload['sourceType']?.toString() ?? '',
      payload['sourceId']?.toString() ?? '',
      payload['sourceLineId']?.toString() ?? '',
      (payload['unitCost'] as num? ?? 0).toDouble(),
      (payload['initialQuantity'] as num? ?? 0).toDouble(),
      payload['costCurrency']?.toString().trim().isNotEmpty == true
          ? payload['costCurrency'].toString().toUpperCase()
          : 'USD',
      (payload['exchangeRate'] as num? ?? 1).toDouble(),
      payload['receivedAt']?.toString() ??
          payload['createdAt']?.toString() ??
          change.createdAt.toIso8601String(),
      storeId,
      branchId,
      payload['createdAt']?.toString() ?? change.createdAt.toIso8601String(),
      payload['updatedAt']?.toString() ?? change.createdAt.toIso8601String(),
      payload['deviceId']?.toString() ?? change.deviceId,
      payload['lastModifiedByDeviceId']?.toString() ?? change.deviceId,
      (payload['version'] as num?)?.toInt() ?? 1,
    ]);
  }

  Future<void> _applyStockMovementChange(
    BusinessSessionContext context,
    VentioDriftDatabase db,
    SyncChange change, {
    required Set<String> refreshKeys,
  }) async {
    final key = BusinessSqliteStore.stockMovementsKey;
    final table = _sqliteTableForKey(key);
    final isDelete = change.operation == 'delete' && change.payload.isEmpty;
    if (isDelete) {
      await db.customStatement(
        'DELETE FROM $table WHERE id = ?',
        <Object?>[change.entityId],
      );
      return;
    }

    final movement = StockMovement.fromJson(change.payload).copyWith(
      id: change.entityId,
      syncStatus: 'synced',
      storeId:
          change.storeId.isEmpty ? context.appIdentity.storeId : change.storeId,
      branchId: change.branchId.trim().isEmpty
          ? context.appIdentity.branchId
          : change.branchId.trim(),
      movementGroupId:
          _syncMetaString(change, 'movementGroupId').trim().isNotEmpty
              ? _syncMetaString(change, 'movementGroupId').trim()
              : _syncMetaString(change, 'groupId').trim(),
      documentLineId: _syncMetaString(change, 'documentLineId').trim(),
      sourceMovementId: _syncMetaString(change, 'sourceMovementId').trim(),
      reversalOfMovementId:
          _syncMetaString(change, 'reversalOfMovementId').trim(),
      idempotencyKey: _stockOperationIdempotencyKey(
        change,
        StockMovement.fromJson(change.payload),
      ),
    );
    final operationKey = _stockOperationIdempotencyKey(change, movement);
    final operation = await _acquireStockOperation(
      db,
      context: context,
      change: change,
      movement: movement,
      idempotencyKey: operationKey,
    );
    if (operation == _StockOperationState.completed) {
      refreshKeys.add(key);
      return;
    }
    if (operation == _StockOperationState.inProgress) {
      return;
    }

    try {
      final hasAppliedMovement = await _hasAppliedStockMovement(
        db,
        movement: movement,
      );
      await BusinessSqliteStore.upsertEntityPayload(
        db,
        key,
        movement.toJson(),
      );
      refreshKeys.add(key);

      if (!hasAppliedMovement) {
        await _applyWarehouseAwareMovement(
          db,
          context: context,
          movement: movement,
        );
        await _applyBatchAwareMovement(db, context, movement);
      }

      await _updateProductCompatibilityCacheFromWarehouseInventory(
        db,
        storeId: movement.storeId.isEmpty
            ? context.appIdentity.storeId
            : movement.storeId,
        productId: movement.productId,
      );
      refreshKeys.add(BusinessSqliteStore.productsKey);
      await _markStockOperationCompleted(
        db,
        context: context,
        change: change,
        movement: movement,
        idempotencyKey: operationKey,
      );
    } catch (error) {
      await _markStockOperationFailed(
        db,
        context: context,
        change: change,
        movement: movement,
        idempotencyKey: operationKey,
        reason: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> _applyBatchAwareMovement(
    VentioDriftDatabase db,
    BusinessSessionContext context,
    StockMovement movement,
  ) async {
    if (movement.batchId.trim().isEmpty) return;
    final storeId = movement.storeId.isEmpty
        ? context.appIdentity.storeId
        : movement.storeId;
    final branchId = movement.branchId.trim().isEmpty
        ? context.appIdentity.branchId
        : movement.branchId.trim();
    final warehouseId = movement.warehouseId.trim().isEmpty
        ? Warehouse.defaultId
        : movement.warehouseId.trim();
    final normalizedType = movement.type.trim().toLowerCase();
    if (BatchInventoryService.isDeficitBatchId(movement.batchId) &&
        (normalizedType.startsWith('transfer_') ||
            normalizedType.startsWith('manufacturing_produce'))) {
      throw LocalizedDomainException(
        'error_physical_batch_stock_required',
        values: <String, Object?>{
          'product': movement.productName,
          'operation': normalizedType.startsWith('transfer_')
              ? 'warehouse transfer'
              : 'manufacturing output',
        },
        fallback:
            'A transfer or manufacturing output cannot use a virtual negative-stock deficit batch. Manufacturing input deficits are allowed only when they represent an actual raw-material shortage.',
      );
    }
    await BatchInventoryService(db).applySyncedBatchMovementInTransaction(
      productId: movement.productId,
      productName: movement.productName,
      warehouseId: warehouseId,
      batchId: movement.batchId,
      quantity: movement.quantity,
      unitCost: movement.unitCost,
      movementDate: movement.date,
      storeId: storeId,
      branchId: branchId,
      deviceId: movement.lastModifiedByDeviceId.trim().isEmpty
          ? movement.deviceId
          : movement.lastModifiedByDeviceId,
    );
  }

  String _stockOperationIdempotencyKey(
    SyncChange change,
    StockMovement movement,
  ) {
    final payloadKey = _syncMetaString(change, 'idempotencyKey').trim();
    if (payloadKey.isNotEmpty) return payloadKey;
    final requestId = _syncMetaString(change, 'requestId').trim();
    if (requestId.isNotEmpty) return requestId;
    final explicit = movement.idempotencyKey.trim();
    if (explicit.isNotEmpty) return explicit;
    return change.id.trim();
  }
}
