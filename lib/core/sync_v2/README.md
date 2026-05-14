# Sync V2 Contract

Ventio now treats local client writes as draft commands and Host output as authoritative events.

- Clients never publish authoritative events.
- LAN and Cloud use the same command/event vocabulary.
- Cloud is only an inbox for client commands and a mirror for Host events.
- Device authorization is per-device: `deviceId + deviceToken + role + transport + revoked`.
