# VENTIO - Fix 3 Applied

Applied Sync Monitoring source-of-truth cleanup:

- Host Monitoring now separates `Last seen` from `Last successful sync`.
- `Last seen` uses Cloud heartbeat / local peer state freshness (`cloudDevice.lastSeenAt` / `state.updatedAt`).
- `Last successful sync` uses ACK/Cursor only (`lastAckCursor`, `lastAppliedHostCursor`, `cloudDevice.lastAckAt`, `cloudDevice.lastAckCursor`).
- Host sync status now uses the same ACK/Cursor-only source as Last successful sync.
- Client Last successful sync and sync status no longer use `state.updatedAt` as a fallback success signal.

This prevents Cloud devices from showing a heartbeat time as if it were a successful sync, and prevents state record updates from being interpreted as successful synchronization.
