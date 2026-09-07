import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ventio/core/security/audit_insert_guard.dart';
import 'package:ventio/core/services/app_logging_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

import '../tool/recover_audit_tail.dart' as recovery;

void main() {
  late Database raw;
  late VentioDriftDatabase db;
  setUp(() async {
    raw = sqlite3.openInMemory();
    db = VentioDriftDatabase(NativeDatabase.opened(raw));
    await db.initializeFoundation();
    SqliteMigrationManager.attachDatabaseOverride(db);
  });
  tearDown(() async {
    await AuditLogger.flushPending();
    await SqliteMigrationManager.shutdown();
  });

  Future<void> append(String id) => AuditLogger.record(
      entityType: 'test', entityId: id, action: 'create', summary: id);

  void unsigned(String id) => raw.execute(
      "INSERT INTO audit_logs (id, created_at, entity_type, entity_id, action, summary) "
      "VALUES (?, '2026-09-07T07:00:00Z', 'test', ?, 'create', 'legacy')", [id, id]);

  test('concurrent callers wait for durable, sequential audit records', () async {
    await Future.wait(List.generate(30, (i) => append('$i')));
    expect(recovery.auditRows(raw), hasLength(30));
    expect((await AuditLogger.verifyIntegrity()).ok, isTrue);
    await db.initializeFoundation();
  });

  test('database rejects unsigned, stale, replacement and mutable writes', () async {
    expect(() => unsigned('old-client'), throwsA(isA<SqliteException>()));
    await append('valid');
    final row = recovery.auditRows(raw).single;
    final fields = row.keys.join(',');
    final placeholders = List.filled(row.length, '?').join(',');
    expect(() => raw.execute('INSERT OR REPLACE INTO audit_logs ($fields) '
        'VALUES ($placeholders)', row.values.toList()), throwsA(isA<SqliteException>()));
    row['id'] = 'stale';
    expect(() => raw.execute('INSERT INTO audit_logs ($fields) VALUES ($placeholders)',
        row.values.toList()), throwsA(isA<SqliteException>()));
    expect(() => raw.execute("UPDATE audit_logs SET summary='changed'"),
        throwsA(isA<SqliteException>()));
    expect(() => raw.execute('DELETE FROM audit_logs'), throwsA(isA<SqliteException>()));
  });

  test('recovery preserves signed prefix and unsigned evidence, then reopens', () async {
    await append('signed');
    final prefix = recovery.auditRows(raw).single;
    raw.execute('DROP TRIGGER trg_audit_logs_validate_insert');
    unsigned('legacy-1');
    unsigned('legacy-2');
    final before = recovery.auditRows(raw);
    await expectLater(db.initializeFoundation(), throwsStateError);
    recovery.recoverTail(raw, backupPath: 'isolated-test.sqlite', backupHash: 'test',
        expectedDigest: recovery.digest(before));
    expect(recovery.auditRows(raw).first, prefix);
    expect(recovery.auditRows(raw), hasLength(4));
    expect(raw.select('SELECT * FROM audit_recovery_originals'), hasLength(2));
    expect(() => raw.execute('DELETE FROM audit_recovery_originals'),
        throwsA(isA<SqliteException>()));
    expect(recovery.validateRecoverableTail(recovery.auditRows(raw)), 0);
    await db.initializeFoundation();
    await append('after-recovery');
    expect((await AuditLogger.verifyIntegrity()).ok, isTrue);
  });

  test('tampered signed history is rejected without resealing', () async {
    await append('signed');
    raw.execute('DROP TRIGGER trg_audit_logs_no_update');
    raw.execute("UPDATE audit_logs SET summary='tampered'");
    final before = recovery.digest(recovery.auditRows(raw));
    expect(() => recovery.recoverTail(raw, backupPath: 'test', backupHash: 'test',
        expectedDigest: before), throwsStateError);
    expect(recovery.digest(recovery.auditRows(raw)), before);
    await expectLater(db.initializeFoundation(), throwsStateError);
  });

  test('a failure halfway through recovery rolls back hashes and protection', () async {
    await append('signed');
    raw.execute('DROP TRIGGER trg_audit_logs_validate_insert');
    unsigned('legacy');
    raw.execute('''CREATE TRIGGER simulate_failure BEFORE INSERT ON audit_logs
      WHEN NEW.entity_type='audit_recovery' BEGIN
      SELECT RAISE(ABORT, 'simulated failure'); END''');
    final before = recovery.digest(recovery.auditRows(raw));
    expect(() => recovery.recoverTail(raw, backupPath: 'test', backupHash: 'test',
        expectedDigest: before), throwsA(isA<SqliteException>()));
    expect(recovery.digest(recovery.auditRows(raw)), before);
    expect(() => raw.execute("UPDATE audit_logs SET summary='changed'"),
        throwsA(isA<SqliteException>()));
    raw.execute(auditInsertGuardSql);
  });
}
