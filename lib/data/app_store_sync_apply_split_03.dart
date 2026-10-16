part of 'app_store.dart';

extension _AppStoreSplitSyncApplyPart3 on AppStore {
  Future<void> _applySyncChangePayload(SyncChange change) async {
    final p = change.payload;
    switch (change.entityType) {
      case 'system':
        if (change.operation == 'reset_store_data') {
          _syncChanges.clear();
          _syncQueue.clear();
          final nextEpoch = change.storeEpoch > appIdentity.storeEpoch
              ? change.storeEpoch
              : appIdentity.storeEpoch + 1;
          _appIdentity = appIdentity.copyWith(
            storeEpoch: nextEpoch,
            updatedAt: DateTime.now(),
          );
          await LocalDatabaseService.setString(
            AppStore._appIdentityKey,
            jsonEncode(_appIdentity!.toJson()),
          );
          _resetBusinessDataInMemory(
            keepStoreProfile: p['keepStoreProfile'] as bool? ?? true,
          );
        } else if (change.operation == 'restore_snapshot') {
          // A direct/LAN bootstrap snapshot contains the Host identity. Never let
          // a Client import that identity or it may start behaving as the Host.
          await _replaceFromBackupMap(
            p,
            preserveLocalIdentityForLanClient: true,
          );
        } else if (change.operation == 'request_snapshot') {
          // Snapshot requests are handled by the selected LAN/Direct
          // transport. The retired Direct relay is intentionally ignored.
        }
        break;
      case 'host_transfer':
        if (change.operation == 'request') {
          // Keep the latest transfer request visible to the current Host UI.
          if (appIdentity.isHost) {
            await LocalDatabaseService.setString(
              AppStore._hostTransferRequestKey,
              jsonEncode(p),
            );
          }
        } else if (change.operation == 'approve') {
          final approvedDeviceId =
              p['approvedDeviceId']?.toString().trim() ?? '';
          if (approvedDeviceId == _deviceId) {
            await LocalDatabaseService.setString(
              AppStore._hostTransferApprovedDeviceKey,
              approvedDeviceId,
            );
          }
        } else if (change.operation == 'new_host_activated' ||
            change.operation == 'HOST_CHANGED' ||
            change.operation == 'notify_clients_host_changed') {
          final newHostDeviceId = p['newHostDeviceId']?.toString().trim() ?? '';
          final oldHostDeviceId = p['oldHostDeviceId']?.toString().trim() ?? '';
          final shouldSwitchToNewHost = newHostDeviceId.isNotEmpty &&
              newHostDeviceId != _deviceId &&
              (appIdentity.isClient ||
                  (appIdentity.isHost && oldHostDeviceId == _deviceId));
          if (shouldSwitchToNewHost) {
            await _forceApplyRoleFromTransfer(
              appIdentity.copyWith(
                deviceRole: DeviceRole.client,
                hostDeviceId: newHostDeviceId,
                updatedAt: DateTime.now(),
              ),
            );
            await _storeHostTransferNotification({
              'type': 'host_changed',
              'newHostDeviceId': newHostDeviceId,
              'oldHostDeviceId': oldHostDeviceId,
              'storeId': p['storeId']?.toString() ?? appIdentity.storeId,
              'branchId': p['branchId']?.toString() ?? appIdentity.branchId,
              'receivedAt': DateTime.now().toIso8601String(),
            });
          }
        }
        break;
      case 'store_profile':
        _storeProfile =
            StoreProfile.fromJson(p).withMergedLogoAssetsFrom(_storeProfile);
        AccountingService.configureMoneyPolicy(_storeProfile);
        break;
      case 'app_identity':
        if (change.entityId == _deviceId) {
          final incomingIdentity = _normalizedLocalIdentity(
            AppIdentity.fromJson(p),
          );
          _assertSafeRoleTransition(
            incomingIdentity,
            source: 'remote app identity change',
          );
          _appIdentity = incomingIdentity;
          await LocalDatabaseService.setString(
            AppStore._appIdentityKey,
            jsonEncode(_appIdentity!.toJson()),
          );
        }
        break;
      case 'role':
        if (change.operation == 'delete') {
          _roles.removeWhere(
            (item) => item.id == change.entityId && !item.isSystem,
          );
        } else {
          _upsertByUpdatedAt<UserRole>(
            _roles,
            UserRole.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'user':
        if (change.operation == 'delete') {
          _users.removeWhere(
            (item) => item.id == change.entityId && !item.isSystem,
          );
          if (_activeUser?.id == change.entityId) _activeUser = null;
        } else {
          final incoming = AppUser.fromJson(p);
          _upsertByUpdatedAt<AppUser>(_users, incoming, (item) => item.id);
          if (_activeUser?.id == incoming.id) _activeUser = incoming;
        }
        break;
      case 'product':
        if (change.operation == 'delete' && p.isEmpty) {
          _products.removeWhere((item) => item.id == change.entityId);
        } else {
          final incomingMetadata = Product.fromJson(p);
          final existing = _findProductById(incomingMetadata.id);
          final inventoryProjection = LocalDatabaseService.isSqliteAuthoritative
              ? await _totalWarehouseStockFromSqlite(incomingMetadata.id)
              : (existing?.stock ?? 0.0);
          final incoming =
              incomingMetadata.copyWith(stock: inventoryProjection);
          _upsertByUpdatedAt<Product>(_products, incoming, (item) => item.id);
        }
        _rebuildProductIndexes();
        break;
      case 'customer':
        if (change.operation == 'delete' && p.isEmpty) {
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyPayload:customer deleteEmpty id=${change.entityId} '
            'before=${_customers.length}',
          );
          _customers.removeWhere((item) => item.id == change.entityId);
        } else {
          final incoming = Customer.fromJson(p);
          final beforeIndex =
              _customers.indexWhere((item) => item.id == incoming.id);
          final before = beforeIndex == -1 ? null : _customers[beforeIndex];
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyPayload:customer upsert id=${incoming.id} '
            'name=${incoming.name} op=${change.operation} seq=${change.sequence} '
            'incomingUpdatedAt=${incoming.updatedAt.toIso8601String()} '
            'incomingDeletedAt=${incoming.deletedAt?.toIso8601String()} '
            'incomingStatus=${incoming.syncStatus} incomingVersion=${incoming.version} '
            'beforeExists=${before != null} '
            'beforeUpdatedAt=${before?.updatedAt.toIso8601String()} '
            'beforeDeletedAt=${before?.deletedAt?.toIso8601String()} '
            'beforeStatus=${before?.syncStatus} beforeVersion=${before?.version}',
          );
          _upsertByUpdatedAt<Customer>(
            _customers,
            incoming,
            (item) => item.id,
          );
          final afterIndex =
              _customers.indexWhere((item) => item.id == incoming.id);
          final after = afterIndex == -1 ? null : _customers[afterIndex];
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyPayload:customer result id=${incoming.id} '
            'afterExists=${after != null} afterName=${after?.name} '
            'afterUpdatedAt=${after?.updatedAt.toIso8601String()} '
            'afterDeletedAt=${after?.deletedAt?.toIso8601String()} '
            'afterStatus=${after?.syncStatus} afterVersion=${after?.version} '
            'total=${_customers.length}',
          );
        }
        _rebuildCustomerIndexes();
        break;
      case 'supplier':
        if (change.operation == 'delete' && p.isEmpty) {
          _suppliers.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<Supplier>(
            _suppliers,
            Supplier.fromJson(p),
            (item) => item.id,
          );
        }
        _rebuildSupplierIndexes();
        break;
      case 'supplier_product_price':
        if (change.operation == 'delete' && p.isEmpty) {
          _supplierProductPrices.removeWhere(
            (item) => item.id == change.entityId,
          );
        } else {
          _applySupplierProductPriceFromSync(SupplierProductPrice.fromJson(p));
        }
        break;
      case 'expense':
        if (change.operation == 'delete' && p.isEmpty) {
          final expenseIndex = _expenseIndexForId(change.entityId);
          if (expenseIndex != -1) {
            _removeExpenseAtIndex(expenseIndex);
            _touchExpensesData();
          }
        } else {
          final incoming = Expense.fromJson(p);
          _upsertByUpdatedAt<Expense>(
            _expenses,
            incoming,
            (item) => item.id,
          );
          _rebuildExpenseIndexes();
          _touchExpensesData();
        }
        break;
      case 'category':
        if (change.operation == 'delete' && p.isEmpty) {
          _categories.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(
            _categories,
            CatalogItem.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'brand':
        if (change.operation == 'delete' && p.isEmpty) {
          _brands.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(
            _brands,
            CatalogItem.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'unit':
        if (change.operation == 'delete' && p.isEmpty) {
          _units.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<CatalogItem>(
            _units,
            CatalogItem.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'sale':
        if (change.operation == 'delete' && p.isEmpty) {
          _sales.removeWhere((item) => item.id == change.entityId);
        } else {
          final incomingSale = Sale.fromJson(p);
          _upsertByUpdatedAt<Sale>(_sales, incomingSale, (item) => item.id);
          final invoiceNumber = _invoiceSequenceFromNo(incomingSale.invoiceNo);
          if (invoiceNumber > _invoiceCounter) _invoiceCounter = invoiceNumber;
        }
        break;
      case 'sale_quotation':
        if (change.operation == 'delete' && p.isEmpty) {
          _saleQuotations.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<SaleQuotation>(
            _saleQuotations,
            SaleQuotation.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'delivery_note':
        if (change.operation == 'delete' && p.isEmpty) {
          _deliveryNotes.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<DeliveryNote>(
            _deliveryNotes,
            DeliveryNote.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'bill_of_materials':
        if (change.operation == 'delete' && p.isEmpty) {
          _billsOfMaterials.removeWhere((item) => item.id == change.entityId);
        } else {
          _upsertByUpdatedAt<BillOfMaterials>(
            _billsOfMaterials,
            BillOfMaterials.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'manufacturing_order':
        if (change.operation == 'delete' && p.isEmpty) {
          _manufacturingOrders.removeWhere(
            (item) => item.id == change.entityId,
          );
        } else {
          _upsertByUpdatedAt<ManufacturingOrder>(
            _manufacturingOrders,
            ManufacturingOrder.fromJson(p),
            (item) => item.id,
          );
        }
        break;
      case 'purchase':
        if (change.operation == 'delete' && p.isEmpty) {
          final purchaseIndex = _purchaseIndexForId(change.entityId);
          if (purchaseIndex != -1) {
            _removePurchaseAtIndex(purchaseIndex);
            _touchPurchasesData();
          }
        } else {
          final incomingPurchase = Purchase.fromJson(p);
          _upsertByUpdatedAt<Purchase>(
            _purchases,
            incomingPurchase,
            (item) => item.id,
          );
          _rebuildPurchaseIndexes();
          _touchPurchasesData();
        }
        break;
      case 'account_transaction':
        if (change.operation == 'delete' && p.isEmpty) {
          final transactionIndex =
              _accountTransactionIndexForId(change.entityId);
          if (transactionIndex != -1) {
            final previous = _accountTransactions[transactionIndex];
            _removeAccountTransactionAtIndex(transactionIndex);
            _replaceAccountTransactionInLedgerCache(
              previous: previous,
              current: previous.copyWith(deletedAt: DateTime.now()),
            );
          }
          _invalidateAccountLedgerCache();
        } else {
          final incoming = AccountTransaction.fromJson(p);
          final previousIndex = _accountTransactionIndexForId(incoming.id);
          final previous =
              previousIndex == -1 ? null : _accountTransactions[previousIndex];
          _upsertByUpdatedAt<AccountTransaction>(
            _accountTransactions,
            incoming,
            (item) => item.id,
          );
          final currentIndex = _accountTransactionIndexForId(incoming.id);
          final current =
              currentIndex == -1 ? null : _accountTransactions[currentIndex];
          if (current != null) {
            _replaceAccountTransactionInLedgerCache(
              previous: previous,
              current: current,
            );
          }
          _rebuildAccountTransactionIndexes();
          _invalidateAccountLedgerCache();
        }
        break;
      case 'stock_movement':
        final movement = StockMovement.fromJson(p);
        if (_stockMovementIndexForId(movement.id) != -1) break;
        if (LocalDatabaseService.isSqliteAuthoritative &&
            movement.quantity.abs() > 0.000001) {
          final sqliteDb = SqliteMigrationManager.database;
          if (sqliteDb != null) {
            final storeId = movement.storeId.trim().isEmpty
                ? appIdentity.storeId
                : movement.storeId.trim();
            final productRow = await sqliteDb.customSelect(
              '''
              SELECT name, track_stock
              FROM products
              WHERE id = ? AND deleted_at = ''
              LIMIT 1
              ''',
              variables: <Variable<Object>>[
                Variable<String>(movement.productId),
              ],
            ).getSingleOrNull();
            final trackStock =
                (productRow?.data['track_stock'] as num? ?? 0).toInt() == 1;
            if (trackStock) {
              final productName =
                  productRow?.data['name']?.toString().trim().isNotEmpty == true
                      ? productRow!.data['name']!.toString()
                      : movement.productName;
              final phaseRow = await sqliteDb.customSelect(
                '''
                SELECT value FROM migration_meta
                WHERE key = 'unified_batch_phase4_state'
                LIMIT 1
                ''',
              ).getSingleOrNull();
              final phaseState =
                  phaseRow?.data['value']?.toString().trim().toLowerCase() ??
                      '';
              if (phaseState == 'blocked') {
                throw LocalizedDomainException(
                  'error_unified_batch_phase4_blocked',
                  values: <String, Object?>{'product': productName},
                  fallback:
                      'Unified Batch migration is blocked by an inventory reconciliation error. Repair inventory before applying synchronized stock movements.',
                );
              }
              if (movement.batchId.trim().isEmpty) {
                var requiresBatch = phaseState == 'completed';
                if (!requiresBatch) {
                  final marker = await sqliteDb.customSelect(
                    '''
                    SELECT 1
                    FROM unified_batch_cutovers uc
                    WHERE uc.store_id = ? AND uc.warehouse_id = ?
                      AND uc.product_id = ?
                      AND datetime(?) >= datetime(uc.cutover_at)
                    LIMIT 1
                    ''',
                    variables: <Variable<Object>>[
                      Variable<String>(storeId),
                      Variable<String>(movement.warehouseId),
                      Variable<String>(movement.productId),
                      Variable<String>(movement.date.toUtc().toIso8601String()),
                    ],
                  ).getSingleOrNull();
                  requiresBatch = marker != null;
                }
                if (requiresBatch) {
                  throw LocalizedDomainException(
                    'error_post_cutover_batch_required',
                    values: <String, Object?>{'product': productName},
                    fallback:
                        'لا يمكن تسجيل حركة مخزون للمنتج $productName بعد تفعيل نظام الدُفعات دون تحديد الدفعة.',
                  );
                }
              }
            }
          }
        }
        final productIndex = _productIndexById[movement.productId];
        if (!_storeProfile.allowNegativeStock &&
            productIndex != null &&
            _products[productIndex].trackStock &&
            _products[productIndex].stock + movement.quantity < -0.000001) {
          throw StateError(
            'Remote stock movement would create negative stock while negative stock is disabled.',
          );
        }
        _putStockMovementAtIndex(
          movement.copyWith(syncStatus: 'synced'),
          _stockMovements.length,
        );
        final productId = movement.productId;
        final index = _productIndexById[productId];
        if (index != null) {
          final product = _products[index];
          if (product.trackStock) {
            if (LocalDatabaseService.isSqliteAuthoritative) {
              await _rebuildProductStockCache(productId);
            } else if (movement.quantity != 0) {
              final at = movement.date;
              _products[index] = product.copyWith(
                stock: product.stock + movement.quantity,
                // Remote stock movements must not overwrite the user-maintained
                // reference cost. Inventory valuation is carried by batches.
                updatedAt:
                    at.isAfter(product.updatedAt) ? at : product.updatedAt,
                syncStatus: 'synced',
              );
            }
          }
        }
        break;
    }
  }

  String? _remoteSyncChangeApplyProblem(SyncChange change) {
    if (change.entityType == 'system') return null;

    bool exists<T>(Iterable<T> items, String Function(T item) idOf) =>
        items.any((item) => idOf(item) == change.entityId);
    final deleteWithEmptyPayload =
        change.operation == 'delete' && change.payload.isEmpty;

    switch (change.entityType) {
      case 'store_profile':
        return null;
      case 'app_identity':
        return null;
      case 'role':
        return deleteWithEmptyPayload ||
                exists<UserRole>(_roles, (item) => item.id)
            ? null
            : 'role ${change.entityId} was not stored locally';
      case 'user':
        return deleteWithEmptyPayload ||
                exists<AppUser>(_users, (item) => item.id)
            ? null
            : 'user ${change.entityId} was not stored locally';
      case 'product':
        return deleteWithEmptyPayload ||
                exists<Product>(_products, (item) => item.id)
            ? null
            : 'product ${change.entityId} was not stored locally';
      case 'customer':
        return deleteWithEmptyPayload ||
                exists<Customer>(_customers, (item) => item.id)
            ? null
            : 'customer ${change.entityId} was not stored locally';
      case 'supplier':
        return deleteWithEmptyPayload ||
                exists<Supplier>(_suppliers, (item) => item.id)
            ? null
            : 'supplier ${change.entityId} was not stored locally';
      case 'supplier_product_price':
        return deleteWithEmptyPayload ||
                exists<SupplierProductPrice>(
                  _supplierProductPrices,
                  (item) => item.id,
                )
            ? null
            : 'supplier product price ${change.entityId} was not stored locally';
      case 'expense':
        return deleteWithEmptyPayload ||
                exists<Expense>(_expenses, (item) => item.id)
            ? null
            : 'expense ${change.entityId} was not stored locally';
      case 'category':
        return deleteWithEmptyPayload ||
                exists<CatalogItem>(_categories, (item) => item.id)
            ? null
            : 'category ${change.entityId} was not stored locally';
      case 'brand':
        return deleteWithEmptyPayload ||
                exists<CatalogItem>(_brands, (item) => item.id)
            ? null
            : 'brand ${change.entityId} was not stored locally';
      case 'unit':
        return deleteWithEmptyPayload ||
                exists<CatalogItem>(_units, (item) => item.id)
            ? null
            : 'unit ${change.entityId} was not stored locally';
      case 'sale':
        return deleteWithEmptyPayload || exists<Sale>(_sales, (item) => item.id)
            ? null
            : 'sale ${change.entityId} was not stored locally';
      case 'sale_quotation':
        return deleteWithEmptyPayload ||
                exists<SaleQuotation>(_saleQuotations, (item) => item.id)
            ? null
            : 'sale quotation ${change.entityId} was not stored locally';
      case 'delivery_note':
        return deleteWithEmptyPayload ||
                exists<DeliveryNote>(_deliveryNotes, (item) => item.id)
            ? null
            : 'delivery note ${change.entityId} was not stored locally';
      case 'bill_of_materials':
        return deleteWithEmptyPayload ||
                exists<BillOfMaterials>(_billsOfMaterials, (item) => item.id)
            ? null
            : 'BOM ${change.entityId} was not stored locally';
      case 'manufacturing_order':
        return deleteWithEmptyPayload ||
                exists<ManufacturingOrder>(
                  _manufacturingOrders,
                  (item) => item.id,
                )
            ? null
            : 'manufacturing order ${change.entityId} was not stored locally';
      case 'purchase':
        return deleteWithEmptyPayload ||
                exists<Purchase>(_purchases, (item) => item.id)
            ? null
            : 'purchase ${change.entityId} was not stored locally';
      case 'account_transaction':
        return deleteWithEmptyPayload ||
                exists<AccountTransaction>(
                  _accountTransactions,
                  (item) => item.id,
                )
            ? null
            : 'account transaction ${change.entityId} was not stored locally';
      case 'stock_movement':
        return exists<StockMovement>(_stockMovements, (item) => item.id)
            ? null
            : 'stock movement ${change.entityId} was not stored locally';
    }
    return null;
  }

  Future<void> assertRemoteSyncChangesApplied(List<SyncChange> changes) async {
    final problems = <String>[];
    for (final change in changes) {
      final problem = _remoteSyncChangeApplyProblem(change);
      if (problem != null) problems.add('${change.id}: $problem');
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Remote sync apply verification failed: ${problems.take(5).join('; ')}',
      );
    }
  }

  Future<void> markSyncChangesSubmittedByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (idSet.contains(item.changeId) &&
          item.status != 'synced' &&
          item.status != 'rejected') {
        _syncQueue[i] = item.copyWith(
          status: 'submitted',
          lastError: '',
          updatedAt: now,
          clearNextRetryAt: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> markSyncChangesSyncedByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final now = DateTime.now();
    final matchedChangeIds = <String>{};
    for (var i = 0; i < _syncChanges.length; i++) {
      final change = _syncChanges[i];
      final matches = idSet.contains(change.id) ||
          idSet.contains(_syncMetaString(change, 'eventId')) ||
          idSet.contains(_syncMetaString(change, 'requestId')) ||
          idSet.contains(_syncMetaString(change, 'sourceCommandId'));
      if (matches) {
        matchedChangeIds.add(change.id);
        _syncChanges[i] = change.copyWith(isSynced: true, syncedAt: now);
      }
    }
    for (var i = 0; i < _syncQueue.length; i++) {
      final item = _syncQueue[i];
      if (idSet.contains(item.changeId) ||
          matchedChangeIds.contains(item.changeId)) {
        _syncQueue[i] = item.copyWith(
          status: 'synced',
          updatedAt: now,
          clearNextRetryAt: true,
        );
      }
    }
    await _saveSyncStateOnly();
    notifyListeners();
  }

  Future<void> settleLegacyLanHostQueue() async {
    await _ensureSyncDataLoaded();
    if (!appIdentity.isHost || appIdentity.isDirectEnabled) return;
    final ids = _syncQueue
        .where((item) => item.target == 'host' && item.status != 'synced')
        .map((item) => item.changeId)
        .where((changeId) => _syncChanges.any(
              (change) => change.id == changeId && change.deviceId == _deviceId,
            ))
        .toList(growable: false);
    if (ids.isNotEmpty) await markSyncChangesSyncedByIds(ids);
  }

  Future<int> settleHostQueueThroughPeerAck() async {
    await _ensureSyncDataLoaded();
    if (!appIdentity.isHost || _syncQueue.isEmpty) return 0;

    final safeFloorSequence = _minimumActivePeerAckSequence();
    if (safeFloorSequence <= 0) return 0;

    final changesById = <String, SyncChange>{
      for (final change in _syncChanges) change.id: change,
    };
    final ids = _syncQueue
        .where((item) => item.target == 'host' && item.status != 'synced')
        .map((item) => item.changeId)
        .where((changeId) {
      final change = changesById[changeId];
      return change != null &&
          change.deviceId == _deviceId &&
          change.sequence > 0 &&
          change.sequence <= safeFloorSequence;
    }).toList(growable: false);
    if (ids.isEmpty) return 0;

    await markSyncChangesSyncedByIds(ids);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] hostQueue:settledThroughPeerAck '
      'count=${ids.length} safeFloorSequence=$safeFloorSequence '
      'remainingPending=${_pendingSyncQueue.length}',
    );
    return ids.length;
  }
}
