import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/models/manufacturing.dart';

import 'phase5_manufacturing_transfer_test.dart' as support;

void main() {
  test('actual manufacturing cost flows Raw to WIP to Finished with waste',
      () async {
    final store = await support.readyPhase5SqliteStore();
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'raw-accounting',
      code: 'RAW-A',
      name: 'Actual Raw',
      stock: 0,
      cost: 2,
    ));
    await store.addOrUpdateProduct(support.phase5Product(
      id: 'fg-accounting',
      code: 'FG-A',
      name: 'Actual Finished',
      stock: 0,
      cost: 0,
    ));
    final rawWarehouse = await store.createWarehouse(name: 'Raw A', code: 'RA');
    final finishedWarehouse =
        await store.createWarehouse(name: 'Finished A', code: 'FA');
    await store.adjustStock(
      productId: 'raw-accounting',
      warehouseId: rawWarehouse.id,
      quantityDelta: 10,
      reason: 'Opening raw inventory',
    );
    final bom = await store.createBillOfMaterials(
      name: 'Accounting BOM',
      outputProductId: 'fg-accounting',
      outputQuantity: 1,
      components: const <BillOfMaterialsLine>[
        BillOfMaterialsLine(
          productId: 'raw-accounting',
          productName: 'Actual Raw',
          quantity: 4,
          unitCost: 999,
        ),
      ],
    );
    final started = await store.startManufacturingOrder(
      bomId: bom.id,
      quantity: 1,
      rawMaterialsWarehouseId: rawWarehouse.id,
      finishedGoodsWarehouseId: finishedWarehouse.id,
    );
    final completed = await store.finishManufacturingOrder(
      orderId: started.id,
      actualQuantity: 1,
      actualConsumedQuantities: const <String, double>{'raw-accounting': 4},
      wasteQuantities: const <String, double>{'raw-accounting': 1},
      wasteReasons: const <String, String>{'raw-accounting': 'Trim loss'},
    );

    expect(completed.totalMaterialCost, closeTo(8, 0.0001));
    expect(completed.totalWasteCost, closeTo(2, 0.0001));
    expect(completed.totalEligibleCost, closeTo(6, 0.0001));
    expect(completed.actualUnitCost, closeTo(6, 0.0001));
    expect(completed.materialCosts.single.unitCost, closeTo(2, 0.0001));
    expect(completed.wasteLines.single.reason, 'Trim loss');
    expect(completed.journalEntryId, isNotEmpty);

    final db = SqliteMigrationManager.database!;
    final totals = await db.customSelect('''
      SELECT SUM(debit) AS debit, SUM(credit) AS credit
      FROM journal_lines WHERE entry_id = ?
    ''', variables: <Variable<Object>>[
      Variable<String>(completed.journalEntryId),
    ]).getSingle();
    expect((totals.data['debit'] as num).toDouble(), closeTo(16, 0.0001));
    expect((totals.data['credit'] as num).toDouble(), closeTo(16, 0.0001));

    final rawAccount =
        await AccountingService.resolveAccountRole('inventory_raw');
    final wipAccount =
        await AccountingService.resolveAccountRole('inventory_wip');
    final finishedAccount =
        await AccountingService.resolveAccountRole('inventory_finished');
    final wasteAccount =
        await AccountingService.resolveAccountRole('manufacturing_waste');
    final lines = await db.customSelect('''
      SELECT account_id, SUM(debit) AS debit, SUM(credit) AS credit
      FROM journal_lines WHERE entry_id = ? GROUP BY account_id
    ''', variables: <Variable<Object>>[
      Variable<String>(completed.journalEntryId),
    ]).get();
    Map<String, Object?> line(String id) =>
        lines.firstWhere((row) => row.data['account_id'] == id).data;
    expect((line(rawAccount)['credit'] as num).toDouble(), closeTo(8, 0.0001));
    expect((line(wipAccount)['debit'] as num).toDouble(), closeTo(8, 0.0001));
    expect((line(wipAccount)['credit'] as num).toDouble(), closeTo(8, 0.0001));
    expect(
        (line(finishedAccount)['debit'] as num).toDouble(), closeTo(6, 0.0001));
    expect((line(wasteAccount)['debit'] as num).toDouble(), closeTo(2, 0.0001));

    final retried = await store.finishManufacturingOrder(
      orderId: started.id,
      actualQuantity: 1,
    );
    expect(retried.journalEntryId, completed.journalEntryId);
    final originalMovementCount = await db.customSelect('''
      SELECT COUNT(*) AS count FROM stock_movements
      WHERE reference_id = ? AND reversal_of_movement_id = ''
    ''', variables: <Variable<Object>>[
      Variable<String>(completed.id),
    ]).getSingle();
    expect(originalMovementCount.read<int>('count'), 2);
  });
}
