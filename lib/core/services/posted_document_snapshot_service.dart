import '../app_brand.dart';
import '../../models/app_user.dart';
import '../../models/customer.dart';
import '../../models/credit_note.dart';
import '../../models/posted_document_snapshot.dart';
import '../../models/purchase.dart';
import '../../models/purchase_item.dart';
import '../../models/product_costing.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../models/store_profile.dart';
import '../../models/supplier.dart';
import '../../models/tax_profile.dart';
import '../../models/user_role.dart';

class PostedDocumentSnapshotService {
  const PostedDocumentSnapshotService._();


  static StoreProfile profileForSale(
    Sale sale,
    StoreProfile currentProfile,
  ) =>
      sale.postedSnapshot?.frozenStoreProfile ?? currentProfile;

  static Sale saleView(Sale sale) {
    final snapshot = sale.postedSnapshot;
    if (snapshot == null || snapshot.documentType != 'sale_invoice') {
      return sale;
    }
    final snapshotItems = snapshot.lines
        .map((line) => SaleItem(
              productId: line.productId,
              productName: line.productName,
              unitPrice: line.unitPrice,
              quantity: line.quantity,
              unitName: line.unitName,
              baseQuantity: line.baseQuantity,
              conversionToBase: line.conversionToBase,
              unitCost: (line.extra['unitCost'] as num? ?? 0).toDouble(),
              costingMethodAtSale: InventoryCostingMethodJson.fromCode(
                line.extra['costingMethodAtSale']?.toString(),
              ),
              costCurrency: line.extra['costCurrency']?.toString() ?? 'USD',
              costExchangeRate:
                  (line.extra['costExchangeRate'] as num? ?? 1).toDouble(),
            ))
        .toList(growable: false);
    final extra = snapshot.extra;
    return sale.copyWith(
      invoiceNo: snapshot.documentNumber,
      customerId: snapshot.party.id,
      customerName: snapshot.party.name,
      date: snapshot.postedAt,
      status: snapshot.status,
      items: snapshotItems,
      discount: snapshot.totals.discount,
      originalDiscount:
          (extra['originalDiscount'] as num?)?.toDouble() ??
              snapshot.totals.discount,
      discountCurrency:
          extra['discountCurrency']?.toString() ?? snapshot.currency.baseCurrency,
      discountExchangeRateAtEntry:
          (extra['discountExchangeRateAtEntry'] as num? ?? 0).toDouble(),
      paymentMethod: snapshot.paymentMethod,
      paymentStatus: snapshot.paymentStatus,
      invoiceCurrency: snapshot.currency.documentCurrency,
      paymentCurrency: snapshot.currency.paymentCurrency,
      exchangeRateAtInvoice: snapshot.currency.exchangeRateAtDocument,
      exchangeRateAtPayment: snapshot.currency.exchangeRateAtPayment,
      transactionAmount:
          (extra['transactionAmount'] as num?)?.toDouble() ??
              snapshot.totals.grandTotal,
      baseAmount: snapshot.totals.baseAmount,
      paidBaseAmount: (extra['paidBaseAmount'] as num? ?? 0).toDouble(),
      exchangeDifferenceAmount:
          (extra['exchangeDifferenceAmount'] as num? ?? 0).toDouble(),
      returnedAmount: (extra['returnedAmount'] as num? ?? 0).toDouble(),
      paidAmount: snapshot.totals.paid,
      cashReceivedAmount:
          (extra['cashReceivedAmount'] as num? ?? 0).toDouble(),
      paidAmountInPaymentCurrency:
          (extra['paidAmountInPaymentCurrency'] as num? ?? 0).toDouble(),
      cashReceivedAmountInPaymentCurrency:
          (extra['cashReceivedAmountInPaymentCurrency'] as num? ?? 0)
              .toDouble(),
      note: snapshot.note,
      warehouseId: snapshot.warehouseId,
      warehouseName: snapshot.warehouseName,
    );
  }


  static StoreProfile profileForPurchase(
    Purchase purchase,
    StoreProfile currentProfile,
  ) =>
      purchase.postedSnapshot?.frozenStoreProfile ?? currentProfile;

  static Purchase purchaseView(Purchase purchase) {
    final snapshot = purchase.postedSnapshot;
    if (snapshot == null || snapshot.documentType != 'purchase_invoice') {
      return purchase;
    }
    final snapshotItems = snapshot.lines
        .map((line) => PurchaseItem(
              lineId: line.lineId,
              productId: line.productId,
              productName: line.productName,
              quantity: line.quantity,
              unitCost: line.unitPrice,
              purchaseUnitId:
                  line.extra['purchaseUnitId']?.toString() ?? 'base',
              purchaseUnitName: line.unitName,
              conversionToBase: line.conversionToBase,
              originalUnitCost:
                  (line.extra['originalUnitCost'] as num?)?.toDouble(),
              unitCostCurrency:
                  line.extra['unitCostCurrency']?.toString() ?? 'USD',
              exchangeRateAtEntry:
                  (line.extra['exchangeRateAtEntry'] as num? ?? 0).toDouble(),
            ))
        .toList(growable: false);
    return purchase.copyWith(
      purchaseNo: snapshot.documentNumber,
      supplierId: snapshot.party.id,
      supplierName: snapshot.party.name,
      date: snapshot.postedAt,
      status: snapshot.status,
      items: snapshotItems,
      note: snapshot.note,
      paymentStatus: snapshot.paymentStatus,
      paymentMethod: snapshot.paymentMethod,
      paidAmount: snapshot.totals.paid,
      warehouseId: snapshot.warehouseId,
      warehouseName: snapshot.warehouseName,
    );
  }

  static PostedDocumentSnapshot forSale({
    required Sale sale,
    required StoreProfile profile,
    Customer? customer,
    AppUser? user,
    UserRole? role,
    bool legacyBackfill = false,
    double? displayedPaidAmount,
    Map<String, String> taxProfileIdByProductId = const <String, String>{},
    double legacyDefaultVatRatePercent = 0,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    final frozenPaid = displayedPaidAmount ?? sale.paidAmount;
    final taxLines = _resolveTaxLines(
      grossLineAmounts:
          sale.items.map((item) => item.lineTotal).toList(growable: false),
      productIds:
          sale.items.map((item) => item.productId).toList(growable: false),
      profile: profile,
      taxProfileIdByProductId: taxProfileIdByProductId,
      discount: sale.discount,
      legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
      legacyBackfill: legacyBackfill,
      decimals: profile.currencyByCode(sale.baseCurrency).decimalPlaces,
    );
    final taxTotal = _sumTax(taxLines, profile.currencyByCode(sale.baseCurrency).decimalPlaces);
    return PostedDocumentSnapshot(
      schemaVersion: PostedDocumentSnapshot.currentSchemaVersion,
      documentType: 'sale_invoice',
      documentId: sale.id,
      documentNumber: sale.invoiceNo,
      postedAt: sale.date,
      createdFromAppVersion: AppBrand.version,
      legacyBackfill: legacyBackfill,
      storeProfile: _profile(profile),
      party: PostedPartySnapshot(
        id: sale.customerId,
        name: sale.customerName,
        phone: customer?.phone ?? '',
        address: customer?.address ?? '',
      ),
      currency: PostedCurrencySnapshot(
        baseCurrency: sale.baseCurrency,
        documentCurrency: sale.invoiceCurrency,
        paymentCurrency: sale.paymentCurrency,
        exchangeRateAtDocument: sale.exchangeRateAtInvoice,
        exchangeRateAtPayment: sale.exchangeRateAtPayment,
        priceStorageDecimals: profile.priceStorageDecimals,
        taxSchemaVersion: 2,
      ),
      lines: <PostedDocumentLineSnapshot>[
        for (var index = 0; index < sale.items.length; index += 1)
          PostedDocumentLineSnapshot(
            lineId: '${sale.id}-line-$index',
            productId: sale.items[index].productId,
            productName: sale.items[index].productName,
            unitName: sale.items[index].unitName,
            quantity: sale.items[index].quantity,
            baseQuantity: sale.items[index].effectiveBaseQuantity,
            conversionToBase: sale.items[index].conversionToBase,
            unitPrice: sale.items[index].unitPrice,
            lineDiscount: taxLines[index].lineDiscount,
            lineTotal: sale.items[index].lineTotal,
            taxCode: taxLines[index].tax.taxCode,
            taxRate: taxLines[index].tax.ratePercent,
            taxableBase: taxLines[index].tax.taxableBase,
            taxAmount: taxLines[index].tax.taxAmount,
            taxMode: taxLines[index].tax.taxMode,
            extra: <String, dynamic>{
              'taxProfileId': taxLines[index].taxProfileId,
              'unitCost': sale.items[index].unitCost,
              'costingMethodAtSale': sale.items[index].costingMethodAtSale.code,
              'costCurrency': sale.items[index].costCurrency,
              'costExchangeRate': sale.items[index].costExchangeRate,
            },
          ),
      ],
      totals: PostedDocumentTotalsSnapshot(
        subtotal: sale.subtotal,
        discount: sale.discount,
        tax: taxTotal,
        grandTotal: sale.total,
        paid: frozenPaid,
        remaining: (sale.effectiveTransactionAmount - frozenPaid)
            .clamp(0, double.infinity)
            .toDouble(),
        roundingAdjustment: 0,
        baseAmount: sale.baseAmount,
      ),
      audit: _audit(
        user: user,
        role: role,
        deviceId: sale.deviceId,
        storeId: sale.storeId,
        branchId: sale.branchId,
        commandId: sale.id,
      ),
      status: sale.status,
      paymentMethod: sale.paymentMethod,
      paymentStatus: sale.paymentStatus,
      note: sale.note,
      warehouseId: sale.warehouseId,
      warehouseName: sale.warehouseName,
      extra: <String, dynamic>{
        'taxPricingMode': 'inclusive',
        'originalDiscount': sale.originalDiscount,
        'discountCurrency': sale.discountCurrency,
        'discountExchangeRateAtEntry': sale.discountExchangeRateAtEntry,
        'transactionAmount': sale.transactionAmount,
        'paidBaseAmount': sale.paidBaseAmount,
        'exchangeDifferenceAmount': sale.exchangeDifferenceAmount,
        'returnedAmount': sale.returnedAmount,
        'cashReceivedAmount': sale.cashReceivedAmount,
        'paidAmountInPaymentCurrency': sale.paidAmountInPaymentCurrency,
        'cashReceivedAmountInPaymentCurrency':
            sale.cashReceivedAmountInPaymentCurrency,
        ...extra,
      },
    );
  }


  static PostedDocumentSnapshot forSaleReturn({
    required CreditNote creditNote,
    required Sale originalSale,
    required StoreProfile profile,
    Customer? customer,
    AppUser? user,
    UserRole? role,
    bool legacyBackfill = false,
    List<int> originalLineIndexes = const <int>[],
    Map<String, String> taxProfileIdByProductId = const <String, String>{},
    double legacyDefaultVatRatePercent = 0,
  }) {
    final rawSubtotal = creditNote.items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    final returnDiscount =
        (rawSubtotal - creditNote.amount).clamp(0, double.infinity).toDouble();
    final originalSnapshot = originalSale.postedSnapshot;
    final fallbackTaxLines = _resolveTaxLines(
      grossLineAmounts:
          creditNote.items.map((item) => item.lineTotal).toList(growable: false),
      productIds: creditNote.items
          .map((item) => item.productId)
          .toList(growable: false),
      profile: profile,
      taxProfileIdByProductId: taxProfileIdByProductId,
      discount: returnDiscount,
      legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
      legacyBackfill: legacyBackfill,
      decimals: profile.currencyByCode(originalSale.baseCurrency).decimalPlaces,
    );
    final taxLines = <_FrozenTaxLine>[];
    for (var index = 0; index < creditNote.items.length; index += 1) {
      final originalIndex = index < originalLineIndexes.length
          ? originalLineIndexes[index]
          : -1;
      final canReuse = !legacyBackfill &&
          originalSnapshot != null &&
          originalSnapshot.documentType == 'sale_invoice' &&
          originalIndex >= 0 &&
          originalIndex < originalSnapshot.lines.length;
      if (!canReuse) {
        taxLines.add(fallbackTaxLines[index]);
        continue;
      }
      final source = originalSnapshot.lines[originalIndex];
      final returned = creditNote.items[index];
      final ratio = source.quantity <= 0
          ? 0.0
          : (returned.quantity / source.quantity)
              .clamp(0, 1)
              .toDouble();
      final decimals =
          profile.currencyByCode(originalSale.baseCurrency).decimalPlaces;
      final lineDiscount =
          _roundMoney(source.lineDiscount * ratio, decimals);
      final grossAfterDiscount = _roundMoney(
        (returned.lineTotal - lineDiscount)
            .clamp(0, double.infinity)
            .toDouble(),
        decimals,
      );
      // Preserve the original posted VAT proportion, but derive the returned
      // taxable base from the returned gross. Rounding the base and VAT
      // independently can otherwise create a one-minor-unit imbalance on
      // partial returns (for example 1/3 of a line).
      final taxAmount = _roundMoney(
        (source.taxAmount * ratio).clamp(0, grossAfterDiscount).toDouble(),
        decimals,
      );
      final taxableBase = _roundMoney(
        (grossAfterDiscount - taxAmount)
            .clamp(0, double.infinity)
            .toDouble(),
        decimals,
      );
      taxLines.add(_FrozenTaxLine(
        lineDiscount: lineDiscount,
        taxProfileId: source.extra['taxProfileId']?.toString() ?? '',
        tax: TaxAmountBreakdown(
          grossAmount: grossAfterDiscount,
          taxableBase: taxableBase,
          taxAmount: taxAmount,
          ratePercent: source.taxRate,
          taxCode: source.taxCode,
          taxMode: source.taxMode,
        ),
      ));
    }
    final taxTotal = _sumTax(
      taxLines,
      profile.currencyByCode(originalSale.baseCurrency).decimalPlaces,
    );
    return PostedDocumentSnapshot(
      schemaVersion: PostedDocumentSnapshot.currentSchemaVersion,
      documentType: 'sale_return',
      documentId: creditNote.id,
      documentNumber: creditNote.creditNoteNo,
      postedAt: creditNote.date,
      createdFromAppVersion: AppBrand.version,
      legacyBackfill: legacyBackfill,
      storeProfile: _profile(profile),
      party: PostedPartySnapshot(
        id: creditNote.customerId,
        name: creditNote.customerName,
        phone: customer?.phone ?? '',
        address: customer?.address ?? '',
      ),
      currency: PostedCurrencySnapshot(
        baseCurrency: originalSale.baseCurrency,
        documentCurrency: creditNote.currency,
        paymentCurrency: creditNote.currency,
        exchangeRateAtDocument: originalSale.exchangeRateAtInvoice,
        exchangeRateAtPayment: originalSale.exchangeRateAtPayment,
        priceStorageDecimals: profile.priceStorageDecimals,
        taxSchemaVersion: 2,
      ),
      lines: <PostedDocumentLineSnapshot>[
        for (var index = 0; index < creditNote.items.length; index += 1)
          PostedDocumentLineSnapshot(
            lineId: '${creditNote.id}-line-$index',
            productId: creditNote.items[index].productId,
            productName: creditNote.items[index].productName,
            unitName: creditNote.items[index].unitName,
            quantity: creditNote.items[index].quantity,
            baseQuantity: creditNote.items[index].effectiveBaseQuantity,
            conversionToBase: creditNote.items[index].conversionToBase,
            unitPrice: creditNote.items[index].unitPrice,
            lineDiscount: taxLines[index].lineDiscount,
            lineTotal: creditNote.items[index].lineTotal,
            taxCode: taxLines[index].tax.taxCode,
            taxRate: taxLines[index].tax.ratePercent,
            taxableBase: taxLines[index].tax.taxableBase,
            taxAmount: taxLines[index].tax.taxAmount,
            taxMode: taxLines[index].tax.taxMode,
            extra: <String, dynamic>{
              'taxProfileId': taxLines[index].taxProfileId,
              'unitCost': creditNote.items[index].unitCost,
              'costingMethodAtSale':
                  creditNote.items[index].costingMethodAtSale.code,
              'costCurrency': creditNote.items[index].costCurrency,
              'costExchangeRate': creditNote.items[index].costExchangeRate,
            },
          ),
      ],
      totals: PostedDocumentTotalsSnapshot(
        subtotal: rawSubtotal,
        discount: returnDiscount,
        tax: taxTotal,
        grandTotal: creditNote.amount,
        paid: creditNote.amount,
        remaining: 0,
        roundingAdjustment: 0,
        baseAmount: creditNote.amount,
      ),
      audit: _audit(
        user: user,
        role: role,
        deviceId: originalSale.deviceId,
        storeId: originalSale.storeId,
        branchId: originalSale.branchId,
        commandId: creditNote.id,
      ),
      status: creditNote.status,
      paymentMethod: creditNote.refundMethod,
      paymentStatus: 'refunded',
      note: creditNote.note,
      warehouseId: originalSale.warehouseId,
      warehouseName: originalSale.warehouseName,
      extra: <String, dynamic>{
        'taxPricingMode': 'inclusive',
        'originalSaleId': creditNote.originalSaleId,
        'originalInvoiceNo': creditNote.originalInvoiceNo,
      },
    );
  }

  static PostedDocumentSnapshot forPurchase({
    required Purchase purchase,
    required StoreProfile profile,
    Supplier? supplier,
    AppUser? user,
    UserRole? role,
    bool legacyBackfill = false,
    double? displayedPaidAmount,
    String? displayedPaymentStatus,
    Map<String, String> taxProfileIdByProductId = const <String, String>{},
    double legacyDefaultVatRatePercent = 0,
  }) {
    final frozenPaid = displayedPaidAmount ?? purchase.paidAmount;
    final frozenPaymentStatus = displayedPaymentStatus ?? purchase.paymentStatus;
    final taxLines = _resolveTaxLines(
      grossLineAmounts: purchase.items
          .map((item) => item.lineTotal)
          .toList(growable: false),
      productIds: purchase.items
          .map((item) => item.productId)
          .toList(growable: false),
      profile: profile,
      taxProfileIdByProductId: taxProfileIdByProductId,
      legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
      legacyBackfill: legacyBackfill,
      decimals: profile.currencyByCode(profile.baseCurrency).decimalPlaces,
    );
    final taxTotal = _sumTax(
      taxLines,
      profile.currencyByCode(profile.baseCurrency).decimalPlaces,
    );
    return PostedDocumentSnapshot(
      schemaVersion: PostedDocumentSnapshot.currentSchemaVersion,
      documentType: 'purchase_invoice',
      documentId: purchase.id,
      documentNumber: purchase.purchaseNo,
      postedAt: purchase.date,
      createdFromAppVersion: AppBrand.version,
      legacyBackfill: legacyBackfill,
      storeProfile: _profile(profile),
      party: PostedPartySnapshot(
        id: purchase.supplierId,
        name: purchase.supplierName,
        phone: supplier?.phone ?? '',
        address: supplier?.address ?? '',
      ),
      currency: PostedCurrencySnapshot(
        baseCurrency: profile.baseCurrency,
        documentCurrency: profile.baseCurrency,
        paymentCurrency: profile.baseCurrency,
        exchangeRateAtDocument: 1,
        exchangeRateAtPayment: 1,
        priceStorageDecimals: profile.priceStorageDecimals,
        taxSchemaVersion: 2,
      ),
      lines: <PostedDocumentLineSnapshot>[
        for (var index = 0; index < purchase.items.length; index += 1)
          PostedDocumentLineSnapshot(
            lineId: purchase.items[index].lineId.isEmpty
                ? '${purchase.id}-line-$index'
                : purchase.items[index].lineId,
            productId: purchase.items[index].productId,
            productName: purchase.items[index].productName,
            unitName: purchase.items[index].purchaseUnitName,
            quantity: purchase.items[index].quantity,
            baseQuantity: purchase.items[index].baseQuantity,
            conversionToBase: purchase.items[index].conversionToBase,
            unitPrice: purchase.items[index].unitCost,
            lineDiscount: 0,
            lineTotal: purchase.items[index].lineTotal,
            taxCode: taxLines[index].tax.taxCode,
            taxRate: taxLines[index].tax.ratePercent,
            taxableBase: taxLines[index].tax.taxableBase,
            taxAmount: taxLines[index].tax.taxAmount,
            taxMode: taxLines[index].tax.taxMode,
            extra: <String, dynamic>{
              'taxProfileId': taxLines[index].taxProfileId,
              'purchaseUnitId': purchase.items[index].purchaseUnitId,
              'originalUnitCost': purchase.items[index].originalUnitCost,
              'unitCostCurrency': purchase.items[index].unitCostCurrency,
              'exchangeRateAtEntry': purchase.items[index].exchangeRateAtEntry,
            },
          ),
      ],
      totals: PostedDocumentTotalsSnapshot(
        subtotal: purchase.subtotal,
        discount: 0,
        tax: taxTotal,
        grandTotal: purchase.subtotal,
        paid: frozenPaid,
        remaining: (purchase.subtotal - frozenPaid)
            .clamp(0, double.infinity)
            .toDouble(),
        roundingAdjustment: 0,
        baseAmount: purchase.subtotal,
      ),
      audit: _audit(
        user: user,
        role: role,
        deviceId: purchase.deviceId,
        storeId: purchase.storeId,
        branchId: purchase.branchId,
        commandId: purchase.id,
      ),
      status: purchase.status,
      paymentMethod: purchase.paymentMethod,
      paymentStatus: frozenPaymentStatus,
      note: purchase.note,
      warehouseId: purchase.warehouseId,
      warehouseName: purchase.warehouseName,
      extra: const <String, dynamic>{'taxPricingMode': 'inclusive'},
    );
  }


  static List<_FrozenTaxLine> _resolveTaxLines({
    required List<double> grossLineAmounts,
    required List<String> productIds,
    required StoreProfile profile,
    Map<String, String> taxProfileIdByProductId = const <String, String>{},
    double discount = 0,
    double legacyDefaultVatRatePercent = 0,
    bool legacyBackfill = false,
    int decimals = 2,
  }) {
    if (grossLineAmounts.isEmpty) return const <_FrozenTaxLine>[];
    final subtotal = grossLineAmounts.fold<double>(
      0,
      (sum, amount) => sum + (amount.isFinite && amount > 0 ? amount : 0),
    );
    final safeDiscount = discount.isFinite
        ? discount.clamp(0, subtotal).toDouble()
        : 0.0;
    var allocatedDiscount = 0.0;
    final result = <_FrozenTaxLine>[];
    for (var index = 0; index < grossLineAmounts.length; index += 1) {
      final gross = grossLineAmounts[index].isFinite && grossLineAmounts[index] > 0
          ? grossLineAmounts[index]
          : 0.0;
      final remainingDiscount =
          (safeDiscount - allocatedDiscount).clamp(0, safeDiscount).toDouble();
      final lineDiscount = index == grossLineAmounts.length - 1
          ? _roundMoney(
              remainingDiscount.clamp(0, gross).toDouble(),
              decimals,
            )
          : _roundMoney(
              subtotal <= 0 ? 0 : safeDiscount * (gross / subtotal),
              decimals,
            )
              .clamp(0, remainingDiscount.clamp(0, gross).toDouble())
              .toDouble();
      allocatedDiscount = _roundMoney(allocatedDiscount + lineDiscount, decimals);
      if (legacyBackfill) {
        result.add(_FrozenTaxLine(
          lineDiscount: lineDiscount,
          taxProfileId: '',
          tax: TaxAmountBreakdown(
            grossAmount:
                (gross - lineDiscount).clamp(0, double.infinity).toDouble(),
            taxableBase:
                (gross - lineDiscount).clamp(0, double.infinity).toDouble(),
            taxAmount: 0,
            ratePercent: 0,
            taxCode: '',
            taxMode: 'none',
          ),
        ));
        continue;
      }
      final productId = index < productIds.length ? productIds[index] : '';
      final requestedProfileId = taxProfileIdByProductId[productId];
      final taxProfile = profile.taxProfileById(
        requestedProfileId,
        legacyDefaultRatePercent: legacyDefaultVatRatePercent,
      );
      result.add(_FrozenTaxLine(
        lineDiscount: lineDiscount,
        taxProfileId: taxProfile.id,
        tax: TaxCalculator.inclusive(
          (gross - lineDiscount).clamp(0, double.infinity).toDouble(),
          taxProfile,
          decimals: decimals,
        ),
      ));
    }
    return result;
  }

  static double _sumTax(List<_FrozenTaxLine> lines, int decimals) =>
      _roundMoney(
        lines.fold<double>(0, (sum, line) => sum + line.tax.taxAmount),
        decimals,
      );

  static double _roundMoney(double value, int decimals) {
    if (!value.isFinite) return 0;
    final safe = decimals.clamp(0, 6).toInt();
    const factors = <double>[1, 10, 100, 1000, 10000, 100000, 1000000];
    final factor = factors[safe];
    return (value * factor).roundToDouble() / factor;
  }

  static PostedStoreProfileSnapshot _profile(StoreProfile profile) =>
      PostedStoreProfileSnapshot(
        profileJson: Map<String, dynamic>.from(profile.toJson()),
      );

  static PostedDocumentAuditSnapshot _audit({
    AppUser? user,
    UserRole? role,
    required String deviceId,
    required String storeId,
    required String branchId,
    required String commandId,
  }) =>
      PostedDocumentAuditSnapshot(
        userId: user?.id ?? '',
        userName: user?.fullName ?? user?.username ?? '',
        roleId: user?.roleId ?? role?.id ?? '',
        roleName: role?.name ?? '',
        deviceId: deviceId,
        storeId: storeId,
        branchId: branchId,
        commandId: commandId,
      );
}


class _FrozenTaxLine {
  const _FrozenTaxLine({
    required this.lineDiscount,
    required this.taxProfileId,
    required this.tax,
  });

  final double lineDiscount;
  final String taxProfileId;
  final TaxAmountBreakdown tax;
}
