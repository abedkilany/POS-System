# VENTIO - Sync Fix #2 Applied

Implemented device management improvements for Sync Monitoring:

## Suspend / Resume
- Suspend now writes to the existing LAN access block list.
- Suspend also calls the Cloud API (`/api/sync/device-suspend`) to set `store_devices.suspended = true`.
- Cloud Client sync checks `/api/sync/device-access` before sync and stops if the Host suspended the device.
- Resume clears the local LAN suspension and sets Cloud `suspended = false`.
- Resume does not reset cursors; the device keeps its last ACK/Cursor so the next sync performs catch-up from the last applied Host sequence/cursor.

## Delete / Wipe
- Delete still removes LAN pairing/registry and revokes the Cloud device.
- Cloud revoke now sets `revoked = true`, `wipe_pending = true`, and `wipe_requested_at = now()`.
- A Cloud Client checks `/api/sync/device-access`; if `wipe_pending` is true, it factory-resets local data.
- For LAN, the Host stores the deleted device token before removing pairing. If the deleted Client connects again with its old token, the Host returns `wipeRequired`, and the Client factory-resets local data.

## Database / API
- Added Cloud columns: `suspended`, `wipe_pending`, `wipe_requested_at`.
- Added API routes:
  - `/api/sync/device-suspend`
  - `/api/sync/device-access`
- Updated `/api/sync/device-revoke` to request wipe.
