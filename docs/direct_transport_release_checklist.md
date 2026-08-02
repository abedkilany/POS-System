# Direct Transport Release Checklist

This document closes the remaining operational work for the Direct transport
without treating an untested deployment as production-ready.

## Phase 6: TURN and ICE

Configure the API deployment with:

- `TURN_SERVER_URLS`: comma- or space-separated `turn:` URLs.
- `TURN_SHARED_SECRET`: the shared secret used by the TURN server.

The API endpoint `/api/sync/ice-config` returns one-hour, device-scoped
credentials. The client combines these servers with saved STUN/TURN settings.
If TURN is not configured, Direct continues with its configured STUN and host
candidates.

## Phase 7: Recovery

When Direct sync fails, the automatic Direct controller clears the failed
session and attempts Direct if the identity is Direct-enabled and Direct settings
are configured. The active transport is not silently changed; the fallback is
an availability path only.

## Phase 8: Device management

- Pair each device through the normal single-use pairing flow.
- Confirm public-key registration for Host and Client.
- Revoke or suspend a device from the device-management surface before
  removing its credentials.
- Re-pair a device after a key reset or secure-storage wipe.

## Phase 9: Network test matrix

Run Direct pairing and sync under:

1. Same LAN.
2. Two independent home routers.
3. Symmetric or restrictive NAT with TURN enabled.
4. A firewall that blocks UDP but allows TCP/TLS TURN.
5. Temporary Internet loss followed by recovery.

Record the selected ICE path (`host`, `srflx`, or `relay`), recovery time, and
whether Direct fallback was used.

## Phase 10: Release gate

Before release, require Flutter tests, static analysis without errors, API
syntax checks, a Windows build, and one successful real-device run for each
supported platform. A deployment is not considered fully validated until the
network matrix above has been executed against the production TURN service.
