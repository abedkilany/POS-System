Ventio Manufacturing Zero-Cost Batch Fix - 2026-09-16

BASELINE REQUIRED:
Ventio_Manufacturing_NegativeStock_Fix_AnalyzeFixed_20260916 (the latest source package supplied immediately before this patch).

HOW TO APPLY:
1. Close Ventio and stop any running Flutter process.
2. Back up the current project folder.
3. Extract this ZIP directly over the current project root, preserving folders and replacing matching files.
4. Do NOT delete or replace your existing assets/fonts directory; this patch intentionally contains no font files.
5. Run:
   flutter analyze
6. Then run at minimum:
   flutter test test/phase5_manufacturing_transfer_test.dart
7. Start Ventio using the latest operational database and retry MFG-1105619325.

EXPECTED FOR THE SUPPLIED DATABASE:
- Existing 0.50 kg zero-cost inventory-count Batch for كاجو مشوي is detected.
- Because it has no prior outbound consumption, Ventio safely repairs its Batch cost.
- Historical positive Unified Batch cost 12.763596004439512 USD/kg is preferred over Product Master reference cost 11.50 USD/kg.
- A matching inventory_batch_revaluation journal is posted before manufacturing.
- 0.48 kg consumption then carries about 6.126526 USD into the finished product.

See MANUFACTURING_ZERO_COST_BATCH_FIX_20260916.md for full details.
