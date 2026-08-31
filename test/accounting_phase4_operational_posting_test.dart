import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';

import 'support/test_business_session_context.dart';

final _authorization = TestBusinessSessionContext();

Future<VentioDriftDatabase> _db() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  SqliteMigrationManager.useDatabaseForTesting(db);
  await AccountingService.updateDefaultVatRatePercent(0, authorization: _authorization);
  return db;
}

Future<List<Map<String, Object?>>> _entryLines(
  VentioDriftDatabase db,
  String referenceType,
  String referenceId,
) async {
  final rows = await db.customSelect(
    '''
    SELECT jl.account_id, jl.debit, jl.credit
    FROM journal_lines jl
    INNER JOIN journal_entries je ON je.id = jl.entry_id
    WHERE je.reference_type = ? AND je.reference_id = ?
      AND je.deleted_at = '' AND je.status = 'posted'
    ORDER BY jl.line_no
    ''',
    variables: <Variable<Object>>[
      Variable<String>(referenceType),
      Variable<String>(referenceId),
    ],
  ).get();
  return rows.map((row) => Map<String, Object?>.from(row.data)).toList();
}

void main() {
  late VentioDriftDatabase db;

  setUp(() async {
    db = await _db();
  });

  tearDown(() async {
    await SqliteMigrationManager.resetForTesting();
  });

  test('Phase 4 sale and purchase use semantic posting roles', () async {
    final sale = Sale(
      id: 'sale-phase4',
      invoiceNo: 'INV-P4-001',
      customerName: 'Phase 4 Customer',
      customerId: 'customer-p4',
      date: DateTime.utc(2026, 8, 23),
      status: 'Paid',
      items: const [
        SaleItem(
          productId: 'product-p4',
          productName: 'Phase 4 Product',
          unitPrice: 100,
          quantity: 1,
          unitCost: 40,
        ),
      ],
      discount: 0,
      paymentMethod: 'Credit',
      paymentStatus: 'unpaid',
      paidAmount: 0,
    );

    await AccountingService.recordSale(
      sale,
      paymentPostedSeparately: true,
    );

    final saleLines = await _entryLines(db, 'sale', sale.id);
    final saleAccounts =
        saleLines.map((line) => line['account_id']?.toString() ?? '').toSet();
    expect(
      saleAccounts,
      contains(
          await AccountingService.resolveAccountRole('accounts_receivable')),
    );
    expect(
      saleAccounts,
      contains(await AccountingService.resolveAccountRole('sales_revenue')),
    );
    expect(
      saleAccounts,
      contains(await AccountingService.resolveAccountRole('cogs')),
    );
    expect(
      saleAccounts,
      contains(
          await AccountingService.resolveAccountRole('inventory_merchandise')),
    );

    final purchase = Purchase(
      id: 'purchase-phase4',
      purchaseNo: 'PO-P4-001',
      supplierId: 'supplier-p4',
      supplierName: 'Phase 4 Supplier',
      date: DateTime.utc(2026, 8, 23),
      status: 'Received',
      items: const [
        PurchaseItem(
          productId: 'raw-p4',
          productName: 'Phase 4 Raw',
          quantity: 1,
          unitCost: 60,
        ),
      ],
      paymentStatus: 'unpaid',
      paymentMethod: 'Credit',
      paidAmount: 0,
    );

    expect(
      await AccountingService.recordPurchase(
        purchase,
        paymentPostedSeparately: true,
      ),
      isTrue,
    );
    final purchaseLines = await _entryLines(db, 'purchase', purchase.id);
    final purchaseAccounts = purchaseLines
        .map((line) => line['account_id']?.toString() ?? '')
        .toSet();
    expect(
      purchaseAccounts,
      contains(
          await AccountingService.resolveAccountRole('inventory_merchandise')),
    );
    expect(
      purchaseAccounts,
      contains(await AccountingService.resolveAccountRole('accounts_payable')),
    );
  });

  test('sale return posts to sales returns and reduces reported revenue',
      () async {
    final customReturns = await AccountingService.createAccount(
      code: '4188',
      name: 'مردودات مبيعات اختبار Phase 4',
      type: 'revenue',
      normalBalance: 'debit',
      parentId: 'acc_revenue',
    );
    await AccountingService.updateAccountRole(
      roleKey: 'sales_returns',
      accountId: customReturns.id,
    );

    final sale = Sale(
      id: 'sale-return-phase4',
      invoiceNo: 'INV-P4-RET',
      customerName: 'Return Customer',
      customerId: 'customer-ret-p4',
      date: DateTime.utc(2026, 8, 23),
      status: 'Paid',
      items: const [
        SaleItem(
          productId: 'product-return-p4',
          productName: 'Return Product',
          unitPrice: 100,
          quantity: 1,
          unitCost: 40,
        ),
      ],
      discount: 0,
      paymentMethod: 'Credit',
      paymentStatus: 'unpaid',
      paidAmount: 0,
    );

    await AccountingService.recordSale(
      sale,
      paymentPostedSeparately: true,
    );
    await AccountingService.recordSaleReturn(
      sale: sale,
      returnReferenceId: 'sale-return-p4-1',
      date: DateTime.utc(2026, 8, 23, 1),
      returnAmount: 20,
      returnCogs: 8,
    );

    final returnLines =
        await _entryLines(db, 'sale_return', 'sale-return-p4-1');
    final returnDebit = returnLines.firstWhere(
      (line) => line['account_id']?.toString() == customReturns.id,
    );
    expect((returnDebit['debit'] as num).toDouble(), 20);
    expect((returnDebit['credit'] as num).toDouble(), 0);

    final report = await AccountingService.incomeStatementReport();
    expect(report.revenue, 80);
    expect(report.costOfGoodsSold, 32);
    expect(report.grossProfit, 48);
  });

  test('sale discount posts to contra-revenue and nets VAT after discount',
      () async {
    final customDiscounts = await AccountingService.createAccount(
      code: '4189',
      name: 'خصومات مبيعات اختبار Phase 4',
      type: 'revenue',
      normalBalance: 'debit',
      parentId: 'acc_revenue',
    );
    await AccountingService.updateAccountRole(
      roleKey: 'sales_discounts',
      accountId: customDiscounts.id,
    );
    await AccountingService.updateDefaultVatRatePercent(10, authorization: _authorization);

    final sale = Sale(
      id: 'sale-discount-phase4',
      invoiceNo: 'INV-P4-DISC',
      customerName: 'Discount Customer',
      customerId: 'customer-disc-p4',
      date: DateTime.utc(2026, 8, 23),
      status: 'Paid',
      items: const [
        SaleItem(
          productId: 'product-disc-p4',
          productName: 'Discount Product',
          unitPrice: 110,
          quantity: 1,
          unitCost: 40,
        ),
      ],
      discount: 11,
      paymentMethod: 'Credit',
      paymentStatus: 'unpaid',
      paidAmount: 0,
    );

    await AccountingService.recordSale(
      sale,
      paymentPostedSeparately: true,
    );

    final lines = await _entryLines(db, 'sale', sale.id);
    final revenue = await AccountingService.resolveAccountRole('sales_revenue');
    final salesTax = await AccountingService.resolveAccountRole('sales_tax');
    final ar =
        await AccountingService.resolveAccountRole('accounts_receivable');

    double amountFor(String accountId, String side) {
      final line = lines.firstWhere(
        (item) => item['account_id']?.toString() == accountId,
      );
      return (line[side] as num).toDouble();
    }

    expect(amountFor(ar, 'debit'), 99);
    expect(amountFor(revenue, 'credit'), 100);
    expect(amountFor(customDiscounts.id, 'debit'), 10);
    expect(amountFor(salesTax, 'credit'), 9);
  });

  test('fully discounted sale still posts contra-revenue and inventory cost',
      () async {
    await AccountingService.updateDefaultVatRatePercent(10, authorization: _authorization);
    final sale = Sale(
      id: 'sale-full-discount-phase4',
      invoiceNo: 'INV-P4-FULL-DISC',
      customerName: 'Full Discount Customer',
      customerId: 'customer-full-disc-p4',
      date: DateTime.utc(2026, 8, 23),
      status: 'Paid',
      items: const [
        SaleItem(
          productId: 'product-full-disc-p4',
          productName: 'Full Discount Product',
          unitPrice: 110,
          quantity: 1,
          unitCost: 40,
        ),
      ],
      discount: 110,
      paymentMethod: 'Credit',
      paymentStatus: 'paid',
      paidAmount: 0,
    );

    await AccountingService.recordSale(
      sale,
      paymentPostedSeparately: true,
    );
    final lines = await _entryLines(db, 'sale', sale.id);
    final revenue = await AccountingService.resolveAccountRole('sales_revenue');
    final discounts =
        await AccountingService.resolveAccountRole('sales_discounts');
    final cogs = await AccountingService.resolveAccountRole('cogs');
    final inventory =
        await AccountingService.resolveAccountRole('inventory_merchandise');

    expect(
      lines.any((line) =>
          line['account_id']?.toString() == revenue &&
          (line['credit'] as num).toDouble() == 100),
      isTrue,
    );
    expect(
      lines.any((line) =>
          line['account_id']?.toString() == discounts &&
          (line['debit'] as num).toDouble() == 100),
      isTrue,
    );
    expect(
      lines.any((line) =>
          line['account_id']?.toString() == cogs &&
          (line['debit'] as num).toDouble() == 40),
      isTrue,
    );
    expect(
      lines.any((line) =>
          line['account_id']?.toString() == inventory &&
          (line['credit'] as num).toDouble() == 40),
      isTrue,
    );
  });

  test('expense types route through configurable detailed expense roles',
      () async {
    final customRent = await AccountingService.createAccount(
      code: '6118',
      name: 'إيجار مخصص اختبار Phase 4',
      type: 'expense',
      normalBalance: 'debit',
      parentId: 'acc_expenses',
    );
    await AccountingService.updateAccountRole(
      roleKey: 'rent_expense',
      accountId: customRent.id,
    );

    final expense = Expense(
      id: 'expense-rent-phase4',
      title: 'Rent',
      category: 'Office',
      amount: 50,
      date: DateTime.utc(2026, 8, 23),
      notes: '',
      status: 'Posted',
    );
    await AccountingService.recordExpenseOnCredit(expense);

    final lines = await _entryLines(db, 'expense', expense.id);
    final payable =
        await AccountingService.resolveAccountRole('accounts_payable');
    expect(
      lines.any((line) =>
          line['account_id']?.toString() == customRent.id &&
          (line['debit'] as num).toDouble() == 50),
      isTrue,
    );
    expect(
      lines.any((line) =>
          line['account_id']?.toString() == payable &&
          (line['credit'] as num).toDouble() == 50),
      isTrue,
    );

    final fallback = Expense(
      id: 'expense-custom-phase4',
      title: 'Legacy Custom Type',
      category: 'Legacy Custom Category',
      amount: 12,
      date: DateTime.utc(2026, 8, 23, 1),
      notes: '',
      status: 'Posted',
    );
    await AccountingService.recordExpenseOnCredit(fallback);
    final fallbackLines = await _entryLines(db, 'expense', fallback.id);
    final general =
        await AccountingService.resolveAccountRole('general_expense');
    expect(
      fallbackLines.any((line) =>
          line['account_id']?.toString() == general &&
          (line['debit'] as num).toDouble() == 12),
      isTrue,
    );
  });

  test('voucher posting uses AR/AP semantic roles and is idempotent', () async {
    final receiptId = await AccountingService.postVoucherPayment(
      database: db,
      voucherType: 'receipt',
      voucherId: 'rv-p4',
      voucherNo: 'RV-P4-001',
      date: DateTime.utc(2026, 8, 23),
      amount: 25,
      paymentMethod: 'bank',
      partyId: 'customer-voucher-p4',
      partyName: 'Voucher Customer',
    );
    expect(receiptId, isNotEmpty);

    final repeated = await AccountingService.postVoucherPayment(
      database: db,
      voucherType: 'receipt',
      voucherId: 'rv-p4',
      voucherNo: 'RV-P4-001',
      date: DateTime.utc(2026, 8, 23),
      amount: 25,
      paymentMethod: 'bank',
      partyId: 'customer-voucher-p4',
      partyName: 'Voucher Customer',
    );
    expect(repeated, receiptId);

    final receiptLines = await _entryLines(db, 'receipt_voucher', 'rv-p4');
    final ar =
        await AccountingService.resolveAccountRole('accounts_receivable');
    expect(
      receiptLines.any((line) =>
          line['account_id']?.toString() == ar &&
          (line['credit'] as num).toDouble() == 25),
      isTrue,
    );

    final count = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type = 'receipt_voucher' AND reference_id = 'rv-p4' AND deleted_at = '' AND status = 'posted'",
        )
        .getSingle();
    expect((count.data['c'] as num).toInt(), 1);

    final paymentId = await AccountingService.postVoucherPayment(
      database: db,
      voucherType: 'payment',
      voucherId: 'pv-p4',
      voucherNo: 'PV-P4-001',
      date: DateTime.utc(2026, 8, 23),
      amount: 30,
      paymentMethod: 'bank',
      partyId: 'supplier-voucher-p4',
      partyName: 'Voucher Supplier',
    );
    expect(paymentId, isNotEmpty);
    final ap = await AccountingService.resolveAccountRole('accounts_payable');
    final paymentLines = await _entryLines(db, 'payment_voucher', 'pv-p4');
    expect(
      paymentLines.any((line) =>
          line['account_id']?.toString() == ap &&
          (line['debit'] as num).toDouble() == 30),
      isTrue,
    );
  });
}
