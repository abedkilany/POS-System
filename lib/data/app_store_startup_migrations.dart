part of 'app_store.dart';

extension _AppStoreSplitStartupMigrations on AppStore {
Future<void> initialize({bool hydrateHeavyData = true}) async {
    var unifiedBatchPhase4Blocked = false;
    StartupTimingService.event('app_store.initialize.begin',
        category: 'app_store');
    await LocalDatabaseService.initialize();
    await _ensureDeviceId();

    final isWebStartup = kIsWeb;
    StartupTimingService.event(
      'app_store.startup_mode',
      category: 'app_store',
      details: isWebStartup ? 'web_persistent_store' : 'db_first',
    );

    if (!isWebStartup &&
        !LocalDatabaseService.isSqliteAuthoritative &&
        !LocalDatabaseService.isInMemoryStoreForTesting) {
      throw StateError('SQLite database is not ready for DB-first startup.');
    }

    await StartupTimingService.measure(
      isWebStartup
          ? 'app_store.web_startup_load'
          : 'app_store.db_first_startup_load',
      () async {
        // Keep boot lean: load only the data needed to decide the login gate
        // and restore the current session. Large business lists hydrate lazily
        // through the existing ensure*Loaded() entry points.
        _storeProfile = _loadStoreProfile();
        await _compactPostedSnapshotLogosIfNeeded();
        AccountingService.configureMoneyPolicy(_storeProfile);
        final rolesFuture = _loadRoles();
        final usersFuture = _loadUsers();
        _invoiceCounter = _loadInvoiceCounter();
        _purchaseCounter = _loadPurchaseCounter();
        _currentRole =
            LocalDatabaseService.getString(AppStore._currentRoleKey) ?? 'admin';
        _roles
          ..clear()
          ..addAll(await rolesFuture);
        _users
          ..clear()
          ..addAll(await usersFuture);
        await _ensureDefaultAdminUser();
        _rememberLogin =
            LocalDatabaseService.getString(AppStore._rememberLoginKey) == 'true';
        _restoreActiveUser();
        _appIdentity = _loadOrCreateAppIdentity();
        final initializedIdentity = appIdentity;
        final directSettings = DirectSyncSettings.load();
        final directBootstrapIncomplete = initializedIdentity.isClient &&
            initializedIdentity.activeSyncTransportNormalized == 'direct' &&
            directSettings.hasBootstrapConfiguration &&
            !directSettings.setupComplete;
        if (directBootstrapIncomplete && _activeUser != null) {
          // A failed first Snapshot must never restore a remembered local
          // session from partially imported data. Keep the device behind the
          // connection gate until a new Snapshot completes and is verified.
          _activeUser = null;
          _rememberLogin = false;
          await LocalDatabaseService.setString(AppStore._activeUserKey, '');
          await LocalDatabaseService.setString(
            AppStore._rememberLoginKey,
            'false',
          );
        }
        _syncSequence = _loadSyncSequence();

        if (!kIsWeb &&
            LocalDatabaseService.isSqliteAuthoritative &&
            !LocalDatabaseService.isSqliteDatabaseForTesting) {
          final db = SqliteMigrationManager.database;
          if (db != null) {
            final phase4Service = UnifiedBatchPhase4ClosureService(db);
            try {
              final closure = await phase4Service.close(
                storeId: initializedIdentity.storeId,
                branchId: initializedIdentity.branchId,
                deviceId: _deviceId,
                allowNegativeStock: _storeProfile.allowNegativeStock,
              );
              debugPrint(
                'Unified Batch Phase 4 closed: ${closure.cutoversCreated} cutover(s) created, ${closure.productWarehousePairs} inventory pair(s) verified.',
              );
              await LocalDatabaseService.setString(
                AppStore._inventoryCostingMethodKey,
                InventoryCostingMethod.batch.code,
              );
              _inventoryCostingMethod = InventoryCostingMethod.batch;
            } catch (error, stackTrace) {
              // A failed closure is a hard integrity boundary. Keep the app
              // available for diagnostics/repair, but do not mark costing as
              // migrated and do not allow further stock mutations until the
              // closure can be completed successfully.
              unifiedBatchPhase4Blocked = true;
              await phase4Service.markBlocked(error: error);
              debugPrint('Unified Batch Phase 4 closure requires attention: $error');
              debugPrint('$stackTrace');
            }
          }
        }
      },
      category: 'app_store',
    );

    if (!kIsWeb &&
        LocalDatabaseService.isSqliteAuthoritative &&
        AccountingService.isAvailable &&
        !unifiedBatchPhase4Blocked) {
      try {
        await AccountingService.ensureInventoryAccountClassificationMigration();
        final reconciled = await AccountingService
            .reconcileInventoryAccountClassification(
          referenceContext: 'startup',
        );
        if (!reconciled) {
          debugPrint(
            'Inventory account classification reconciliation is blocked by a valuation mismatch.',
          );
        }
      } catch (error, stackTrace) {
        // Reclassification is deliberately conservative. A genuine
        // inventory/GL discrepancy must never be hidden by an automatic
        // gain/loss posting. Startup remains available for repair and a later
        // retry.
        debugPrint(
            'Inventory account reclassification was not applied: $error');
        debugPrint('$stackTrace');
      }
    }

    // In-memory tests exercise synchronous AppStore getters immediately after
    // initialize(). Production keeps the DB-first boot lean and hydrates heavy
    // collections lazily, while tests need an explicit deterministic boundary.
    if (hydrateHeavyData && LocalDatabaseService.isInMemoryStoreForTesting) {
      await ensureHeavyDataLoaded(failOnError: true);
    }

    _isReady = true;
    notifyListeners();
    StartupTimingService.event('app_store.ready', category: 'app_store');
  }

Future<String?> _loadEntityListJsonForStartup(String key) {
    if (LocalDatabaseService.isInMemoryStoreForTesting) {
      return Future<String?>.value(LocalDatabaseService.testingRawValue(key));
    }
    if (kIsWeb) {
      return Future<String?>.value(LocalDatabaseService.getString(key));
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return Future.value(null);
    if (BusinessSqliteStore.isTypedEntityKey(key)) {
      return BusinessSqliteStore.readEntityListJsonByKey(db, key);
    }
    if (SyncSqliteStore.isSqliteBackedKey(key)) {
      return SyncSqliteStore.readKeyJson(db, key);
    }
    return Future.value(null);
  }

Future<List<String>> _loadEntityListJsonBatchesForStartup(
    String key, {
    int batchSize = 100,
  }) {
    if (LocalDatabaseService.isInMemoryStoreForTesting) {
      final raw = LocalDatabaseService.testingRawValue(key);
      if (raw == null || raw.isEmpty) return Future.value(const <String>[]);
      return Future.value(<String>[raw]);
    }
    if (kIsWeb) {
      final raw = LocalDatabaseService.getString(key);
      if (raw == null || raw.isEmpty) return Future.value(const <String>[]);
      return Future.value(<String>[raw]);
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return Future.value(const <String>[]);
    if (BusinessSqliteStore.isTypedEntityKey(key)) {
      return BusinessSqliteStore.readEntityListJsonBatches(
        db,
        key,
        batchSize: batchSize,
      );
    }
    if (key == AppStore._syncChangesKey) {
      return SyncSqliteStore.readSyncChangesJsonBatches(
        db,
        batchSize: batchSize,
      );
    }
    if (key == AppStore._syncQueueKey) {
      return SyncSqliteStore.readSyncQueueJsonBatches(
        db,
        batchSize: batchSize,
      );
    }
    return Future.value(const <String>[]);
  }

Future<List<T>> _decodeDeferredList<T>(
      String key, T Function(Map<String, dynamic>) fromJson,
      {int? batchSize}) async {
    return StartupTimingService.measure(
      'app_store.decode.$key',
      () async {
        if (batchSize != null && batchSize > 0) {
          final batches = await _loadEntityListJsonBatchesForStartup(
            key,
            batchSize: batchSize,
          );
          if (batches.isNotEmpty) {
            final result = <T>[];
            for (final batchRaw in batches) {
              if (batchRaw.trim().isEmpty) {
                await Future<void>.delayed(Duration.zero);
                continue;
              }
              final decoded = batchRaw.length > 250000
                  ? await compute(_decodeJsonListPayload, batchRaw)
                  : _decodeJsonListPayload(batchRaw);
              for (final item in decoded) {
                result.add(fromJson(item));
              }
              await Future<void>.delayed(Duration.zero);
            }
            return result;
          }
        }
        final raw = await _loadEntityListJsonForStartup(key);
        if (raw == null || raw.isEmpty) return <T>[];
        final decoded = raw.length > 250000
            ? await compute(_decodeJsonListPayload, raw)
            : _decodeJsonListPayload(raw);
        final result = <T>[];
        const chunkSize = 750;
        for (var index = 0; index < decoded.length; index += 1) {
          result.add(fromJson(decoded[index]));
          if ((index + 1) % chunkSize == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        return result;
      },
      category: 'app_store',
    );
  }

Future<List<T>> _loadTypedEntityList<T>(
    String key,
    Future<List<T>?> Function() typedLoader,
    T Function(Map<String, dynamic>) fromJson, {
    int? batchSize,
  }) async {
    final typed = await typedLoader();
    if (typed != null) return typed;
    if (LocalDatabaseService.isSqliteAuthoritative) return <T>[];
    return _decodeDeferredList<T>(
      key,
      fromJson,
      batchSize: batchSize,
    );
  }

Future<List<StockMovement>> _loadStockMovementsForStartup() async {
    final typed = await LocalDatabaseService.getStockMovementsFromSqlite();
    if (typed != null) return typed;
    if (LocalDatabaseService.isSqliteAuthoritative) {
      return <StockMovement>[];
    }
    return _decodeDeferredList<StockMovement>(
      AppStore._stockMovementsKey,
      StockMovement.fromJson,
      batchSize: 100,
    );
  }

Future<List<AccountTransaction>> _loadAccountTransactionsForStartup() async {
    final typed = await LocalDatabaseService.getAccountTransactionsFromSqlite();
    if (typed != null) return typed;
    return _decodeDeferredList<AccountTransaction>(
      AppStore._accountTransactionsKey,
      AccountTransaction.fromJson,
      batchSize: 100,
    );
  }


Future<void> _compactPostedSnapshotLogosIfNeeded() async {
    if (kIsWeb || !LocalDatabaseService.isSqliteAuthoritative) return;
    final db = SqliteMigrationManager.database;
    if (db == null) return;

    final historicalAssets = <String, String>{
      ..._storeProfile.historicalLogoAssetsBase64,
    };
    final currentLogoAssetId = _storeProfile.logoAssetId.isNotEmpty
        ? _storeProfile.logoAssetId
        : StoreProfile.logoAssetIdForData(_storeProfile.logoDataBase64);

    var rowsChanged = 0;
    var bytesRemoved = 0;
    var storeProfileUpdated = false;

    void rememberAsset(String assetId, String data) {
      if (assetId.isEmpty || data.isEmpty) return;
      if (assetId == currentLogoAssetId &&
          data == _storeProfile.logoDataBase64) {
        return;
      }
      historicalAssets.putIfAbsent(assetId, () => data);
    }

    bool compactSnapshotMap(Map<String, dynamic> snapshot) {
      final rawStoreProfile = snapshot['storeProfile'];
      if (rawStoreProfile is! Map) return false;
      final storeProfile = Map<String, dynamic>.from(rawStoreProfile);
      final rawProfileJson = storeProfile['profileJson'];
      if (rawProfileJson is! Map) return false;
      final profileJson = Map<String, dynamic>.from(rawProfileJson);
      var changed = false;

      final rawHistory = profileJson['historicalLogoAssetsBase64'];
      if (rawHistory is Map) {
        for (final entry in rawHistory.entries) {
          final assetId = entry.key.toString().trim();
          final data = entry.value?.toString() ?? '';
          rememberAsset(assetId, data);
        }
        profileJson.remove('historicalLogoAssetsBase64');
        changed = true;
      }

      if (profileJson.containsKey('logoDataBase64')) {
        final logoData = profileJson['logoDataBase64']?.toString() ?? '';
        var assetId = profileJson['logoAssetId']?.toString().trim() ?? '';
        if (logoData.isNotEmpty) {
          if (assetId.isEmpty) {
            assetId = StoreProfile.logoAssetIdForData(logoData);
          }
          rememberAsset(assetId, logoData);
          if (assetId.isNotEmpty) profileJson['logoAssetId'] = assetId;
        }
        profileJson.remove('logoDataBase64');
        changed = true;
      }

      final schemaVersion = (snapshot['schemaVersion'] as num? ?? 1).toInt();
      if (schemaVersion < PostedDocumentSnapshot.currentSchemaVersion) {
        snapshot['schemaVersion'] = PostedDocumentSnapshot.currentSchemaVersion;
        changed = true;
      }

      if (!changed) return false;
      storeProfile['profileJson'] = profileJson;
      snapshot['storeProfile'] = storeProfile;
      return true;
    }

    String compactSnapshotJson(String raw) {
      if (raw.trim().isEmpty || !raw.contains('logoDataBase64')) return raw;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return raw;
        final snapshot = Map<String, dynamic>.from(decoded);
        if (!compactSnapshotMap(snapshot)) return raw;
        return jsonEncode(snapshot);
      } catch (_) {
        return raw;
      }
    }

    String compactCreditNotesJson(String raw) {
      if (raw.trim().isEmpty || !raw.contains('logoDataBase64')) return raw;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return raw;
        var changed = false;
        final notes = <Object?>[];
        for (final item in decoded) {
          if (item is! Map) {
            notes.add(item);
            continue;
          }
          final note = Map<String, dynamic>.from(item);
          final rawSnapshot = note['postedSnapshot'];
          if (rawSnapshot is Map) {
            final snapshot = Map<String, dynamic>.from(rawSnapshot);
            if (compactSnapshotMap(snapshot)) {
              note['postedSnapshot'] = snapshot;
              changed = true;
            }
          }
          notes.add(note);
        }
        return changed ? jsonEncode(notes) : raw;
      } catch (_) {
        return raw;
      }
    }

    try {
      await db.transaction(() async {
        for (final table in const <String>['sales', 'purchases']) {
          final rows = await db.customSelect(
            "SELECT id, posted_snapshot_json FROM $table "
            "WHERE posted_snapshot_json <> '' "
            "AND instr(posted_snapshot_json, 'logoDataBase64') > 0",
          ).get();
          for (final row in rows) {
            final id = row.data['id']?.toString() ?? '';
            final before = row.data['posted_snapshot_json']?.toString() ?? '';
            final after = compactSnapshotJson(before);
            if (id.isEmpty || after == before) continue;
            await db.customUpdate(
              'UPDATE $table SET posted_snapshot_json = ? WHERE id = ?',
              variables: <Variable<Object>>[
                Variable<String>(after),
                Variable<String>(id),
              ],
            );
            rowsChanged += 1;
            bytesRemoved += before.length - after.length;
          }
        }

        final creditRows = await db.customSelect(
          "SELECT value FROM settings WHERE key = 'credit_notes_v1' LIMIT 1",
        ).get();
        if (creditRows.isNotEmpty) {
          final before = creditRows.first.data['value']?.toString() ?? '';
          final after = compactCreditNotesJson(before);
          if (after != before) {
            final now = DateTime.now().toUtc().toIso8601String();
            await db.customUpdate(
              "UPDATE settings SET value = ?, updated_at = ? WHERE key = 'credit_notes_v1'",
              variables: <Variable<Object>>[
                Variable<String>(after),
                Variable<String>(now),
              ],
            );
            await db.customUpdate(
              "UPDATE local_key_values SET value = ?, updated_at = ? WHERE key = 'credit_notes_v1'",
              variables: <Variable<Object>>[
                Variable<String>(after),
                Variable<String>(now),
              ],
            );
            rowsChanged += 1;
            bytesRemoved += (before.length - after.length) * 2;
          }
        }

        final normalizedProfile = _storeProfile.copyWith(
          logoAssetId: currentLogoAssetId,
          historicalLogoAssetsBase64: historicalAssets,
        );
        final beforeProfileJson = jsonEncode(_storeProfile.toJson());
        final afterProfileJson = jsonEncode(normalizedProfile.toJson());
        if (afterProfileJson != beforeProfileJson) {
          final now = DateTime.now().toUtc().toIso8601String();
          await db.customInsert(
            'INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, ?)',
            variables: <Variable<Object>>[
              Variable<String>(AppStore._storeProfileKey),
              Variable<String>(afterProfileJson),
              Variable<String>(now),
            ],
          );
          await db.customInsert(
            'INSERT OR REPLACE INTO local_key_values (key, value, updated_at) VALUES (?, ?, ?)',
            variables: <Variable<Object>>[
              Variable<String>(AppStore._storeProfileKey),
              Variable<String>(afterProfileJson),
              Variable<String>(now),
            ],
          );
          _storeProfile = normalizedProfile;
          storeProfileUpdated = true;
        }
      });

      if (storeProfileUpdated) {
        // Keep LocalDatabaseService's SQLite mirror aligned with the direct
        // transactional update above. The persisted value is identical.
        await LocalDatabaseService.setString(
          AppStore._storeProfileKey,
          jsonEncode(_storeProfile.toJson()),
        );
      }

      if (rowsChanged > 0) {
        debugPrint(
          'Logo asset compaction migrated $rowsChanged row(s), removed approximately $bytesRemoved JSON character(s).',
        );
        if (bytesRemoved > 1024 * 1024) {
          try {
            await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
            await db.customStatement('VACUUM');
          } catch (error) {
            debugPrint('Logo compaction VACUUM deferred: $error');
          }
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Posted logo asset compaction skipped: $error');
      debugPrint('$stackTrace');
    }
  }

Future<void> _backfillPostedDocumentSnapshotsIfNeeded() async {
    if (!LocalDatabaseService.isSqliteAuthoritative) return;
    final db = SqliteMigrationManager.database;
    if (db == null) return;

    await db.transaction(() async {
      for (var index = 0; index < _sales.length; index += 1) {
        final sale = _sales[index];
        if (sale.isDeleted || sale.postedSnapshot != null) continue;
        Customer? customer;
        for (final candidate in _customers) {
          if (candidate.id == sale.customerId && !candidate.isDeleted) {
            customer = candidate;
            break;
          }
        }
        final snapshot = PostedDocumentSnapshotService.forSale(
          sale: sale,
          profile: _storeProfile,
          customer: customer,
          legacyBackfill: true,
        );
        final backfilledSale = sale.copyWith(postedSnapshot: snapshot);
        final updated = await db.customUpdate(
          "UPDATE sales SET posted_snapshot_json = ? WHERE id = ? AND posted_snapshot_json = ''",
          variables: <Variable<Object>>[
            Variable<String>(jsonEncode(snapshot.toJson())),
            Variable<String>(sale.id),
          ],
        );
        if (updated > 0) {
          _sales[index] = backfilledSale;
        }
      }

      for (var index = 0; index < _purchases.length; index += 1) {
        final purchase = _purchases[index];
        if (purchase.isDeleted || purchase.isDraft || purchase.postedSnapshot != null) {
          continue;
        }
        Supplier? supplier;
        for (final candidate in _suppliers) {
          if (candidate.id == purchase.supplierId && !candidate.isDeleted) {
            supplier = candidate;
            break;
          }
        }
        final snapshot = PostedDocumentSnapshotService.forPurchase(
          purchase: purchase,
          profile: _storeProfile,
          supplier: supplier,
          legacyBackfill: true,
        );
        final backfilledPurchase =
            purchase.copyWith(postedSnapshot: snapshot);
        final updated = await db.customUpdate(
          "UPDATE purchases SET posted_snapshot_json = ? WHERE id = ? AND posted_snapshot_json = ''",
          variables: <Variable<Object>>[
            Variable<String>(jsonEncode(snapshot.toJson())),
            Variable<String>(purchase.id),
          ],
        );
        if (updated > 0) {
          _purchases[index] = backfilledPurchase;
        }
      }
    });
}
}
