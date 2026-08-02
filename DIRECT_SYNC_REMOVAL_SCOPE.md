# Direct Sync Removal Scope

## Decision

Ventio no longer uses Direct Sync as a data synchronization transport.
Shared business-data synchronization is supported through exactly two
transports:

- LAN for devices on the same local network.
- Direct for devices communicating through the Ventio VPS as a signaling and
  relay-assisted connection.

There are no Direct Sync devices that require migration.

## In scope for removal

- Direct Sync push, pull, snapshot, realtime, heartbeat, and maintenance flows.
- Direct Sync pairing and device-management flows.
- Direct Sync fallback from LAN or Direct.
- Direct Sync settings, queue targets, UI controls, and runtime controllers.
- Direct Sync-only server routes and authorization branches.
- Direct Sync-only tests, fixtures, and localization strings.

## Explicitly retained

- VPS connectivity required by Direct pairing, signaling, ICE/STUN/TURN
  configuration, and device authorization.
- LAN synchronization and LAN pairing.
- Direct synchronization and Direct recovery flows.
- Account authentication and subscription/account APIs that are not used to
  synchronize business data.
- Future direct-storage backup integrations, which must remain separate from
  synchronization and must not introduce a Direct Sync transport.

## Compatibility policy

Legacy persisted identities may still contain old Direct values. On read, they
must be normalized to a supported state (Direct or local-only) without making
an outbound Direct Sync request. No new Direct Sync value may be written.

Deprecated server endpoints may temporarily return HTTP 410 with
a retired endpoint response; they must not perform authorization, database mutation,
or synchronization work.

## Acceptance criteria for the next phases

1. No production app path constructs or calls a Direct Sync transport/service.
2. Direct never falls back to Direct Sync.
3. Client transport selection is limited to LAN or Direct.
4. Host transport configuration remains compatible with LAN and Direct.
5. VPS endpoints used by Direct remain available.
6. Direct-only endpoints and database branches are either removed or inert and
   return the documented 410 response.
7. `flutter analyze` and the complete test suite pass after each removal phase.
