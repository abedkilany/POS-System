# Host Heartbeat Patch

This patch fixes the online web status issue where the Web app showed the Host as connected just because the Vercel/Cloud API was reachable.

## What changed

- Added `/api/sync/host-heartbeat`:
  - `POST` from the Windows Host updates `last_seen_at`.
  - `GET` from Web/online clients returns the latest Host heartbeat for the store/branch.
- Added `store_host_heartbeats` table to `database/neon_sync_schema.sql`.
- The API endpoint also creates the heartbeat table/index automatically if they are missing.
- `CloudSyncService.syncNow()` now sends a heartbeat whenever the cloud-enabled Host sync loop runs.
- The Web status indicator now checks Host heartbeat freshness instead of Cloud API health.

## Status behavior

- Cloud unreachable: Cloud offline.
- Cloud reachable + heartbeat newer than 90 seconds: Host connected.
- Cloud reachable + heartbeat missing or older than 90 seconds: Host offline.
- Pending local changes still show Sync pending, but only after Host heartbeat is confirmed fresh.

## Important

For Web to show Host connected, the Windows Host must be running, configured as Host, cloud sync enabled, and using the same Store ID / Branch ID / Cloud token as the Web client.
