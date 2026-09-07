import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:ventio/core/security/audit_integrity.dart';
import 'package:ventio/core/security/audit_insert_guard.dart';

List<Map<String, Object?>> auditRows(Database db) => db
    .select('SELECT * FROM audit_logs ORDER BY rowid')
    .map((row) => Map<String, Object?>.from(row))
    .toList();

String digest(List<Map<String, Object?>> rows) =>
    sha256.convert(utf8.encode(jsonEncode(rows))).toString();

/// Only an entirely unsigned suffix after a verified prefix is recoverable.
/// Never rewrite an existing hash or accept a gap inside signed history.
int validateRecoverableTail(List<Map<String, Object?>> rows) {
  var previous = '';
  var missing = 0;
  for (final row in rows) {
    final hash = row['record_hash'];
    if (row['hash_version'] != 1) {
      throw StateError('Unsupported audit hash version: ${row['id']}');
    }
    if (hash == '') {
      if (row['previous_hash'] != '') {
        throw StateError('Partially signed row cannot be recovered: ${row['id']}');
      }
      missing++;
    } else {
      if (missing > 0 || row['previous_hash'] != previous ||
          hash != computeAuditRecordHashFromRow(row, previousHash: previous)) {
        throw StateError('Signed audit history is invalid: ${row['id']}');
      }
      previous = hash as String;
    }
  }
  return missing;
}

void recoverTail(Database db, {required String backupPath,
    required String backupHash, required String expectedDigest}) {
  db.execute('BEGIN IMMEDIATE');
  try {
    final rows = auditRows(db);
    if (digest(rows) != expectedDigest) {
      throw StateError('Audit data changed after backup; close Ventio and retry.');
    }
    final count = validateRecoverableTail(rows);
    if (count == 0) {
      db.execute('ROLLBACK');
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute('''CREATE TABLE IF NOT EXISTS audit_recovery_originals (
      id TEXT PRIMARY KEY NOT NULL, recovered_at TEXT NOT NULL,
      original_json TEXT NOT NULL, backup_path TEXT NOT NULL,
      backup_sha256 TEXT NOT NULL
    )''');
    db.execute('DROP TRIGGER IF EXISTS trg_audit_logs_no_update');
    var previous = '';
    final recoveredIds = <String>[];
    for (final row in rows) {
      if (row['record_hash'] == '') {
        db.execute('INSERT INTO audit_recovery_originals VALUES (?, ?, ?, ?, ?)',
            [row['id'], now, jsonEncode(row), backupPath, backupHash]);
        final hash = computeAuditRecordHashFromRow(row, previousHash: previous);
        db.execute('UPDATE audit_logs SET previous_hash = ?, record_hash = ? WHERE id = ?',
            [previous, hash, row['id']]);
        previous = hash;
        recoveredIds.add(row['id'] as String);
      } else {
        previous = row['record_hash'] as String;
      }
    }
    db.execute('''CREATE TRIGGER trg_audit_logs_no_update
      BEFORE UPDATE ON audit_logs BEGIN
      SELECT RAISE(ABORT, 'audit_logs are append-only'); END''');
    db.execute('''CREATE TRIGGER IF NOT EXISTS trg_audit_logs_no_delete
      BEFORE DELETE ON audit_logs BEGIN
      SELECT RAISE(ABORT, 'audit_logs are append-only'); END''');
    db.execute(auditInsertGuardSql);
    for (final operation in ['UPDATE', 'DELETE']) {
      db.execute('''CREATE TRIGGER IF NOT EXISTS trg_audit_recovery_no_${operation.toLowerCase()}
        BEFORE $operation ON audit_recovery_originals BEGIN
        SELECT RAISE(ABORT, 'audit recovery evidence is immutable'); END''');
    }
    final marker = <String, Object?>{
      'id': 'audit_recovery_${DateTime.now().microsecondsSinceEpoch}',
      'created_at': now, 'entity_type': 'audit_recovery',
      'entity_id': 'unsigned_tail', 'action': 'seal_unsigned_tail',
      'summary': 'Unsigned audit records sealed during authorized recovery',
      'details': jsonEncode({'count': count, 'ids': recoveredIds,
        'backupPath': backupPath, 'backupSha256': backupHash,
        'provenance': 'Original unsigned rows preserved in audit_recovery_originals. '
            'New hashes attest to content at recovery time, not original authenticity.'}),
      'source_module': 'authorized_recovery', 'is_important': 1,
      'hash_version': 1, 'previous_hash': previous,
    };
    marker['record_hash'] = computeAuditRecordHashFromRow(marker, previousHash: previous);
    db.execute('INSERT INTO audit_logs (${marker.keys.join(',')}) VALUES '
        '(${List.filled(marker.length, '?').join(',')})', marker.values.toList());
    if (validateRecoverableTail(auditRows(db)) != 0) {
      throw StateError('Post-recovery validation failed.');
    }
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) throw ArgumentError('Usage: dart run tool/recover_audit_tail.dart DATABASE [--apply]');
  final path = File(args.first).absolute.path;
  final source = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    if (source.select('PRAGMA integrity_check').single.values.single != 'ok') {
      throw StateError('SQLite integrity check failed.');
    }
    final rows = auditRows(source);
    final count = validateRecoverableTail(rows);
    stdout.writeln(jsonEncode({'rows': rows.length, 'verifiedPrefix': rows.length-count,
      'unsignedTail': count, 'auditDigest': digest(rows)}));
    final rehearse = args.contains('--rehearse');
    if ((!args.contains('--apply') && !rehearse) || count == 0) return;
    final directory = Directory('${File(path).parent.path}/audit_recovery_backups');
    directory.createSync(recursive: true);
    final backupPath = '${directory.path}/before_recovery_${DateTime.now().microsecondsSinceEpoch}.sqlite';
    final backup = sqlite3.open(backupPath);
    try {
      await source.backup(backup, nPage: 4096).drain<void>();
      if (digest(auditRows(backup)) != digest(rows) ||
          backup.select('PRAGMA integrity_check').single.values.single != 'ok') {
        throw StateError('Backup verification failed.');
      }
    } finally {
      backup.close();
    }
    final backupHash = (await sha256.bind(File(backupPath).openRead()).first).toString();
    final target = rehearse ? '$backupPath.rehearsal.sqlite' : path;
    if (rehearse) await File(backupPath).copy(target);
    final db = sqlite3.open(target, mode: OpenMode.readWrite);
    try {
      db.execute('PRAGMA busy_timeout=5000');
      db.execute('PRAGMA synchronous=FULL');
      recoverTail(db, backupPath: backupPath, backupHash: backupHash,
          expectedDigest: digest(rows));
      stdout.writeln(jsonEncode({'recovered': count, 'backup': backupPath,
        'target': target,
        'backupSha256': backupHash, 'verifiedRows': auditRows(db).length}));
    } finally {
      db.close();
    }
  } finally {
    source.close();
  }
}
