# Audit startup recovery

The inspected database had 820 cryptographically consistent audit records,
followed by 18 records with both hash fields empty. Existing update/delete
triggers prevented automatic legacy sealing. The historical writer/version
could not be established from the available logs.

The application now rejects missing/malformed hashes, stale chain tips,
duplicate IDs and replacement inserts at the SQLite boundary. AuditLogger
serializes awaited flushes, reads the chain tip and inserts within a transaction,
and propagates failures while retaining the queued record. Schema version 33
verifies existing signed history on initialization. Failed initialization closes
its database and is not retried as a fresh install.

## Controlled recovery

With Ventio closed, `dart run tool/recover_audit_tail.dart DATABASE` performs a
read-only audit check. `--rehearse` makes a SQLite backup and recovers an isolated
copy; `--apply` makes and validates a backup before recovering the named database.
Do not use `--apply` on a database another application is writing to.

Recovery only permits an entirely unsigned suffix after a verified signed
prefix. It rejects unsupported hash versions, partial signatures, signed gaps,
changed source audit content and modified signed history. Original unsigned rows
are preserved in immutable `audit_recovery_originals`, alongside recovery time
and backup SHA-256. A signed audit event explicitly records that the new hashes
attest to content at recovery time, not historical authenticity. Existing signed
hashes and business records are not rewritten by this tool.

Changes, temporary trigger removal, protection reinstatement, evidence, and the
recovery event share one transaction. Failures roll back the entire recovery.
The production migration never silently reseals protected unsigned history.

## Verification

Behavior tests cover concurrent appends, unsigned/stale/replacement writes,
update/delete guards, recovery evidence, tampered signed history, and rollback
after an injected failure. An isolated copy of the affected database completed
database and AppStore startup twice after recovery.

That startup also reported existing batch/warehouse quantity and inventory
valuation discrepancies. These are distinct from the audit startup blocker and
were not repaired by this change.

The local Windows repair build is 1.0.34+34; no release was published to the
update server. It was installed successfully, with its installed app.so matching
the built artifact. Captured startup output confirmed AppStore ready at 2015 ms,
MainShell ready at 2064 ms and the refreshed Dashboard ready at 3208 ms.

The production recovery preserved all 89 non-audit tables byte-for-byte at the
row-value level before normal app startup migrations. It sealed 18 unsigned
records, preserved their originals and appended one recovery event (839 audit
records total). SQLite integrity_check returned ok.

Verified original database backup:
`C:/Users/User/AppData/Roaming/Ventio/audit_recovery_backups/before_recovery_1788800195561285.sqlite`

SHA-256: `05688fd0ce9c17a03b1ed8a41ab25889d8bc829c62cae7bd829f1ceff49b3b5a`

Previous installed application:
`C:/Users/User/AppData/Local/Ventio-repair-backups/20260907-audit/installed-before-repair`
