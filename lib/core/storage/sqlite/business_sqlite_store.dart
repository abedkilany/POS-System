import 'dart:convert';

import 'package:drift/drift.dart';

import 'sync_sqlite_store.dart';
import 'ventio_drift_database.dart';

/// SQLite-backed store for Ventio business and settings data.
///
/// Phase 3B stores the main business entities in dedicated SQLite tables
/// instead of keeping everything as one generic JSON key/value table. The
/// public LocalDatabaseService API is intentionally kept stable so the rest of
/// the app can continue using the existing model serializers while the local
/// persistence layer becomes SQLite/Drift authoritative.
class BusinessSqliteStore {
  BusinessSqliteStore._();

  static const String phase3MigratedMetaKey = 'sqlite_phase3_business_migrated';
  static const String phase3TypedTablesMetaKey = 'sqlite_phase3_typed_tables_migrated';
  static const String phase3ValidatedMetaKey = 'sqlite_phase3_validation_passed';

  static const String productsKey = 'products_v4';
  static const String customersKey = 'customers_v4';
  static const String salesKey = 'sales_v4';
  static const String suppliersKey = 'suppliers_v4';
  static const String supplierProductPricesKey = 'supplier_product_prices_v1';
  static const String expensesKey = 'expenses_v4';
  static const String purchasesKey = 'purchases_v1';
  static const String stockMovementsKey = 'stock_movements_v1';
  static const String accountTransactionsKey = 'account_transactions_v1';
  static const String categoriesKey = 'product_categories_v1';
  static const String brandsKey = 'product_brands_v1';
  static const String unitsKey = 'product_units_v1';
  static const String rolesKey = 'roles_v1';
  static const String usersKey = 'users_v1';

  static const Set<String> _entityListKeys = <String>{
    productsKey,
    customersKey,
    salesKey,
    suppliersKey,
    supplierProductPricesKey,
    expensesKey,
    purchasesKey,
    stockMovementsKey,
    accountTransactionsKey,
    categoriesKey,
    brandsKey,
    unitsKey,
    rolesKey,
    usersKey,
  };

  static const Map<String, String> _tableByKey = <String, String>{
    productsKey: 'products',
    customersKey: 'customers',
    salesKey: 'sales',
    suppliersKey: 'suppliers',
    supplierProductPricesKey: 'supplier_product_prices',
    expensesKey: 'expenses',
    purchasesKey: 'purchases',
    stockMovementsKey: 'stock_movements',
    accountTransactionsKey: 'account_transactions',
    categoriesKey: 'catalog_categories',
    brandsKey: 'catalog_brands',
    unitsKey: 'catalog_units',
    rolesKey: 'user_roles',
    usersKey: 'app_users',
  };

  static const Map<String, String> _entityTypeByKey = <String, String>{
    productsKey: 'product',
    customersKey: 'customer',
    salesKey: 'sale',
    suppliersKey: 'supplier',
    supplierProductPricesKey: 'supplierProductPrice',
    expensesKey: 'expense',
    purchasesKey: 'purchase',
    stockMovementsKey: 'stockMovement',
    accountTransactionsKey: 'accountTransaction',
    categoriesKey: 'category',
    brandsKey: 'brand',
    unitsKey: 'unit',
    rolesKey: 'role',
    usersKey: 'user',
  };

  static bool isBusinessKey(String key) {
    if (SyncSqliteStore.isSqliteBackedKey(key)) return false;
    if (key.startsWith('sqlite_phase')) return false;
    return true;
  }

  static bool isTypedEntityKey(String key) => _entityListKeys.contains(key);

  static List<String> get adminEntityKeys => List<String>.unmodifiable(_entityListKeys);

  static Future<void> migrateFromHiveIfNeeded(
    VentioDriftDatabase db, {
    required Map<String, String> hiveEntries,
  }) async {
    final typedDone = await _metaValue(db, phase3TypedTablesMetaKey) == 'true';
    if (typedDone) return;

    for (final entry in hiveEntries.entries) {
      if (!isBusinessKey(entry.key)) continue;
      await saveKeyJson(db, entry.key, entry.value);
    }
    await _setMeta(db, phase3MigratedMetaKey, 'true');
    await _setMeta(db, phase3TypedTablesMetaKey, 'true');
  }

  static Future<void> markFreshInstallValidated(VentioDriftDatabase db) async {
    await _setMeta(db, phase3MigratedMetaKey, 'true');
    await _setMeta(db, phase3TypedTablesMetaKey, 'true');
    await _setMeta(db, phase3ValidatedMetaKey, 'true');
  }

  static Future<bool> isValidationPassed(VentioDriftDatabase db) async {
    return await _metaValue(db, phase3ValidatedMetaKey) == 'true';
  }

  static Future<Map<String, String>> hydrateKeyMirror(VentioDriftDatabase db) async {
    final mirror = await hydrateScalarKeyMirror(db);

    for (final entry in _tableByKey.entries) {
      mirror[entry.key] = await _readEntityListJson(db, entry.value);
    }

    return mirror;
  }

  /// Startup-fast mirror hydration.
  ///
  /// Phase 3 used to rebuild JSON strings for every typed table during
  /// LocalDatabaseService.initialize(), then AppStore decoded the same JSON
  /// again immediately after. With large datasets this made app launch pay for
  /// products/sales/stock/accounting even before the user opened a page.
  ///
  /// Keep only scalar/settings keys in the startup mirror. Typed entity lists
  /// are loaded by AppStore in two stages: small catalog/login-critical lists
  /// during initialize(), and large transactional lists shortly after startup.
  static Future<Map<String, String>> hydrateScalarKeyMirror(VentioDriftDatabase db) async {
    final rows = await db.customSelect('''
      SELECT key, value
      FROM local_key_values
      ORDER BY key ASC
    ''').get();
    final mirror = <String, String>{
      for (final row in rows) row.read<String>('key'): row.read<String>('value'),
    };

    for (final key in _entityListKeys) {
      mirror.remove(key);
    }

    // These lists are small and needed for login/catalog initialization. Keep
    // them available synchronously to AppStore without loading transactional
    // tables such as sales, purchases, stock movements, and accounting ledger.
    for (final key in <String>{categoriesKey, brandsKey, unitsKey, rolesKey, usersKey}) {
      final table = _tableByKey[key];
      if (table != null) mirror[key] = await _readEntityListJson(db, table);
    }

    final settingsRows = await db.customSelect('''
      SELECT key, value
      FROM settings
      ORDER BY key ASC
    ''').get();
    for (final row in settingsRows) {
      mirror[row.read<String>('key')] = row.read<String>('value');
    }
    return mirror;
  }

  static Future<String?> readEntityListJsonByKey(VentioDriftDatabase db, String key) async {
    final table = _tableByKey[key];
    if (table == null) return null;
    return _readEntityListJson(db, table);
  }

  static Future<void> saveKeyJson(VentioDriftDatabase db, String key, String value) async {
    if (isTypedEntityKey(key)) {
      // Performance fix: normal app saves must be incremental. The old Phase 3B
      // compatibility path deleted the whole entity table and re-inserted every
      // row on every product/customer/sale change, which preserved Hive's slow
      // "rewrite the whole list" behavior inside SQLite. Keep local_key_values
      // out of the hot path as well; hydrateKeyMirror rebuilds the JSON mirror
      // from the typed tables on startup.
      await _mergeEntityList(db, key, value);
      return;
    }

    // Settings and scalar app state get their own typed table. local_key_values
    // remains as a compatibility mirror for older diagnostics/exports.
    await db.customInsert(
      '''
      INSERT OR REPLACE INTO settings (key, value, updated_at)
      VALUES (?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(key),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
    await _saveLocalMirrorValue(db, key, value);
  }



  static Future<void> upsertEntityPayload(
    VentioDriftDatabase db,
    String key,
    Map<String, dynamic> payload, {
    int? sortIndex,
  }) async {
    final table = _tableByKey[key];
    final entityType = _entityTypeByKey[key];
    if (table == null || entityType == null) {
      throw ArgumentError('Key $key is not a typed SQLite entity key.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final id = (payload['id']?.toString().isNotEmpty ?? false) ? payload['id'].toString() : '${entityType}_${now.hashCode}';
    final payloadJson = jsonEncode(payload);
    final createdAt = _dateString(payload['createdAt']) ?? _dateString(payload['date']) ?? now;
    final updatedAt = _dateString(payload['updatedAt']) ?? createdAt;
    final deletedAt = _dateString(payload['deletedAt']) ?? '';
    await db.customInsert(
      """
      INSERT OR REPLACE INTO $table
        (id, entity_type, payload_json, created_at, updated_at, deleted_at, device_id, sync_status, store_id, branch_id, version, sort_index)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      variables: <Variable<Object>>[
        Variable<String>(id),
        Variable<String>(entityType),
        Variable<String>(payloadJson),
        Variable<String>(createdAt),
        Variable<String>(updatedAt),
        Variable<String>(deletedAt),
        Variable<String>(payload['deviceId']?.toString() ?? ''),
        Variable<String>(payload['syncStatus']?.toString() ?? ''),
        Variable<String>(payload['storeId']?.toString() ?? ''),
        Variable<String>(payload['branchId']?.toString() ?? ''),
        Variable<int>(_intValue(payload['version'], fallback: 1)),
        Variable<int>(sortIndex ?? 0),
      ],
    );
  }

  static Future<void> deleteKey(VentioDriftDatabase db, String key) async {
    final table = _tableByKey[key];
    if (table != null) {
      await db.customStatement('DELETE FROM $table;');
      await db.customStatement('DELETE FROM local_key_values WHERE key = ?;', <Object?>[key]);
      return;
    }
    await db.customStatement('DELETE FROM settings WHERE key = ?;', <Object?>[key]);
    await db.customStatement('DELETE FROM local_key_values WHERE key = ?;', <Object?>[key]);
  }

  static Future<void> clear(VentioDriftDatabase db) async {
    for (final table in _tableByKey.values) {
      await db.customStatement('DELETE FROM $table;');
    }
    await db.customStatement('DELETE FROM settings;');
    await db.customStatement('DELETE FROM local_key_values;');
  }

  static Future<BusinessSqliteValidationResult> validateAgainstHive(
    VentioDriftDatabase db, {
    required Map<String, String> hiveEntries,
  }) async {
    final problems = <String>[];
    for (final key in _entityListKeys) {
      final hiveCount = _jsonListLength(hiveEntries[key]);
      final sqliteCount = await _entityCount(db, _tableByKey[key]!);
      if (hiveEntries.containsKey(key) && hiveCount != sqliteCount) {
        problems.add('$key hive=$hiveCount sqlite=$sqliteCount');
      }
    }

    if (problems.isEmpty) {
      await _setMeta(db, phase3ValidatedMetaKey, 'true');
      return const BusinessSqliteValidationResult(ok: true, message: 'Business entity counts match Hive source data.');
    }

    await _setMeta(db, phase3ValidatedMetaKey, 'false');
    return BusinessSqliteValidationResult(ok: false, message: problems.join('; '));
  }

  static Future<void> _mergeEntityList(VentioDriftDatabase db, String key, String jsonText) async {
    final table = _tableByKey[key]!;
    final entityType = _entityTypeByKey[key]!;
    final now = DateTime.now().toUtc().toIso8601String();
    final decoded = jsonDecode(jsonText);
    if (decoded is! List) {
      throw FormatException('Expected a JSON list for $key');
    }

    final existingRows = await db.customSelect('SELECT id, payload_json, sort_index FROM $table').get();
    final existingPayloadById = <String, String>{
      for (final row in existingRows) row.read<String>('id'): row.read<String>('payload_json'),
    };
    final existingSortById = <String, int>{
      for (final row in existingRows) row.read<String>('id'): row.read<int>('sort_index'),
    };
    final seenIds = <String>{};

    await db.transaction(() async {
      for (var index = 0; index < decoded.length; index += 1) {
        final raw = decoded[index];
        if (raw is! Map) continue;
        final payload = Map<String, dynamic>.from(raw);
        final id = (payload['id']?.toString().isNotEmpty ?? false) ? payload['id'].toString() : '${entityType}_$index';
        seenIds.add(id);
        final payloadJson = jsonEncode(payload);
        if (existingPayloadById[id] == payloadJson && existingSortById[id] == index) {
          continue;
        }
        final createdAt = _dateString(payload['createdAt']) ?? _dateString(payload['date']) ?? now;
        final updatedAt = _dateString(payload['updatedAt']) ?? createdAt;
        final deletedAt = _dateString(payload['deletedAt']) ?? '';
        await db.customInsert(
          '''
          INSERT OR REPLACE INTO $table
            (id, entity_type, payload_json, created_at, updated_at, deleted_at, device_id, sync_status, store_id, branch_id, version, sort_index)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          variables: <Variable<Object>>[
            Variable<String>(id),
            Variable<String>(entityType),
            Variable<String>(payloadJson),
            Variable<String>(createdAt),
            Variable<String>(updatedAt),
            Variable<String>(deletedAt),
            Variable<String>(payload['deviceId']?.toString() ?? ''),
            Variable<String>(payload['syncStatus']?.toString() ?? ''),
            Variable<String>(payload['storeId']?.toString() ?? ''),
            Variable<String>(payload['branchId']?.toString() ?? ''),
            Variable<int>(_intValue(payload['version'], fallback: 1)),
            Variable<int>(index),
          ],
        );
      }

      final staleIds = existingPayloadById.keys.where((id) => !seenIds.contains(id)).toList(growable: false);
      for (final id in staleIds) {
        await db.customStatement('DELETE FROM $table WHERE id = ?;', <Object?>[id]);
      }
    });
  }

  static Future<String> _readEntityListJson(VentioDriftDatabase db, String table) async {
    final rows = await db.customSelect('''
      SELECT payload_json
      FROM $table
      ORDER BY sort_index ASC, updated_at ASC, id ASC
    ''').get();
    final payloads = <dynamic>[];
    for (final row in rows) {
      final text = row.read<String>('payload_json');
      try {
        payloads.add(jsonDecode(text));
      } catch (_) {
        // Skip corrupt rows instead of breaking app startup; validation will
        // catch count mismatches before Hive can be retired.
      }
    }
    return jsonEncode(payloads);
  }

  static Future<int> _entityCount(VentioDriftDatabase db, String table) async {
    final rows = await db.customSelect('SELECT COUNT(*) AS c FROM $table').get();
    return rows.first.read<int>('c');
  }

  static int _jsonListLength(String? jsonText) {
    if (jsonText == null || jsonText.isEmpty) return 0;
    try {
      final decoded = jsonDecode(jsonText);
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  static int _intValue(Object? value, {required int fallback}) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static String? _dateString(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static Future<void> _saveLocalMirrorValue(VentioDriftDatabase db, String key, String value) async {
    await db.customInsert(
      '''
      INSERT OR REPLACE INTO local_key_values (key, value, updated_at)
      VALUES (?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(key),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }

  static Future<String?> _metaValue(VentioDriftDatabase db, String key) async {
    final rows = await db.customSelect(
      'SELECT value FROM migration_meta WHERE key = ?',
      variables: <Variable<Object>>[Variable<String>(key)],
    ).get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  static Future<void> _setMeta(VentioDriftDatabase db, String key, String value) async {
    await db.customInsert(
      'INSERT OR REPLACE INTO migration_meta (key, value, updated_at) VALUES (?, ?, ?)',
      variables: <Variable<Object>>[
        Variable<String>(key),
        Variable<String>(value),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }
}

class BusinessSqliteValidationResult {
  const BusinessSqliteValidationResult({required this.ok, required this.message});
  final bool ok;
  final String message;
}
