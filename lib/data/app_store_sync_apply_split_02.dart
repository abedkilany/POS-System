part of 'app_store.dart';

extension _AppStoreSplitSyncApplyPart2 on AppStore {
  Future<void> _applyRemoteSyncChanges(
    List<SyncChange> incoming, {
    bool markAppliedAsSynced = false,
    bool mirrorToDirect = false,
  }) async {
    final existingIds = _syncChanges.map((item) => item.id).toSet();
    final existingEventIds = _syncChanges
        .map((item) => _syncMetaString(item, 'eventId'))
        .where((item) => item.isNotEmpty)
        .toSet();
    final acceptedSourceCommandIds = <String>{
      ..._syncChanges
          .map((item) => _syncMetaString(item, 'sourceCommandId'))
          .where((item) => item.isNotEmpty),
      ..._syncChanges
          .map((item) => _syncMetaString(item, 'requestId'))
          .where((item) => item.isNotEmpty),
    };
    final lastAppliedSequence = SyncDeviceStateStore.load(
      appIdentity,
    ).lastAppliedSequence;
    final currentEpoch = appIdentity.storeEpoch;
    final sorted = [...incoming]..sort((a, b) {
        final epochCompare = a.storeEpoch.compareTo(b.storeEpoch);
        if (epochCompare != 0) return epochCompare;
        if (a.sequence != 0 || b.sequence != 0) {
          return a.sequence.compareTo(b.sequence);
        }
        return a.createdAt.compareTo(b.createdAt);
      });
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] applyRemote:start incoming=${incoming.length} '
      'sorted=${sorted.length} markApplied=$markAppliedAsSynced '
      'mirrorToDirect=$mirrorToDirect lastAppliedSequence=$lastAppliedSequence '
      'currentEpoch=$currentEpoch',
    );
    for (final change in sorted.take(40)) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:item ${SyncDiagnosticsLog.summarizeChange(change)}',
      );
    }
    var changed = false;
    var saveAllBusinessData = false;
    var storeProfileChanged = false;
    var productsChanged = false;
    var customersChanged = false;
    var salesChanged = false;
    var saleQuotationsChanged = false;
    var deliveryNotesChanged = false;
    var billsOfMaterialsChanged = false;
    var manufacturingOrdersChanged = false;
    var suppliersChanged = false;
    var supplierProductPricesChanged = false;
    var categoriesChanged = false;
    var brandsChanged = false;
    var unitsChanged = false;
    var expensesChanged = false;
    var purchasesChanged = false;
    var stockMovementsChanged = false;
    var warehousesChanged = false;
    var accountTransactionsChanged = false;
    var rolesUsersChanged = false;
    var invoiceCounterChanged = false;
    var purchaseCounterChanged = false;

    void markEntityDirty(SyncChange change) {
      switch (change.entityType) {
        case 'system':
          if (change.operation == 'reset_store_data' ||
              change.operation == 'restore_snapshot') {
            saveAllBusinessData = true;
            rolesUsersChanged = true;
          }
          break;
        case 'store_profile':
          storeProfileChanged = true;
          break;
        case 'app_identity':
          saveAllBusinessData = true;
          break;
        case 'role':
        case 'user':
          rolesUsersChanged = true;
          break;
        case 'product':
          productsChanged = true;
          break;
        case 'customer':
          customersChanged = true;
          break;
        case 'sale':
          salesChanged = true;
          invoiceCounterChanged = true;
          break;
        case 'sale_quotation':
          saleQuotationsChanged = true;
          break;
        case 'delivery_note':
          deliveryNotesChanged = true;
          break;
        case 'bill_of_materials':
          billsOfMaterialsChanged = true;
          break;
        case 'manufacturing_order':
          manufacturingOrdersChanged = true;
          break;
        case 'supplier':
          suppliersChanged = true;
          break;
        case 'supplier_product_price':
          supplierProductPricesChanged = true;
          break;
        case 'category':
          categoriesChanged = true;
          break;
        case 'brand':
          brandsChanged = true;
          break;
        case 'unit':
          unitsChanged = true;
          break;
        case 'expense':
          expensesChanged = true;
          break;
        case 'purchase':
          purchasesChanged = true;
          purchaseCounterChanged = true;
          break;
        case 'stock_movement':
          stockMovementsChanged = true;
          productsChanged = true;
          break;
        case 'warehouse':
          warehousesChanged = true;
          break;
        case 'account_transaction':
          accountTransactionsChanged = true;
          break;
      }
    }

    for (final change in sorted) {
      if (_isReplayOrDuplicateSyncEvent(
        change,
        existingEnvelopeIds: existingIds,
        existingEventIds: existingEventIds,
        acceptedSourceCommandIds: acceptedSourceCommandIds,
        lastAppliedSequence: lastAppliedSequence,
      )) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:skipDuplicate '
          '${SyncDiagnosticsLog.summarizeChange(change)} '
          'lastAppliedSequence=$lastAppliedSequence',
        );
        continue;
      }
      final incomingEpoch = change.storeEpoch;
      if (incomingEpoch < currentEpoch &&
          !(change.entityType == 'system' &&
              change.operation == 'reset_store_data')) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:skipEpoch '
          '${SyncDiagnosticsLog.summarizeChange(change)} '
          'incomingEpoch=$incomingEpoch currentEpoch=$currentEpoch',
        );
        continue;
      }
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:before '
        '${SyncDiagnosticsLog.summarizeChange(change)} '
        'localDevice=$_deviceId countBeforeCustomers=${_customers.length} '
        'existsBefore=${_customers.any((item) => item.id == change.entityId)}',
      );
      await _applySyncChangePayload(change);
      if (change.entityType == 'customer') {
        final storedIndex =
            _customers.indexWhere((item) => item.id == change.entityId);
        final stored = storedIndex == -1 ? null : _customers[storedIndex];
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:after entity=customer '
          'id=${change.entityId} name=${stored?.name} '
          'deletedAt=${stored?.deletedAt?.toIso8601String()} '
          'syncStatus=${stored?.syncStatus} version=${stored?.version} '
          'countAfter=${_customers.length}',
        );
      }
      _rememberRemoteSqliteBusinessRows(change);
      markEntityDirty(change);
      // Host-authority sync note:
      // Any draft accepted by the Host must become a new authoritative Host
      // event, even in LAN-only mode. v12 only restamped events that were also
      // mirrored to Direct; pure Local/LAN installs kept the original Client
      // timestamp, so other Clients could miss the delta behind their cursor.
      // Restamping on every Host acceptance makes Local sync timing stable.
      final acceptedAt = DateTime.now();
      final shouldRestampAsHostAuthority =
          appIdentity.isHost && change.deviceId != _deviceId;
      final incomingMeta = _syncV2MetaOf(change);
      final requestId = (incomingMeta['requestId'] ?? change.id).toString();
      final authoritativeEventId = shouldRestampAsHostAuthority
          ? _newSyncEnvelopeId(acceptedAt, 'evt')
          : (_syncMetaString(change, 'eventId').isNotEmpty
              ? _syncMetaString(change, 'eventId')
              : change.id);
      final authoritativePayload = shouldRestampAsHostAuthority
          ? <String, dynamic>{
              ...change.payload,
              '_syncV2': <String, dynamic>{
                ...incomingMeta,
                'kind': 'authoritativeEvent',
                'requestId': requestId,
                'eventId': authoritativeEventId,
                'acceptedByHostDeviceId': _deviceId,
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
              deviceId: _deviceId,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              payload: authoritativePayload,
              storeEpoch: appIdentity.storeEpoch,
              sequence: _nextSyncSequence(),
            )
          : change;
      final storedChange = markAppliedAsSynced
          ? authoritativeChange.copyWith(isSynced: true, syncedAt: acceptedAt)
          : authoritativeChange.copyWith(isSynced: false, syncedAt: null);
      _syncChanges.add(storedChange);
      _sqliteDirtySyncChanges.add(storedChange);
      existingIds.add(change.id);
      existingIds.add(storedChange.id);
      final storedEventId = _syncMetaString(storedChange, 'eventId');
      if (storedEventId.isNotEmpty) existingEventIds.add(storedEventId);
      final storedSourceCommandId = _syncMetaString(
        storedChange,
        'sourceCommandId',
      );
      if (storedSourceCommandId.isNotEmpty) {
        acceptedSourceCommandIds.add(storedSourceCommandId);
      }
      final storedRequestId = _syncMetaString(storedChange, 'requestId');
      if (storedRequestId.isNotEmpty) {
        acceptedSourceCommandIds.add(storedRequestId);
      }
      changed = true;
    }
    if (changed) {
      _ensureCatalogDefaults();
      _normalizeCustomers();
      if (saveAllBusinessData) {
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] applyRemote:saveAll customersChanged=$customersChanged');
        await _saveAll();
      } else {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] applyRemote:saveDirty customersChanged=$customersChanged '
          'productsChanged=$productsChanged sync=true',
        );
        await Future.wait([
          if (rolesUsersChanged) _saveRolesAndUsers(),
          _saveDirty(
            products: productsChanged,
            customers: customersChanged,
            sales: salesChanged,
            saleQuotations: saleQuotationsChanged,
            deliveryNotes: deliveryNotesChanged,
            billsOfMaterials: billsOfMaterialsChanged,
            manufacturingOrders: manufacturingOrdersChanged,
            suppliers: suppliersChanged,
            supplierProductPrices: supplierProductPricesChanged,
            expenses: expensesChanged,
            purchases: purchasesChanged,
            stockMovements: stockMovementsChanged,
            warehouses: warehousesChanged,
            accountTransactions: accountTransactionsChanged,
            storeProfile: storeProfileChanged,
            categories: categoriesChanged,
            brands: brandsChanged,
            units: unitsChanged,
            invoiceCounter: invoiceCounterChanged,
            purchaseCounter: purchaseCounterChanged,
            sync: true,
          ),
        ]);
      }
      _touchDataRevisions(
        products: productsChanged,
        customers: customersChanged,
        sales: salesChanged,
        deliveryNotes: deliveryNotesChanged,
        storeProfile: storeProfileChanged,
      );
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:notify changed=true customers=${_customers.length} '
        'visibleCustomers=${_customers.length} '
        'customerNames=${_customers.map((item) => item.name).join(',')}',
      );
      notifyListeners();
    } else {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] applyRemote:done changed=false customers=${_customers.length} '
        'visibleCustomers=${_customers.length}',
      );
    }
  }

  void _addDuplicateConflicts<T>(
    List<DataConflict> output,
    Iterable<T> items,
    String entityType,
    String keyName,
    String Function(T item) keyOf,
    String Function(T item) idOf, {
    bool blocking = false,
    String message = '',
  }) {
    final groups = <String, List<T>>{};
    final display = <String, String>{};
    for (final item in items) {
      final raw = keyOf(item).trim();
      final key = _conflictKey(raw);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => <T>[]).add(item);
      display.putIfAbsent(key, () => raw);
    }
    groups.forEach((key, grouped) {
      final ids = grouped
          .map(idOf)
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList();
      if (ids.length > 1) {
        output.add(
          DataConflict(
            entityType: entityType,
            keyName: keyName,
            keyValue: display[key] ?? key,
            recordIds: ids,
            blocking: blocking,
            message: message,
          ),
        );
      }
    });
  }

  List<DataConflict> _detectDataConflicts() {
    final result = <DataConflict>[];
    _addDuplicateConflicts<Customer>(
      result,
      _customers.where(
        (item) => !item.isDeleted && item.id != AppStore.walkInCustomerId,
      ),
      'Customers',
      'name',
      (item) => item.name,
      (item) => item.id,
      message:
          'Created offline on more than one device. Keep both records and review manually.',
    );
    _addDuplicateConflicts<Supplier>(
      result,
      _suppliers.where((item) => !item.isDeleted),
      'Suppliers',
      'name',
      (item) => item.name,
      (item) => item.id,
      message:
          'Supplier names are duplicated after sync. Review manually; records were not merged.',
    );
    _addDuplicateConflicts<Product>(
      result,
      _products.where((item) => !item.isDeleted),
      'Products',
      'code',
      (item) => item.code,
      (item) => item.id,
      blocking: true,
      message:
          'Duplicate product codes can affect search, sales, stock, and reports.',
    );
    _addDuplicateConflicts<Product>(
      result,
      _products.where(
        (item) => !item.isDeleted && item.barcode.trim().isNotEmpty,
      ),
      'Products',
      'barcode',
      (item) => item.barcode,
      (item) => item.id,
      blocking: true,
      message:
          'Barcode is ambiguous. Avoid barcode sales until one product barcode is changed.',
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _categories.where((item) => !item.isDeleted),
      'Categories',
      'English name',
      (item) => item.nameEn,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _categories.where((item) => !item.isDeleted),
      'Categories',
      'Arabic name',
      (item) => item.nameAr,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _brands.where((item) => !item.isDeleted),
      'Brands',
      'English name',
      (item) => item.nameEn,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _brands.where((item) => !item.isDeleted),
      'Brands',
      'Arabic name',
      (item) => item.nameAr,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _units.where((item) => !item.isDeleted),
      'Units',
      'English name',
      (item) => item.nameEn,
      (item) => item.id,
    );
    _addDuplicateConflicts<CatalogItem>(
      result,
      _units.where((item) => !item.isDeleted),
      'Units',
      'Arabic name',
      (item) => item.nameAr,
      (item) => item.id,
    );
    _addDuplicateConflicts<AppUser>(
      result,
      _users,
      'Users',
      'username',
      (item) => item.username,
      (item) => item.id,
      blocking: true,
      message:
          'Duplicate usernames are a security conflict. Rename or disable one user before relying on login.',
    );
    _addDuplicateConflicts<UserRole>(
      result,
      _roles,
      'Roles',
      'name',
      (item) => item.name,
      (item) => item.id,
      blocking: true,
      message: 'Duplicate role names can confuse permissions. Rename one role.',
    );
    _addDuplicateConflicts<SupplierProductPrice>(
      result,
      _supplierProductPrices.where((item) => !item.isDeleted),
      'Supplier Product Prices',
      'product + supplier',
      (item) => '${item.productId} / ${item.supplierId}',
      (item) => item.id,
      blocking: true,
      message:
          'A product should have only one active price per supplier. Merge or delete the duplicate record.',
    );
    _addDuplicateConflicts<Sale>(
      result,
      _sales.where((item) => !item.isDeleted),
      'Sales',
      'invoice number',
      (item) => item.invoiceNo,
      (item) => item.id,
      blocking: true,
      message:
          'Duplicate invoice numbers must be reviewed before printing/exporting final reports.',
    );
    return result;
  }

  bool _remoteWins(dynamic incoming, dynamic local) {
    final incomingVersion = _readVersion(incoming);
    final localVersion = _readVersion(local);
    if (incomingVersion != localVersion) return incomingVersion > localVersion;

    final incomingUpdatedAt = _readUpdatedAt(incoming);
    final localUpdatedAt = _readUpdatedAt(local);
    if (incomingUpdatedAt.isAfter(localUpdatedAt)) return true;
    if (incomingUpdatedAt.isBefore(localUpdatedAt)) return false;

    // Deterministic tie-breaker for same-version/same-time writes. This avoids
    // oscillation between devices while keeping the Host-authoritative event
    // stream stable.
    try {
      final incomingDevice = (incoming.lastModifiedByDeviceId as String?) ??
          (incoming.deviceId as String?) ??
          '';
      final localDevice = (local.lastModifiedByDeviceId as String?) ??
          (local.deviceId as String?) ??
          '';
      return incomingDevice.compareTo(localDevice) >= 0;
    } catch (_) {
      return true;
    }
  }

  void _upsertByUpdatedAt<T>(
    List<T> list,
    T incoming,
    String Function(T item) idOf,
  ) {
    final index = list.indexWhere((item) => idOf(item) == idOf(incoming));
    if (index == -1) {
      list.add(incoming);
    } else if (_remoteWins(incoming, list[index])) {
      list[index] = incoming;
    }
  }

  void _applySupplierProductPriceFromSync(SupplierProductPrice incoming) {
    final normalized = incoming.copyWith(syncStatus: 'synced');
    if (!normalized.isDeleted) {
      for (var i = 0; i < _supplierProductPrices.length; i++) {
        final item = _supplierProductPrices[i];
        if (item.isDeleted || item.id == normalized.id) continue;
        final sameProductSupplier = item.productId == normalized.productId &&
            item.supplierId == normalized.supplierId;
        if (!sameProductSupplier) continue;
        if (_remoteWins(normalized, item)) {
          _supplierProductPrices[i] = item.copyWith(
            deletedAt: normalized.updatedAt,
            updatedAt: normalized.updatedAt,
            syncStatus: 'synced',
            notes: [
              item.notes,
              'Merged duplicate supplier price from sync',
            ].where((part) => part.trim().isNotEmpty).join(' — '),
          );
        } else {
          return;
        }
      }
    }
    if (normalized.isPreferred && !normalized.isDeleted) {
      for (var i = 0; i < _supplierProductPrices.length; i++) {
        final item = _supplierProductPrices[i];
        if (!item.isDeleted &&
            item.productId == normalized.productId &&
            item.id != normalized.id &&
            item.isPreferred) {
          _supplierProductPrices[i] = item.copyWith(
            isPreferred: false,
            updatedAt: normalized.updatedAt.isAfter(item.updatedAt)
                ? normalized.updatedAt
                : item.updatedAt,
            syncStatus: 'synced',
          );
        }
      }
    }
    _upsertByUpdatedAt<SupplierProductPrice>(
      _supplierProductPrices,
      normalized,
      (item) => item.id,
    );
  }
}
