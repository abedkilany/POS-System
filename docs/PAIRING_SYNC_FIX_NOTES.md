# Pairing Sync Fix Notes

This build fixes the cloud pairing flow where a Client could claim a pairing code and receive the Store ID/device token, but then remain Cloud offline and fail to pull or push data.

## Fixes

- Device-token authentication is now accepted by cloud sync endpoints even when `REQUIRE_DEVICE_TOKEN_AUTH` is not set.
- Endpoints that receive device credentials validate `deviceId + deviceToken + role + transport + revoked` through `assertDeviceAllowed`.
- Host pairing code creation now also queues/publishes the Host bootstrap snapshot and heartbeat so a newly paired Client can pull data immediately.
- Client `Join Store` now performs an immediate initial cloud sync after claiming the code.
- Client cloud auto-sync is enabled and the pull cursor is cleared after pairing so the initial snapshot can be downloaded.

## Recommended server setting

You can still set `REQUIRE_DEVICE_TOKEN_AUTH=true` later for strict mode after confirming all devices are paired. With this build, paired Clients can sync by device token without needing the shared Cloud token.
