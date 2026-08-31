import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/security/audit_integrity.dart';

import 'helpers/app_store_source.dart';

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start marker: $start');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end marker: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  group('Phase 4 encrypted backup and secret protection contracts', () {
    test('manual and automatic backups use encrypted export paths', () {
      final settings = _source('lib/features/settings/settings_page_backup.dart');
      final localAuto = _source('lib/core/services/local_auto_backup_service_io.dart');
      final google = _source('lib/core/services/google_drive_backup_service.dart');

      expect(settings, contains('store.exportEncryptedBackupJson(password)'));
      expect(settings, contains('store.decryptBackupJson(rawJson, recoveryKey)'));
      expect(localAuto, contains('store.exportEncryptedBackupJson(recoverySecret)'));
      expect(google, contains('store.exportEncryptedBackupJson(recoverySecret)'));
      expect(localAuto, contains("'cipher': 'aes-256-gcm'"));
      expect(google, contains("'cipher': 'aes-256-gcm'"));
    });

    test('device-bound auth and cloud secrets use secure storage', () {
      final localDb = _source('lib/core/services/local_database_service.dart');
      final accountAuth = _source('lib/core/services/account_auth_service.dart');
      final drive = _source('lib/core/services/google_drive_backup_service.dart');

      expect(localDb, contains('static Future<void> initializeSecureStorage()'));
      expect(localDb, contains("'account_auth_admin_token_v1'"));
      expect(localDb, contains("'google_drive_backup_client_secret_v1'"));
      expect(accountAuth, contains('LocalDatabaseService.setSecureString('));
      expect(accountAuth, contains('static Future<void> migrateLegacySecrets()'));
      expect(drive, contains('LocalDatabaseService.setSecureString('));
      expect(drive, contains('_readSecretWithLegacyMigration'));

      final authJson = _between(
        accountAuth,
        'Map<String, dynamic> toJson() => {',
        'static AccountAuthCache? load()',
      );
      expect(authJson, isNot(contains("'adminToken'")));
      expect(authJson, isNot(contains("'accountToken'")));
      expect(authJson, isNot(contains("'refreshToken'")));
    });

    test('backup payload excludes device secrets from scalar snapshot', () {
      final recovery = _source('lib/data/app_store_backup_recovery.dart');
      expect(recovery, contains('Map<String, String> _backupSafeLocalDatabaseEntries()'));
      expect(recovery, contains("'secretPolicy': 'device-secrets-excluded-v1'"));
      expect(recovery, contains("'localDatabaseEntries': _backupSafeLocalDatabaseEntries()"));
      expect(recovery, contains("'google_drive_backup_access_token_v1'"));
      expect(recovery, contains("'account_auth_refresh_token_v1'"));
    });
  });

  group('Phase 5 authentication and sensitive action contracts', () {
    test('domain re-authentication guard is exposed and action-scoped', () {
      final appStore = readAppStoreImplementationSource();
      final access = _source('lib/data/app_store_access_auth.dart');

      expect(appStore, contains('Future<bool> authorizeSensitiveAction({'));
      expect(appStore, contains('void requireSensitiveActionAuthorization(String action)'));
      expect(access, contains("static const String backupRestore = 'backup.restore';"));
      expect(access, contains("static const String saleReverse = 'sales.reverse';"));
      expect(access, contains("static const String purchaseReverse = 'purchases.reverse';"));
      expect(access, contains("static const String databaseDestructive = 'database.destructive';"));
      expect(access, contains('Duration validity = const Duration(minutes: 3)'));
      expect(access, contains('_sensitiveAuthorizationActions.contains(action)'));
    });

    test('high-risk domain mutations require recent authorization', () {
      final restore = _source('lib/data/app_store_backup_recovery.dart');
      final identity = _source('lib/data/app_store_identity_users.dart');
      final sales = _source('lib/data/app_store_sales_returns.dart');
      final purchases = _source('lib/data/app_store_purchases.dart');
      final persistence = _source('lib/data/app_store_persistence_sync_core.dart');

      expect(restore, contains('requireSensitiveActionAuthorization(SensitiveAction.backupRestore);'));
      expect(identity, contains('requireSensitiveActionAuthorization(SensitiveAction.rolesManage);'));
      expect(identity, contains('requireSensitiveActionAuthorization(SensitiveAction.usersManage);'));
      expect(identity, contains('requireSensitiveActionAuthorization(SensitiveAction.storeOwnerCredentials);'));
      expect(sales, contains('requireSensitiveActionAuthorization(SensitiveAction.saleReverse);'));
      expect(purchases, contains('requireSensitiveActionAuthorization(SensitiveAction.purchaseReverse);'));
      expect(persistence, contains('requireSensitiveActionAuthorization(SensitiveAction.databaseDestructive);'));
    });

    test('login throttling and stronger local password floor are present', () {
      final identity = _source('lib/data/app_store_identity_users.dart');
      final appStore = readAppStoreImplementationSource();

      expect(identity, contains('void _registerLoginFailure('));
      expect(identity, contains('const Duration(minutes: 5)'));
      expect(identity, contains('const Duration(seconds: 30)'));
      expect(identity, contains('password.trim().length < 6'));
      expect(appStore, contains("final Map<String, DateTime> _loginBlockedUntil"));
    });

    test('database mutation UI requires domain re-auth and protects audit table', () {
      final page = _source('lib/features/database/database_page.dart');
      final sql = _source('lib/core/services/database_sql_editor_service.dart');

      expect(page, contains('SensitiveAction.databaseDestructive'));
      expect(page, contains('_ensureDatabaseMutationAuthorization()'));
      expect(page, contains('_auditDatabaseMutation'));
      expect(sql, contains("audit_logs is append-only and cannot be modified from the SQL editor."));
    });
  });

  group('Phase 6 append-only audit contracts', () {
    test('SQLite schema seals audit rows and blocks update/delete', () {
      final db = _source('lib/core/storage/sqlite/ventio_drift_database.dart');
      expect(db, contains('int get schemaVersion => 31;'));
      expect(db, contains("previous_hash TEXT NOT NULL DEFAULT ''"));
      expect(db, contains("record_hash TEXT NOT NULL DEFAULT ''"));
      expect(db, contains('hash_version INTEGER NOT NULL DEFAULT 1'));
      expect(db, contains('CREATE TRIGGER IF NOT EXISTS trg_audit_logs_no_update'));
      expect(db, contains('CREATE TRIGGER IF NOT EXISTS trg_audit_logs_no_delete'));
      expect(db, contains("RAISE(ABORT, 'audit_logs are append-only')"));
    });

    test('audit logger chains records and supports integrity verification', () {
      final logging = _source('lib/core/services/app_logging_service.dart');
      final auditBlock = logging.substring(logging.indexOf('class AuditLogger'));

      expect(auditBlock, contains('static Future<AuditIntegrityResult> verifyIntegrity()'));
      expect(auditBlock, contains('SELECT record_hash FROM audit_logs ORDER BY rowid DESC LIMIT 1'));
      expect(auditBlock, contains('computeAuditRecordHash('));
      expect(auditBlock, contains('Audit logs are append-only and cannot be deleted.'));
    });

    test('general reset preserves audit rows and diagnostics verifies them', () {
      final localDb = _source('lib/core/services/local_database_service.dart');
      final clearAll = _between(
        localDb,
        'static Future<void> clearAll() async {',
        'static Future<void> flushPendingWrites()',
      );
      final diagnostics = _source('lib/features/maintenance/diagnostics_page.dart');

      expect(clearAll, isNot(contains('DELETE FROM audit_logs')));
      expect(diagnostics, contains('AuditLogger.verifyIntegrity()'));
      expect(diagnostics, contains("tr.text('verify_audit_integrity')"));
      expect(diagnostics, isNot(contains('AuditLogger.deleteAll()')));
    });

    test('audit hash is deterministic and tamper-sensitive', () {
      final base = computeAuditRecordHash(
        previousHash: '',
        id: 'audit-1',
        createdAt: '2026-08-31T00:00:00.000Z',
        entityType: 'sale',
        entityId: 'S-1',
        action: 'cancel',
        fieldName: '',
        summary: 'Sale cancelled',
        details: 'reason=test',
        userId: 'U-1',
        userName: 'admin',
        storeId: 'STORE-1',
        branchId: 'BR-1',
        sessionId: 'SESSION-1',
        traceId: 'TRACE-1',
        deviceId: 'DV-1',
        sourceModule: 'sales',
        oldValue: '{}',
        newValue: '{}',
        isImportant: true,
        hashVersion: 1,
      );
      final same = computeAuditRecordHash(
        previousHash: '',
        id: 'audit-1',
        createdAt: '2026-08-31T00:00:00.000Z',
        entityType: 'sale',
        entityId: 'S-1',
        action: 'cancel',
        fieldName: '',
        summary: 'Sale cancelled',
        details: 'reason=test',
        userId: 'U-1',
        userName: 'admin',
        storeId: 'STORE-1',
        branchId: 'BR-1',
        sessionId: 'SESSION-1',
        traceId: 'TRACE-1',
        deviceId: 'DV-1',
        sourceModule: 'sales',
        oldValue: '{}',
        newValue: '{}',
        isImportant: true,
        hashVersion: 1,
      );
      final changed = computeAuditRecordHash(
        previousHash: '',
        id: 'audit-1',
        createdAt: '2026-08-31T00:00:00.000Z',
        entityType: 'sale',
        entityId: 'S-1',
        action: 'cancel',
        fieldName: '',
        summary: 'Sale cancelled',
        details: 'reason=changed',
        userId: 'U-1',
        userName: 'admin',
        storeId: 'STORE-1',
        branchId: 'BR-1',
        sessionId: 'SESSION-1',
        traceId: 'TRACE-1',
        deviceId: 'DV-1',
        sourceModule: 'sales',
        oldValue: '{}',
        newValue: '{}',
        isImportant: true,
        hashVersion: 1,
      );

      expect(same, base);
      expect(changed, isNot(base));
      expect(base, hasLength(64));
    });
  });
}
