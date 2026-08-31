# Phase 4 — Unified Encrypted Backup & Secret Protection

## Status
Implemented on the P0–P3 baseline.

## What changed
- Manual backups now export through the existing AES-256-GCM encrypted backup format (PBKDF2-HMAC-SHA256, 200,000 iterations).
- Local automatic `.vtb` backups and Google Drive backups now encrypt `backup.json` with the Store Recovery Key before writing/uploading the ZIP archive.
- Local `.vtb` restore first tries the active Store Recovery Key and falls back to an interactive password/recovery-key prompt for backups from another or freshly restored device.
- Account authentication tokens and Google Drive client/refresh/access secrets are stored through `FlutterSecureStorage` rather than normal local database scalar storage.
- Legacy plaintext token/scalar values are migrated into secure storage and removed from the ordinary database.
- Backup payload sanitization excludes device-bound secrets even if a legacy value still exists during migration.
- Reset-protection backups are encrypted with an operator-chosen backup password so they remain recoverable after a factory reset deletes device-bound secure-storage keys.

## Secret policy
The business backup contains portable business/application data, not device-bound authentication secrets. Account tokens, Google Drive secrets, and retired direct API token material are excluded from portable backup payloads.

## Recovery behavior
Automatic backups use the Store Recovery Key so they can run unattended. Manual encrypted backups use the password chosen by the operator. After a disaster/fresh install, restoring an automatic archive requires the original Store Recovery Key if the current identity no longer has it.
