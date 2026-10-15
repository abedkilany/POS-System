part of 'local_database_service.dart';

extension _LocalDatabaseServiceImplPart1
    on _LocalDatabaseServiceImplementation {
  int _intValue(Object? value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
      final doubleParsed = double.tryParse(value);
      if (doubleParsed != null) return doubleParsed.toInt();
    }
    return fallback;
  }

  double _doubleValue(Object? value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  bool get isSqliteAuthoritative =>
      _sqliteReady && SqliteMigrationManager.database != null;

  bool get isInMemoryStoreForTesting => _memoryStoreForTesting != null;

  bool get isSqliteDatabaseForTesting => _sqliteDatabaseForTesting;

  bool get hasPendingBusinessEntityWrites =>
      _pendingBusinessEntityWrites.isNotEmpty;

  bool get canQueryBusinessSqlite =>
      _memoryStore == null && _webStore == null && isSqliteAuthoritative;

  @visibleForTesting
  void useInMemoryStoreForTesting([Map<String, String>? seed]) {
    _memoryStoreForTesting =
        Map<String, String>.from(seed ?? const <String, String>{});
  }

  @visibleForTesting
  void clearInMemoryStoreForTesting() {
    _memoryStoreForTesting = null;
  }

  @visibleForTesting
  Future<void> useSqliteDatabaseForTesting(
    VentioDriftDatabase db,
  ) async {
    _memoryStoreForTesting = null;
    _webStore = null;
    _webPreferences = null;
    _webIndexedStore = null;
    SqliteMigrationManager.attachDatabaseOverride(db);
    _sqliteDatabaseForTesting = true;
    _sqliteMirror
      ..clear()
      ..addAll(await BusinessSqliteStore.hydrateScalarKeyMirror(db))
      ..addAll(await SyncSqliteStore.hydrateScalarKeyMirror(db));
    _sqliteReady = true;
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    _memoryStoreForTesting = null;
    _webStore = null;
    _webPreferences = null;
    _webIndexedStore = null;
    _webIndexedWriteChain = Future<void>.value();
    _sqliteReady = false;
    _sqliteDatabaseForTesting = false;
    _sqliteMirror.clear();
    _secureStringMirror.clear();
    _pendingScalarWrites.clear();
    _pendingScalarDeletes.clear();
    _pendingBusinessEntityWrites.clear();
    _pendingSyncChanges.clear();
    _pendingSyncQueueItems.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    await SqliteMigrationManager.resetForTesting();
  }

  Future<void> initialize() async {
    if (_memoryStoreForTesting != null) return;
    if (_sqliteReady && SqliteMigrationManager.database != null) return;
    final inFlight = _initializeInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final initFuture = _initializeInternal();
    _initializeInFlight = initFuture;
    try {
      await initFuture;
    } finally {
      if (identical(_initializeInFlight, initFuture)) {
        _initializeInFlight = null;
      }
    }
  }

  Future<void> _initializeInternal() {
    return StartupTimingService.measure(
      'local_database.sqlite_bootstrap',
      () async {
        if (kIsWeb) {
          try {
            final prefs = await SharedPreferences.getInstance().timeout(
              const Duration(seconds: 5),
            );
            final legacyStore = <String, String>{
              for (final key in prefs.getKeys())
                if (prefs.getString(key) != null) key: prefs.getString(key)!,
            };
            final indexedStore = WebIndexedStore();
            await indexedStore.open();
            final existingIndexedStore = await indexedStore.readAll();
            _webIndexedStore = indexedStore;
            _webPreferences = prefs;
            _webStore = <String, String>{
              ...legacyStore,
              ...existingIndexedStore,
            };

            // Migrate the old localStorage-backed values once. IndexedDB wins
            // when a key exists in both stores, so a partially completed
            // migration can safely be resumed on the next launch.
            for (final entry in legacyStore.entries) {
              if (!existingIndexedStore.containsKey(entry.key)) {
                await indexedStore.put(entry.key, entry.value);
              }
              await prefs.remove(entry.key);
            }
          } catch (error, stackTrace) {
            debugPrint(
              'Web IndexedDB bootstrap fell back to SharedPreferences: $error',
            );
            debugPrint('$stackTrace');
            _webIndexedStore = null;
            try {
              final prefs = await SharedPreferences.getInstance();
              _webPreferences = prefs;
              _webStore = <String, String>{
                for (final key in prefs.getKeys())
                  if (prefs.getString(key) != null) key: prefs.getString(key)!,
              };
            } catch (_) {
              _webPreferences = null;
              _webStore = <String, String>{};
            }
          }
          return;
        }

        final existingSqliteStatus = await StartupTimingService.measure(
          'sqlite_restore_or_validate',
          SqliteMigrationManager.initializeFromExistingSqliteIfValidated,
          category: 'database',
        );
        var db = SqliteMigrationManager.database;
        if (existingSqliteStatus.lastStatus == 'failed') {
          final reason = existingSqliteStatus.message
              .replaceFirst(RegExp(r'^Bad state: '), '');
          throw StateError(
              'SQLite database failed to initialize. Reason: $reason');
        }
        if (!existingSqliteStatus.sqliteFoundationReady || db == null) {
          final freshSqliteStatus = await StartupTimingService.measure(
            'sqlite_fresh_initialize',
            SqliteMigrationManager.initializeFreshSqlite,
            category: 'database',
          );
          db = SqliteMigrationManager.database;
          if (db == null) {
            final details = <String>[
              freshSqliteStatus.message,
              existingSqliteStatus.message,
            ]
                .map((message) => message.trim())
                .map((message) => message.startsWith('Bad state: ')
                    ? message.substring('Bad state: '.length).trim()
                    : message)
                .firstWhere(
                  (message) => message.isNotEmpty,
                  orElse: () => 'No diagnostic details were returned.',
                );
            throw StateError(
              'SQLite database failed to initialize. Reason: $details',
            );
          }
        }
        final activeDb = db;

        // Schema 25: warehouse_inventory is the sole persisted inventory source.
        // Migrate any genuinely legacy stock once, then physically remove the
        // retired products.stock column before business data is hydrated.
        await StartupTimingService.measure(
          'retire_legacy_product_stock',
          () async {
            await InventoryReconciliationRepository.backfillFromLegacyData(
                activeDb);
            await activeDb.dropLegacyProductStockColumn();
          },
          category: 'database',
        );

        _sqliteMirror
          ..clear()
          ..addAll(await StartupTimingService.measure(
            'hydrate_business_scalar_mirror',
            () => BusinessSqliteStore.hydrateScalarKeyMirror(activeDb),
            category: 'database',
          ))
          ..addAll(await StartupTimingService.measure(
            'hydrate_sync_scalar_mirror',
            () => SyncSqliteStore.hydrateScalarKeyMirror(activeDb),
            category: 'database',
          ));
        _pendingScalarWrites.clear();
        _pendingScalarDeletes.clear();
        _pendingBusinessEntityWrites.clear();
        _pendingSyncChanges.clear();
        _pendingSyncQueueItems.clear();
        _flushTimer?.cancel();
        _flushTimer = null;
        _sqliteReady = true;
        // Keep the app responsive on cold start. The deferred maintenance
        // work is intentionally not kicked off automatically here anymore,
        // because it can monopolize SQLite for several minutes on large data
        // sets and block page navigation right after launch.
      },
      category: 'bootstrap',
    );
  }

  // Keep the maintenance routine available for a controlled migration run;
  // it is deliberately not part of startup because it can hold SQLite busy.
  // ignore: unused_element
  Future<void> _runDeferredBootstrapMaintenance(
    VentioDriftDatabase db,
  ) async {
    try {
      await StartupTimingService.measure(
        'local_database.sqlite_deferred_maintenance',
        () async {
          await StartupTimingService.measure(
            'migrate_complex_business_tables',
            () => BusinessSqliteStore.migrateComplexTablesFromPayloadJson(db),
            category: 'database',
          );
          await StartupTimingService.measure(
            'rebuild_business_tables_without_payload_json',
            () => db.rebuildBusinessTablesWithoutPayloadJson(),
            category: 'database',
          );
          await StartupTimingService.measure(
            'backfill_warehouse_inventory',
            () => InventoryReconciliationRepository.backfillFromLegacyData(db),
            category: 'database',
          );
          await StartupTimingService.measure(
            'hydrate_secure_scalars',
            _hydrateAndMigrateSecureScalars,
            category: 'database',
          );
        },
        category: 'bootstrap',
        details: 'deferred',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[STARTUP][bootstrap] deferred sqlite maintenance failed: $error\n$stackTrace',
      );
    }
  }

  Map<String, String>? get _memoryStore => _memoryStoreForTesting;

  String? testingRawValue(String key) => _memoryStore?[key];

  /// Loads the small set of device-bound secrets before the widget tree starts.
  /// Business/database initialization remains independently asynchronous.
  Future<void> initializeSecureStorage() async {
    if (_memoryStoreForTesting != null) return;
    for (final key in _phase4SecureKeys) {
      try {
        final value = await _secureStorage.read(key: key);
        if (value == null || value.isEmpty) {
          _secureStringMirror.remove(key);
        } else {
          _secureStringMirror[key] = value;
        }
      } catch (_) {
        // Secure storage may be unavailable on unsupported web contexts.
        // Callers still fail closed because no secret is exposed from SQLite.
      }
    }
  }

  String? getSecureString(String key) => _secureStringMirror[key];

  Future<String?> readSecureString(String key) async {
    final memory = _memoryStore;
    if (memory != null) return _secureStringMirror[key];
    try {
      final value = await _secureStorage.read(key: key);
      if (value == null || value.isEmpty) {
        _secureStringMirror.remove(key);
        return null;
      }
      _secureStringMirror[key] = value;
      return value;
    } catch (_) {
      return _secureStringMirror[key];
    }
  }

  Future<void> setSecureString(String key, String value) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) {
      await deleteSecureString(key);
      return;
    }
    _secureStringMirror[key] = cleaned;
    if (_memoryStore != null) return;
    await _secureStorage.write(key: key, value: cleaned);
  }

  Future<void> deleteSecureString(String key) async {
    _secureStringMirror.remove(key);
    if (_memoryStore != null) return;
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {}
  }

  Future<void> _persistWebString(String key, String value) async {
    final indexedStore = _webIndexedStore;
    if (indexedStore != null) {
      final write = _webIndexedWriteChain
          .catchError((_) {})
          .then((_) => indexedStore.put(key, value));
      _webIndexedWriteChain = write.then<void>((_) {});
      await write;
      return;
    }
    final prefs = _webPreferences;
    if (prefs != null) await prefs.setString(key, value);
  }

  Future<void> _deleteWebString(String key) async {
    final indexedStore = _webIndexedStore;
    if (indexedStore != null) {
      final write = _webIndexedWriteChain
          .catchError((_) {})
          .then((_) => indexedStore.delete(key));
      _webIndexedWriteChain = write.then<void>((_) {});
      await write;
      return;
    }
    final prefs = _webPreferences;
    if (prefs != null) await prefs.remove(key);
  }

  Future<void> _hydrateAndMigrateSecureScalars() async {
    // Phase 1 security split:
    // - recoveryKey stays in FlutterSecureStorage.
    // - deviceToken is application identity data and is stored back inside
    //   app_identity_v1 in the local database. Keep this legacy secure key only
    //   long enough to migrate devices that used the previous secure-token build.
    final legacySecureDeviceToken =
        (await _secureStorage.read(key: _legacySecureDeviceTokenKey))?.trim() ??
            '';
    await initializeSecureStorage();
    await _deleteRawScalarValueImmediate('direct_api_token');

    final rawIdentity = _rawScalarValue(_appIdentityKey);
    if (rawIdentity != null && rawIdentity.trim().isNotEmpty) {
      final decoded = _tryDecodeJsonMap(rawIdentity);
      if (decoded != null) {
        final legacyDeviceToken =
            (decoded['deviceToken'] ?? decoded['device_token'] ?? '')
                .toString()
                .trim();
        if (legacyDeviceToken.isEmpty && legacySecureDeviceToken.isNotEmpty) {
          decoded['deviceToken'] = legacySecureDeviceToken;
        }
        final legacyRecoveryKey =
            (decoded['recoveryKey'] ?? decoded['recovery_key'] ?? '')
                .toString()
                .trim();
        if (legacyRecoveryKey.isNotEmpty &&
            (_secureStringMirror[_secureRecoveryKeyKey] ?? '').isEmpty) {
          final cleanRecoveryKey = legacyRecoveryKey.toUpperCase();
          await _secureStorage.write(
              key: _secureRecoveryKeyKey, value: cleanRecoveryKey);
          _secureStringMirror[_secureRecoveryKeyKey] = cleanRecoveryKey;
        }
        final sanitized = _sanitizeAppIdentityJson(jsonEncode(decoded));
        if (sanitized != rawIdentity) {
          await _writeRawScalarValueImmediate(_appIdentityKey, sanitized);
        }
      }
    }
    if (legacySecureDeviceToken.isNotEmpty) {
      await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
      _secureStringMirror.remove(_legacySecureDeviceTokenKey);
    }
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  String _sanitizeAppIdentityJson(String value) {
    final decoded = _tryDecodeJsonMap(value);
    if (decoded == null) return value;
    decoded.remove('recoveryKey');
    decoded.remove('recovery_key');
    return jsonEncode(decoded);
  }

  String _mergeSecureIdentitySecretsIntoIdentityJson(String value) {
    final recoveryKey =
        (_secureStringMirror[_secureRecoveryKeyKey] ?? '').trim();
    if (recoveryKey.isEmpty) return value;
    final decoded = _tryDecodeJsonMap(value);
    if (decoded == null) return value;
    if (recoveryKey.isNotEmpty) decoded['recoveryKey'] = recoveryKey;
    return jsonEncode(decoded);
  }

  String? _rawScalarValue(String key) {
    if (_pendingScalarDeletes.contains(key)) return null;
    final pending = _pendingScalarWrites[key];
    if (pending != null) return pending;
    final memory = _memoryStore;
    if (memory != null) return memory[key];
    if (_webStore != null) return _webStore![key];
    return _sqliteMirror[key];
  }

  Future<void> _writeRawScalarValueImmediate(String key, String value) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory[key] = value;
      return;
    }
    if (_webStore != null) {
      _webStore![key] = value;
      await _persistWebString(key, value);
      return;
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await SyncSqliteStore.saveKeyJson(db, key, value);
        } else {
          await BusinessSqliteStore.saveKeyJson(db, key, value);
        }
        _sqliteMirror[key] = value;
        return;
      }
    }
    throw StateError('SQLite database has not been initialized.');
  }

  Future<void> _deleteRawScalarValueImmediate(String key) async {
    final memory = _memoryStore;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    if (_webStore != null) {
      _webStore!.remove(key);
      await _deleteWebString(key);
      return;
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await SyncSqliteStore.saveKeyJson(
              db, key, key == SyncSqliteStore.syncSequenceKey ? '0' : '[]');
        } else {
          await BusinessSqliteStore.deleteKey(db, key);
          _sqliteMirror.remove(key);
        }
        return;
      }
    }
  }

  String? getString(String key) {
    final value = _rawScalarValue(key);
    if (key == _appIdentityKey && value != null) {
      return _mergeSecureIdentitySecretsIntoIdentityJson(value);
    }
    return value;
  }

  Future<List<StockMovement>?> getStockMovementsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getStockMovements();
  }

  Future<List<WarehouseInventory>?> getWarehouseInventoriesFromSqlite() async {
    if (_webStore != null) {
      final raw = _webStore![_webWarehouseInventoryKey];
      if (raw == null || raw.isEmpty) return <WarehouseInventory>[];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => WarehouseInventory.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false);
    }
    if (_memoryStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             warehouse_id AS warehouseId, product_id AS productId,
             quantity, version, created_at AS createdAt,
             updated_at AS updatedAt, device_id AS deviceId,
             sync_status AS syncStatus,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM warehouse_inventory
      ORDER BY store_id ASC, warehouse_id ASC, product_id ASC
    ''').get();
    return rows
        .map((row) =>
            WarehouseInventory.fromJson(Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  Future<List<InventoryReconciliation>?>
      getInventoryReconciliationsFromSqlite() async {
    if (_webStore != null) {
      final raw = _webStore![_webInventoryReconciliationsKey];
      if (raw == null || raw.isEmpty) return <InventoryReconciliation>[];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => InventoryReconciliation.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false);
    }
    if (_memoryStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             warehouse_id AS warehouseId, product_id AS productId,
             legacy_product_stock AS legacyProductStock,
             ledger_balance AS ledgerBalance,
             warehouse_balance AS warehouseBalance,
             difference, classification, status, created_at AS createdAt,
             resolved_at AS resolvedAt, resolution_note AS resolutionNote
      FROM inventory_reconciliations
      ORDER BY store_id ASC, warehouse_id ASC, product_id ASC
    ''').get();
    return rows
        .map((row) => InventoryReconciliation.fromJson(
            Map<String, dynamic>.from(row.data)))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>?> getStockOperationsFromSqlite() async {
    if (_webStore != null) {
      final raw = _webStore![_webStockOperationsKey];
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }
    if (_memoryStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, store_id AS storeId, branch_id AS branchId,
             operation_type AS operationType, document_type AS documentType,
             document_id AS documentId, movement_group_id AS movementGroupId,
             idempotency_key AS idempotencyKey, status, created_at AS createdAt,
             started_at AS startedAt, updated_at AS updatedAt,
             completed_at AS completedAt, failure_reason AS failureReason,
             attempt_count AS attemptCount, device_id AS deviceId,
             last_modified_by_device_id AS lastModifiedByDeviceId
      FROM stock_operations
      ORDER BY store_id ASC, created_at ASC, id ASC
    ''').get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>?> getInventoryBatchesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, product_id AS productId, product_name AS productName,
             supplier_batch_number AS supplierBatchNumber,
             manufacturing_date AS manufacturingDate,
             expiration_date AS expirationDate, status,
             source_type AS sourceType, source_id AS sourceId,
             source_line_id AS sourceLineId, unit_cost AS unitCost,
             initial_quantity AS initialQuantity,
             cost_currency AS costCurrency, exchange_rate AS exchangeRate,
             received_at AS receivedAt,
             store_id AS storeId, branch_id AS branchId,
             created_at AS createdAt, updated_at AS updatedAt,
             device_id AS deviceId,
             last_modified_by_device_id AS lastModifiedByDeviceId,
             sync_status AS syncStatus, version
      FROM inventory_batches
      ORDER BY store_id, product_id, expiration_date, id
    ''').get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>?>
      getInventoryBatchBalancesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, batch_id AS batchId, product_id AS productId,
             warehouse_id AS warehouseId, store_id AS storeId,
             branch_id AS branchId, quantity,
             reserved_quantity AS reservedQuantity, version,
             created_at AS createdAt, updated_at AS updatedAt,
             device_id AS deviceId,
             last_modified_by_device_id AS lastModifiedByDeviceId,
             sync_status AS syncStatus
      FROM inventory_batch_balances
      ORDER BY store_id, warehouse_id, product_id, batch_id
    ''').get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>?>
      getInventoryBatchReportFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) return null;
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT b.id AS batchId, b.product_id AS productId,
             b.product_name AS productName,
             b.supplier_batch_number AS supplierBatchNumber,
             b.manufacturing_date AS manufacturingDate,
             b.expiration_date AS expirationDate, b.status,
             b.source_type AS sourceType, b.source_id AS sourceId,
             b.source_line_id AS sourceLineId, b.received_at AS receivedAt,
             bb.warehouse_id AS warehouseId, bb.quantity,
             bb.reserved_quantity AS reservedQuantity,
             p.expiry_tracking_enabled AS expiryTrackingEnabled,
             p.expiry_alert_days AS alertDays,
             CASE WHEN b.unit_cost > 0 THEN b.unit_cost ELSE p.usd_cost END AS unitCost
      FROM inventory_batches b
      JOIN inventory_batch_balances bb ON bb.batch_id = b.id
      JOIN products p ON p.id = b.product_id
      WHERE b.source_type <> 'inventory_deficit'
      ORDER BY b.product_name ASC,
               CASE WHEN trim(b.received_at) = '' THEN b.created_at ELSE b.received_at END ASC,
               b.expiration_date ASC, b.id ASC
    ''').get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  /// Backward-compatible alias for older callers. The report is now the
  /// complete Unified Batch ledger, not expiry-only.
  Future<List<Map<String, dynamic>>?> getExpiryBatchReportFromSqlite() =>
      getInventoryBatchReportFromSqlite();
}
