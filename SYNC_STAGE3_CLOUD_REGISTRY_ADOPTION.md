# Sync Stage 3 Cloud Registry Adoption

This build keeps Host Registry as the single source of truth for Sync Monitoring, and adds the missing Cloud Pairing adoption path.

## Changes

- Pairing status API now returns the consumed Client's `claimedByDeviceName` and `claimedDeviceToken` when a Host checks a consumed Cloud pairing code.
- The Host adopts the consumed Cloud Client into `LanSyncSettings.hostRegistry` from `_refreshCloudPairingStatus()`.
- Added `LanSyncSettings.withCloudPairedHostRegistryDevice(...)` for safe Host Registry upsert of Cloud-paired Clients.
- Monitoring remains based only on `hostRegistry`; Cloud rows are still status overlays, not discovery sources.
- Cloud-only registry devices no longer show as LAN-authorized just because they have a device token.

## Expected result

A Client paired via Cloud appears in Sync Monitoring after the Host refreshes/checks the consumed Cloud pairing code, without reintroducing old `store_devices` history as a discovery source.
