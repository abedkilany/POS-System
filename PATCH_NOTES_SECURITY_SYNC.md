# Security & Sync Patch Notes

This build includes the requested review fixes focused on safe synchronization and production hardening.

## Sync fixes
- Remote delete changes are now applied consistently for products, customers, suppliers, expenses, categories, brands, units, and sales.
- Cloud pull now filters both `sync_events` and `entity_snapshots` by `store_id` and `branch_id`.
- Cloud request acknowledgements now require `storeId` and only mark requests as accepted when `id`, `store_id`, and `branch_id` all match.
- Cloud materialized snapshots are now branch-scoped using `(store_id, branch_id, entity_type, entity_id)`.
- Neon schema and rebuild/backfill SQL scripts were updated for branch-scoped snapshots.

## Backup security
- New encrypted backups now use a random salt, random nonce, SHA-256 stream keystream, 100000-round key derivation, and HMAC-SHA256 authentication.
- Old encrypted backup files remain readable for backward compatibility.
- Backup password minimum length increased from 6 to 8 characters.

## Deployment/API hardening
- Legacy Next/Vercel API route filtering was updated to include branch scoping.
- Existing JS Vercel serverless endpoints were syntax-checked with Node.

## Notes
- For an existing Neon database, run `database/neon_sync_schema.sql` again or manually apply the `branch_id` migration before deploying this version.
- If you have old snapshots, run `database/neon_rebuild_snapshots_from_events.sql` after the schema migration.
- Flutter/Dart SDK was not available in this environment, so `flutter analyze` was not executed here.
