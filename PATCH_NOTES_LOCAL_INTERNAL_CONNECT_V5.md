# Local Internal Connect V5

This patch reorganizes first-run access so the app no longer forces LAN setup before the login screen.

## Changes

- Startup now opens the platform-style login screen directly.
- Removed the old first-run SyncSetup gate from `StoreManagerApp`.
- Added a new login-screen option: **اتصال بإعدادات داخلية**.
- Internal connection accepts:
  - Host IP
  - Port
  - Store ID
  - Store Token
- Internal connection stores LAN settings as a client device and binds the device to the entered Store ID.
- Creates a local system session for the linked store so the device can enter the store dashboard without creating an online platform account.
- Keeps online registration/login available for platform accounts.

## Intended flow

Online path:

`Login/Register -> Platform Home -> Create/Link Store -> Device/Sync Settings`

Local internal path:

`Login Screen -> اتصال بإعدادات داخلية -> Host IP + Store ID + Token -> LAN sync -> Store Dashboard`

## Notes

- Web builds still cannot use the existing dart:io LAN sync server/client. For browser-based local LAN sync, a separate HTTP/CORS-compatible sync layer is required.
- Local internal connection is meant for internal store devices that already received Store ID and Store Token from the store owner/host.
