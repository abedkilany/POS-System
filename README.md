# Ventio

Ventio is an offline-first sales, inventory, synchronization, and backup app.
Business data is synchronized between devices through LAN or Direct.

## Pure DB-First Contract

## Runtime contract

- SQLite is the source of truth for app state, business data, and settings.
- The Host is authoritative for shared business data.
- LAN is used inside the local network.
- Direct uses the VPS only for pairing, signaling, ICE configuration, and device authorization.
- The VPS is a control-plane relay for Direct pairing and signaling, not a business-data store.

See [PURE_DB_FIRST_CONTRACT.md](./PURE_DB_FIRST_CONTRACT.md) and
[SYNC_ARCHITECTURE_V2_HOST_AUTHORITY.md](./SYNC_ARCHITECTURE_V2_HOST_AUTHORITY.md).

## Current release

- Version: `1.0.19+19`
- Backup import supports JSON backups, local `.vtb` archives, and encrypted backup JSON.
- Local automatic backups are stored as `.vtb` archives containing `backup.json` and `manifest.json`.

## Production setup

Configure these values on the VPS deployment:

```bash
DATABASE_URL=postgresql://...
ACCOUNT_JWT_SECRET=choose-a-long-random-account-secret
ADMIN_JWT_SECRET=choose-a-different-long-random-admin-secret
VENTIO_API_ALLOWED_ORIGINS=https://your-app-domain.com
REQUIRE_DEVICE_TOKEN_AUTH=true
```

`ACCOUNT_JWT_SECRET` and `ADMIN_JWT_SECRET` are required and must be different.
The API uses short-lived access tokens with database-backed refresh sessions.
Changing either secret invalidates existing access tokens; users must sign in
again after a deployment that introduces this authentication contract.

The `/api` service provides Direct pairing, signaling, ICE configuration,
device authorization, and Host status. Business payloads move between the
Host and Client over LAN or the Direct peer channel.

## Backup and restore

- Exported backups are JSON.
- Local automatic backups use `.vtb` archives.
- The restore flow accepts both formats and can prompt for a password for encrypted backups.
- Use the Host device for import and restore operations.

## Connecting devices

Each device has its own local identity. To connect devices to the same store,
use the Host pairing code through LAN or Direct. A Client must choose one
transport; a Host may expose both LAN and Direct.

## Deployment

1. Configure the VPS API and its production database.
2. Deploy the project.
3. Open Settings → Sync in the app.
4. Select LAN or Direct and complete Host pairing.

Retired transport endpoints return `LEGACY_SYNC_REMOVED` and cannot move business data.
