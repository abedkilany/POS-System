# Ventio

Ventio is an offline-first sales, inventory, sync, and backup management app with LAN, cloud, and Google Drive backup support.

## Pure DB-First Contract

The runtime goal is now `pure db-first` for native app startup and normal data access:

- SQLite is the source of truth for app state, business data, and settings during normal runtime.
- Legacy JSON and `SharedPreferences` are allowed only for one-time migration, import/restore flows, or tests.
- Any remaining web-specific or test-only storage shims must not become the production source of truth.

See [PURE_DB_FIRST_CONTRACT.md](./PURE_DB_FIRST_CONTRACT.md) for the execution phases and acceptance rules.

## Current Release

- Version: `1.0.31+41`
- Backup import supports:
  - JSON backups
  - local `.vtb` archives
  - encrypted backup JSON with password prompt
- Local automatic backups are stored as `.vtb` archives containing `backup.json` and `manifest.json`

## Production Setup

Set these in your deployment environment:

```bash
DATABASE_URL=postgresql://...
CLOUD_SYNC_TOKEN=choose-a-long-random-secret
ACCOUNT_JWT_SECRET=choose-a-long-random-admin-secret
ADMIN_JWT_SECRET=choose-a-long-random-admin-secret
VENTIO_API_ALLOWED_ORIGINS=https://your-app-domain.com
# Optional but recommended for single-store deployments:
CLOUD_SYNC_STORE_ID=store_your_store_id
REQUIRE_DEVICE_TOKEN_AUTH=true
```

## Deployment Notes

- `/api` is the active production API.
- Cloud sync requires `CLOUD_SYNC_TOKEN`.
- Device auth should be enabled in production.
- If `CLOUD_SYNC_STORE_ID` is configured, the app Store ID must match it.
- If `VENTIO_API_ALLOWED_ORIGINS` is set, only those origins will be accepted in production.

## Backup And Restore

- Exported backups are JSON.
- Local automatic backups use `.vtb` archives.
- The restore flow accepts both formats and can prompt for a password for encrypted backups.
- Use the Host device for import and restore operations.

## Neon Setup

1. Create a Neon database.
2. Run `database/neon_sync_schema.sql`.
3. Deploy this project.
4. Open the app, go to Settings → Sync, enter the API URL and `CLOUD_SYNC_TOKEN`, then save and sync.

If you already synced data with an older API, run `database/neon_rebuild_snapshots_from_events.sql` once to rebuild snapshots, including stock deltas.

## Important Note About Store IDs

Each browser has its own local identity. To connect multiple devices to the same cloud store, set the same Store ID in Settings → Device / Store identity before syncing, or restore/import from the main store first. If `CLOUD_SYNC_STORE_ID` is configured, the Store ID in the app must match it.

## Host-Authoritative Sync

See `SYNC_ARCHITECTURE_V2_HOST_AUTHORITY.md` for the current data flow and setup rules.

## Release Notes

Earlier release notes are preserved in the git history and previous tags.
