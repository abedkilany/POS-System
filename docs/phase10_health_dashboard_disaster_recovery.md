# Phase 10 — Health Dashboard + Disaster Recovery

## Goal

Phase 10 turns Ventio's existing integrity mechanisms into one production health gate and adds a non-destructive disaster-recovery drill. It does not silently repair accounting or inventory data. Critical integrity findings are surfaced so they can be corrected through the original business workflow or a verified restore.

## Production health gate

`lib/features/maintenance/phase10_health_service.dart` composes the authoritative checks built in earlier phases:

- SQLite `quick_check` for normal health refreshes and full `integrity_check` for deep diagnostics.
- SQLite `foreign_key_check`.
- Production durability settings: WAL journal, FULL/EXTRA synchronous mode, and foreign keys enabled.
- Phase 6 append-only audit hash-chain verification.
- Business-reference integrity verification.
- Phase 9 multi-warehouse / Unified Batch / manufacturing traceability integrity.
- Accounting production integrity, including journal balance, control accounts, cash, vouchers and inventory GL-to-batch valuation reconciliation.
- Host recovery identity / Store Recovery Key readiness.

The existing Maintenance dashboard consumes these checks as `MaintenanceIssue` records. A dedicated Production Health card shows critical, warning and healthy check counts. Diagnostic exports include the complete Phase 10 report.

## Disaster-recovery readiness

`DisasterRecoveryService.assessReadiness()` requires all of the following before reporting the Host as recovery-ready:

1. This device is the Host.
2. The production health gate has no critical findings.
3. A valid Store Recovery Key is available.
4. Automatic local backup is enabled.
5. A successful local backup exists within 48 hours.
6. A non-destructive restore drill has passed within 30 days.

The Maintenance Center exposes the readiness checklist directly to the operator.

## Verified recovery checkpoint

`createVerifiedCheckpoint()` creates a dedicated timestamped `.vtb` file under `Recovery checkpoints` rather than reusing the scheduled daily backup. Recovery checkpoints are retained separately with a bounded history.

After creation, Ventio immediately performs a non-destructive restore drill:

1. Read the `.vtb` bytes.
2. Verify ZIP CRC/integrity.
3. Require both `manifest.json` and `backup.json`.
4. Require the manifest to declare encrypted AES-256-GCM content.
5. Require the payload to match Ventio's encrypted backup format.
6. Decrypt with the Store Recovery Key.
7. Run Ventio backup schema/section validation on the decrypted content.
8. Record the successful verification time and path.
9. Append an important disaster-recovery audit event.

No live business data is changed during this drill.

## Restore post-check

The normal Settings backup-import flow now runs the full Phase 10 health gate immediately after a restore. The user receives an explicit success message only when the post-restore health gate contains no critical findings. If critical findings exist, the restore is reported as completed with a strong instruction to open Maintenance before normal work continues.

## Security

- Recovery checkpoint creation requires Host role and `backup.export` permission.
- Verification from Maintenance additionally requires maintenance-management access through the page and service.
- Backup payload remains AES-256-GCM encrypted with the Store Recovery Key.
- Recovery verification actions are appended to the Phase 6 audit chain.
- Device/account secrets remain excluded according to Phase 4 backup policy.

## Deferred runtime validation

Per the current project execution policy, Phase 10 does not run `flutter analyze` or the full Flutter test suite during implementation. Those gates remain deferred to the final production validation phase. Static Phase 10 contract verification is included in `tool/verify_phase10_health_disaster_recovery.py`.
