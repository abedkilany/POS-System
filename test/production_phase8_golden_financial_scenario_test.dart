import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/sync_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/supplier.dart';
import 'package:ventio/models/tax_profile.dart';
import 'package:ventio/models/user_role.dart';

const _storeId = 'ST-GOLDEN-P8';
const _branchId = 'BR-GOLDEN-P8';
const _customerId = 'customer-golden-p8';
const _supplierId = 'supplier-golden-p8';
const _standardProductId = 'product-golden-standard-p8';
const _exemptProductId = 'product-golden-exempt-p8';
const _drawerCode = 'GOLD-P8';

Map<String, dynamic> _expected() => Map<String, dynamic>.from(
      jsonDecode(
        File('test/fixtures/production_phase8_golden_financial_expected.json')
            .readAsStringSync(),
      ) as Map,
    );

double _n(Map<String, dynamic> expected, String key) =>
    (expected[key] as num).toDouble();

Future<AppStore> _readyGoldenStore(VentioDriftDatabase db) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStorage = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async {
    switch (call.method) {
      case 'read':
        return secureStorage[call.arguments['key'] as String];
      case 'write':
        secureStorage[call.arguments['key'] as String] =
            call.arguments['value'] as String? ?? '';
        return null;
      case 'delete':
        secureStorage.remove(call.arguments['key'] as String);
        return null;
      case 'containsKey':
        return secureStorage.containsKey(call.arguments['key'] as String);
      case 'readAll':
        return secureStorage;
      case 'deleteAll':
        secureStorage.clear();
        return null;
    }
    return null;
  });

  await BusinessSqliteStore.markFreshInstallValidated(db);
  await SyncSqliteStore.markSyncMigrationCompleted(db);
  await LocalDatabaseService.useSqliteDatabaseForTesting(db);
  await LocalDatabaseService.initialize();

  final store = AppStore();
  await store.initialize();
  await store.recoverOnlineStoreOwnerIdentity(
    storeId: _storeId,
    branchId: _branchId,
    storeName: 'Golden Financial Store',
    username: 'owner',
    password: 'OwnerPass123',
    deviceRole: DeviceRole.host,
    syncMode: SyncMode.localOnly,
  );
  expect(await store.login('owner', 'OwnerPass123'), isTrue);
  await store.applySessionUser(
    activeUser: store.activeUser!,
    currentRole: 'Admin',
    permissions: Set<String>.from(AppPermission.all),
    rememberLogin: true,
  );
  await store.ensureHeavyDataLoaded(failOnError: true);
  return store;
}

Future<double> _roleSignedBalance(
  VentioDriftDatabase db,
  String roleKey,
) async {
  final accountId = await AccountingService.resolveAccountRole(roleKey);
  final row = await db.customSelect(
    '''
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
    FROM journal_lines jl
    INNER JOIN journal_entries je ON je.id = jl.entry_id
    WHERE jl.account_id = ?
      AND je.status IN ('posted', 'reversed')
      AND je.deleted_at = ''
    ''',
    variables: <Variable<Object>>[Variable<String>(accountId)],
  ).getSingle();
  return (row.data['balance'] as num? ?? 0).toDouble();
}

Future<double> _warehouseQuantity(
  VentioDriftDatabase db,
  String productId,
) async {
  final row = await db.customSelect(
    '''
    SELECT COALESCE(SUM(quantity), 0) AS quantity
    FROM warehouse_inventory
    WHERE store_id = ? AND product_id = ?
    ''',
    variables: <Variable<Object>>[
      const Variable<String>(_storeId),
      Variable<String>(productId),
    ],
  ).getSingle();
  return (row.data['quantity'] as num? ?? 0).toDouble();
}

Future<double> _inventorySubledgerValue(VentioDriftDatabase db) async {
  final row = await db.customSelect(
    '''
    SELECT COALESCE(SUM(ibb.quantity * ib.unit_cost), 0) AS value
    FROM inventory_batch_balances ibb
    INNER JOIN inventory_batches ib ON ib.id = ibb.batch_id
    WHERE ib.store_id = ?
    ''',
    variables: const <Variable<Object>>[Variable<String>(_storeId)],
  ).getSingle();
  return (row.data['value'] as num? ?? 0).toDouble();
}

Future<double> _purchaseBatchUnitCost(
  VentioDriftDatabase db, {
  required String purchaseId,
  required String productId,
}) async {
  final row = await db.customSelect(
    '''
    SELECT unit_cost
    FROM inventory_batches
    WHERE store_id = ? AND source_type = 'purchase'
      AND source_id = ? AND product_id = ?
    ORDER BY received_at, id
    LIMIT 1
    ''',
    variables: <Variable<Object>>[
      const Variable<String>(_storeId),
      Variable<String>(purchaseId),
      Variable<String>(productId),
    ],
  ).getSingle();
  return (row.data['unit_cost'] as num? ?? 0).toDouble();
}

void main() {
  test('production Phase 8 golden financial scenario closes to known balances',
      () async {
    final expected = _expected();

    await LocalDatabaseService.resetForTesting();
    await SqliteMigrationManager.resetForTesting();
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    final store = await _readyGoldenStore(db);
    addTearDown(() async {
      await store.prepareForShutdown();
      store.dispose();
      await LocalDatabaseService.resetForTesting();
      await SqliteMigrationManager.resetForTesting();
    });

    await store.updateTaxConfiguration(
      profiles: <TaxProfile>[
        TaxProfile.standardZero.copyWith(
          code: 'VAT',
          name: 'Standard VAT',
          ratePercent: _n(expected, 'vatRatePercent'),
        ),
        TaxProfile.zeroRated,
        TaxProfile.exempt,
      ],
      defaultTaxProfileId: TaxProfile.standardId,
    );

    await store.addOrUpdateCustomer(
      Customer(
        id: _customerId,
        name: 'Golden Customer',
        phone: '000',
        address: 'Beirut',
      ),
    );
    await store.addOrUpdateSupplier(
      Supplier(
        id: _supplierId,
        name: 'Golden Supplier',
        phone: '000',
        address: 'Beirut',
        notes: 'Production Phase 8 fixture',
      ),
    );
    await store.addOrUpdateProduct(
      Product(
        id: _standardProductId,
        name: 'Golden Standard VAT Item',
        code: 'GOLD-STD',
        price: 22,
        cost: 0,
        stock: 0,
        category: 'Golden',
        taxProfileId: TaxProfile.standardId,
      ),
    );
    await store.addOrUpdateProduct(
      Product(
        id: _exemptProductId,
        name: 'Golden Exempt Item',
        code: 'GOLD-EX',
        price: 10,
        cost: 0,
        stock: 0,
        category: 'Golden',
        taxProfileId: TaxProfile.exemptId,
      ),
    );

    await AccountingService.createCashLocation(
      name: 'Golden Drawer',
      type: 'cash_drawer',
      code: _drawerCode,
      isDefault: true,
      storeId: _storeId,
      branchId: _branchId,
      deviceId: store.deviceId,
      createdBy: 'owner',
    );
    final drawerRow = await db.customSelect(
      "SELECT id FROM cash_locations WHERE code = ? AND deleted_at = '' LIMIT 1",
      variables: const <Variable<Object>>[Variable<String>(_drawerCode)],
    ).getSingle();
    final drawerId = drawerRow.data['id']!.toString();
    await AccountingService.recordOpeningCashLocationBalance(
      cashLocationId: drawerId,
      amount: _n(expected, 'openingCash'),
      storeId: _storeId,
      branchId: _branchId,
      createdBy: 'owner',
      notes: 'Production Phase 8 opening cash',
    );
    await AccountingService.openCashDrawer(
      authorization: store,
      drawerNo: _drawerCode,
      openingBalance: _n(expected, 'openingCash'),
      cashLocationId: drawerId,
      openedBy: 'owner',
      openedByUserId: store.activeUser!.id,
      storeId: _storeId,
      branchId: _branchId,
      deviceId: store.deviceId,
    );
    final sessionRow = await db.customSelect(
      "SELECT id FROM cash_drawer_sessions WHERE cash_location_id = ? AND status = 'open' LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(drawerId)],
    ).getSingle();
    final sessionId = sessionRow.data['id']!.toString();

    final mainPurchase = await store.createPurchase(
      supplierId: _supplierId,
      supplierName: 'Golden Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: _standardProductId,
          productName: 'Golden Standard VAT Item',
          quantity: 10,
          unitCost: 11,
        ),
        PurchaseItem(
          productId: _exemptProductId,
          productName: 'Golden Exempt Item',
          quantity: 10,
          unitCost: 5,
        ),
      ],
    );
    expect(mainPurchase.subtotal, _n(expected, 'mainPurchaseGross'));
    expect(mainPurchase.postedSnapshot!.totals.tax,
        _n(expected, 'mainPurchaseInputVat'));

    // Exercise a complete purchase return before any downstream batch usage.
    // Its purchase + reversal must net to zero in the final golden balances.
    final returnPurchase = await store.createPurchase(
      supplierId: _supplierId,
      supplierName: 'Golden Supplier',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      items: const <PurchaseItem>[
        PurchaseItem(
          productId: _standardProductId,
          productName: 'Golden Standard VAT Item',
          quantity: 2,
          unitCost: 11,
        ),
      ],
    );
    await store.returnPurchase(
      returnPurchase.id,
      reason: 'Production Phase 8 golden purchase return',
    );

    await store.settlePurchasePayment(
      purchaseId: mainPurchase.id,
      amount: _n(expected, 'supplierPayment'),
      paymentMethod: 'Cash',
      notes: 'Golden supplier payment',
      idempotencyKey: 'golden-p8-supplier-payment',
    );

    final sale = await store.createSale(
      customerId: _customerId,
      customerName: 'Golden Customer',
      paymentMethod: 'Credit',
      paymentStatus: 'credit',
      discount: _n(expected, 'saleDiscountGross'),
      items: const <SaleItem>[
        SaleItem(
          productId: _standardProductId,
          productName: 'Golden Standard VAT Item',
          unitPrice: 22,
          quantity: 4,
        ),
        SaleItem(
          productId: _exemptProductId,
          productName: 'Golden Exempt Item',
          unitPrice: 10,
          quantity: 2,
        ),
      ],
    );
    expect(sale.subtotal, _n(expected, 'saleGrossBeforeDiscount'));
    expect(sale.total, _n(expected, 'saleReceivable'));
    expect(sale.postedSnapshot!.totals.tax,
        _n(expected, 'saleOutputVatAfterDiscount'));

    await store.settleSalePayment(
      saleId: sale.id,
      amount: _n(expected, 'customerReceipt'),
      paymentMethod: 'Cash',
      notes: 'Golden customer receipt',
      idempotencyKey: 'golden-p8-customer-receipt',
    );

    final creditNote = await store.returnSale(
      sale.id,
      returnedQuantities: const <String, double>{_standardProductId: 1},
    );
    expect(creditNote.amount, _n(expected, 'saleReturnGross'));
    expect(creditNote.postedSnapshot!.totals.tax,
        _n(expected, 'saleReturnVat'));

    await store.addOrUpdateExpense(
      Expense(
        id: 'expense-golden-rent-p8',
        title: 'Rent',
        category: 'Rent',
        amount: _n(expected, 'cashExpense'),
        date: DateTime.now(),
        notes: 'Production Phase 8 golden expense',
      ),
    );
    await store.postExpense('expense-golden-rent-p8', paidInCash: true);

    final cashRow = await db.customSelect(
      'SELECT current_balance FROM cash_locations WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(drawerId)],
    ).getSingle();
    final cashBalance = (cashRow.data['current_balance'] as num).toDouble();
    expect(cashBalance, closeTo(_n(expected, 'endingCash'), 0.000001));
    expect(
      await AccountingService.calculateCashDrawerExpectedCash(sessionId),
      closeTo(_n(expected, 'endingCash'), 0.000001),
    );

    expect(await _roleSignedBalance(db, 'accounts_receivable'),
        closeTo(_n(expected, 'endingAccountsReceivable'), 0.000001));
    expect(await _roleSignedBalance(db, 'accounts_payable'),
        closeTo(-_n(expected, 'endingAccountsPayable'), 0.000001));
    expect(await _roleSignedBalance(db, 'inventory_merchandise'),
        closeTo(_n(expected, 'endingInventory'), 0.000001));
    expect(await _roleSignedBalance(db, 'purchase_tax'),
        closeTo(_n(expected, 'endingInputVat'), 0.000001));
    expect(await _roleSignedBalance(db, 'sales_tax'),
        closeTo(-_n(expected, 'endingOutputVat'), 0.000001));
    expect(
      await _roleSignedBalance(db, 'sales_revenue'),
      closeTo(-_n(expected, 'saleRevenueBeforeDiscountNet'), 0.000001),
    );
    expect(
      await _roleSignedBalance(db, 'sales_discounts'),
      closeTo(_n(expected, 'saleDiscountNet'), 0.000001),
    );
    expect(
      await _roleSignedBalance(db, 'sales_returns'),
      closeTo(_n(expected, 'saleReturnNet'), 0.000001),
    );
    expect(await _roleSignedBalance(db, 'cogs'),
        closeTo(_n(expected, 'netCogs'), 0.000001));
    expect(await _roleSignedBalance(db, 'rent_expense'),
        closeTo(_n(expected, 'operatingExpense'), 0.000001));
    expect(await _roleSignedBalance(db, 'owner_capital'),
        closeTo(-_n(expected, 'openingCash'), 0.000001));

    expect(await _warehouseQuantity(db, _standardProductId),
        closeTo(_n(expected, 'endingStandardQuantity'), 0.000001));
    expect(await _warehouseQuantity(db, _exemptProductId),
        closeTo(_n(expected, 'endingExemptQuantity'), 0.000001));
    expect(await _inventorySubledgerValue(db),
        closeTo(_n(expected, 'endingInventory'), 0.000001));
    expect(
      await _purchaseBatchUnitCost(
        db,
        purchaseId: mainPurchase.id,
        productId: _standardProductId,
      ),
      closeTo(_n(expected, 'standardInventoryUnitCost'), 0.000001),
    );
    expect(
      await _purchaseBatchUnitCost(
        db,
        purchaseId: mainPurchase.id,
        productId: _exemptProductId,
      ),
      closeTo(_n(expected, 'exemptInventoryUnitCost'), 0.000001),
    );

    final allJournals = await db.customSelect(
      '''
      SELECT COALESCE(SUM(jl.debit), 0) AS debit,
             COALESCE(SUM(jl.credit), 0) AS credit
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      WHERE je.status = 'posted' AND je.deleted_at = ''
      ''',
    ).getSingle();
    final totalDebit = (allJournals.data['debit'] as num).toDouble();
    final totalCredit = (allJournals.data['credit'] as num).toDouble();
    expect(totalDebit, closeTo(totalCredit, 0.000001));

    final netSales = _n(expected, 'saleRevenueBeforeDiscountNet') -
        _n(expected, 'saleDiscountNet') -
        _n(expected, 'saleReturnNet');
    final grossProfit = netSales - _n(expected, 'netCogs');
    final netIncome = grossProfit - _n(expected, 'operatingExpense');
    expect(netSales, closeTo(_n(expected, 'netSales'), 0.000001));
    expect(grossProfit, closeTo(_n(expected, 'grossProfit'), 0.000001));
    expect(netIncome, closeTo(_n(expected, 'netIncome'), 0.000001));

    final incomeStatement = await AccountingService.incomeStatementReport();
    expect(incomeStatement.grossSales,
        closeTo(_n(expected, 'saleRevenueBeforeDiscountNet'), 0.000001));
    expect(incomeStatement.salesDiscounts,
        closeTo(_n(expected, 'saleDiscountNet'), 0.000001));
    expect(incomeStatement.salesReturns,
        closeTo(_n(expected, 'saleReturnNet'), 0.000001));
    expect(incomeStatement.netSales,
        closeTo(_n(expected, 'netSales'), 0.000001));
    expect(incomeStatement.costOfGoodsSold,
        closeTo(_n(expected, 'netCogs'), 0.000001));
    expect(incomeStatement.grossProfit,
        closeTo(_n(expected, 'grossProfit'), 0.000001));
    expect(incomeStatement.expenses,
        closeTo(_n(expected, 'operatingExpense'), 0.000001));
    expect(incomeStatement.netProfit,
        closeTo(_n(expected, 'netIncome'), 0.000001));

    final balanceSheet = await AccountingService.balanceSheetReport();
    expect(balanceSheet.assets,
        closeTo(_n(expected, 'endingAssets'), 0.000001));
    expect(balanceSheet.liabilities,
        closeTo(_n(expected, 'endingLiabilities'), 0.000001));
    expect(balanceSheet.equity,
        closeTo(_n(expected, 'endingEquity'), 0.000001));
    expect(balanceSheet.retainedEarnings,
        closeTo(_n(expected, 'endingRetainedEarnings'), 0.000001));
    expect(balanceSheet.liabilitiesAndEquity,
        closeTo(_n(expected, 'endingLiabilitiesAndEquity'), 0.000001));
    expect(balanceSheet.difference,
        closeTo(_n(expected, 'balanceSheetDifference'), 0.000001));
  });

  test('golden scenario uses application write paths and read-only SQL evidence',
      () {
    final source = File('test/production_phase8_golden_financial_scenario_test.dart')
        .readAsStringSync();
    final scenarioStart = source.indexOf(
      "test('production Phase 8 golden financial scenario closes to known balances'",
    );
    final scenarioEnd = source.indexOf(
      "test('golden scenario uses application write paths and read-only SQL evidence'",
      scenarioStart,
    );
    expect(scenarioStart, greaterThanOrEqualTo(0));
    expect(scenarioEnd, greaterThan(scenarioStart));
    final scenarioSource = source.substring(scenarioStart, scenarioEnd);
    for (final required in <String>[
      'store.createPurchase(',
      'store.returnPurchase(',
      'store.settlePurchasePayment(',
      'store.createSale(',
      'store.settleSalePayment(',
      'store.returnSale(',
      'store.addOrUpdateExpense(',
      'store.postExpense(',
      'AccountingService.createCashLocation(',
      'AccountingService.recordOpeningCashLocationBalance(',
      'AccountingService.openCashDrawer(',
      'calculateCashDrawerExpectedCash(',
      '_inventorySubledgerValue(',
      'journal_entries',
      'AccountingService.incomeStatementReport(',
      'AccountingService.balanceSheetReport(',
    ]) {
      expect(scenarioSource, contains(required), reason: required);
    }
    expect(source, contains('inventory_batch_balances'));
    for (final forbidden in <String>[
      '.customInsert(',
      '.customUpdate(',
      '.customDelete(',
      '.customStatement(',
      'INSERT INTO ',
      'UPDATE ',
      'DELETE FROM ',
    ]) {
      expect(scenarioSource, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
