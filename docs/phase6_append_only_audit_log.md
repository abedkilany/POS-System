# Phase 6 — Append-only Audit Log

## Status
Implemented on the P0–P3 baseline.

## Database enforcement
The SQLite foundation schema is now version 30. `audit_logs` includes:
- `previous_hash`
- `record_hash`
- `hash_version`

On migration, legacy audit rows are sealed in SQLite row insertion order. Only after legacy rows are sealed are immutable triggers installed. SQLite triggers reject `UPDATE` and `DELETE` against `audit_logs`.

## Tamper evidence
Each new audit record contains a SHA-256 hash over its protected fields plus the previous audit record hash. `AuditLogger.verifyIntegrity()` walks the append order and verifies both the chain linkage and each record hash.

This is tamper-evident chaining, not an external signature/HMAC authority. The database triggers prevent normal application/API mutation, while the chain makes offline/direct-file modification detectable when integrity verification is run.

## Retention/reset behavior
Audit records are intentionally excluded from generic local `clearAll()` deletion. Business reset, client local clear, and factory reset add important audit events instead of erasing history. The old diagnostic "clear audit log" operation is replaced by "verify audit integrity".

The SQL editor separately blocks write statements targeting `audit_logs`.
