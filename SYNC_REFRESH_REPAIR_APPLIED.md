# Sync Monitoring Refresh + Repair

Applied change:
- The Sync Monitoring Refresh action now performs a safe legacy Cloud repair before adopting Cloud devices.
- It reads the Host Registry / pairedDevices as the trusted source of truth.
- It repairs only Cloud rows whose device_id is already trusted by the Host and whose store_devices.host_device_id is empty.
- It does not adopt arbitrary store_devices records.
- Added server endpoint:
  - POST /api/sync/devices/repair-host-links
- After repair, the Host reloads Cloud devices and adopts the repaired devices into Host Registry.

Expected behavior:
- Old Cloud-paired clients that already exist in Host Registry/pairedDevices can appear in Monitoring after pressing Refresh.
- Random old Cloud devices are not linked to the current Host.
