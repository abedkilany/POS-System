# LAN Sync Reliability Patch

This build improves LAN auto sync reliability without changing the existing Host/Client setup flow.

## What changed

- Host now re-stamps accepted Client changes with the Host receive time before storing them.
  - This prevents another Client with a newer cursor from missing an offline Client change.
- Client automatic sync now retries failed Host queue items on every auto tick.
  - Failed LAN items no longer stay blocked behind long retry windows.
- Auto LAN controller now detects saved setting changes.
  - Changing Host/Client mode, host IP, port, token, or auto-sync state is applied without requiring an app restart.
- Host server auto-restarts when the configured LAN port changes.
- Client sync now falls back to a full Host snapshot repair if incremental pull fails after push is complete.
- Initial clone and full pull now update LAN connection/sync timestamps and cursor.
- Added a manual **Repair LAN sync** button for Client devices.
  - It retries failed Host queue items and pulls a full snapshot from the Host.

## Notes

- LAN sync is still desktop/mobile only. Flutter Web cannot run the local LAN Host server.
- For best results, keep one device as the Host and set all other LAN devices as Clients.
- If a Client has been offline for a long time, use **Repair LAN sync** once after reconnecting.
