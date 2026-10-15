part of 'app_logging_service.dart';

class AuditLogger {
  AuditLogger._();

  static const int defaultLimit = 200;
  static final List<_PendingAuditLog> _pending = <_PendingAuditLog>[];
  static Future<void>? _flushInFlight;

  static Future<void> record({
    required String entityType,
    required String entityId,
    required String action,
    required String summary,
    String fieldName = '',
    String oldValue = '',
    String newValue = '',
    String details = '',
    String userId = '',
    String userName = '',
    String storeId = '',
    String branchId = '',
    String sessionId = '',
    String traceId = '',
    String deviceId = '',
    String sourceModule = '',
    bool isImportant = true,
  }) async {
    final item = _PendingAuditLog(
      id: _id('audit'),
      createdAt: DateTime.now().toUtc(),
      entityType: entityType.trim().isEmpty ? 'general' : entityType.trim(),
      entityId: entityId,
      action: action.trim().isEmpty ? 'update' : action.trim(),
      fieldName: fieldName,
      oldValue: oldValue,
      newValue: newValue,
      summary: summary,
      details: details,
      userId: userId,
      userName: userName,
      storeId: storeId,
      branchId: branchId,
      sessionId: sessionId,
      traceId: traceId,
      deviceId: deviceId,
      sourceModule: sourceModule,
      isImportant: isImportant,
    );
    _pending.add(item);
    await flushPending();
  }

  static Future<void> flushPending() {
    return _flushInFlight ??= _flushPendingInternal().whenComplete(() {
      _flushInFlight = null;
    });
  }

  static Future<void> _flushPendingInternal() async {
    final db = SqliteMigrationManager.database;
    if (db == null) return;
    while (_pending.isNotEmpty) {
      final item = _pending.first;
      // Read the chain tip and append in the same transaction. Failed writes
      // remain queued and propagate to callers instead of reporting success.
      await db.transaction(() => _insertAuditLog(db, item));
      _pending.removeAt(0);
    }
  }

  static Future<List<AuditLogRecord>> fetch({
    AuditLogQuery query = const AuditLogQuery(),
  }) async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) return const <AuditLogRecord>[];
    final where = <String>[];
    final args = <Object?>[];
    if (query.entityType != null && query.entityType!.trim().isNotEmpty) {
      where.add('entity_type = ?');
      args.add(query.entityType!.trim());
    }
    if (query.search.trim().isNotEmpty) {
      where.add('(summary LIKE ? OR details LIKE ? OR action LIKE ?)');
      final value = '%${query.search.trim()}%';
      args.addAll(<Object?>[value, value, value]);
    }
    final sql = StringBuffer('SELECT * FROM audit_logs');
    if (where.isNotEmpty) {
      sql.write(' WHERE ');
      sql.write(where.join(' AND '));
    }
    sql.write(' ORDER BY created_at DESC LIMIT ?');
    args.add(query.limit <= 0 ? defaultLimit : query.limit);
    final rows = await db
        .customSelect(sql.toString(),
            variables: args.map((item) => Variable<Object>(item)).toList())
        .get();
    return rows
        .map((row) => AuditLogRecord.fromMap(row.data))
        .toList(growable: false);
  }

  static Future<int> cleanup({
    Duration retention = const Duration(days: 36500),
  }) async {
    await flushPending();
    // Phase 6 audit records have no retention-based deletion path.
    return 0;
  }

  static Future<int> deleteAll() async {
    throw StateError('Audit logs are append-only and cannot be deleted.');
  }

  static Future<AuditIntegrityResult> verifyIntegrity() async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) {
      return const AuditIntegrityResult(
        ok: true,
        checkedRows: 0,
        message: 'Audit database is not initialized.',
      );
    }
    final rows = await db
        .customSelect(
          'SELECT * FROM audit_logs ORDER BY rowid ASC',
        )
        .get();
    var previousHash = '';
    var checked = 0;
    for (final row in rows) {
      final data = row.data;
      final actualPrevious = data['previous_hash']?.toString() ?? '';
      final actualHash = data['record_hash']?.toString() ?? '';
      final expectedHash = computeAuditRecordHashFromRow(
        data,
        previousHash: previousHash,
      );
      checked += 1;
      if (actualPrevious != previousHash ||
          actualHash.isEmpty ||
          actualHash != expectedHash) {
        return AuditIntegrityResult(
          ok: false,
          checkedRows: checked,
          firstInvalidId: data['id']?.toString() ?? '',
          message: 'Audit hash chain verification failed.',
        );
      }
      previousHash = actualHash;
    }
    return AuditIntegrityResult(
      ok: true,
      checkedRows: checked,
      message: 'Audit hash chain is valid.',
    );
  }

  static Future<Map<String, int>> counts() async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) return const <String, int>{'auditLogs': 0};
    final row = await db
        .customSelect('SELECT COUNT(*) AS row_count FROM audit_logs')
        .getSingle();
    return <String, int>{'auditLogs': row.read<int>('row_count')};
  }

  static Future<void> _insertAuditLog(
      VentioDriftDatabase db, _PendingAuditLog item) async {
    final previousRows = await db
        .customSelect(
          'SELECT record_hash FROM audit_logs ORDER BY rowid DESC LIMIT 1',
        )
        .get();
    final previousHash = previousRows.isEmpty
        ? ''
        : (previousRows.first.data['record_hash']?.toString() ?? '');
    if (previousRows.isNotEmpty && previousHash.isEmpty) {
      throw StateError(
        'Audit integrity failure: previous record is missing its hash.',
      );
    }
    final createdAt = item.createdAt.toIso8601String();
    final recordHash = computeAuditRecordHash(
      previousHash: previousHash,
      id: item.id,
      createdAt: createdAt,
      entityType: item.entityType,
      entityId: item.entityId,
      action: item.action,
      fieldName: item.fieldName,
      oldValue: item.oldValue,
      newValue: item.newValue,
      summary: item.summary,
      details: item.details,
      userId: item.userId,
      userName: item.userName,
      storeId: item.storeId,
      branchId: item.branchId,
      sessionId: item.sessionId,
      traceId: item.traceId,
      deviceId: item.deviceId,
      sourceModule: item.sourceModule,
      isImportant: item.isImportant,
    );
    await db.customInsert(
      '''
      INSERT INTO audit_logs (
        id, created_at, entity_type, entity_id, action, field_name, old_value,
        new_value, summary, details, user_id, user_name, store_id, branch_id,
        session_id, trace_id, device_id, source_module, is_important,
        previous_hash, record_hash, hash_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(item.id),
        Variable<String>(createdAt),
        Variable<String>(item.entityType),
        Variable<String>(item.entityId),
        Variable<String>(item.action),
        Variable<String>(item.fieldName),
        Variable<String>(item.oldValue),
        Variable<String>(item.newValue),
        Variable<String>(item.summary),
        Variable<String>(item.details),
        Variable<String>(item.userId),
        Variable<String>(item.userName),
        Variable<String>(item.storeId),
        Variable<String>(item.branchId),
        Variable<String>(item.sessionId),
        Variable<String>(item.traceId),
        Variable<String>(item.deviceId),
        Variable<String>(item.sourceModule),
        Variable<int>(item.isImportant ? 1 : 0),
        Variable<String>(previousHash),
        Variable<String>(recordHash),
      ],
    );
  }
}

class _PendingAppLog {
  const _PendingAppLog({
    required this.id,
    required this.createdAt,
    required this.level,
    required this.area,
    required this.action,
    required this.message,
    required this.details,
    required this.stackTrace,
    required this.userId,
    required this.storeId,
    required this.branchId,
    required this.sessionId,
    required this.traceId,
    required this.devicePlatform,
    required this.deviceModel,
    required this.appVersion,
    required this.osVersion,
    required this.createdBySource,
    required this.isImportant,
  });

  final String id;
  final DateTime createdAt;
  final AppLogLevel level;
  final String area;
  final String action;
  final String message;
  final String details;
  final String stackTrace;
  final String userId;
  final String storeId;
  final String branchId;
  final String sessionId;
  final String traceId;
  final String devicePlatform;
  final String deviceModel;
  final String appVersion;
  final String osVersion;
  final String createdBySource;
  final bool isImportant;
}

class _PendingAuditLog {
  const _PendingAuditLog({
    required this.id,
    required this.createdAt,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.fieldName,
    required this.oldValue,
    required this.newValue,
    required this.summary,
    required this.details,
    required this.userId,
    required this.userName,
    required this.storeId,
    required this.branchId,
    required this.sessionId,
    required this.traceId,
    required this.deviceId,
    required this.sourceModule,
    required this.isImportant,
  });

  final String id;
  final DateTime createdAt;
  final String entityType;
  final String entityId;
  final String action;
  final String fieldName;
  final String oldValue;
  final String newValue;
  final String summary;
  final String details;
  final String userId;
  final String userName;
  final String storeId;
  final String branchId;
  final String sessionId;
  final String traceId;
  final String deviceId;
  final String sourceModule;
  final bool isImportant;
}

String _id(String prefix) =>
    '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_randomSuffix()}';

String _randomSuffix() {
  final value =
      DateTime.now().microsecondsSinceEpoch ^ identityHashCode(Object());
  return value.abs().toRadixString(36);
}

AppLogLevel _parseAppLogLevel(String? value) {
  for (final level in AppLogLevel.values) {
    if (level.name == value) return level;
  }
  return AppLogLevel.info;
}

DateTime? _parseDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return DateTime.tryParse(value);
}
