# Device Cash Drawer Settings

Added a Settings → Sync card for linking the current device ID to one cash drawer.

## Changes
- Added `_CurrentDeviceCashDrawerSettingsCard` to `lib/features/settings/settings_page.dart` after `SyncMonitoringSection`.
- Added `AccountingService.linkCashDrawerToDevice(...)` and `AccountingService.unlinkCashDrawerFromDevice(...)`.
- Added Arabic/English translation keys for the new card.

## Behavior
- The current device can be linked to exactly one `cash_drawer` cash location.
- Saving a drawer clears any previous drawer linked to the same `device_id`.
- The branch ID is stored on the drawer when available.
- Cash sales already resolve the open drawer by current `device_id`, so this setting controls which drawer the device uses.

## UI path
Settings → Sync → Current device cash drawer
