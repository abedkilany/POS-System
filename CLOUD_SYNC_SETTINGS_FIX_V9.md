# Cloud Sync Settings Fix V9

This version restores Cloud Sync settings for Windows/Desktop builds.

## What changed

- Added a dedicated **Cloud sync settings / إعدادات المزامنة السحابية** card in Settings for non-web builds.
- The Windows HOST can now configure:
  - Cloud API URL
  - Cloud sync token
  - Auto sync interval
  - Auto cloud sync on/off
- Added actions:
  - Save as HOST
  - Test API
  - Sync now
  - Retry cloud queue
- Saving from this card marks the current Windows device as `DeviceRole.host` and `SyncMode.cloudConnected`.
- Fixed a safety issue where desktop code could fall back to `Uri.base.origin`, which is web-only.

## How to use

1. Open the Windows app on the HOST device.
2. Go to Settings.
3. In **Cloud sync settings**, enter your Vercel URL and token.
4. Click **Save as HOST**.
5. Click **Test API**.
6. Click **Sync now**.
7. Restart the app once after the first save so auto cloud sync starts with the new configuration.
