# POS System — Host Authority Sync V8

This build keeps the Flutter offline/LAN POS app and adds a cleaner Vercel + Neon cloud path.

## What changed

- Vercel deployment builds Flutter Web with `npm run build` and serves `build/web`.
- `/api` is the active production API. The older `vercel-api/` folder is kept only as reference and is not used by the root Vercel deployment.
- Cloud sync now requires `CLOUD_SYNC_TOKEN`; the API no longer accepts unauthenticated sync when the token is missing.
- Optional `CLOUD_SYNC_STORE_ID` can restrict a deployed API/token to one store ID.
- Stock movements now update `entity_snapshots`, so new browsers/devices pull current inventory instead of stale product snapshots.
- Sync architecture v2 makes the Host the only source of truth. Web/remote clients submit changes to a Cloud relay inbox; the Host accepts them and republishes authoritative events.
- Flutter Web saves the cloud pull cursor and supports automatic cloud sync after the API URL/token are configured.

## Vercel environment variables

Set these in Vercel Project Settings → Environment Variables:

```bash
DATABASE_URL=postgresql://...
CLOUD_SYNC_TOKEN=choose-a-long-random-secret
# Optional but recommended for single-store deployments:
CLOUD_SYNC_STORE_ID=store_your_store_id
```

## Neon setup

1. Create a Neon database.
2. Run `database/neon_sync_schema.sql` once in the Neon SQL editor. If it was already run before, run it again; it is idempotent and adds the new `cloud_change_requests` relay table.
3. Deploy this project to Vercel.
4. Open the app URL, go to Settings → Sync, enter the Vercel URL and the same `CLOUD_SYNC_TOKEN`, then save and sync.

If you already synced data with an older API, run `database/neon_rebuild_snapshots_from_events.sql` once to rebuild snapshots, including stock deltas.

## Important note about store IDs

Each browser has its own local identity. To connect multiple devices to the same cloud store, set the same Store ID in Settings → Device / Store identity before syncing, or restore/import from the main store first. If `CLOUD_SYNC_STORE_ID` is configured, the Store ID in the app must match it.


## Host-authoritative sync

See `SYNC_ARCHITECTURE_V2_HOST_AUTHORITY.md` for the new data flow and setup rules.
