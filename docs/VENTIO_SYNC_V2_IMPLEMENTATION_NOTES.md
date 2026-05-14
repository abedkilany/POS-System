# Ventio Sync V2 Implementation Notes

This build moves the codebase toward the agreed Host-authoritative model:

1. The Host is the only authority that publishes accepted events to the Cloud mirror.
2. LAN Clients queue local draft changes to the Host target.
3. Cloud Clients queue local draft changes to the Cloud request inbox (`cloud_host`).
4. The Host pulls Cloud requests, applies them locally, and republishes accepted changes as authoritative Cloud events.
5. Clients receive Host/Cloud authoritative events through pull/snapshot repair.
6. Each device now carries a device-scoped token in `AppIdentity.deviceToken` so the server can validate `role + transport + revoked + device token` after re-pairing.
7. Cloud API endpoints remain backward-compatible unless `REQUIRE_DEVICE_TOKEN_AUTH=true` is enabled in Vercel.

Important migration note: keep `REQUIRE_DEVICE_TOKEN_AUTH=false` until every Client has opened the updated app and registered with `/api/sync/devices`, otherwise old devices will not have a stored `device_token` and will be rejected.
