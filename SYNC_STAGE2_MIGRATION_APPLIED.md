# Sync Stage 2 — Host Registry Migration Applied

Implemented the second saved phase for Sync Monitoring cleanup.

## What changed

- Added `LanSyncSettings.withMigratedHostRegistry(hostDeviceId)`.
- Added `LanSyncSettings.hostRegistryNeedsMigration(hostDeviceId)`.
- Added host startup migration in `LanSyncService.startHost()`.
- On first Host startup after update, existing `pairedDevices` are adopted into `hostRegistry` with the current Host `deviceId`.
- Updated LAN host registration and pairing-code creation to preserve the migrated registry instead of overwriting it with stale settings.
- Updated Settings save flow for Host role to preserve and migrate `hostRegistry`.

## Behavior

Existing valid Clients paired with the Host do not need to be paired again.

Migration source:

```text
pairedDevices
```

Migration target:

```text
hostRegistry
```

Each migrated Client receives:

```text
clientDeviceId
clientDeviceToken
hostDeviceId = current host deviceId
status = active
source = migrated_from_paired_devices
pairedAt = migration time
```

## Scope

This stage does not yet refactor Sync Monitoring to read only from Host Registry. That remains Stage 3.
