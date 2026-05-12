# Ventio patch notes

Applied security and production-hardening fixes:

- Replaced new encrypted backup exports with AES-256-GCM using PBKDF2-HMAC-SHA256.
- Kept backward compatibility for older encrypted backup versions.
- Tightened permission checks so unauthenticated users no longer implicitly pass `hasPermission()`.
- Preserved first-run admin setup flow so the default `admin/admin123` account must be replaced before app access.
- Increased cloud/LAN auto-sync polling from 5 seconds to a 30-second minimum.
- Enabled Android release minification and resource shrinking with ProGuard rules.
- Updated web/PWA branding metadata.
- Moved the unused legacy Vercel API folder to `docs/archive/vercel-api-reference/`.

Note: Flutter/Dart SDK was not available in this environment, so run `flutter pub get`, `flutter analyze`, and `flutter test` locally before release.
