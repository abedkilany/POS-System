# Auth sync force-login behavior

When a Client pulls authoritative users or roles from the Host through LAN/Cloud sync, Ventio now clears the current local login session and disables remembered login.

This makes the app return to the Login page so the operator must authenticate using the Host-provided user list and permissions.

Implemented in `AppStore.applyRemoteSyncChanges`:
- detects remote `user` events
- detects remote `role` events
- detects `restore_snapshot` payloads containing users/roles
- applies only on Clients, not Host
- clears `activeUserId` and `rememberLogin`
