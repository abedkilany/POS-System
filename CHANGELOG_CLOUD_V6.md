# Cloud V6 changes

- Root Vercel deployment now builds Flutter Web and serves `build/web`.
- Root `/api` is the active Neon sync API.
- Cloud token is mandatory. Missing `CLOUD_SYNC_TOKEN` now fails closed.
- Optional `CLOUD_SYNC_STORE_ID` protects one-store deployments from cross-store pulls/pushes.
- `stock_movement` events now update product rows in `entity_snapshots`.
- First-time cloud pulls exclude `stock_movement` snapshots to avoid double-applying stock deltas.
- Flutter Web persists the cloud pull cursor.
- Flutter Web has auto cloud sync settings and a 30-second automatic sync controller.
- Added `database/neon_rebuild_snapshots_from_events.sql` for existing Neon data.
