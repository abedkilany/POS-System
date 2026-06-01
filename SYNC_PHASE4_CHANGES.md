# Ventio Sync Phase 4 Changes

This build applies the Stage 4 sync cleanup/refactor:

- Normal sync runs now use the unified push -> pull -> optional snapshot repair orchestration through transport adapters.
- CloudSyncTransportAdapter no longer delegates normal `syncNow()` to CloudSyncService.syncNow().
- LanSyncTransportAdapter no longer delegates normal `syncNow()` to LanSyncService.syncNow().
- Old AutoCloudSyncController was removed from CloudSyncService.
- Old AutoLanSyncController was removed from LAN service implementations.
- Legacy LAN V1 endpoints `/pull` and `/sync` are disabled with HTTP 410 Gone.
- Removed the inactive `lib/core/sync_v2` folder.

Notes:
- The low-level CloudSyncService and LanSyncService still keep their safe push/pull/repair methods because the unified adapters depend on them as transport primitives.
- `dart analyze` was not run in this environment because Dart tooling is unavailable.
