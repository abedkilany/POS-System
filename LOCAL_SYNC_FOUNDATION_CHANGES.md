# Local Database Sync Foundation

This update prepares the local database for the next LAN and Cloud sync phases.

## Added metadata to syncable entities
The following models now carry durable sync metadata:

- Product
- Customer
- Supplier
- Expense
- CatalogItem
- Sale

New metadata fields:

- `storeId`
- `branchId`
- `version`
- `lastModifiedByDeviceId`
- existing fields kept: `createdAt`, `updatedAt`, `deletedAt`, `deviceId`, `syncStatus`

## Added Sync Queue
A new model was added:

- `lib/models/sync_queue_item.dart`

The queue tracks where each local change must be sent next:

- `host` for client devices
- `cloud` for host devices with cloud/marketplace enabled
- `local` changes are not queued

## AppStore changes
- Added `_syncQueue` persisted under `sync_queue_v1`.
- Every local change still creates a `SyncChange`.
- Eligible changes are also added to `SyncQueueItem`.
- Added retry bookkeeping through `markSyncQueueItemFailed`.
- `markSyncChangesSyncedByIds` now also marks matching queue items as synced.
- Local schema version updated to `11`.

## Migration behavior
Existing local data is normalized with the current `storeId`, `branchId`, `deviceId`, and version metadata.

## Why this matters
This creates the foundation for:

- Client -> Host sync
- Host -> Cloud sync
- conflict detection by `version`, `updatedAt`, and `lastModifiedByDeviceId`
- future marketplace publishing from Host only
