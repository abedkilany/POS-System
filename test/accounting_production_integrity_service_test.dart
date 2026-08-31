import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/accounting_production_integrity_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';

import 'phase5_manufacturing_transfer_test.dart' as support;

void main() {
  test('production integrity gate detects an unbalanced posted journal', () async {
    await support.readyPhase5SqliteStore();
    final db = SqliteMigrationManager.database!;
    final account = await db.customSelect(
      "SELECT id FROM accounts WHERE deleted_at = '' AND is_active = 1 AND is_postable = 1 ORDER BY id LIMIT 1",
    ).getSingle();
    final accountId = account.read<String>('id');
    final now = DateTime.now().toUtc().toIso8601String();

    await db.customInsert(
      '''
      INSERT INTO journal_entries
        (id, entry_no, entry_date, reference_type, reference_id, reference_no,
         description, status, source, created_by, posted_at, created_at,
         updated_at, store_id, branch_id)
      VALUES ('closure-bad-je', 'CLOSURE-BAD-1', ?, 'closure_test',
              'closure-bad-ref', 'CLOSURE-BAD', 'forced imbalance',
              'posted', 'system', 'test', ?, ?, ?, '', '')
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO journal_lines
        (id, entry_id, line_no, account_id, debit, credit, created_at, updated_at)
      VALUES ('closure-bad-jl', 'closure-bad-je', 0, ?, 10, 0, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(accountId),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final report = await AccountingProductionIntegrityService(db).audit();
    expect(report.isProductionReady, isFalse);
    expect(
      report.issues.any((issue) => issue.code == 'unbalanced_or_empty_journal'),
      isTrue,
    );
  });

  test('production integrity detects semantic inventory account misclassification',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'semantic-mismatch-product',
      code: 'SEM-MISMATCH',
      stock: 0,
      cost: 2,
    ));
    final warehouse = await store.createWarehouse(
      name: 'Semantic mismatch',
      code: 'SEM',
    );
    await store.adjustStock(
      productId: 'semantic-mismatch-product',
      warehouseId: warehouse.id,
      quantityDelta: 5,
      reason: 'Semantic mismatch opening',
    );

    final db = SqliteMigrationManager.database!;
    final rawAccount =
        await AccountingService.resolveAccountRole('inventory_raw');
    final merchandiseAccount =
        await AccountingService.resolveAccountRole('inventory_merchandise');
    final now = DateTime.now().toUtc().toIso8601String();
    await db.customInsert(
      '''
      INSERT INTO journal_entries
        (id, entry_no, entry_date, reference_type, reference_id, reference_no,
         description, status, source, created_by, posted_at, created_at,
         updated_at, store_id, branch_id)
      VALUES ('semantic-mismatch-je', 'SEM-MISMATCH-1', ?,
              'semantic_mismatch_test', 'semantic-mismatch-ref', 'SEM-MISMATCH',
              'forced semantic inventory mismatch', 'posted', 'system', 'test',
              ?, ?, ?, '', '')
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customInsert(
      '''
      INSERT INTO journal_lines
        (id, entry_id, line_no, account_id, debit, credit, created_at, updated_at)
      VALUES ('semantic-mismatch-raw', 'semantic-mismatch-je', 1, ?, 10, 0, ?, ?),
             ('semantic-mismatch-merch', 'semantic-mismatch-je', 2, ?, 0, 10, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(rawAccount),
        Variable<String>(now),
        Variable<String>(now),
        Variable<String>(merchandiseAccount),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );

    final report = await AccountingProductionIntegrityService(db).audit();
    expect(
      report.issues.any((issue) => issue.code == 'inventory_gl_valuation_mismatch'),
      isFalse,
    );
    expect(
      report.issues.any((issue) =>
          issue.code == 'inventory_semantic_account_mismatch'),
      isTrue,
    );
  });

  test('Unified Batch gate detects warehouse quantity that no longer matches batches', () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'closure-batch-product',
      code: 'CLOSE-BATCH',
      stock: 0,
      cost: 2,
    ));
    final warehouse = await store.createWarehouse(
      name: 'Closure Batch',
      code: 'CBATCH',
    );
    await store.adjustStock(
      productId: 'closure-batch-product',
      warehouseId: warehouse.id,
      quantityDelta: 5,
      reason: 'Closure Batch opening',
    );

    final db = SqliteMigrationManager.database!;
    await db.customUpdate(
      'UPDATE warehouse_inventory SET quantity = quantity + 1 WHERE product_id = ? AND warehouse_id = ?',
      variables: <Variable<Object>>[
        const Variable<String>('closure-batch-product'),
        Variable<String>(warehouse.id),
      ],
    );

    final report = await AccountingProductionIntegrityService(db).audit();
    expect(report.isProductionReady, isFalse);
    expect(
      report.issues.any((issue) =>
          issue.code == 'unified_batch_quantity_mismatch' &&
          issue.entityId == 'closure-batch-product'),
      isTrue,
    );
  });
}
