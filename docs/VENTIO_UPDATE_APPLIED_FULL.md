# Ventio Full Update Applied

This package includes a deeper implementation pass on top of the previous build.

## Added in this pass

1. Cloud pairing API foundation:
   - `POST /api/sync/pairing/create` for Host-created short-lived pairing codes.
   - `POST /api/sync/pairing/claim` for Clients to claim a code and receive `storeId`, `deviceId`, `deviceToken`, role and transport.
   - `POST /api/sync/device-revoke` for Host-side Client revocation.
2. Database migration script:
   - `database/neon_sync_v2_pairing.sql`.
3. Flutter service methods in `CloudSyncService`:
   - `createPairingCode(...)`
   - `claimPairingCode(...)`
   - `revokeDevice(...)`
4. Shared Sync V2 contract file:
   - `lib/core/sync_v2/sync_v2_contracts.dart`

## Already present from the previous pass

- Host-only Cloud authoritative publishing path.
- Cloud Client relay inbox path.
- Device headers on Cloud API calls.
- Client-only `Clear Local Data` and `Rebuild From Host` UI.
- Mobile Sales product-first layout, bottom checkout bar, inline scanner preview, anti-duplicate barcode handling, beep and haptic feedback.
- Login remember-session foundation and delayed sync startup.

## Still needs real-device validation

- Camera scanner behavior on Android/iOS.
- LAN snapshot rebuild with multiple devices.
- Cloud pairing flow after deploying new Vercel API files.
- Turning on `REQUIRE_DEVICE_TOKEN_AUTH=true` only after all devices are paired with device tokens.
