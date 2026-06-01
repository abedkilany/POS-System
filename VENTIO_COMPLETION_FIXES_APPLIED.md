# VENTIO - Completion fixes applied

Applied on Ventio 5.5(1):

1. Device name propagation completion
   - Added `deviceName` to LAN `pushPendingOnly` payload.
   - Added `deviceName` to LAN `/changes/ack` payload.
   - Host now updates `HostRegistryDevice.deviceName` when `/changes/ack` is received, not only on `/changes/push`.

2. Cloud wipe confirmation
   - Cloud `device-access` no longer clears `wipe_pending` when returning the wipe command.
   - Added `/api/sync/device-wipe-ack` endpoint.
   - Client sends wipe acknowledgement only after local `factoryResetLocalDevice()` completes.
   - If the acknowledgement fails, `wipe_pending` remains true and the device receives the wipe command again on next contact.

3. Host Sync Monitoring pending changes
   - Host Monitoring now calculates per-device pending changes from host authoritative `syncChanges` using the device ACK cursor/sequence.
   - The UI no longer displays a fixed em dash for Host-side pending changes.

Validation summary:
- Fix 1 completed across syncNow, pushPendingOnly, and /changes/ack.
- Fix 2 completed for LAN/Cloud suspend/delete/wipe flow, including cloud wipe confirmation.
- Fix 3 remains applied: Last Seen is separate from Last Successful Sync.
- Fix 4 completed with real Pending Changes values.
- Fix 5 remains applied in the top status indicator.
