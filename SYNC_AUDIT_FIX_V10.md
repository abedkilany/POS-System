# Sync Audit Fix v10

This build fixes several causes of partial / missing automatic sync:

1. Remote desktop Clients now queue their local changes to `cloud_host` when Cloud Sync is enabled. Previously only Web clients did this, so Windows clients outside the LAN could read cloud data but their edits never reached the Host.
2. Cloud Sync now pushes any pending `cloud_host` queue from non-Host clients, not only Web.
3. Bootstrap / restore snapshots received from Host no longer overwrite the local Client identity. Previously a Client could import the Host `appIdentity` and start behaving like the Host.
4. LAN delta pull cursor no longer jumps to current time when no changes are returned. This prevents missing Host changes created during the pull race window.
5. Cloud delta pull cursor no longer jumps forward on empty result sets, reducing the same race risk for Vercel/Neon sync.

Recommended test:
- HOST Windows: Cloud enabled + role Host.
- Remote Windows/Web: Cloud enabled + role Client + same Store ID.
- LAN Client: LAN-only or LAN client setup; it should queue to Host, not Cloud.
