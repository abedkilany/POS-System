# Ventio Phase 1 — Immutable Posted Document Snapshot

## Status
Implemented in code. Full `flutter analyze` and full test suite intentionally deferred per project decision.

## Implemented
- Added generic `PostedDocumentSnapshot` model with schema version, document metadata, frozen StoreProfile, party snapshot, currency snapshot, line snapshots, tax-ready fields, totals, audit metadata, legacyBackfill, and extensible extra data.
- Added `PostedDocumentSnapshotService` for posted sale, sale return, and purchase snapshots.
- Added snapshot fields to `Sale`, `Purchase`, and `CreditNote` serialization/copy paths.
- Sale posting now creates the snapshot inside the posting transaction before persistence.
- Purchase receive/posting paths now create snapshots inside their transaction before persistence.
- Sale-return creation now creates a historical snapshot.
- Added SQLite `posted_snapshot_json` storage for sales and purchases, loading and preservation logic.
- Existing non-empty snapshots are preserved when older payloads are written, preventing an old/snapshot-less payload from erasing an immutable historical snapshot.
- Added legacy backfill for posted sales and non-draft purchases with `legacyBackfill = true`.
- Added sale-return backfill/loading support in AppStore paths.
- Invoice PDF uses snapshot-derived sale + frozen StoreProfile when a snapshot exists.
- Purchase PDF uses snapshot-derived purchase + frozen StoreProfile when a snapshot exists.
- Thermal sale printing/virtual-printer rendering uses the snapshot-derived sale/profile.
- Added targeted snapshot tests for serialization/immutability behavior.

## Important design decisions
- Tax fields are present now but remain zero/none until Phase 2 defines Tax Profiles and VAT rules.
- `roundingAdjustment` remains zero in Phase 1; actual tax/currency rounding policy belongs to Phase 2.
- Legacy backfill does not attempt to invent unavailable historical data.

## Deferred verification
The current execution environment does not provide Flutter/Dart SDK, and the project decision is to postpone expensive verification. Therefore this phase is **code-complete but not release-verified** until the next agreed verification gate runs:
- `flutter analyze`
- targeted snapshot tests
- full Flutter tests
- migration tests
- PDF/thermal regression tests

## Next phase
Phase 2 — Tax Profiles, VAT, and legal invoice behavior.
