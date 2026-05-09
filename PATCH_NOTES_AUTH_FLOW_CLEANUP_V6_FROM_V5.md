# PATCH NOTES - Auth Flow Cleanup V6 From V5

Base version: `Store_Manager_local_internal_connect_v5(1).zip`

## What changed

- Kept the first screen as platform login/register.
- Platform login uses username + password only.
- Added a Desktop/Windows-only `Platform API URL` field on login/register when the app is not running on Web.
- Web uses the current site origin automatically for the Platform API URL.
- Desktop can also receive the API URL at build time with:
  `--dart-define=PLATFORM_API_BASE_URL=https://your-vercel-app.vercel.app`
- Hid `اتصال بإعدادات داخلية` on Web.
- Kept `اتصال بإعدادات داخلية` only for Desktop/Windows local LAN connection.
- Added clearer auth error messages instead of always showing `wrong pin`.
- Fixed a NavigationRail/AppBar syntax issue introduced in previous patch work.

## Intended flow

### Web

1. Login or create platform account.
2. Create or link store online.
3. Manage store online.
4. No internal LAN connect button.

### Windows/Desktop

1. Login or create platform account using Platform API URL.
2. Or use internal local connection without platform account.
3. Internal local connection requires Host IP, port, Store ID, and Store Token.
4. PIN remains reserved for internal store users later, not platform accounts.

## Notes

- If Windows login says the Platform API URL is not configured, enter the Vercel app URL in the `Platform API URL` field or build with the dart-define above.
- Local internal connection is not available on Web.
