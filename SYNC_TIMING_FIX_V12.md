# Sync Timing Fix v12

Fixes a Host Authority timing issue where the Host accepted a Client draft but kept the draft's original Client `createdAt` timestamp.

Because LAN and Cloud delta pulls use cursors, another Client whose cursor was already newer than that original timestamp could miss the accepted event and only receive it after a later path, making propagation look like ~20 seconds even when all devices were set to 5 seconds.

The Host now restamps accepted remote drafts with the Host acceptance time before publishing them as authoritative events. The event id is preserved for idempotency.
