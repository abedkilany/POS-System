# VENTIO - Fix #5 Applied

Updated the top status indicator to separate connection from sync state.

Key changes:
- Added Role, Active Transport, Connection Status, Sync Status, Pending Changes, and Last Successful Sync details.
- Summary label now shows `Connection • Sync` instead of a single misleading `Synced` label.
- Client summary uses only the active transport (LAN or Cloud), so inactive/configured transports do not create false warnings.
- Host summary can account for LAN and Cloud together when both are available.
- `Synced` is shown only when a real ACK/Cursor exists in `SyncDeviceStateStore`.
- Cloud heartbeat/readiness is treated as connection/last seen, not as successful sync.
