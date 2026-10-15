part of 'app_store.dart';

extension _AppStoreSplitIdentityUsersPart3 on AppStore {
  Future<void> applyStoreOwnerCredentials({
    required String username,
    required String password,
    String? fullName,
  }) async {
    requireSensitiveActionAuthorization(SensitiveAction.storeOwnerCredentials);
    final owner = storeOwnerUser;
    if (owner == null) return;
    final cleanPassword = password.trim();
    if (cleanPassword.length < 6) {
      throw ArgumentError(
          'Store Owner password must be at least 6 characters.');
    }
    final index = _users.indexWhere((item) => item.id == owner.id);
    if (index == -1) return;
    final normalizedUsername = username.trim().toLowerCase().isEmpty
        ? owner.username.trim().toLowerCase()
        : username.trim().toLowerCase();
    final cleanName = (fullName ?? owner.fullName).trim().isEmpty
        ? owner.fullName
        : (fullName ?? owner.fullName).trim();
    final updated = owner.copyWith(
      username: normalizedUsername,
      fullName: cleanName,
      passwordHash: await _hashPasswordAsync(cleanPassword),
      roleId: 'admin',
      extraPermissions: const <String>{},
      deniedPermissions: const <String>{},
      isActive: true,
      isSystem: true,
      updatedAt: DateTime.now(),
    );
    _users[index] = updated;
    if (_activeUser?.id == updated.id) _activeUser = updated;
    await _saveRolesAndUsers();
    await AuditLogger.record(
      entityType: 'user',
      entityId: updated.id,
      action: 'store_owner_credentials_changed',
      summary: 'Store Owner credentials changed',
      details: jsonEncode(<String, Object?>{
        'username': updated.username,
        'fullName': updated.fullName,
        'passwordChanged': true,
      }),
      userId: _activeUser?.id ?? '',
      userName: _activeUser?.username ?? '',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'security',
      isImportant: true,
    );
    notifyListeners();
  }

  Future<void> addOrUpdateUser(AppUser user, {String? password}) async {
    requirePermission(AppPermission.usersManage);
    requireSensitiveActionAuthorization(SensitiveAction.usersManage);
    if (user.fullName.trim().isEmpty || user.username.trim().isEmpty) {
      throw ArgumentError('Name and username are required.');
    }
    if (roleById(user.roleId) == null) throw ArgumentError('Role not found.');
    final normalizedUsername = user.username.trim().toLowerCase();
    final duplicate = _users.any(
      (item) =>
          item.id != user.id &&
          item.username.trim().toLowerCase() == normalizedUsername,
    );
    if (duplicate) throw ArgumentError('Username already exists.');
    final now = DateTime.now();
    final isCreate = user.id.trim().isEmpty ||
        _users.indexWhere((item) => item.id == user.id) == -1;
    if (isCreate && (password == null || password.trim().length < 6)) {
      throw ArgumentError('Password must be at least 6 characters.');
    }
    if (!isCreate &&
        password != null &&
        password.trim().isNotEmpty &&
        password.trim().length < 6) {
      throw ArgumentError('Password must be at least 6 characters.');
    }
    final id = user.id.trim().isEmpty
        ? 'user_${now.microsecondsSinceEpoch}'
        : user.id.trim();
    final index = _users.indexWhere((item) => item.id == id);
    final current = index == -1 ? null : _users[index];
    final editingStoreOwner = current != null && _isStoreOwnerUser(current);

    if (editingStoreOwner) {
      if (password != null &&
          password.trim().isNotEmpty &&
          password.trim().length < 6) {
        throw ArgumentError(
            'Store Owner password must be at least 6 characters.');
      }
      if (user.roleId != 'admin' || user.isActive != true) {
        throw const AppStoreActionException(
          'Store Owner must always keep Full Access and cannot be disabled.',
        );
      }
      if (user.extraPermissions.isNotEmpty ||
          user.deniedPermissions.isNotEmpty) {
        throw const AppStoreActionException(
          'Store Owner permissions are locked and cannot have local overrides.',
        );
      }
    }

    final saved = AppUser(
      id: id,
      fullName: user.fullName.trim(),
      username: normalizedUsername,
      passwordHash: password != null && password.trim().isNotEmpty
          ? await _hashPasswordAsync(password.trim())
          : user.passwordHash,
      roleId: editingStoreOwner ? 'admin' : user.roleId,
      extraPermissions: editingStoreOwner
          ? const <String>{}
          : user.extraPermissions.intersection(
              Set<String>.from(AppPermission.all),
            ),
      deniedPermissions: editingStoreOwner
          ? const <String>{}
          : user.deniedPermissions.intersection(
              Set<String>.from(AppPermission.all),
            ),
      isActive: editingStoreOwner ? true : user.isActive,
      isSystem: editingStoreOwner ? true : user.isSystem,
      createdAt: user.createdAt ?? now,
      updatedAt: now,
      lastLoginAt: user.lastLoginAt,
    );

    if (editingStoreOwner) {
      await _syncStoreOwnerUserToControlPlane(current, saved,
          password: password);
    }

    if (index == -1) {
      _users.add(saved);
    } else {
      if (_users[index].isSystem && saved.roleId != 'admin') {
        throw StateError('The built-in admin user must keep the Admin role.');
      }
      if (_users[index].isSystem && !editingStoreOwner) {
        throw StateError(
            'System users cannot be edited as regular local users.');
      }
      _users[index] = saved;
      if (_activeUser?.id == saved.id) _activeUser = saved;
    }
    _recordSyncChange(
      entityType: 'user',
      entityId: saved.id,
      operation: isCreate ? 'create' : 'update',
      payload: saved.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    await AuditLogger.record(
      entityType: 'user',
      entityId: saved.id,
      action: isCreate ? 'create' : 'update',
      summary: isCreate ? 'User created' : 'User updated',
      details: jsonEncode(<String, Object?>{
        'username': saved.username,
        'fullName': saved.fullName,
        'roleId': saved.roleId,
        'isActive': saved.isActive,
        'extraPermissions': saved.extraPermissions.toList()..sort(),
        'deniedPermissions': saved.deniedPermissions.toList()..sort(),
        'passwordChanged': password != null && password.trim().isNotEmpty,
      }),
      userId: _activeUser?.id ?? '',
      userName: _activeUser?.username ?? '',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'security',
      isImportant: true,
    );
    notifyListeners();
  }

  Future<void> deleteUser(String id) async {
    requirePermission(AppPermission.usersManage);
    requireSensitiveActionAuthorization(SensitiveAction.usersManage);
    final user = _users.firstWhere((item) => item.id == id);
    final adminCount =
        _users.where((item) => item.roleId == 'admin' && item.isActive).length;
    if (user.roleId == 'admin' && adminCount <= 1) {
      throw StateError(
        'Create another active admin before deleting this user.',
      );
    }
    if (user.isSystem) {
      throw StateError('The built-in admin user cannot be deleted.');
    }
    _users.removeWhere((item) => item.id == id);
    _recordSyncChange(
      entityType: 'user',
      entityId: id,
      operation: 'delete',
      payload: user.toJson(),
    );
    await _saveRolesAndUsers();
    await _saveSyncStateOnly();
    await AuditLogger.record(
      entityType: 'user',
      entityId: id,
      action: 'delete',
      summary: 'User deleted',
      details: jsonEncode(<String, Object?>{
        'username': user.username,
        'fullName': user.fullName,
        'roleId': user.roleId,
      }),
      userId: _activeUser?.id ?? '',
      userName: _activeUser?.username ?? '',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      sessionId: _deviceId,
      traceId: _deviceId,
      deviceId: _deviceId,
      sourceModule: 'security',
      isImportant: true,
    );
    notifyListeners();
  }

  Future<String> _hashPasswordAsync(String password) async {
    final salt = _generateSalt();
    return compute(_hashPasswordInBackground, <String, String>{
      'password': password,
      'salt': salt,
      'iterations': AppStore._passwordHashIterations.toString(),
    });
  }

  String _hashPasswordWithSalt(
    String password,
    String salt, {
    required int iterations,
  }) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(pc.Pbkdf2Parameters(base64Url.decode(salt), iterations, 32));
    final hash = derivator.process(
      Uint8List.fromList(utf8.encode('ventio|password|$password')),
    );
    return '${AppStore._passwordHashPrefix}$iterations:$salt:${base64UrlEncode(hash)}';
  }

  String _hashLegacyLocalCredentialWithSalt(String password, String salt) {
    const legacyPurpose = 'store_manager_pro|local_'
        'p'
        'in_v2';
    List<int> digest = utf8.encode('$legacyPurpose|$salt|$password');
    for (var i = 0; i < 12000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return '${AppStore._legacyLocalCredentialHashPrefix}$salt:${base64UrlEncode(digest)}';
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  StoreProfile _loadStoreProfile() {
    final raw = LocalDatabaseService.getString(AppStore._storeProfileKey);
    if (raw == null) return StoreProfile.defaults;
    return StoreProfile.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  void _normalizeCustomers() {
    // Keep ID as the only source of truth.
    // Do not merge, delete, or hide customers only because they share the same name.
    // Offline devices may legitimately create separate records with identical names;
    // those records are surfaced through dataConflicts after sync instead.
    final normalized = <Customer>[];
    var hasWalkIn = false;
    final seenIds = <String>{};

    for (final customer in _customers) {
      final trimmedName = customer.name.trim();
      final normalizedName = trimmedName.toLowerCase();
      final isWalkIn = customer.id == AppStore.walkInCustomerId ||
          normalizedName == AppStore.walkInCustomerName.toLowerCase();

      if (isWalkIn) {
        if (!hasWalkIn) {
          normalized.add(walkInCustomer);
          hasWalkIn = true;
          seenIds.add(AppStore.walkInCustomerId);
        }
        continue;
      }

      if (seenIds.contains(customer.id)) {
        continue;
      }

      normalized.add(customer.copyWith(name: trimmedName));
      seenIds.add(customer.id);
    }

    if (!hasWalkIn) {
      normalized.insert(0, walkInCustomer);
    } else {
      normalized
        ..removeWhere((c) => c.id == AppStore.walkInCustomerId)
        ..insert(0, walkInCustomer);
    }

    _customers
      ..clear()
      ..addAll(normalized);
    _rebuildCustomerIndexes();
  }

  Future<void> _persistProductDerivedData() async {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;
    await Future.wait(<Future<void>>[
      _upsertSqliteBusinessRows(
        AppStore._priceListsKey,
        _priceLists.map((item) => item.toJson()),
      ),
      _upsertSqliteBusinessRows(
        AppStore._productPricesKey,
        _productPrices.map((item) => item.toJson()),
      ),
      _upsertSqliteBusinessRows(
        AppStore._productPriceOverridesKey,
        _productPriceOverrides.map((item) => item.toJson()),
      ),
      _upsertSqliteBusinessRows(
        AppStore._productCostsKey,
        _productCosts.map((item) => item.toJson()),
      ),
      LocalDatabaseService.setString(
        AppStore._inventoryCostingMethodKey,
        _inventoryCostingMethod.code,
      ),
      _upsertSqliteBusinessRows(
        AppStore._costingMethodHistoryKey,
        _costingMethodHistory.map((item) => item.toJson()),
      ),
      _upsertSqliteBusinessRows(
        AppStore._inventoryCostLayersKey,
        _inventoryCostLayers.map((item) => item.toJson()),
      ),
    ]);
  }

  Future<void> _upsertSqliteBusinessRows(
    String key,
    Iterable<Map<String, dynamic>> rows,
  ) {
    final materializedRows = rows.toList(growable: false);
    if (!LocalDatabaseService.isSqliteAuthoritative) {
      return LocalDatabaseService.setString(key, jsonEncode(materializedRows));
    }
    return LocalDatabaseService.upsertBusinessEntityJsons(
      key,
      materializedRows,
    );
  }

  void _markProductDerivedDataDirty() {
    _productDerivedDataDirty = true;
    _productDerivedDataFlushTimer?.cancel();
    _productDerivedDataFlushTimer = null;
    // Once shutdown draining has started, do not create a new timer-owned async
    // task. prepareForShutdown() drains the dirty flag synchronously instead.
    if (_shutdownPrepared) return;
    _productDerivedDataFlushTimer = Timer(
      const Duration(milliseconds: 120),
      () {
        _productDerivedDataFlushTimer = null;
        unawaited(_flushProductDerivedData());
      },
    );
  }

  Future<void> _flushProductDerivedData() async {
    // Drain until both the dirty flag and any already-started write are clear.
    // The in-flight check must happen before the dirty check: an active writer
    // sets dirty=false before awaiting SQLite, so returning on !dirty here would
    // let shutdown close Drift while that writer is still running.
    while (true) {
      final inFlight = _productDerivedDataFlushInFlight;
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      if (!_productDerivedDataDirty) return;

      _productDerivedDataDirty = false;
      final future = _persistProductDerivedData();
      _productDerivedDataFlushInFlight = future;
      try {
        await future;
      } finally {
        if (identical(_productDerivedDataFlushInFlight, future)) {
          _productDerivedDataFlushInFlight = null;
        }
      }
    }
  }

  Future<bool> _schedulePurchaseAccounting(Purchase purchase) async {
    if (!AccountingService.isAvailable) return true;
    final purchaseId = purchase.id.trim();
    if (purchaseId.isEmpty) return false;
    while (_pendingPurchaseAccountingTasks.length >=
        AppStore._maxPurchaseAccountingBacklog) {
      final pending = _pendingPurchaseAccountingTasks.values.toList();
      if (pending.isEmpty) break;
      await Future.any<void>(
        pending.map((task) => task.catchError((_) => false)),
      );
    }
    final future = _purchaseAccountingQueue.then<bool>(
      (_) => _postPurchaseAccounting(purchase),
      onError: (_) => _postPurchaseAccounting(purchase),
    );
    _purchaseAccountingQueue = future.then<void>(
      (_) {},
      onError: (_) {},
    );
    _pendingPurchaseAccountingTasks[purchaseId] = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_pendingPurchaseAccountingTasks[purchaseId], future)) {
          _pendingPurchaseAccountingTasks.remove(purchaseId);
        }
      }),
    );
    return future;
  }

  Future<bool> _postPurchaseAccounting(Purchase purchase) async {
    try {
      return await _traceAsync<bool>(
        'purchases.createPurchase',
        'accounting_post',
        () => AccountingService.recordPurchase(purchase,
            paymentPostedSeparately: true),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.error(
          area: 'purchases',
          action: 'record_purchase_accounting',
          message: 'Purchase accounting posting failed.',
          details:
              'purchaseId=${purchase.id} purchaseNo=${purchase.purchaseNo} error=$error',
          stackTrace: stackTrace.toString(),
          userId: _activeUser?.id ?? '',
          storeId: appIdentity.storeId,
          branchId: appIdentity.branchId,
          sessionId: _deviceId,
          traceId: _deviceId,
          devicePlatform: appIdentity.platform.name,
          deviceModel: appIdentity.deviceName.isNotEmpty
              ? appIdentity.deviceName
              : _deviceId,
          isImportant: true,
        ),
      );
      return false;
    }
  }

  Future<void> _waitForPendingPurchaseAccounting(String purchaseId) async {
    final pending = _pendingPurchaseAccountingTasks[purchaseId.trim()];
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // The background poster already logged the failure.
    }
  }

  Future<void> waitForPendingAccounting({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!AccountingService.isAvailable) return;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final pending = <Future<void>>[
        ..._pendingPurchaseAccountingTasks.values,
      ];
      if (pending.isEmpty) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      try {
        await Future.wait<void>(
          pending.map(
            (future) => future.catchError((_) {}),
          ),
        ).timeout(remaining);
      } on TimeoutException {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _rebuildProductIndexes() {
    _productIndexById.clear();
    _productIdByNormalizedCode.clear();
    _productIdByNormalizedBarcode.clear();
    for (var i = 0; i < _products.length; i += 1) {
      final product = _products[i];
      _productIndexById[product.id] = i;
      if (product.isDeleted) continue;
      final code = product.code.trim().toLowerCase();
      if (code.isNotEmpty) _productIdByNormalizedCode[code] = product.id;
      final barcode = product.barcode.trim().toLowerCase();
      if (barcode.isNotEmpty) {
        _productIdByNormalizedBarcode[barcode] = product.id;
      }
    }
    _cachedProducts = null;
    _cachedProductsGeneration = -1;
  }

  void _rebuildCustomerIndexes() {
    _customerIndexById.clear();
    _customerIdByNormalizedName.clear();
    for (var i = 0; i < _customers.length; i += 1) {
      final customer = _customers[i];
      _customerIndexById[customer.id] = i;
      if (customer.isDeleted) continue;
      final normalizedName = customer.name.trim().toLowerCase();
      if (normalizedName.isNotEmpty) {
        _customerIdByNormalizedName[normalizedName] = customer.id;
      }
    }
  }

  void _rebuildSupplierIndexes() {
    _supplierIndexById.clear();
    _supplierIdByNormalizedName.clear();
    for (var i = 0; i < _suppliers.length; i += 1) {
      final supplier = _suppliers[i];
      _supplierIndexById[supplier.id] = i;
      if (supplier.isDeleted) continue;
      final normalizedName = supplier.name.trim().toLowerCase();
      if (normalizedName.isNotEmpty) {
        _supplierIdByNormalizedName[normalizedName] = supplier.id;
      }
    }
  }

  void _rebuildMutableEntityIndexes() {
    _rebuildProductIndexes();
    _rebuildCustomerIndexes();
    _rebuildSupplierIndexes();
    _rebuildPurchaseIndexes();
    _rebuildExpenseIndexes();
    _rebuildAccountTransactionIndexes();
    _rebuildStockMovementIndexes();
  }

  void _rebuildProductInventoryProjectionFromMovements() {
    final totals = <String, double>{};
    for (final movement in _stockMovements) {
      final productId = movement.productId.trim();
      if (productId.isEmpty) continue;
      totals.update(
        productId,
        (value) => value + movement.quantity,
        ifAbsent: () => movement.quantity,
      );
    }
    for (var index = 0; index < _products.length; index += 1) {
      final product = _products[index];
      if (product.isDeleted || !product.trackStock) continue;
      _products[index] = product.copyWith(stock: totals[product.id] ?? 0.0);
    }
  }

  void _rebuildStockMovementIndexes() {
    _stockMovementIndexById.clear();
    for (var i = 0; i < _stockMovements.length; i++) {
      final id = _stockMovements[i].id.trim();
      if (id.isEmpty) continue;
      _stockMovementIndexById[id] = i;
    }
  }
}
