import 'store_profile.dart';

/// Immutable representation of a posted business document.
///
/// Phase 1 deliberately stores the rendering/accounting-relevant values that
/// existed at posting time so later edits to store/profile/product settings do
/// not change historical documents.
class PostedDocumentSnapshot {
  const PostedDocumentSnapshot({
    required this.schemaVersion,
    required this.documentType,
    required this.documentId,
    required this.documentNumber,
    required this.postedAt,
    required this.createdFromAppVersion,
    required this.legacyBackfill,
    required this.storeProfile,
    required this.party,
    required this.currency,
    required this.lines,
    required this.totals,
    required this.audit,
    this.status = '',
    this.paymentMethod = '',
    this.paymentStatus = '',
    this.note = '',
    this.warehouseId = '',
    this.warehouseName = '',
    this.extra = const <String, dynamic>{},
  });

  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final String documentType;
  final String documentId;
  final String documentNumber;
  final DateTime postedAt;
  final String createdFromAppVersion;
  final bool legacyBackfill;
  final PostedStoreProfileSnapshot storeProfile;
  final PostedPartySnapshot party;
  final PostedCurrencySnapshot currency;
  final List<PostedDocumentLineSnapshot> lines;
  final PostedDocumentTotalsSnapshot totals;
  final PostedDocumentAuditSnapshot audit;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final String note;
  final String warehouseId;
  final String warehouseName;
  final Map<String, dynamic> extra;

  StoreProfile get frozenStoreProfile => storeProfile.toStoreProfile();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'documentType': documentType,
        'documentId': documentId,
        'documentNumber': documentNumber,
        'postedAt': postedAt.toIso8601String(),
        'createdFromAppVersion': createdFromAppVersion,
        'legacyBackfill': legacyBackfill,
        'storeProfile': storeProfile.toJson(),
        'party': party.toJson(),
        'currency': currency.toJson(),
        'lines': lines.map((item) => item.toJson()).toList(growable: false),
        'totals': totals.toJson(),
        'audit': audit.toJson(),
        'status': status,
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'note': note,
        'warehouseId': warehouseId,
        'warehouseName': warehouseName,
        'extra': extra,
      };

  factory PostedDocumentSnapshot.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    return PostedDocumentSnapshot(
      schemaVersion: (json['schemaVersion'] as num? ?? 1).toInt(),
      documentType: json['documentType']?.toString() ?? '',
      documentId: json['documentId']?.toString() ?? '',
      documentNumber: json['documentNumber']?.toString() ?? '',
      postedAt: DateTime.tryParse(json['postedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      createdFromAppVersion: json['createdFromAppVersion']?.toString() ?? '',
      legacyBackfill: json['legacyBackfill'] == true,
      storeProfile: PostedStoreProfileSnapshot.fromJson(
        _map(json['storeProfile']),
      ),
      party: PostedPartySnapshot.fromJson(_map(json['party'])),
      currency: PostedCurrencySnapshot.fromJson(_map(json['currency'])),
      lines: rawLines is List
          ? rawLines
              .whereType<Map>()
              .map((item) => PostedDocumentLineSnapshot.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const <PostedDocumentLineSnapshot>[],
      totals: PostedDocumentTotalsSnapshot.fromJson(_map(json['totals'])),
      audit: PostedDocumentAuditSnapshot.fromJson(_map(json['audit'])),
      status: json['status']?.toString() ?? '',
      paymentMethod: json['paymentMethod']?.toString() ?? '',
      paymentStatus: json['paymentStatus']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      warehouseId: json['warehouseId']?.toString() ?? '',
      warehouseName: json['warehouseName']?.toString() ?? '',
      extra: _map(json['extra']),
    );
  }

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
}

class PostedStoreProfileSnapshot {
  const PostedStoreProfileSnapshot({required this.profileJson});

  /// Full StoreProfile JSON is frozen intentionally. This preserves the legal
  /// identity, logo/footer, currency definitions, exchange-rate history and
  /// rounding/display rules that the renderer used when the document posted.
  final Map<String, dynamic> profileJson;

  StoreProfile toStoreProfile() => StoreProfile.fromJson(
        Map<String, dynamic>.from(profileJson),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'profileJson': profileJson,
      };

  factory PostedStoreProfileSnapshot.fromJson(Map<String, dynamic> json) =>
      PostedStoreProfileSnapshot(
        profileJson: json['profileJson'] is Map
            ? Map<String, dynamic>.from(json['profileJson'] as Map)
            : <String, dynamic>{},
      );
}

class PostedPartySnapshot {
  const PostedPartySnapshot({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.taxNumber = '',
    this.registrationNumber = '',
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final String taxNumber;
  final String registrationNumber;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'taxNumber': taxNumber,
        'registrationNumber': registrationNumber,
      };

  factory PostedPartySnapshot.fromJson(Map<String, dynamic> json) =>
      PostedPartySnapshot(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        taxNumber: json['taxNumber']?.toString() ?? '',
        registrationNumber: json['registrationNumber']?.toString() ?? '',
      );
}

class PostedCurrencySnapshot {
  const PostedCurrencySnapshot({
    required this.baseCurrency,
    required this.documentCurrency,
    required this.paymentCurrency,
    required this.exchangeRateAtDocument,
    required this.exchangeRateAtPayment,
    required this.priceStorageDecimals,
    this.taxSchemaVersion = 1,
  });

  final String baseCurrency;
  final String documentCurrency;
  final String paymentCurrency;
  final double exchangeRateAtDocument;
  final double exchangeRateAtPayment;
  final int priceStorageDecimals;
  final int taxSchemaVersion;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'baseCurrency': baseCurrency,
        'documentCurrency': documentCurrency,
        'paymentCurrency': paymentCurrency,
        'exchangeRateAtDocument': exchangeRateAtDocument,
        'exchangeRateAtPayment': exchangeRateAtPayment,
        'priceStorageDecimals': priceStorageDecimals,
        'taxSchemaVersion': taxSchemaVersion,
      };

  factory PostedCurrencySnapshot.fromJson(Map<String, dynamic> json) =>
      PostedCurrencySnapshot(
        baseCurrency: json['baseCurrency']?.toString() ?? 'USD',
        documentCurrency: json['documentCurrency']?.toString() ?? 'USD',
        paymentCurrency: json['paymentCurrency']?.toString() ?? 'USD',
        exchangeRateAtDocument:
            (json['exchangeRateAtDocument'] as num? ?? 1).toDouble(),
        exchangeRateAtPayment:
            (json['exchangeRateAtPayment'] as num? ?? 0).toDouble(),
        priceStorageDecimals:
            (json['priceStorageDecimals'] as num? ?? 2).toInt(),
        taxSchemaVersion: (json['taxSchemaVersion'] as num? ?? 1).toInt(),
      );
}

class PostedDocumentLineSnapshot {
  const PostedDocumentLineSnapshot({
    required this.lineId,
    required this.productId,
    required this.productName,
    required this.unitName,
    required this.quantity,
    required this.baseQuantity,
    required this.conversionToBase,
    required this.unitPrice,
    required this.lineDiscount,
    required this.lineTotal,
    required this.taxCode,
    required this.taxRate,
    required this.taxableBase,
    required this.taxAmount,
    required this.taxMode,
    this.extra = const <String, dynamic>{},
  });

  final String lineId;
  final String productId;
  final String productName;
  final String unitName;
  final double quantity;
  final double baseQuantity;
  final double conversionToBase;
  final double unitPrice;
  final double lineDiscount;
  final double lineTotal;
  final String taxCode;
  final double taxRate;
  final double taxableBase;
  final double taxAmount;
  final String taxMode;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lineId': lineId,
        'productId': productId,
        'productName': productName,
        'unitName': unitName,
        'quantity': quantity,
        'baseQuantity': baseQuantity,
        'conversionToBase': conversionToBase,
        'unitPrice': unitPrice,
        'lineDiscount': lineDiscount,
        'lineTotal': lineTotal,
        'taxCode': taxCode,
        'taxRate': taxRate,
        'taxableBase': taxableBase,
        'taxAmount': taxAmount,
        'taxMode': taxMode,
        'extra': extra,
      };

  factory PostedDocumentLineSnapshot.fromJson(Map<String, dynamic> json) =>
      PostedDocumentLineSnapshot(
        lineId: json['lineId']?.toString() ?? '',
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        unitName: json['unitName']?.toString() ?? '',
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        baseQuantity: (json['baseQuantity'] as num? ?? 0).toDouble(),
        conversionToBase: (json['conversionToBase'] as num? ?? 1).toDouble(),
        unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
        lineDiscount: (json['lineDiscount'] as num? ?? 0).toDouble(),
        lineTotal: (json['lineTotal'] as num? ?? 0).toDouble(),
        taxCode: json['taxCode']?.toString() ?? '',
        taxRate: (json['taxRate'] as num? ?? 0).toDouble(),
        taxableBase: (json['taxableBase'] as num? ?? 0).toDouble(),
        taxAmount: (json['taxAmount'] as num? ?? 0).toDouble(),
        taxMode: json['taxMode']?.toString() ?? 'none',
        extra: PostedDocumentSnapshot._map(json['extra']),
      );
}

class PostedDocumentTotalsSnapshot {
  const PostedDocumentTotalsSnapshot({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.grandTotal,
    required this.paid,
    required this.remaining,
    required this.roundingAdjustment,
    required this.baseAmount,
  });

  final double subtotal;
  final double discount;
  final double tax;
  final double grandTotal;
  final double paid;
  final double remaining;
  final double roundingAdjustment;
  final double baseAmount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'grandTotal': grandTotal,
        'paid': paid,
        'remaining': remaining,
        'roundingAdjustment': roundingAdjustment,
        'baseAmount': baseAmount,
      };

  factory PostedDocumentTotalsSnapshot.fromJson(Map<String, dynamic> json) =>
      PostedDocumentTotalsSnapshot(
        subtotal: (json['subtotal'] as num? ?? 0).toDouble(),
        discount: (json['discount'] as num? ?? 0).toDouble(),
        tax: (json['tax'] as num? ?? 0).toDouble(),
        grandTotal: (json['grandTotal'] as num? ?? 0).toDouble(),
        paid: (json['paid'] as num? ?? 0).toDouble(),
        remaining: (json['remaining'] as num? ?? 0).toDouble(),
        roundingAdjustment:
            (json['roundingAdjustment'] as num? ?? 0).toDouble(),
        baseAmount: (json['baseAmount'] as num? ?? 0).toDouble(),
      );
}

class PostedDocumentAuditSnapshot {
  const PostedDocumentAuditSnapshot({
    this.userId = '',
    this.userName = '',
    this.roleId = '',
    this.roleName = '',
    this.deviceId = '',
    this.storeId = '',
    this.branchId = '',
    this.traceId = '',
    this.commandId = '',
  });

  final String userId;
  final String userName;
  final String roleId;
  final String roleName;
  final String deviceId;
  final String storeId;
  final String branchId;
  final String traceId;
  final String commandId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'userId': userId,
        'userName': userName,
        'roleId': roleId,
        'roleName': roleName,
        'deviceId': deviceId,
        'storeId': storeId,
        'branchId': branchId,
        'traceId': traceId,
        'commandId': commandId,
      };

  factory PostedDocumentAuditSnapshot.fromJson(Map<String, dynamic> json) =>
      PostedDocumentAuditSnapshot(
        userId: json['userId']?.toString() ?? '',
        userName: json['userName']?.toString() ?? '',
        roleId: json['roleId']?.toString() ?? '',
        roleName: json['roleName']?.toString() ?? '',
        deviceId: json['deviceId']?.toString() ?? '',
        storeId: json['storeId']?.toString() ?? '',
        branchId: json['branchId']?.toString() ?? '',
        traceId: json['traceId']?.toString() ?? '',
        commandId: json['commandId']?.toString() ?? '',
      );
}
