# Sync / Backup Host Guard Patch

Applied changes:

1. Manual Backup Export now exports business data only and does not include device identity or sync queues.
2. Manual Import keeps the current device identity, Store ID, role, cloud token, and sync settings.
3. Manual Import clears the cloud pull cursor so clients can pull a fresh state after restore.
4. Cloud Host settings now validate that no other active Host exists for the same Store/Branch before saving Host mode.
5. The Vercel Host heartbeat API now rejects a second fresh Host with HTTP 409.
6. Web cloud settings now include an explicit HOST / CLIENT selector.
7. Pending sync count now uses the queue count rather than stale unsynced changes.
8. Cloud request ACK now sends branchId to avoid unacknowledged relay requests on non-default branches.
9. Auto cloud sync debounce was increased from 1s to 3s to reduce UI/network churn after rapid edits.

Important usage rule:
- Use one Host only. Import Backup on the Host, then let Clients sync.
