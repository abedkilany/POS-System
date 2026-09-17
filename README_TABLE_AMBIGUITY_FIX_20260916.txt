Ventio - Manufacturing Table ambiguity analyzer fix
Date: 2026-09-16

Baseline:
Apply this patch on top of the latest Ventio project that already includes:
- Manufacturing negative-stock fix
- PostedDocumentSnapshot analyze fix
- Zero-cost manufacturing batch fix

Change:
lib/data/app_store_manufacturing.dart

At the customUpdate used by zero-cost batch repair, changed:
  updates: const <TableInfo<Table, Object?>>{},
to:
  updates: const {},

Reason:
The AppStore library imports both package:drift/drift.dart and package:flutter/material.dart.
Both expose a symbol named Table, so the explicit generic type caused analyzer error ambiguous_import.
The customUpdate parameter provides sufficient contextual typing, so the empty set can be inferred safely without naming Table.

No manufacturing/accounting behavior was changed by this patch.

After applying, run:
  flutter analyze
