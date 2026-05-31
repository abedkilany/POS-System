# Sync Stage 1 — Host Registry Applied

This update implements the first saved redesign phase for Sync Monitoring & Pairing.

## What changed

- Added `HostRegistryDevice` model in LAN sync settings.
- Added `LanSyncSettings.hostRegistry` as the Host-owned registry of Client devices.
- `hostRegistry` is serialized inside `lan_sync_settings_v2`.
- Existing `pairedDevices` are automatically migrated into `hostRegistry` when settings are loaded.
- New LAN pairing claims now write both:
  - `pairedDevices[clientDeviceId] = deviceToken`
  - `hostRegistry[clientDeviceId] = HostRegistryDevice(...)`
- Deleting a sync device removes it from both `pairedDevices` and `hostRegistry`.

## Compatibility

Existing Clients do **not** need to be paired again. Any device already present in `pairedDevices` is adopted into `hostRegistry` with:

- `status = active`
- `source = migrated_from_paired_devices`

## Scope

This is Stage 1 only. Sync Monitoring still has its old display logic. The next stage should refactor Monitoring to read from `hostRegistry` only and treat Cloud/LAN/PeerState as informational status fields.
