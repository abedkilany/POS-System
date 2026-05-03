# Cloud Sync v4 Notes

This version adds a portable sync API for Vercel + Neon while keeping the existing local Hive and Desktop/LAN design.

## What was added

- `api/health.js`
- `api/sync/push.js`
- `api/sync/pull.js`
- `api/_db.js`
- `database/neon_sync_schema.sql`
- root `package.json` with `@neondatabase/serverless`

## Required Vercel environment variables

- `DATABASE_URL` — created by the Vercel Neon integration.
- `CLOUD_SYNC_TOKEN` — optional but recommended. If set, the Flutter app must send the same value as Bearer token.

## Run this SQL in Neon

Open Neon SQL Editor and run:

```sql
-- paste database/neon_sync_schema.sql here
```

## API endpoints

- `GET /api/health`
- `POST /api/sync/push`
- `GET /api/sync/pull?store_id=STORE_ID&since=ISO_DATE`

## Important behavior

- Desktop keeps Local Hive + LAN.
- Web/Vercel queues cloud sync changes instead of LAN changes.
- Flutter still talks only to an HTTPS API, never directly to Neon.

## Next integration step

The sync API is now present. The next step is exposing Cloud API URL/token controls in the Web settings screen and calling `CloudSyncService.syncNow(...)` automatically after changes and periodically when online.
