# POS Sync Architecture v2 - Host Authority

This version changes sync from multi-master to Host-authoritative.

## Rules

1. The Host device is the only source of truth.
2. LAN clients send changes to the Host via `/changes/push`.
3. Web/remote clients send change requests to Cloud relay `/api/sync/requests/push`.
4. The Host pulls remote requests from `/api/sync/requests/pull`, applies them locally, then republishes accepted changes to `/api/sync/push` as authoritative events.
5. Cloud stores two things:
   - `sync_events`: authoritative Host-published events and snapshots.
   - `cloud_change_requests`: pending remote/web client requests waiting for Host acceptance.
6. New/returning devices hydrate from Cloud snapshots/events, which are mirrors of Host state.

## Required Neon migration

Run `database/neon_sync_schema.sql` again. It is idempotent and will add the `cloud_change_requests` table.

## Required device setup

- Main shop machine: Device Role = Host, Sync Mode = Cloud Connected if remote/web devices are used.
- LAN machines: Device Role = Client, Sync Mode = LAN Only or Cloud Connected, but their writes go to Host over LAN.
- Browser/remote devices: Device Role = Client, Sync Mode = Cloud Connected. Their writes go to the Host relay inbox.

## Important behavior

A remote browser may show its local edit immediately, but that edit is not authoritative until the Host comes online, pulls the request, applies it, and publishes it back to Cloud.
