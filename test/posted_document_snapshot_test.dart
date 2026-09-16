import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/posted_document_snapshot_service.dart';
import 'package:ventio/models/posted_document_snapshot.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/store_profile.dart';

void main() {
  test('posted sale view keeps historical store and line values', () {
    const historicalProfile = StoreProfile(
      name: 'Historical Store',
      legalName: 'Historical Store SAL',
      phone: '01-111111',
      address: 'Beirut - Old Address',
      currency: 'USD',
      footerNote: 'Historical footer',
      usdToLbpRate: 89500,
    );
    final postedAt = DateTime.utc(2026, 8, 30, 12);
    final original = Sale(
      id: 'sale-snapshot-1',
      invoiceNo: '000001',
      customerId: 'customer-1',
      customerName: 'Historical Customer',
      date: postedAt,
      status: 'Paid',
      items: const <SaleItem>[
        SaleItem(
          productId: 'product-1',
          productName: 'Historical Product Name',
          unitPrice: 12.5,
          quantity: 2,
          unitCost: 5,
          unitName: 'pcs',
        ),
      ],
      discount: 1,
      paymentMethod: 'Cash',
      paymentStatus: 'paid',
      invoiceCurrency: 'USD',
      paymentCurrency: 'USD',
      baseCurrency: 'USD',
      exchangeRateAtInvoice: 1,
      transactionAmount: 24,
      baseAmount: 24,
      paidAmount: 24,
      deviceId: 'device-1',
      storeId: 'store-1',
      branchId: 'branch-1',
    );
    final posted = original.copyWith(
      postedSnapshot: PostedDocumentSnapshotService.forSale(
        sale: original,
        profile: historicalProfile,
      ),
    );

    const currentProfile = StoreProfile(
      name: 'Renamed Store',
      legalName: 'Renamed Store SAL',
      phone: '01-999999',
      address: 'Beirut - New Address',
      currency: 'USD',
      footerNote: 'New footer',
      usdToLbpRate: 100000,
    );
    final mutatedLiveSale = posted.copyWith(
      invoiceNo: '999999',
      customerName: 'Renamed Customer',
      items: const <SaleItem>[
        SaleItem(
          productId: 'product-1',
          productName: 'Renamed Product',
          unitPrice: 99,
          quantity: 2,
          unitCost: 7,
          unitName: 'box',
        ),
      ],
      discount: 0,
    );

    final frozenProfile = PostedDocumentSnapshotService.profileForSale(
      mutatedLiveSale,
      currentProfile,
    );
    final frozenSale = PostedDocumentSnapshotService.saleView(mutatedLiveSale);

    expect(frozenProfile.name, 'Historical Store');
    expect(frozenProfile.legalName, 'Historical Store SAL');
    expect(frozenProfile.phone, '01-111111');
    expect(frozenProfile.address, 'Beirut - Old Address');
    expect(frozenProfile.usdToLbpRate, 89500);
    expect(frozenSale.invoiceNo, '000001');
    expect(frozenSale.customerName, 'Historical Customer');
    expect(frozenSale.items.single.productName, 'Historical Product Name');
    expect(frozenSale.items.single.unitPrice, 12.5);
    expect(frozenSale.items.single.unitName, 'pcs');
    expect(frozenSale.discount, 1);
  });

  test('posted purchase view keeps historical document number and line values',
      () {
    const historicalProfile = StoreProfile(
      name: 'Historical Store',
      phone: '01-111111',
      address: 'Beirut',
      currency: 'USD',
      footerNote: 'Historical footer',
    );
    final postedAt = DateTime.utc(2026, 8, 30, 13);
    final original = Purchase(
      id: 'purchase-snapshot-1',
      purchaseNo: 'PO-0001',
      supplierId: 'supplier-1',
      supplierName: 'Historical Supplier',
      date: postedAt,
      status: 'received',
      items: const <PurchaseItem>[
        PurchaseItem(
          lineId: 'purchase-line-1',
          productId: 'product-1',
          productName: 'Historical Raw Material',
          quantity: 4,
          unitCost: 7.5,
          purchaseUnitName: 'kg',
        ),
      ],
      paymentStatus: 'paid',
      paymentMethod: 'Cash',
      paidAmount: 30,
      warehouseId: 'warehouse-1',
      warehouseName: 'Historical Warehouse',
    );
    final posted = original.copyWith(
      postedSnapshot: PostedDocumentSnapshotService.forPurchase(
        purchase: original,
        profile: historicalProfile,
      ),
    );
    final mutatedLivePurchase = posted.copyWith(
      purchaseNo: 'PO-9999',
      supplierName: 'Renamed Supplier',
      items: const <PurchaseItem>[
        PurchaseItem(
          lineId: 'purchase-line-1',
          productId: 'product-1',
          productName: 'Renamed Raw Material',
          quantity: 4,
          unitCost: 99,
          purchaseUnitName: 'box',
        ),
      ],
    );

    final frozenPurchase =
        PostedDocumentSnapshotService.purchaseView(mutatedLivePurchase);

    expect(frozenPurchase.purchaseNo, 'PO-0001');
    expect(frozenPurchase.supplierName, 'Historical Supplier');
    expect(frozenPurchase.items.single.productName, 'Historical Raw Material');
    expect(frozenPurchase.items.single.unitCost, 7.5);
    expect(frozenPurchase.items.single.purchaseUnitName, 'kg');
    expect(frozenPurchase.warehouseId, 'warehouse-1');
    expect(frozenPurchase.warehouseName, 'Historical Warehouse');
  });

  test('snapshot JSON round-trip preserves legacy and tax-ready fields', () {
    const profile = StoreProfile(
      name: 'Legacy Store',
      phone: '',
      address: '',
      currency: 'USD',
      footerNote: '',
    );
    final sale = Sale(
      id: 'legacy-sale-1',
      invoiceNo: 'LEG-1',
      customerName: 'Legacy Customer',
      date: DateTime.utc(2025, 1, 2),
      status: 'Paid',
      items: const <SaleItem>[
        SaleItem(
          productId: 'p1',
          productName: 'Legacy Product',
          unitPrice: 10,
          quantity: 1,
        ),
      ],
      discount: 0,
    );
    final snapshot = PostedDocumentSnapshotService.forSale(
      sale: sale,
      profile: profile,
      legacyBackfill: true,
    );

    final restored = PostedDocumentSnapshot.fromJson(snapshot.toJson());

    expect(restored.schemaVersion, PostedDocumentSnapshot.currentSchemaVersion);
    expect(restored.legacyBackfill, isTrue);
    expect(restored.documentType, 'sale_invoice');
    expect(restored.lines.single.taxCode, '');
    expect(restored.lines.single.taxRate, 0);
    expect(restored.lines.single.taxAmount, 0);
    expect(restored.lines.single.taxMode, 'none');
    expect(restored.frozenStoreProfile.name, 'Legacy Store');
  });
  test('posted snapshots reference logo assets without duplicating base64', () {
    const firstLogo = 'AQIDBAUGBwgJ';
    const secondLogo = 'CQgHBgUEAwIB';
    const historicalProfile = StoreProfile(
      name: 'Logo Store',
      phone: '',
      address: '',
      currency: 'USD',
      footerNote: '',
      logoDataBase64: firstLogo,
      logoFileName: 'logo.png',
      logoMimeType: 'image/png',
    );
    final sale = Sale(
      id: 'logo-sale-1',
      invoiceNo: 'LOGO-1',
      customerName: 'Customer',
      date: DateTime.utc(2026, 9, 16),
      status: 'Paid',
      items: const <SaleItem>[
        SaleItem(
          productId: 'p1',
          productName: 'Product',
          unitPrice: 1,
          quantity: 1,
        ),
      ],
      discount: 0,
    );
    final snapshot = PostedDocumentSnapshotService.forSale(
      sale: sale,
      profile: historicalProfile,
    );
    final encoded = snapshot.toJson();
    final frozenProfileJson = Map<String, dynamic>.from(
      encoded['storeProfile'] as Map,
    );
    final rawProfileJson = Map<String, dynamic>.from(
      frozenProfileJson['profileJson'] as Map,
    );
    final firstAssetId = StoreProfile.logoAssetIdForData(firstLogo);

    expect(rawProfileJson['logoAssetId'], firstAssetId);
    expect(rawProfileJson.containsKey('logoDataBase64'), isFalse);
    expect(rawProfileJson.containsKey('historicalLogoAssetsBase64'), isFalse);

    final currentProfile = historicalProfile.copyWith(
      logoDataBase64: secondLogo,
      logoFileName: 'new-logo.png',
    );
    expect(currentProfile.historicalLogoAssetsBase64[firstAssetId], firstLogo);

    final postedSale = sale.copyWith(postedSnapshot: snapshot);
    final resolved = PostedDocumentSnapshotService.profileForSale(
      postedSale,
      currentProfile,
    );
    expect(resolved.logoDataBase64, firstLogo);
    expect(resolved.logoAssetId, firstAssetId);
  });

  test('logo history keeps one copy per unique historical logo', () {
    const firstLogo = 'AQIDBAUG';
    const secondLogo = 'BwgJCgsM';
    const profile = StoreProfile(
      name: 'Store',
      phone: '',
      address: '',
      currency: 'USD',
      footerNote: '',
      logoDataBase64: firstLogo,
    );
    final firstAssetId = StoreProfile.logoAssetIdForData(firstLogo);
    final secondAssetId = StoreProfile.logoAssetIdForData(secondLogo);

    final changed = profile.copyWith(logoDataBase64: secondLogo);
    expect(changed.logoAssetId, secondAssetId);
    expect(changed.historicalLogoAssetsBase64[firstAssetId], firstLogo);
    expect(changed.historicalLogoAssetsBase64.containsKey(secondAssetId), isFalse);

    final restored = changed.copyWith(logoDataBase64: firstLogo);
    expect(restored.logoAssetId, firstAssetId);
    expect(restored.historicalLogoAssetsBase64[secondAssetId], secondLogo);
    expect(restored.historicalLogoAssetsBase64.containsKey(firstAssetId), isFalse);
  });

}
