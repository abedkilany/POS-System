import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/models/manufacturing.dart';

import 'phase5_manufacturing_transfer_test.dart' as support;

void main() {
  test(
      'manufacturing reversal restores stock, reverses journal, and is idempotent',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
        id: 'raw-reverse', code: 'RAW-R', stock: 0, cost: 3));
    await store.addOrUpdateProduct(support.phase5Product(
        id: 'fg-reverse', code: 'FG-R', stock: 0, cost: 0));
    final raw = await store.createWarehouse(name: 'Raw reverse', code: 'RR');
    final finished =
        await store.createWarehouse(name: 'Finished reverse', code: 'FR');
    await store.adjustStock(
      productId: 'raw-reverse',
      warehouseId: raw.id,
      quantityDelta: 10,
      reason: 'Opening',
    );
    final bom = await store.createBillOfMaterials(
      name: 'Reverse BOM',
      outputProductId: 'fg-reverse',
      outputQuantity: 1,
      components: const <BillOfMaterialsLine>[
        BillOfMaterialsLine(
            productId: 'raw-reverse', productName: 'Raw reverse', quantity: 2),
      ],
    );
    final openingLedger = await AccountingService.generalLedgerReport();
    final openingBalances = <String, double>{
      for (final account in openingLedger)
        account.accountId: account.closingBalance,
    };
    final completed = await store.completeManufacturingOrder(
      bomId: bom.id,
      quantity: 1,
      rawMaterialsWarehouseId: raw.id,
      finishedGoodsWarehouseId: finished.id,
      wasteQuantities: const <String, double>{'raw-reverse': 0.5},
    );
    final reversed = await store.reverseManufacturingOrder(
      orderId: completed.id,
      reason: 'Incorrect production run',
    );
    expect(reversed.status, 'reversed');
    expect(reversed.reversalJournalEntryId, isNotEmpty);
    expect(reversed.reversalReason, 'Incorrect production run');
    expect(
      await support.sqliteWarehouseQuantity(
        productId: 'raw-reverse',
        warehouseId: raw.id,
        storeId: store.appIdentity.storeId,
      ),
      closeTo(10, 0.0001),
    );
    expect(
      await support.sqliteWarehouseQuantity(
        productId: 'fg-reverse',
        warehouseId: finished.id,
        storeId: store.appIdentity.storeId,
      ),
      closeTo(0, 0.0001),
    );
    final db = SqliteMigrationManager.database!;
    final reversalLinks = await db.customSelect('''
      SELECT COUNT(*) AS count FROM stock_movements
      WHERE reference_id = ? AND reversal_of_movement_id != ''
    ''', variables: <Variable<Object>>[
      Variable<String>(completed.id),
    ]).getSingle();
    expect(reversalLinks.read<int>('count'), 2);

    final retried = await store.reverseManufacturingOrder(
      orderId: completed.id,
      reason: 'Retry',
    );
    expect(retried.reversalJournalEntryId, reversed.reversalJournalEntryId);
    final ledger = await AccountingService.generalLedgerReport();
    for (final account in ledger) {
      // Manufacturing reversal must restore the ledger baseline, including
      // any opening inventory adjustment that predates the order.
      expect(
        account.closingBalance,
        closeTo(openingBalances[account.accountId] ?? 0, 0.0001),
      );
    }
  });
}
