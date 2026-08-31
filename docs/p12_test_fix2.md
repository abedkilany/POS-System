# P12 Test Fix 2 — Unified Batch translation contract

After the P12 translation cleanup, `settings_page.dart` intentionally stopped hardcoding the English `Unified Batch` title and description and now resolves both through translation keys.

The production behavior was correct, but `test/unified_batch_phase4_test.dart` still asserted the retired hardcoded widget source. The contract now verifies the translated title and description instead:

- `tr.text('unified_batch')`
- `tr.text('unified_batch_fixed_desc')`

No production logic, schema, accounting, inventory, security, or synchronization behavior changed in this fix.
