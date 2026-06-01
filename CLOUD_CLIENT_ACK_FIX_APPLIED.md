# Cloud Client ACK Fix Applied

This build fixes Cloud Clients showing `Online • Not synced yet` even after successful Cloud sync.

## Root cause

Cloud Clients were able to update `last_seen_at` through `/api/sync/pull`, so Monitoring showed them as Online. However, after applying authoritative Cloud changes locally, the Client attempted to publish its ACK through `/api/sync/devices`. That endpoint required the deployment Cloud token only, while paired Clients may only have device-scoped credentials. As a result, the Host-visible ACK fields in `store_devices` stayed empty:

- `last_ack_at = null`
- `last_ack_cursor = null`
- `last_ack_sequence = 0`

## Fix

- `server_api/sync/devices.js`
  - `POST /api/sync/devices` now accepts either the deployment token or valid device-scoped credentials.
  - When device auth is used, the endpoint verifies that the authenticated header `X-Device-Id` matches the `deviceId` in the body, preventing one device from updating another device row.
  - This allows Cloud Clients to update `last_ack_cursor`, `last_ack_sequence`, and `last_ack_at` after local apply succeeds.

- `server_api/_db.js`
  - Device authorization now accepts the device `active_transport` when the legacy `transport` field is empty. This keeps older Cloud rows compatible with device-scoped auth.

## Expected result

After the next successful Cloud Client sync, Neon `store_devices` should show non-empty ACK values for the Client row, and Sync Monitoring should change from:

`Online • Not synced yet • Last successful sync: Never`

to a real ACK-based state such as:

`Online • Synced • Last successful sync: <ACK time>`
