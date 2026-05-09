# Store Manager v7 - Fixed Platform URL

Base version: `Store_Manager_local_internal_connect_v5(1).zip`

## Changes
- Fixed the platform API base URL inside the app:
  - `https://pos-system-lyart-seven.vercel.app`
- Removed the need for normal users to enter any Platform API URL.
- Windows/Desktop now uses the same central platform URL for Login/Register automatically.
- Web continues to use the hosted origin.
- Internal LAN connection remains Desktop-only and is hidden on Web.
- Replaced the confusing `wrong pin` login error with a platform login message.

## Expected flow
- Web: Login / Register only.
- Windows/Desktop: Login / Register + optional internal LAN connection.
- Internal connection asks only for Host IP, Port, Store ID, Store Token.

## Notes
- Platform auth calls use `/api/auth/login`, `/api/auth/register`, `/api/store/create`, `/api/store/link` on the fixed platform base URL.
- Cloud sync still requires its own token only for protected sync endpoints.
