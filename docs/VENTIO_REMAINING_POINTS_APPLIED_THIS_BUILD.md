# Ventio remaining points applied in this build

This build continues from `Ventio_SYNC_V2_FULL_APPLIED` and applies the remaining items that can be safely implemented without running Flutter on physical LAN/Camera devices.

## Applied

1. Sync V2 bridge is now attached to every local SyncChange payload through `_syncV2` metadata.
   - Host-created local changes are tagged as `authoritativeEvent`.
   - Client-created local changes are tagged as `draftCommand`.
   - Each local change receives a `clientMutationId` and source role/transport metadata.

2. Host acceptance now restamps incoming Client changes as Host-authoritative events.
   - Accepted changes are tagged as `authoritativeEvent`.
   - The original command id is preserved as `sourceCommandId`.
   - Host device id, store id, branch id, store epoch, and sequence are stamped by the Host.

3. Cloud authoritative endpoint hardening.
   - `/api/sync/push` rejects payloads tagged as `draftCommand`.
   - Drafts must go through the Host relay inbox.

4. Cloud request relay hardening.
   - `/api/sync/requests/push` rejects payloads tagged as `authoritativeEvent`.
   - Authoritative events can only be published by the Host.

5. Client `Clear Local Data` lifecycle is stronger.
   - Clears local sync queue and local sync changes.
   - Clears cloud pull cursor.
   - Clears LAN pull cursor from saved LAN settings.
   - Preserves device identity so the Client does not become a different device accidentally.
   - Does not create or enqueue any sync deletion event.

6. Client `Rebuild From Host` over LAN now uses a full replacement snapshot.
   - `repairFromHostSnapshot` now calls `importSyncSnapshotJson` instead of merge.
   - Local sync changes are marked synced after the rebuild.
   - LAN cursor is reset to the Host snapshot generated time.

7. Data management buttons are now role-strict.
   - Host shows `Reset Data`.
   - Client shows `Clear Local Data` and `Rebuild From Host`.
   - Old LAN settings no longer make a Host accidentally show Client maintenance buttons.

## Still requires real-device validation

- Camera scanner behavior on Android/iOS.
- LAN Host/Client snapshot rebuild across two physical devices.
- Cloud pairing and `REQUIRE_DEVICE_TOKEN_AUTH=true` after all devices are paired.
- Full regression through `flutter analyze` and `flutter test` on a machine with Flutter SDK.

## Local checks performed here

- Node syntax check passed for API files.
- Lightweight source checks confirmed the new guards and metadata are present.

Flutter SDK is not available in this execution environment, so Flutter analyzer/tests must be run locally.
