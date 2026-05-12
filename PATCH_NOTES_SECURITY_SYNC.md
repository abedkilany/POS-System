# Ventio security/sync patch notes

Implemented agreed changes:

1. Removed default admin password creation
   - No `admin/admin123` account is created on fresh installs.
   - First launch now creates the first admin from the setup screen.
   - Existing legacy default admin installs are detected and forced through setup before use.

2. Upgraded password hashing
   - New user passwords use PBKDF2-HMAC-SHA256 with 210,000 iterations and 32-byte derived keys.
   - Existing legacy hashes are still accepted for login compatibility, but new/changed passwords are written using the new hash format.

3. PIN handling
   - PIN sync events are no longer emitted.
   - Incoming legacy `security_pin` sync changes are ignored.
   - The Settings PIN management card was removed from the admin settings UI.

4. Cloud pull pagination
   - `/api/sync/pull` now returns `hasMore` and `nextCursor`.
   - Snapshot pulls and event pulls are paginated with stable cursors.
   - The Flutter cloud client loops through all pages and saves the final pull cursor only after all pages complete successfully.

Notes:
- I could not run `flutter analyze` or `flutter test` in this environment because Flutter/Dart is not installed here.
- `node --check api/sync/pull.js` passed.
