# Sync Stage 3 — Host Registry Monitoring

Applied the third saved repair phase for Sync Monitoring & Diagnostics.

## What changed

- Host Monitoring device discovery now reads only from `LanSyncSettings.hostRegistry`.
- Cloud devices no longer add rows to the Host Monitoring table by themselves.
- Peer sync history no longer adds rows to the Host Monitoring table by itself.
- LAN paired devices no longer add monitoring rows directly; LAN state is used as status/auth information for devices already present in Host Registry.
- Test Paired Clients now uses Host Registry as the source of truth and uses Cloud/LAN/peer states only as status overlays.

## Result

The Host Monitoring screen should now show only Clients that belong to the current Host Registry, preventing old Cloud records, historical peer states, or devices from other Hosts from appearing as active monitored devices.
