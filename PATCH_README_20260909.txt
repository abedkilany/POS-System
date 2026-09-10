Ventio Unified Batch / Negative Stock hardening patch — 2026-09-09

Apply this patch over the exact baseline:
Ventio_FIXED_UnifiedBatch_Printing_20260908(1).zip

This patch contains application/source changes only.
NO database file is included or modified.
NO font file is included. Keep your existing assets/fonts and other private assets.

Main changes:
- Phase 4 cutover fail-closed state and blocked valuation guard
- Batch identity enforcement after cutover
- Deficit-aware reverse/edit path
- Physical-only warehouse transfers and manufacturing
- Sync guards against deficit transfer/manufacturing and out-of-order deficit reversals
- BOM estimated cost from Unified Batch
- Legacy cutover cost fallback scoped by warehouse
- Arabic/English/French batch error translations

See VENTIO_UNIFIED_BATCH_HARDENING_REPORT_20260909.md for details and validation results.
