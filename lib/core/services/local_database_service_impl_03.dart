part of 'local_database_service.dart';

extension _LocalDatabaseServiceImplPart3
    on _LocalDatabaseServiceImplementation {
  Future<void> upsertBusinessEntityJson(
      String key, Map<String, dynamic> payloadJson,
      {int? sortIndex}) async {
    await upsertBusinessEntityJsons(
      key,
      <Map<String, dynamic>>[payloadJson],
      sortIndices: <int?>[sortIndex],
    );
  }

  Future<void> upsertBusinessEntityJsons(
    String key,
    List<Map<String, dynamic>> payloadJsons, {
    List<int?>? sortIndices,
  }) async {
    if (payloadJsons.isEmpty) return;
    final memory = _memoryStore;
    if (memory != null) {
      return;
    }
    if (_webStore != null) {
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await BusinessSqliteStore.upsertEntityPayloads(
      db,
      key,
      payloadJsons
          .map((payload) => Map<String, dynamic>.from(payload))
          .toList(growable: false),
      sortIndices: sortIndices,
    );
    _sqliteMirror.remove(key);
  }

  Future<void> upsertSyncChange(SyncChange change) async {
    await upsertSyncChanges(<SyncChange>[change]);
  }

  Future<void> upsertSyncChanges(List<SyncChange> changes) async {
    if (changes.isEmpty) return;
    final memory = _memoryStore;
    if (memory != null) {
      return;
    }
    if (_webStore != null) {
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await SyncSqliteStore.upsertSyncChanges(db, changes);
    _sqliteMirror.remove(SyncSqliteStore.syncChangesKey);
  }

  Future<void> upsertSyncQueueItem(SyncQueueItem item) async {
    await upsertSyncQueueItems(<SyncQueueItem>[item]);
  }

  Future<void> upsertSyncQueueItems(List<SyncQueueItem> items) async {
    if (items.isEmpty) return;
    final memory = _memoryStore;
    if (memory != null) {
      return;
    }
    if (_webStore != null) {
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await SyncSqliteStore.upsertSyncQueueItems(db, items);
    _sqliteMirror.remove(SyncSqliteStore.syncQueueKey);
  }

  Future<void> setString(String key, String value) async {
    if (key == _appIdentityKey) {
      if (_memoryStore != null || _webStore != null) {
        await _writeRawScalarValueImmediate(key, value);
        return;
      }
      final decoded = _tryDecodeJsonMap(value);
      final recoveryKey =
          (decoded?['recoveryKey'] ?? decoded?['recovery_key'] ?? '')
              .toString()
              .trim();
      if (recoveryKey.isNotEmpty) {
        final cleanRecoveryKey = recoveryKey.toUpperCase();
        await _secureStorage.write(
            key: _secureRecoveryKeyKey, value: cleanRecoveryKey);
        _secureStringMirror[_secureRecoveryKeyKey] = cleanRecoveryKey;
      }
      await _writeRawScalarValueImmediate(key, _sanitizeAppIdentityJson(value));
      return;
    }
    final memory = _memoryStore;
    if (memory != null) {
      await _writeRawScalarValueImmediate(key, value);
      return;
    }
    if (_webStore != null) {
      await _writeRawScalarValueImmediate(key, value);
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
      return;
    }
    await _writeRawScalarValueImmediate(key, value);
  }

  bool containsKey(String key) {
    if (_pendingScalarDeletes.contains(key)) return false;
    if (_pendingScalarWrites.containsKey(key)) return true;
    final memory = _memoryStore;
    if (memory != null) return memory.containsKey(key);
    if (_webStore != null) return _webStore!.containsKey(key);
    if (_sqliteReady) {
      return _sqliteMirror.containsKey(key);
    }
    return false;
  }

  Future<void> deleteString(String key) async {
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

    if (key == _appIdentityKey) {
      await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
      await _secureStorage.delete(key: _secureRecoveryKeyKey);
      _secureStringMirror.remove(_legacySecureDeviceTokenKey);
      _secureStringMirror.remove(_secureRecoveryKeyKey);
    }
    if (_sqliteReady) {
      final db = SqliteMigrationManager.database;
      if (db != null) {
        if (SyncSqliteStore.isSqliteBackedKey(key)) {
          await setString(
              key, key == SyncSqliteStore.syncSequenceKey ? '0' : '[]');
        } else {
          await BusinessSqliteStore.deleteKey(db, key);
          _sqliteMirror.remove(key);
        }
        return;
      }
    }
    return;
  }

  Future<void> clearAll() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingScalarWrites.clear();
    _pendingScalarDeletes.clear();
    _pendingBusinessEntityWrites.clear();
    _pendingSyncChanges.clear();
    _pendingSyncQueueItems.clear();
    final memory = _memoryStore;
    if (memory != null) {
      memory.clear();
      return;
    }
    if (_webStore != null) {
      final prefs = _webPreferences;
      final keys = List<String>.from(_webStore!.keys);
      _webStore!.clear();
      if (prefs != null) {
        for (final key in keys) {
          await prefs.remove(key);
        }
      }
      return;
    }
    await _secureStorage.delete(key: _legacySecureDeviceTokenKey);
    _secureStringMirror.remove(_legacySecureDeviceTokenKey);
    for (final key in _phase4SecureKeys) {
      await deleteSecureString(key);
    }
    final db = SqliteMigrationManager.database;
    if (_sqliteReady && db != null) {
      await BusinessSqliteStore.clear(db);
      await SyncSqliteStore.saveKeyJson(
          db, SyncSqliteStore.syncChangesKey, '[]');
      await SyncSqliteStore.saveKeyJson(db, SyncSqliteStore.syncQueueKey, '[]');
      await SyncSqliteStore.saveKeyJson(
          db, SyncSqliteStore.syncSequenceKey, '0');
      await db.customUpdate('DELETE FROM app_logs');
      // Phase 6 audit history is append-only and intentionally survives
      // data resets/restores. The reset/restore action is appended separately.
      _sqliteMirror
        ..clear()
        ..addAll(<String, String>{
          SyncSqliteStore.syncChangesKey: '[]',
          SyncSqliteStore.syncQueueKey: '[]',
          SyncSqliteStore.syncSequenceKey: '0',
        });
      return;
    }
    return;
  }

  Future<void> flushPendingWrites() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingScalarWrites.clear();
    _pendingScalarDeletes.clear();
    _pendingBusinessEntityWrites.clear();
    _pendingSyncChanges.clear();
    _pendingSyncQueueItems.clear();
  }

  Future<void> runSqliteAuthoritativeTransaction(
      Future<void> Function() action) async {
    final db = SqliteMigrationManager.database;
    if (db == null || !_sqliteReady) {
      await action();
      return;
    }
    await db.transaction(() async {
      await action();
    });
  }

  /// Rehydrates the SQLite scalar mirror from the committed database state.
  ///
  /// Immediate snapshot writes update the in-memory mirror while a Drift
  /// transaction is still open. If that transaction rolls back, SQLite is
  /// correct but the mirror would otherwise keep the rejected values. Call
  /// this after an authoritative transaction failure before exposing runtime
  /// state again.
  Future<void> refreshSqliteMirrorAfterRollback() async {
    final db = SqliteMigrationManager.database;
    if (db == null ||
        !_sqliteReady ||
        _memoryStore != null ||
        _webStore != null) {
      return;
    }
    _sqliteMirror
      ..clear()
      ..addAll(await BusinessSqliteStore.hydrateScalarKeyMirror(db))
      ..addAll(await SyncSqliteStore.hydrateScalarKeyMirror(db));
    _pendingScalarWrites.clear();
    _pendingScalarDeletes.clear();
    _pendingBusinessEntityWrites.clear();
    _pendingSyncChanges.clear();
    _pendingSyncQueueItems.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  Future<void> replaceBusinessEntityJsonListImmediate(
      String key, List<Map<String, dynamic>> payloads,
      {List<int?>? sortIndices}) async {
    var orderedPayloads = payloads;
    if (sortIndices != null && sortIndices.length == payloads.length) {
      final entries = <({Map<String, dynamic> payload, int? sortIndex})>[];
      for (var i = 0; i < payloads.length; i += 1) {
        entries.add((payload: payloads[i], sortIndex: sortIndices[i]));
      }
      entries.sort((a, b) {
        final aIndex = a.sortIndex ?? 1 << 30;
        final bIndex = b.sortIndex ?? 1 << 30;
        return aIndex.compareTo(bIndex);
      });
      orderedPayloads =
          entries.map((item) => item.payload).toList(growable: false);
    }
    final encoded = jsonEncode(orderedPayloads);
    final memory = _memoryStore;
    if (memory != null) {
      memory[key] = encoded;
      return;
    }
    if (_webStore != null) {
      _webStore![key] = encoded;
      await _persistWebString(key, encoded);
      return;
    }
    final db = SqliteMigrationManager.database;
    if (_sqliteReady && db != null) {
      await BusinessSqliteStore.saveKeyJson(db, key, encoded);
      _sqliteMirror[key] = encoded;
    }
  }

  Future<void> replaceWarehouseInventoryRowsImmediate(
      List<Map<String, dynamic>> rows,
      {bool allowNegativeStock = false}) async {
    if (!allowNegativeStock) {
      for (final row in rows) {
        final quantity = _doubleValue(row['quantity'], fallback: 0);
        if (quantity < -0.000001) {
          throw StateError(
            'Negative warehouse inventory is not allowed by the current stock policy.',
          );
        }
      }
    }
    final memory = _memoryStore;
    if (memory != null) return;
    if (_webStore != null) {
      final encoded = jsonEncode(rows);
      _webStore![_webWarehouseInventoryKey] = encoded;
      await _persistWebString(_webWarehouseInventoryKey, encoded);
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await db.customStatement('DELETE FROM warehouse_inventory');
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO warehouse_inventory
          (id, store_id, branch_id, warehouse_id, product_id, quantity,
           version, created_at, updated_at, device_id, sync_status,
           last_modified_by_device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(
              row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ??
              row['branch_id']?.toString() ??
              'main'),
          Variable<String>(row['warehouseId']?.toString() ??
              row['warehouse_id']?.toString() ??
              ''),
          Variable<String>(row['productId']?.toString() ??
              row['product_id']?.toString() ??
              ''),
          Variable<double>(_doubleValue(row['quantity'], fallback: 0)),
          Variable<int>(_intValue(row['version'], fallback: 1)),
          Variable<String>(row['createdAt']?.toString() ??
              row['created_at']?.toString() ??
              DateTime.now().toIso8601String()),
          Variable<String>(row['updatedAt']?.toString() ??
              row['updated_at']?.toString() ??
              DateTime.now().toIso8601String()),
          Variable<String>(row['deviceId']?.toString() ??
              row['device_id']?.toString() ??
              ''),
          Variable<String>(row['syncStatus']?.toString() ??
              row['sync_status']?.toString() ??
              'synced'),
          Variable<String>(row['lastModifiedByDeviceId']?.toString() ??
              row['last_modified_by_device_id']?.toString() ??
              ''),
        ],
      );
    }
  }

  Future<void> replaceStockOperationsRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) async {
    final memory = _memoryStore;
    if (memory != null) return;
    if (_webStore != null) {
      final encoded = jsonEncode(rows);
      _webStore![_webStockOperationsKey] = encoded;
      await _persistWebString(_webStockOperationsKey, encoded);
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await db.customStatement('DELETE FROM stock_operations');
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO stock_operations
          (id, store_id, branch_id, operation_type, document_type, document_id,
           movement_group_id, idempotency_key, status, created_at, started_at,
           updated_at, completed_at, failure_reason, attempt_count, device_id,
           last_modified_by_device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(
              row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ??
              row['branch_id']?.toString() ??
              'main'),
          Variable<String>(row['operationType']?.toString() ??
              row['operation_type']?.toString() ??
              ''),
          Variable<String>(row['documentType']?.toString() ??
              row['document_type']?.toString() ??
              ''),
          Variable<String>(row['documentId']?.toString() ??
              row['document_id']?.toString() ??
              ''),
          Variable<String>(row['movementGroupId']?.toString() ??
              row['movement_group_id']?.toString() ??
              ''),
          Variable<String>(row['idempotencyKey']?.toString() ??
              row['idempotency_key']?.toString() ??
              ''),
          Variable<String>(row['status']?.toString() ?? 'pending'),
          Variable<String>(row['createdAt']?.toString() ??
              row['created_at']?.toString() ??
              DateTime.now().toIso8601String()),
          Variable<String>(row['startedAt']?.toString() ??
              row['started_at']?.toString() ??
              ''),
          Variable<String>(row['updatedAt']?.toString() ??
              row['updated_at']?.toString() ??
              ''),
          Variable<String>(row['completedAt']?.toString() ??
              row['completed_at']?.toString() ??
              ''),
          Variable<String>(row['failureReason']?.toString() ??
              row['failure_reason']?.toString() ??
              ''),
          Variable<int>(_intValue(row['attemptCount'] ?? row['attempt_count'],
              fallback: 0)),
          Variable<String>(row['deviceId']?.toString() ??
              row['device_id']?.toString() ??
              ''),
          Variable<String>(row['lastModifiedByDeviceId']?.toString() ??
              row['last_modified_by_device_id']?.toString() ??
              ''),
        ],
      );
    }
  }

  Future<void> replaceStockMovementRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) async {
    final memory = _memoryStore;
    if (memory != null || _webStore != null) return;
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    final replacedAt = DateTime.now().toUtc().toIso8601String();
    await db.customUpdate(
      "UPDATE stock_movements SET deleted_at = ?, updated_at = ? WHERE deleted_at = ''",
      variables: <Variable<Object>>[
        Variable<String>(replacedAt),
        Variable<String>(replacedAt),
      ],
    );
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO stock_movements
          (id, entity_type, created_at, updated_at, deleted_at, device_id,
           sync_status, store_id, branch_id, version, sort_index, product_id,
           product_name, movement_type, quantity, movement_date, reference_id,
           reference_no, reason, adjustment_category, notes, evidence_ref,
           warehouse_id, warehouse_name, movement_group_id, document_line_id,
           source_movement_id, reversal_of_movement_id, idempotency_key,
           unit_cost, last_modified_by_device_id, reviewed_at, reviewed_by,
           review_note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(row['entityType']?.toString() ??
              row['entity_type']?.toString() ??
              'stock_movement'),
          Variable<String>(row['createdAt']?.toString() ??
              row['created_at']?.toString() ??
              DateTime.now().toIso8601String()),
          Variable<String>(row['updatedAt']?.toString() ??
              row['updated_at']?.toString() ??
              DateTime.now().toIso8601String()),
          Variable<String>(row['deletedAt']?.toString() ??
              row['deleted_at']?.toString() ??
              ''),
          Variable<String>(row['deviceId']?.toString() ??
              row['device_id']?.toString() ??
              ''),
          Variable<String>(row['syncStatus']?.toString() ??
              row['sync_status']?.toString() ??
              'pending'),
          Variable<String>(
              row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ??
              row['branch_id']?.toString() ??
              'main'),
          Variable<int>(_intValue(row['version'], fallback: 1)),
          Variable<int>(
              _intValue(row['sortIndex'] ?? row['sort_index'], fallback: 0)),
          Variable<String>(row['productId']?.toString() ??
              row['product_id']?.toString() ??
              ''),
          Variable<String>(row['productName']?.toString() ??
              row['product_name']?.toString() ??
              ''),
          Variable<String>(row['movementType']?.toString() ??
              row['movement_type']?.toString() ??
              row['type']?.toString() ??
              'adjustment'),
          Variable<double>(_doubleValue(row['quantity'], fallback: 0)),
          Variable<String>(row['movementDate']?.toString() ??
              row['movement_date']?.toString() ??
              row['date']?.toString() ??
              DateTime.now().toIso8601String()),
          Variable<String>(row['referenceId']?.toString() ??
              row['reference_id']?.toString() ??
              ''),
          Variable<String>(row['referenceNo']?.toString() ??
              row['reference_no']?.toString() ??
              ''),
          Variable<String>(row['reason']?.toString() ?? ''),
          Variable<String>(row['adjustmentCategory']?.toString() ??
              row['adjustment_category']?.toString() ??
              ''),
          Variable<String>(row['notes']?.toString() ?? ''),
          Variable<String>(row['evidenceRef']?.toString() ??
              row['evidence_ref']?.toString() ??
              ''),
          Variable<String>(row['warehouseId']?.toString() ??
              row['warehouse_id']?.toString() ??
              'main'),
          Variable<String>(row['warehouseName']?.toString() ??
              row['warehouse_name']?.toString() ??
              'Main warehouse'),
          Variable<String>(row['movementGroupId']?.toString() ??
              row['movement_group_id']?.toString() ??
              ''),
          Variable<String>(row['documentLineId']?.toString() ??
              row['document_line_id']?.toString() ??
              ''),
          Variable<String>(row['sourceMovementId']?.toString() ??
              row['source_movement_id']?.toString() ??
              ''),
          Variable<String>(row['reversalOfMovementId']?.toString() ??
              row['reversal_of_movement_id']?.toString() ??
              ''),
          Variable<String>(row['idempotencyKey']?.toString() ??
              row['idempotency_key']?.toString() ??
              ''),
          Variable<double>(
              _doubleValue(row['unitCost'] ?? row['unit_cost'], fallback: 0)),
          Variable<String>(row['lastModifiedByDeviceId']?.toString() ??
              row['last_modified_by_device_id']?.toString() ??
              row['device_id']?.toString() ??
              ''),
          Variable<String>(row['reviewedAt']?.toString() ??
              row['reviewed_at']?.toString() ??
              ''),
          Variable<String>(row['reviewedBy']?.toString() ??
              row['reviewed_by']?.toString() ??
              ''),
          Variable<String>(row['reviewNote']?.toString() ??
              row['review_note']?.toString() ??
              ''),
        ],
      );
    }
  }

  Future<void> replaceInventoryReconciliationsRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) async {
    final memory = _memoryStore;
    if (memory != null) return;
    if (_webStore != null) {
      final encoded = jsonEncode(rows);
      _webStore![_webInventoryReconciliationsKey] = encoded;
      await _persistWebString(_webInventoryReconciliationsKey, encoded);
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await db.customStatement('DELETE FROM inventory_reconciliations');
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO inventory_reconciliations
          (id, store_id, branch_id, warehouse_id, product_id,
           legacy_product_stock, ledger_balance, warehouse_balance, difference,
           classification, status, created_at, resolved_at, resolution_note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(
              row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ??
              row['branch_id']?.toString() ??
              'main'),
          Variable<String>(row['warehouseId']?.toString() ??
              row['warehouse_id']?.toString() ??
              ''),
          Variable<String>(row['productId']?.toString() ??
              row['product_id']?.toString() ??
              ''),
          Variable<double>(_doubleValue(
              row['legacyProductStock'] ?? row['legacy_product_stock'],
              fallback: 0)),
          Variable<double>(_doubleValue(
              row['ledgerBalance'] ?? row['ledger_balance'],
              fallback: 0)),
          Variable<double>(_doubleValue(
              row['warehouseBalance'] ?? row['warehouse_balance'],
              fallback: 0)),
          Variable<double>(_doubleValue(row['difference'], fallback: 0)),
          Variable<String>(row['classification']?.toString() ?? ''),
          Variable<String>(row['status']?.toString() ?? 'open'),
          Variable<String>(row['createdAt']?.toString() ??
              row['created_at']?.toString() ??
              DateTime.now().toIso8601String()),
          Variable<String>(row['resolvedAt']?.toString() ??
              row['resolved_at']?.toString() ??
              ''),
          Variable<String>(row['resolutionNote']?.toString() ??
              row['resolution_note']?.toString() ??
              ''),
        ],
      );
    }
  }

  Future<void> replaceInventoryMigrationAdjustmentsRowsImmediate(
    List<Map<String, dynamic>> rows,
  ) async {
    final memory = _memoryStore;
    if (memory != null) return;
    if (_webStore != null) {
      final encoded = jsonEncode(rows);
      _webStore![_webInventoryMigrationAdjustmentsKey] = encoded;
      await _persistWebString(_webInventoryMigrationAdjustmentsKey, encoded);
      return;
    }
    final db = SqliteMigrationManager.database;
    if (!_sqliteReady || db == null) return;
    await db.customStatement('DELETE FROM inventory_migration_adjustments');
    for (final row in rows) {
      await db.customInsert(
        '''
        INSERT OR REPLACE INTO inventory_migration_adjustments
          (id, migration_batch_id, store_id, branch_id, warehouse_id, product_id,
           legacy_product_stock, ledger_balance, applied_delta, created_at,
           updated_at, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(row['id']?.toString() ?? ''),
          Variable<String>(row['migrationBatchId']?.toString() ??
              row['migration_batch_id']?.toString() ??
              ''),
          Variable<String>(
              row['storeId']?.toString() ?? row['store_id']?.toString() ?? ''),
          Variable<String>(row['branchId']?.toString() ??
              row['branch_id']?.toString() ??
              'main'),
          Variable<String>(row['warehouseId']?.toString() ??
              row['warehouse_id']?.toString() ??
              ''),
          Variable<String>(row['productId']?.toString() ??
              row['product_id']?.toString() ??
              ''),
          Variable<double>(_doubleValue(
              row['legacyProductStock'] ?? row['legacy_product_stock'],
              fallback: 0)),
          Variable<double>(_doubleValue(
              row['ledgerBalance'] ?? row['ledger_balance'],
              fallback: 0)),
          Variable<double>(_doubleValue(
              row['appliedDelta'] ?? row['applied_delta'],
              fallback: 0)),
          Variable<String>(row['createdAt']?.toString() ??
              row['created_at']?.toString() ??
              DateTime.now().toIso8601String()),
          Variable<String>(row['updatedAt']?.toString() ??
              row['updated_at']?.toString() ??
              DateTime.now().toIso8601String()),
          Variable<String>(row['notes']?.toString() ?? ''),
        ],
      );
    }
  }

  List<String> keys() {
    final memory = _memoryStore;
    if (memory != null) return memory.keys.toList()..sort();
    if (_webStore != null) return _webStore!.keys.toList()..sort();
    if (_sqliteReady) return _sqliteMirror.keys.toList()..sort();
    return const <String>[];
  }

  Map<String, String> allEntries() {
    final memory = _memoryStore;
    if (memory != null) return Map<String, String>.from(memory);
    if (_webStore != null) return Map<String, String>.from(_webStore!);
    if (_sqliteReady) return Map<String, String>.from(_sqliteMirror);
    return const <String, String>{};
  }
}
