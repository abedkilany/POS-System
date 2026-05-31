# Sync fixes 4, 5, and 7 applied

## Fix #4 — Client Sync UI
- Client now shows a clear Active Transport selector.
- Client can keep LAN and Cloud settings visible/saved at the same time.
- Switching the active transport no longer removes the other transport settings.
- The generic "Connect to new host" action was removed from the Client UI; replacing a Host requires resetting local data and pairing again.

## Fix #5 — Transfer Host Role
- Approving a Host transfer no longer immediately converts the old Host to Client.
- Approval records an approved_pending_activation state.
- The new Host becomes Host only after explicit activation.
- Activation publishes HOST_CHANGED as an authoritative sync event.
- Clients, including the old Host when it receives HOST_CHANGED, update hostDeviceId and switch to the new Host.
- Snapshot creation is not forced during transfer.

## Fix #7 — Client Pairing UI
- Client pairing UI no longer exposes Host-only Active/Disabled pairing-code states.
- Client pairing focuses on scanning/entering a Host pairing code.
- Connect-to-different-Host is removed from normal Client UI to avoid accidental data replacement.
