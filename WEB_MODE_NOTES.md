# Web mode update

This version skips the LAN Host/Client setup screen when running on Flutter Web / Vercel.

Changes:

- `lib/app.dart` now uses `kIsWeb` to bypass the LAN setup gate.
- `lib/features/settings/settings_page.dart` shows a Cloud/Web sync notice instead of LAN controls on Web.
- `vercel.json` was added for Flutter Web SPA routing.
- `.gitignore` was updated to allow publishing `build/web` if using the simple Vercel static deploy flow.

Next step for real online sync: connect the web build to a Vercel API + Neon PostgreSQL backend.
