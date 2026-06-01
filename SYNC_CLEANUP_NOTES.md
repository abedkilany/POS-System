# Sync cleanup notes

Cleaned on top of Ventio sync fixes 1-7.

## Removed / cleaned
- Removed unused `Connect to New Host` UI state and legacy confirmation flow from `settings_page.dart`.
- Removed unused legacy client pairing handlers that depended on the removed Connect-to-new-host flow.
- Removed stale Connect-to-New-Host translation keys.
- Renamed Client QR pairing state enum from Host-style terms (`active`, `disabled`, `consumed`, `invalid`) to user-oriented Client terms (`noCode`, `ready`, `connecting`, `connected`, `failed`, `expired`).
- Updated Client pairing state handling so the UI no longer uses Host-only Active/Disabled concepts internally.
- Updated a stale Cloud sync comment that still referenced Connect to New Host.
- Corrected Host Transfer approval UI state so Old Host remains shown as Host after approval pending activation.

## Notes
- Flutter/Dart tools were not available in this environment, so `flutter analyze` could not be executed here.
- JavaScript API files were syntax-checked with `node --check`.
