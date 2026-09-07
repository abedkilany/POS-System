/// Also enforced for older executables and writers outside AuditLogger.
const auditInsertGuardSql = '''
CREATE TRIGGER IF NOT EXISTS trg_audit_logs_validate_insert
BEFORE INSERT ON audit_logs
BEGIN
  SELECT CASE WHEN NEW.hash_version <> 1
    OR length(NEW.record_hash) <> 64
    OR NEW.record_hash GLOB '*[^0-9a-f]*'
    THEN RAISE(ABORT, 'Audit integrity failure: valid integrity hash required. Update Ventio before writing.') END;
  SELECT CASE WHEN NEW.previous_hash <> COALESCE(
    (SELECT record_hash FROM audit_logs ORDER BY rowid DESC LIMIT 1), '')
    THEN RAISE(ABORT, 'Audit integrity failure: stale previous hash.') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM audit_logs WHERE id = NEW.id)
    OR (NEW.rowid <> -1 AND NEW.rowid <= COALESCE((SELECT MAX(rowid) FROM audit_logs), 0))
    THEN RAISE(ABORT, 'audit_logs are append-only') END;
END;
''';
