# Ventio Logo Asset Compaction — 2026-09-16

## Scope
This patch is intentionally limited to the repeated store-logo payload that was inflating posted document snapshots. It does not redesign audit-log retention or sync-event retention.

## Behavior
- StoreProfile keeps the active logo once in `logoDataBase64` and identifies it with a SHA-256 content id (`logoAssetId`).
- When the logo changes, the previous logo is moved once into `historicalLogoAssetsBase64`, keyed by its content id.
- Posted document snapshots no longer embed `logoDataBase64` or the historical logo registry. They freeze only `logoAssetId` and the small logo metadata.
- PDF/thermal rendering resolves the historical logo from the active/historical StoreProfile asset registry, so changing the logo does not alter old posted documents.
- Incoming StoreProfile replacements/sync merges preserve already-known historical logo assets.

## Legacy database migration
At SQLite startup Ventio performs an idempotent logo-only compaction:
- strips embedded logo base64 from existing `sales.posted_snapshot_json`;
- strips embedded logo base64 from existing `purchases.posted_snapshot_json`;
- strips embedded logo base64 from posted snapshots inside `credit_notes_v1`;
- collects any distinct historical logos into StoreProfile once;
- upgrades affected snapshot schema to v3;
- attempts WAL checkpoint + VACUUM when more than 1 MiB was reclaimed.

Audit logs and historical sync payloads are deliberately not rewritten by this patch because those areas have separate integrity/retention concerns and were left for later discussion.

## Regression coverage added
`test/posted_document_snapshot_test.dart` now covers:
- posted snapshot JSON contains a logo asset id but not base64;
- old posted documents resolve their original logo after the live store logo changes;
- each unique historical logo is stored only once.

## Validation performed in this workspace
The repaired production DB was compacted with the same rules:
- size before: 68,792,320 bytes;
- size after VACUUM: 47,194,112 bytes;
- reduction: 21,598,208 bytes (~31.4%);
- 102 sales snapshots compacted;
- 5 received purchase snapshots compacted;
- 5 credit-note snapshots compacted (stored in both settings mirrors);
- only 1 unique logo was found;
- `PRAGMA integrity_check = ok`;
- sales/purchase counts and financial totals unchanged;
- audit logs, sync events, pending sync changes, warehouse inventory, inventory batches, costing history, and reconciliation rows remained byte-for-byte unchanged.

Flutter/Dart SDK is not installed in this execution environment, so the added Dart tests could not be executed here. Static contract checks were performed and the database migration was executed and verified against the production copy.
