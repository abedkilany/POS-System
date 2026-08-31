import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Canonical Phase 6 hash for an immutable audit record.
///
/// A positional JSON array is intentionally used instead of a map so field
/// ordering is stable across Dart runtimes and schema readers.
String computeAuditRecordHash({
  required String previousHash,
  required String id,
  required String createdAt,
  required String entityType,
  required String entityId,
  required String action,
  required String fieldName,
  required String oldValue,
  required String newValue,
  required String summary,
  required String details,
  required String userId,
  required String userName,
  required String storeId,
  required String branchId,
  required String sessionId,
  required String traceId,
  required String deviceId,
  required String sourceModule,
  required bool isImportant,
  int hashVersion = 1,
}) {
  final canonical = jsonEncode(<Object?>[
    hashVersion,
    previousHash,
    id,
    createdAt,
    entityType,
    entityId,
    action,
    fieldName,
    oldValue,
    newValue,
    summary,
    details,
    userId,
    userName,
    storeId,
    branchId,
    sessionId,
    traceId,
    deviceId,
    sourceModule,
    isImportant ? 1 : 0,
  ]);
  return sha256.convert(utf8.encode(canonical)).toString();
}

String computeAuditRecordHashFromRow(
  Map<String, Object?> row, {
  required String previousHash,
}) {
  int asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  return computeAuditRecordHash(
    previousHash: previousHash,
    id: row['id']?.toString() ?? '',
    createdAt: row['created_at']?.toString() ?? '',
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
    isImportant: asInt(row['is_important'], 1) == 1,
    hashVersion: asInt(row['hash_version'], 1),
  );
}
