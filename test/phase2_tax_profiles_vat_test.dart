import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/posted_document_snapshot_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/credit_note.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/store_profile.dart';
import 'package:ventio/models/tax_profile.dart';

import 'support/test_business_session_context.dart';

final _authorization = TestBusinessSessionContext();

const _phase2Profile = StoreProfile(
  name: 'Phase 2 VAT Store',
  legalName: 'Phase 2 VAT Store SAL',
  phone: '01-000000',
  address: 'Beirut',
  currency: 'USD',
  footerNote: '',
  vatNumber: 'VAT-12345',
  baseCurrency: 'USD',
  taxProfiles: <TaxProfile>[
    TaxProfile(
      id: TaxProfile.standardId,
      code: 'VAT',
      name: 'Standard VAT',
      ratePercent: 10,
    ),
    TaxProfile.zeroRated,
    TaxProfile.exempt,
  ],
  defaultTaxProfileId: TaxProfile.standardId,
  taxConfigurationVersion: 1,
);

Map<String, String> get _mixedTaxMap => const <String, String>{
      'standard': TaxProfile.standardId,
      'zero': TaxProfile.zeroRatedId,
      'exempt': TaxProfile.exemptId,
    };

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

double _sideAmount(
  List<Map<String, Object?>> lines,
  String accountId,
  String side,
) {
  return lines
      .where((line) => line['account_id']?.toString() == accountId)
      .fold<double>(
        0,
        (sum, line) => sum + ((line[side] as num?)?.toDouble() ?? 0),
      );
}

void main() {
  test('tax calculator extracts inclusive VAT and preserves zero/exempt modes', () {
    final standard = TaxCalculator.inclusive(
      110,
      _phase2Profile.taxProfileById(TaxProfile.standardId),
    );
    final zero = TaxCalculator.inclusive(
      110,
      _phase2Profile.taxProfileById(TaxProfile.zeroRatedId),
    );
    final exempt = TaxCalculator.inclusive(
      110,
      _phase2Profile.taxProfileById(TaxProfile.exemptId),
    );

    expect(standard.taxableBase, 100);
    expect(standard.taxAmount, 10);
    expect(standard.ratePercent, 10);
    expect(standard.taxMode, 'standard');
    expect(zero.taxableBase, 110);
    expect(zero.taxAmount, 0);
    expect(zero.taxMode, 'zero_rated');
    expect(exempt.taxableBase, 110);
    expect(exempt.taxAmount, 0);
    expect(exempt.taxMode, 'exempt');
  });

  test('mixed sale freezes line VAT after proportional document discount', () {
    final sale = Sale(
      id: 'phase2-mixed-sale',
      invoiceNo: 'VAT-S-001',
      customerId: 'customer-vat',
      customerName: 'VAT Customer',
      date: DateTime.utc(2026, 8, 30),
      status: 'Paid',
      items: const <SaleItem>[
        SaleItem(
          productId: 'standard',
          productName: 'Standard item',
          unitPrice: 110,
          quantity: 1,
          unitCost: 40,
        ),
        SaleItem(
          productId: 'exempt',
          productName: 'Exempt item',
          unitPrice: 100,
          quantity: 1,
          unitCost: 30,
        ),
        SaleItem(
          productId: 'zero',
          productName: 'Zero-rated item',
          unitPrice: 50,
          quantity: 1,
          unitCost: 20,
        ),
      ],
      discount: 26,
      paymentMethod: 'Credit',
      paymentStatus: 'unpaid',
      invoiceCurrency: 'USD',
      paymentCurrency: 'USD',
      baseCurrency: 'USD',
      exchangeRateAtInvoice: 1,
      transactionAmount: 234,
      baseAmount: 234,
      paidAmount: 0,
    );

    final snapshot = PostedDocumentSnapshotService.forSale(
      sale: sale,
      profile: _phase2Profile,
      taxProfileIdByProductId: _mixedTaxMap,
    );

    expect(snapshot.currency.taxSchemaVersion, 2);
    expect(snapshot.totals.discount, 26);
    expect(snapshot.lines.fold<double>(0, (sum, line) => sum + line.lineDiscount),
        closeTo(26, 0.000001));
    expect(snapshot.totals.tax, 9);
    expect(snapshot.totals.grandTotal, 234);

    final standard = snapshot.lines[0];
    expect(standard.lineDiscount, 11);
    expect(standard.taxableBase, 90);
    expect(standard.taxAmount, 9);
    expect(standard.taxRate, 10);
    expect(standard.taxMode, 'standard');
    expect(standard.extra['taxProfileId'], TaxProfile.standardId);

    final exempt = snapshot.lines[1];
    expect(exempt.lineDiscount, 10);
    expect(exempt.taxableBase, 90);
    expect(exempt.taxAmount, 0);
    expect(exempt.taxMode, 'exempt');

    final zero = snapshot.lines[2];
    expect(zero.lineDiscount, 5);
    expect(zero.taxableBase, 45);
    expect(zero.taxAmount, 0);
    expect(zero.taxMode, 'zero_rated');
  });

  test('discount allocation stays exact at currency precision', () {
    final sale = Sale(
      id: 'phase2-rounding-sale',
      invoiceNo: 'VAT-S-RND',
      customerName: 'Rounding Customer',
      date: DateTime.utc(2026, 8, 30),
      status: 'Paid',
      items: const <SaleItem>[
        SaleItem(
          productId: 'standard',
          productName: 'A',
          unitPrice: 0.01,
          quantity: 1,
        ),
        SaleItem(
          productId: 'standard',
          productName: 'B',
          unitPrice: 0.01,
          quantity: 1,
        ),
        SaleItem(
          productId: 'standard',
          productName: 'C',
          unitPrice: 0.01,
          quantity: 1,
        ),
      ],
      discount: 0.02,
    );
    final snapshot = PostedDocumentSnapshotService.forSale(
      sale: sale,
      profile: _phase2Profile,
      taxProfileIdByProductId: _mixedTaxMap,
    );
    expect(
      snapshot.lines.fold<double>(0, (sum, line) => sum + line.lineDiscount),
      0.02,
    );
    expect(
      snapshot.lines.every(
        (line) => line.lineDiscount >= 0 && line.lineDiscount <= line.lineTotal,
      ),
      isTrue,
    );
  });

  test('frozen sale VAT drives accounting even after current VAT rate changes',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    SqliteMigrationManager.useDatabaseForTesting(db);
    addTearDown(SqliteMigrationManager.resetForTesting);

    final rawSale = Sale(
      id: 'phase2-frozen-sale',
      invoiceNo: 'VAT-S-002',
      customerId: 'customer-vat-2',
      customerName: 'Frozen VAT Customer',
      date: DateTime.utc(2026, 8, 30),
      status: 'Paid',
      items: const <SaleItem>[
        SaleItem(
          productId: 'standard',
          productName: 'Standard item',
          unitPrice: 110,
          quantity: 1,
          unitCost: 40,
        ),
      ],
      discount: 0,
      paymentMethod: 'Credit',
      paymentStatus: 'unpaid',
      paidAmount: 0,
    );
    final sale = rawSale.copyWith(
      postedSnapshot: PostedDocumentSnapshotService.forSale(
        sale: rawSale,
        profile: _phase2Profile,
        taxProfileIdByProductId: _mixedTaxMap,
      ),
    );

    // Deliberately make the live fallback rate different from the posted fact.
    await AccountingService.updateDefaultVatRatePercent(
      20,
      authorization: _authorization,
    );
    await AccountingService.recordSale(
      sale,
      paymentPostedSeparately: true,
    );

    final lines = await _entryLines(db, 'sale', sale.id);
    final ar = await AccountingService.resolveAccountRole('accounts_receivable');
    final revenue = await AccountingService.resolveAccountRole('sales_revenue');
    final salesTax = await AccountingService.resolveAccountRole('sales_tax');

    expect(_sideAmount(lines, ar, 'debit'), 110);
    expect(_sideAmount(lines, revenue, 'credit'), 100);
    expect(_sideAmount(lines, salesTax, 'credit'), 10);
  });

  test('mixed purchase posts net inventory plus frozen input VAT', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    SqliteMigrationManager.useDatabaseForTesting(db);
    addTearDown(SqliteMigrationManager.resetForTesting);

    final rawPurchase = Purchase(
      id: 'phase2-mixed-purchase',
      purchaseNo: 'VAT-P-001',
      supplierId: 'supplier-vat',
      supplierName: 'VAT Supplier',
      date: DateTime.utc(2026, 8, 30),
      status: 'Received',
      items: const <PurchaseItem>[
        PurchaseItem(
          lineId: 'purchase-standard',
          productId: 'standard',
          productName: 'Taxed raw material',
          quantity: 1,
          unitCost: 110,
        ),
        PurchaseItem(
          lineId: 'purchase-exempt',
          productId: 'exempt',
          productName: 'Exempt raw material',
          quantity: 1,
          unitCost: 100,
        ),
      ],
      paymentStatus: 'unpaid',
      paymentMethod: 'Credit',
      paidAmount: 0,
    );
    final purchase = rawPurchase.copyWith(
      postedSnapshot: PostedDocumentSnapshotService.forPurchase(
        purchase: rawPurchase,
        profile: _phase2Profile,
        taxProfileIdByProductId: _mixedTaxMap,
      ),
    );

    expect(purchase.postedSnapshot!.totals.tax, 10);
    expect(purchase.postedSnapshot!.lines[0].taxableBase, 100);
    expect(purchase.postedSnapshot!.lines[1].taxableBase, 100);

    await AccountingService.updateDefaultVatRatePercent(
      20,
      authorization: _authorization,
    );
    expect(
      await AccountingService.recordPurchase(
        purchase,
        paymentPostedSeparately: true,
      ),
      isTrue,
    );

    final lines = await _entryLines(db, 'purchase', purchase.id);
    final inventory =
        await AccountingService.resolveAccountRole('inventory_merchandise');
    final inputVat = await AccountingService.resolveAccountRole('purchase_tax');
    final ap = await AccountingService.resolveAccountRole('accounts_payable');

    expect(_sideAmount(lines, inventory, 'debit'), 200);
    expect(_sideAmount(lines, inputVat, 'debit'), 10);
    expect(_sideAmount(lines, ap, 'credit'), 210);
  });

  test('sale return reverses VAT from original posted line, not current rate',
      () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    SqliteMigrationManager.useDatabaseForTesting(db);
    addTearDown(SqliteMigrationManager.resetForTesting);

    final rawSale = Sale(
      id: 'phase2-return-origin',
      invoiceNo: 'VAT-S-RET',
      customerId: 'customer-return-vat',
      customerName: 'Return VAT Customer',
      date: DateTime.utc(2026, 8, 30),
      status: 'Paid',
      items: const <SaleItem>[
        SaleItem(
          productId: 'standard',
          productName: 'Return taxed item',
          unitPrice: 55,
          quantity: 2,
          unitCost: 20,
        ),
      ],
      discount: 0,
      paymentMethod: 'Credit',
      paymentStatus: 'unpaid',
      paidAmount: 0,
    );
    final originalSale = rawSale.copyWith(
      postedSnapshot: PostedDocumentSnapshotService.forSale(
        sale: rawSale,
        profile: _phase2Profile,
        taxProfileIdByProductId: _mixedTaxMap,
      ),
    );
    final creditNote = CreditNote(
      id: 'phase2-return-note',
      creditNoteNo: 'CN-VAT-001',
      originalSaleId: originalSale.id,
      originalInvoiceNo: originalSale.invoiceNo,
      customerName: originalSale.customerName,
      customerId: originalSale.customerId,
      date: DateTime.utc(2026, 8, 30, 1),
      items: const <SaleItem>[
        SaleItem(
          productId: 'standard',
          productName: 'Return taxed item',
          unitPrice: 55,
          quantity: 1,
          unitCost: 20,
        ),
      ],
      amount: 55,
    );
    final returnSnapshot = PostedDocumentSnapshotService.forSaleReturn(
      creditNote: creditNote,
      originalSale: originalSale,
      profile: _phase2Profile.copyWith(
        taxProfiles: <TaxProfile>[
          TaxProfile.standardZero.copyWith(ratePercent: 20),
          TaxProfile.zeroRated,
          TaxProfile.exempt,
        ],
        taxConfigurationVersion: 1,
      ),
      originalLineIndexes: const <int>[0],
      taxProfileIdByProductId: _mixedTaxMap,
    );

    expect(returnSnapshot.lines.single.taxableBase, 50);
    expect(returnSnapshot.lines.single.taxAmount, 5);
    expect(returnSnapshot.lines.single.taxRate, 10);
    expect(returnSnapshot.totals.tax, 5);

    await AccountingService.updateDefaultVatRatePercent(
      20,
      authorization: _authorization,
    );
    await AccountingService.recordSaleReturn(
      sale: originalSale,
      returnReferenceId: creditNote.id,
      date: creditNote.date,
      returnAmount: creditNote.amount,
      returnCogs: 20,
      returnedItems: creditNote.items,
      returnSnapshot: returnSnapshot,
    );

    final lines = await _entryLines(db, 'sale_return', creditNote.id);
    final salesReturns = await AccountingService.resolveAccountRole('sales_returns');
    final salesTax = await AccountingService.resolveAccountRole('sales_tax');
    final ar = await AccountingService.resolveAccountRole('accounts_receivable');

    expect(_sideAmount(lines, salesReturns, 'debit'), 50);
    expect(_sideAmount(lines, salesTax, 'debit'), 5);
    expect(_sideAmount(lines, ar, 'credit'), 55);
  });

  test('legacy backfill never invents unavailable historical VAT facts', () {
    final sale = Sale(
      id: 'phase2-legacy-sale',
      invoiceNo: 'LEGACY-VAT-1',
      customerName: 'Legacy Customer',
      date: DateTime.utc(2025, 1, 1),
      status: 'Paid',
      items: const <SaleItem>[
        SaleItem(
          productId: 'standard',
          productName: 'Legacy item',
          unitPrice: 110,
          quantity: 1,
        ),
      ],
      discount: 0,
    );

    final snapshot = PostedDocumentSnapshotService.forSale(
      sale: sale,
      profile: _phase2Profile,
      legacyBackfill: true,
      legacyDefaultVatRatePercent: 10,
      taxProfileIdByProductId: _mixedTaxMap,
    );

    expect(snapshot.legacyBackfill, isTrue);
    expect(snapshot.totals.tax, 0);
    expect(snapshot.lines.single.taxRate, 0);
    expect(snapshot.lines.single.taxAmount, 0);
    expect(snapshot.lines.single.taxMode, 'none');
    expect(snapshot.lines.single.extra['taxProfileId'], '');
    expect(sale.copyWith(postedSnapshot: snapshot).hasTaxBreakdown, isFalse);
  });

  test('tax profiles and product assignment survive JSON round-trip', () {
    final restoredProfile = StoreProfile.fromJson(_phase2Profile.toJson());
    expect(restoredProfile.taxConfigurationVersion, 1);
    expect(restoredProfile.defaultTaxProfileId, TaxProfile.standardId);
    expect(restoredProfile.taxProfiles, hasLength(3));
    expect(
      restoredProfile.taxProfileById(TaxProfile.standardId).ratePercent,
      10,
    );
    expect(
      restoredProfile.taxProfileById(TaxProfile.exemptId).treatment,
      TaxTreatment.exempt,
    );

    final now = DateTime.utc(2026, 8, 30);
    final product = Product(
      id: 'phase2-tax-product',
      name: 'Tax Product',
      code: 'TAX-001',
      price: 110,
      cost: 50,
      stock: 0,
      category: 'General',
      createdAt: now,
      updatedAt: now,
      taxProfileId: TaxProfile.exemptId,
    );
    final restoredProduct = Product.fromJson(product.toJson());
    expect(restoredProduct.taxProfileId, TaxProfile.exemptId);
  });

  test('SQLite product persistence round-trip keeps tax profile id', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 30);
    final product = Product(
      id: 'phase2-tax-sqlite-product',
      name: 'SQLite Tax Product',
      code: 'TAX-SQL-001',
      price: 110,
      cost: 50,
      stock: 0,
      category: 'General',
      createdAt: now,
      updatedAt: now,
      taxProfileId: TaxProfile.zeroRatedId,
    );
    await BusinessSqliteStore.upsertEntityPayloads(
      db,
      BusinessSqliteStore.productsKey,
      <Map<String, dynamic>>[product.toJson()],
    );
    final restored = await BusinessSqliteStore.readProductById(db, product.id);
    expect(restored?.taxProfileId, TaxProfile.zeroRatedId);
  });

  test('schema 33 keeps product tax profile persistence column', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    await db.initializeFoundation();
    addTearDown(db.close);

    expect(db.schemaVersion, 33);
    final columns = await db.customSelect("PRAGMA table_info('products')").get();
    expect(
      columns.map((row) => row.data['name']?.toString()).toSet(),
      contains('tax_profile_id'),
    );
  });
}
