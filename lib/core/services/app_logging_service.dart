import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';

import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';

enum AppLogLevel { debug, info, warning, error, critical }

class AppLogRecord {
  const AppLogRecord({
    required this.id,
    required this.createdAt,
    required this.level,
    required this.area,
    required this.action,
    required this.message,
    required this.details,
    required this.userId,
    required this.storeId,
    required this.branchId,
    required this.sessionId,
    required this.traceId,
    required this.devicePlatform,
    required this.deviceModel,
    required this.appVersion,
    required this.osVersion,
    required this.stackTrace,
    required this.isSynced,
    required this.syncedAt,
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
  final String userId;
  final String storeId;
  final String branchId;
  final String sessionId;
  final String traceId;
  final String devicePlatform;
  final String deviceModel;
  final String appVersion;
  final String osVersion;
  final String stackTrace;
  final bool isSynced;
  final DateTime? syncedAt;
  final String createdBySource;
  final bool isImportant;

  factory AppLogRecord.fromMap(Map<String, Object?> row) {
    return AppLogRecord(
      id: row['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      level: _parseAppLogLevel(row['level']?.toString()),
      area: row['area']?.toString() ?? '',
      action: row['action']?.toString() ?? '',
      message: row['message']?.toString() ?? '',
      details: row['details']?.toString() ?? '',
      userId: row['user_id']?.toString() ?? '',
      storeId: row['store_id']?.toString() ?? '',
      branchId: row['branch_id']?.toString() ?? '',
      sessionId: row['session_id']?.toString() ?? '',
      traceId: row['trace_id']?.toString() ?? '',
      devicePlatform: row['device_platform']?.toString() ?? '',
      deviceModel: row['device_model']?.toString() ?? '',
      appVersion: row['app_version']?.toString() ?? '',
      osVersion: row['os_version']?.toString() ?? '',
      stackTrace: row['stack_trace']?.toString() ?? '',
      isSynced: (row['is_synced'] is int
              ? row['is_synced'] as int
              : int.tryParse(row['is_synced']?.toString() ?? '0') ?? 0) ==
          1,
      syncedAt: _parseDate(row['synced_at']?.toString()),
      createdBySource: row['created_by_source']?.toString() ?? 'app',
      isImportant:
          (int.tryParse(row['is_important']?.toString() ?? '1') ?? 1) == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'level': level.name,
        'area': area,
        'action': action,
        'message': message,
        'details': details,
        'userId': userId,
        'storeId': storeId,
        'branchId': branchId,
        'sessionId': sessionId,
        'traceId': traceId,
        'devicePlatform': devicePlatform,
        'deviceModel': deviceModel,
        'appVersion': appVersion,
        'osVersion': osVersion,
        'stackTrace': stackTrace,
        'isSynced': isSynced,
        'syncedAt': syncedAt?.toIso8601String() ?? '',
        'createdBySource': createdBySource,
        'isImportant': isImportant,
      };
}

class AuditLogRecord {
  const AuditLogRecord({
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

  factory AuditLogRecord.fromMap(Map<String, Object?> row) {
    return AuditLogRecord(
      id: row['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      entityType: row['entity_type']?.toString() ?? '',
      entityId: row['entity_id']?.toString() ?? '',
      action: row['action']?.toString() ?? '',
      fieldName: row['field_name']?.toString() ?? '',
      oldValue: row['old_value']?.toString() ?? '',
      newValue: row['new_value']?.toString() ?? '',
      summary: row['summary']?.toString() ?? '',
      details: row['details']?.toString() ?? '',
      userId: row['user_id']?.toString() ?? '',
      userName: row['user_name']?.toString() ?? '',
      storeId: row['store_id']?.toString() ?? '',
      branchId: row['branch_id']?.toString() ?? '',
      sessionId: row['session_id']?.toString() ?? '',
      traceId: row['trace_id']?.toString() ?? '',
      deviceId: row['device_id']?.toString() ?? '',
      sourceModule: row['source_module']?.toString() ?? '',
      isImportant:
          (int.tryParse(row['is_important']?.toString() ?? '1') ?? 1) == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'entityType': entityType,
        'entityId': entityId,
        'action': action,
        'fieldName': fieldName,
        'oldValue': oldValue,
        'newValue': newValue,
        'summary': summary,
        'details': details,
        'userId': userId,
        'userName': userName,
        'storeId': storeId,
        'branchId': branchId,
        'sessionId': sessionId,
        'traceId': traceId,
        'deviceId': deviceId,
        'sourceModule': sourceModule,
        'isImportant': isImportant,
      };
}

class AppLogQuery {
  const AppLogQuery({
    this.level,
    this.area,
    this.limit = 200,
    this.includeSynced = true,
    this.onlyUnsynced = false,
    this.search = '',
  });

  final AppLogLevel? level;
  final String? area;
  final int limit;
  final bool includeSynced;
  final bool onlyUnsynced;
  final String search;
}

class AuditLogQuery {
  const AuditLogQuery({
    this.entityType,
    this.limit = 200,
    this.search = '',
  });

  final String? entityType;
  final int limit;
  final String search;
}

class AppLogger {
  AppLogger._();

  static const int defaultLimit = 200;
  static final List<_PendingAppLog> _pending = <_PendingAppLog>[];
  static bool _flushInProgress = false;

  static Future<void> debug({
    required String area,
    required String action,
    required String message,
    String details = '',
    String stackTrace = '',
    String userId = '',
    String storeId = '',
    String branchId = '',
    String sessionId = '',
    String traceId = '',
    String devicePlatform = '',
    String deviceModel = '',
    String appVersion = '',
    String osVersion = '',
    String createdBySource = 'app',
    bool isImportant = false,
  }) =>
      log(
        level: AppLogLevel.debug,
        area: area,
        action: action,
        message: message,
        details: details,
        stackTrace: stackTrace,
        userId: userId,
        storeId: storeId,
        branchId: branchId,
        sessionId: sessionId,
        traceId: traceId,
        devicePlatform: devicePlatform,
        deviceModel: deviceModel,
        appVersion: appVersion,
        osVersion: osVersion,
        createdBySource: createdBySource,
        isImportant: isImportant,
      );

  static Future<void> info({
    required String area,
    required String action,
    required String message,
    String details = '',
    String stackTrace = '',
    String userId = '',
    String storeId = '',
    String branchId = '',
    String sessionId = '',
    String traceId = '',
    String devicePlatform = '',
    String deviceModel = '',
    String appVersion = '',
    String osVersion = '',
    String createdBySource = 'app',
    bool isImportant = false,
  }) =>
      log(
        level: AppLogLevel.info,
        area: area,
        action: action,
        message: message,
        details: details,
        stackTrace: stackTrace,
        userId: userId,
        storeId: storeId,
        branchId: branchId,
        sessionId: sessionId,
        traceId: traceId,
        devicePlatform: devicePlatform,
        deviceModel: deviceModel,
        appVersion: appVersion,
        osVersion: osVersion,
        createdBySource: createdBySource,
        isImportant: isImportant,
      );

  static Future<void> warning({
    required String area,
    required String action,
    required String message,
    String details = '',
    String stackTrace = '',
    String userId = '',
    String storeId = '',
    String branchId = '',
    String sessionId = '',
    String traceId = '',
    String devicePlatform = '',
    String deviceModel = '',
    String appVersion = '',
    String osVersion = '',
    String createdBySource = 'app',
    bool isImportant = false,
  }) =>
      log(
        level: AppLogLevel.warning,
        area: area,
        action: action,
        message: message,
        details: details,
        stackTrace: stackTrace,
        userId: userId,
        storeId: storeId,
        branchId: branchId,
        sessionId: sessionId,
        traceId: traceId,
        devicePlatform: devicePlatform,
        deviceModel: deviceModel,
        appVersion: appVersion,
        osVersion: osVersion,
        createdBySource: createdBySource,
        isImportant: isImportant,
      );

  static Future<void> error({
    required String area,
    required String action,
    required String message,
    String details = '',
    String stackTrace = '',
    String userId = '',
    String storeId = '',
    String branchId = '',
    String sessionId = '',
    String traceId = '',
    String devicePlatform = '',
    String deviceModel = '',
    String appVersion = '',
    String osVersion = '',
    String createdBySource = 'app',
    bool isImportant = false,
  }) =>
      log(
        level: AppLogLevel.error,
        area: area,
        action: action,
        message: message,
        details: details,
        stackTrace: stackTrace,
        userId: userId,
        storeId: storeId,
        branchId: branchId,
        sessionId: sessionId,
        traceId: traceId,
        devicePlatform: devicePlatform,
        deviceModel: deviceModel,
        appVersion: appVersion,
        osVersion: osVersion,
        createdBySource: createdBySource,
        isImportant: isImportant,
      );

  static Future<void> critical({
    required String area,
    required String action,
    required String message,
    String details = '',
    String stackTrace = '',
    String userId = '',
    String storeId = '',
    String branchId = '',
    String sessionId = '',
    String traceId = '',
    String devicePlatform = '',
    String deviceModel = '',
    String appVersion = '',
    String osVersion = '',
    String createdBySource = 'app',
    bool isImportant = false,
  }) =>
      log(
        level: AppLogLevel.critical,
        area: area,
        action: action,
        message: message,
        details: details,
        stackTrace: stackTrace,
        userId: userId,
        storeId: storeId,
        branchId: branchId,
        sessionId: sessionId,
        traceId: traceId,
        devicePlatform: devicePlatform,
        deviceModel: deviceModel,
        appVersion: appVersion,
        osVersion: osVersion,
        createdBySource: createdBySource,
        isImportant: isImportant,
      );

  static Future<void> log({
    required AppLogLevel level,
    required String area,
    required String action,
    required String message,
    String details = '',
    String stackTrace = '',
    String userId = '',
    String storeId = '',
    String branchId = '',
    String sessionId = '',
    String traceId = '',
    String devicePlatform = '',
    String deviceModel = '',
    String appVersion = '',
    String osVersion = '',
    String createdBySource = 'app',
    bool isImportant = false,
    bool persist = true,
  }) async {
    final now = DateTime.now().toUtc();
    final payload = _PendingAppLog(
      id: _id('log'),
      createdAt: now,
      level: level,
      area: area.trim().isEmpty ? 'general' : area.trim(),
      action: action.trim().isEmpty ? 'event' : action.trim(),
      message: message.trim().isEmpty ? 'No message provided.' : message.trim(),
      details: details,
      stackTrace: stackTrace,
      userId: userId,
      storeId: storeId,
      branchId: branchId,
      sessionId: sessionId,
      traceId: traceId,
      devicePlatform: devicePlatform.isNotEmpty
          ? devicePlatform
          : (kIsWeb ? 'web' : defaultTargetPlatform.name),
      deviceModel: deviceModel,
      appVersion: appVersion,
      osVersion: osVersion,
      createdBySource: createdBySource,
      isImportant: isImportant,
    );
    if (!persist) {
      return;
    }
    _pending.add(payload);
    await flushPending();
  }

  static Future<void> flushPending() async {
    if (_flushInProgress) return;
    final db = SqliteMigrationManager.database;
    if (db == null) return;
    _flushInProgress = true;
    try {
      while (_pending.isNotEmpty) {
        final item = _pending.first;
        try {
          await _insertAppLog(db, item);
          _pending.removeAt(0);
        } catch (error, stackTrace) {
          debugPrint('AppLogger flush failed: $error\n$stackTrace');
          break;
        }
      }
    } finally {
      _flushInProgress = false;
    }
  }

  static Future<List<AppLogRecord>> fetch({
    AppLogQuery query = const AppLogQuery(),
  }) async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) return const <AppLogRecord>[];
    final where = <String>[];
    final args = <Object?>[];
    if (query.level != null) {
      where.add('level = ?');
      args.add(query.level!.name);
    }
    if (query.area != null && query.area!.trim().isNotEmpty) {
      where.add('area = ?');
      args.add(query.area!.trim());
    }
    if (query.onlyUnsynced) {
      where.add('is_synced = 0');
    } else if (!query.includeSynced) {
      where.add('is_synced = 0');
    }
    if (query.search.trim().isNotEmpty) {
      where.add('(message LIKE ? OR details LIKE ? OR action LIKE ?)');
      final value = '%${query.search.trim()}%';
      args.addAll(<Object?>[value, value, value]);
    }
    final sql = StringBuffer('SELECT * FROM app_logs');
    if (where.isNotEmpty) {
      sql.write(' WHERE ');
      sql.write(where.join(' AND '));
    }
    sql.write(' ORDER BY created_at DESC LIMIT ?');
    args.add(query.limit <= 0 ? defaultLimit : query.limit);
    final rows = await db.customSelect(sql.toString(), variables: args.map((item) => Variable<Object>(item)).toList()).get();
    return rows.map((row) => AppLogRecord.fromMap(row.data)).toList(growable: false);
  }

  static Future<int> cleanup({
    Duration retention = const Duration(days: 14),
  }) async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) return 0;
    final cutoff = DateTime.now().toUtc().subtract(retention).toIso8601String();
    return db.customUpdate(
      'DELETE FROM app_logs WHERE is_important = 0 AND created_at < ?',
      variables: <Variable<Object>>[Variable<String>(cutoff)],
    );
  }

  static Future<int> deleteAll({bool includeImportant = false}) async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) return 0;
    return db.customUpdate(
      includeImportant
          ? 'DELETE FROM app_logs'
          : 'DELETE FROM app_logs WHERE is_important = 0',
    );
  }

  static Future<Map<String, int>> counts() async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) return const <String, int>{'appLogs': 0};
    final appRow =
        await db.customSelect('SELECT COUNT(*) AS row_count FROM app_logs').getSingle();
    final auditRow =
        await db.customSelect('SELECT COUNT(*) AS row_count FROM audit_logs').getSingle();
    return <String, int>{
      'appLogs': appRow.read<int>('row_count'),
      'auditLogs': auditRow.read<int>('row_count'),
    };
  }

  static Future<String> buildDiagnosticReport({
    Map<String, dynamic> maintenanceSummary = const <String, dynamic>{},
    int limit = 200,
  }) async {
    final logs = await fetch(query: AppLogQuery(limit: limit));
    final audits = await AuditLogger.fetch(query: AuditLogQuery(limit: limit));
    return jsonEncode(<String, dynamic>{
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'summary': maintenanceSummary,
      'technicalLogs': logs.map((item) => item.toJson()).toList(),
      'auditLogs': audits.map((item) => item.toJson()).toList(),
    });
  }

  static Future<void> _insertAppLog(
      VentioDriftDatabase db, _PendingAppLog item) async {
    await db.customInsert(
      '''
      INSERT INTO app_logs (
        id, created_at, level, area, action, message, details, user_id,
        store_id, branch_id, session_id, trace_id, device_platform,
        device_model, app_version, os_version, stack_trace, is_synced,
        synced_at, created_by_source, is_important
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, '', ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(item.id),
        Variable<String>(item.createdAt.toIso8601String()),
        Variable<String>(item.level.name),
        Variable<String>(item.area),
        Variable<String>(item.action),
        Variable<String>(item.message),
        Variable<String>(item.details),
        Variable<String>(item.userId),
        Variable<String>(item.storeId),
        Variable<String>(item.branchId),
        Variable<String>(item.sessionId),
        Variable<String>(item.traceId),
        Variable<String>(item.devicePlatform),
        Variable<String>(item.deviceModel),
        Variable<String>(item.appVersion),
        Variable<String>(item.osVersion),
        Variable<String>(item.stackTrace),
        Variable<String>(item.createdBySource),
        Variable<int>(item.isImportant ? 1 : 0),
      ],
    );
  }
}

class AuditLogger {
  AuditLogger._();

  static const int defaultLimit = 200;
  static final List<_PendingAuditLog> _pending = <_PendingAuditLog>[];
  static bool _flushInProgress = false;

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

  static Future<void> flushPending() async {
    if (_flushInProgress) return;
    final db = SqliteMigrationManager.database;
    if (db == null) return;
    _flushInProgress = true;
    try {
      while (_pending.isNotEmpty) {
        final item = _pending.first;
        try {
          await _insertAuditLog(db, item);
          _pending.removeAt(0);
        } catch (error, stackTrace) {
          debugPrint('AuditLogger flush failed: $error\n$stackTrace');
          break;
        }
      }
    } finally {
      _flushInProgress = false;
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
    final rows = await db.customSelect(sql.toString(), variables: args.map((item) => Variable<Object>(item)).toList()).get();
    return rows.map((row) => AuditLogRecord.fromMap(row.data)).toList(growable: false);
  }

  static Future<int> cleanup({
    Duration retention = const Duration(days: 36500),
  }) async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) return 0;
    final cutoff = DateTime.now().toUtc().subtract(retention).toIso8601String();
    return db.customUpdate(
      'DELETE FROM audit_logs WHERE 1 = 0 AND created_at < ?',
      variables: <Variable<Object>>[Variable<String>(cutoff)],
    );
  }

  static Future<int> deleteAll() async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) return 0;
    return db.customUpdate('DELETE FROM audit_logs');
  }

  static Future<Map<String, int>> counts() async {
    await flushPending();
    final db = SqliteMigrationManager.database;
    if (db == null) return const <String, int>{'auditLogs': 0};
    final row =
        await db.customSelect('SELECT COUNT(*) AS row_count FROM audit_logs').getSingle();
    return <String, int>{'auditLogs': row.read<int>('row_count')};
  }

  static Future<void> _insertAuditLog(
      VentioDriftDatabase db, _PendingAuditLog item) async {
    await db.customInsert(
      '''
      INSERT INTO audit_logs (
        id, created_at, entity_type, entity_id, action, field_name, old_value,
        new_value, summary, details, user_id, user_name, store_id, branch_id,
        session_id, trace_id, device_id, source_module, is_important
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(item.id),
        Variable<String>(item.createdAt.toIso8601String()),
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
  final value = DateTime.now().microsecondsSinceEpoch ^ identityHashCode(Object());
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
