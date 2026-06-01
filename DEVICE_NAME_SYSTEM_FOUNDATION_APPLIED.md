# Device Name / System Foundation Update

Applied on this build:

- Added `Device Name` to the System Foundation identity card.
- Kept System Foundation read-only except for Device Name.
- Added an edit dialog for Device Name with trim, empty-name rejection, and 60-character limit.
- Saving Device Name updates local `AppIdentity.deviceName`.
- Saving Device Name triggers Cloud device registration update when Cloud is configured/enabled, so `store_devices.device_name` can be refreshed.
- First-run default naming no longer uses the legacy `Main device`; it falls back to `deviceId` when no real/detected name provider is available.
- Legacy `Main device` values are not automatically replaced; they remain until the user edits the name manually.
