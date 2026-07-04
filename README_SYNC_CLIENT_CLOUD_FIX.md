# Client-Cloud sync fix

Fixed a deadlock in `lib/core/services/cloud_sync_service.dart`.

## Root cause
`_clientCloudHostWorkNeedsDrain()` used `store.hasOutstandingSyncWorkForTarget('cloud_host')`.
That method counts every non-synced row, including fresh `pending`, `failed`, and `rejected` rows.

On a Client-Cloud device, a new local change creates a `cloud_host` pending row. The cloud sync flow checked the drain guard before pushing, saw that row as "outstanding", and returned sync deferred. Result:

- pending changes were not sent to the Host
- pull from Host/Cloud was deferred too
- Client-Cloud looked stuck with pending changes

## Fix
The drain guard now only blocks when there are `submitted` `cloud_host` rows, meaning requests already reached Cloud and are waiting for Host confirmation.

Fresh `pending`/`failed` rows are allowed to be pushed. `rejected` rows no longer block pulling authoritative Host data.

## Unified safe rebuild fresh snapshot request binding

Rebuild now uses a request-bound fresh Host snapshot:

1. Client drains all pending `cloud_host` changes and waits until no submitted requests remain.
2. Client creates a `rebuildRequestId` and sends it with the relay `cloud_snapshot_manifest` request, together with `requiredMinSequence`.
3. Host builds a snapshot on demand and tags the snapshot envelope/chunks with `rebuildRequestId`, `snapshotRequestId`, `requiredMinSequence`, and `freshRebuildSnapshot`.
4. Client rejects any snapshot whose `rebuildRequestId` does not exactly match the active rebuild request, or whose `syncGeneratedSequence` is below `requiredMinSequence`.
5. Client resets ACK/progress only inside `_applyCloudSnapshotEnvelope()` after the matching fresh snapshot has been downloaded.

Legacy cached snapshots are no longer accepted for Cloud rebuild fallback; if no matching fresh snapshot is available, rebuild stays deferred and keeps the previous ACK intact.
