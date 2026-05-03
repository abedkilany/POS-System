# Cloud Sync v5 notes

Fixes in this version:

1. `/api/sync/push` now writes to both:
   - `sync_events` = event log
   - `entity_snapshots` = latest state for new devices

2. `restore_snapshot` uploads are materialized into separate rows:
   - product, customer, sale, supplier, category, brand, unit, role, user, store_profile

3. `/api/sync/pull` without a `since` cursor returns `entity_snapshots`, so a new browser/device can hydrate its local Hive storage.

Important:

- All devices that should share data must use the same Store ID.
- You can see the Store ID in Settings → Cloud sync chips.
- To change it: Settings → System foundation → Store ID.
- For the existing database that already has `sync_events` but empty `entity_snapshots`, run:
  `database/neon_sync_backfill_from_events.sql`
