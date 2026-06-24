import 'sale_item.dart';

class SaleQuotation {
  SaleQuotation({
    required this.id,
    required this.quotationNo,
    required this.customerName,
    required this.date,
    required this.status,
    required this.items,
    required this.discount,
    this.customerId = '',
    this.invoiceCurrency = 'USD',
    this.note = '',
    this.validUntil,
    this.convertedSaleId = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.storeId = '',
    this.branchId = '',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : createdAt = createdAt ?? updatedAt ?? date,
        updatedAt = updatedAt ?? createdAt ?? date;

  final String id, quotationNo, customerName, customerId, status, invoiceCurrency, note, convertedSaleId, deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final DateTime date, createdAt, updatedAt;
  final DateTime? validUntil, deletedAt;
  final List<SaleItem> items;
  final double discount;
  final int version;

  bool get isDeleted => deletedAt != null;
  bool get isConverted => status.toLowerCase() == 'converted' || convertedSaleId.trim().isNotEmpty;
  double get subtotal => items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  double get total => (subtotal - discount).clamp(0, double.infinity).toDouble();

  SaleQuotation copyWith({
    String? id,
    String? quotationNo,
    String? customerName,
    String? customerId,
    DateTime? date,
    DateTime? validUntil,
    String? status,
    List<SaleItem>? items,
    double? discount,
    String? invoiceCurrency,
    String? note,
    String? convertedSaleId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? deviceId,
    String? syncStatus,
    String? storeId,
    String? branchId,
    int? version,
    String? lastModifiedByDeviceId,
  }) =>
      SaleQuotation(
        id: id ?? this.id,
        quotationNo: quotationNo ?? this.quotationNo,
        customerName: customerName ?? this.customerName,
        customerId: customerId ?? this.customerId,
        date: date ?? this.date,
        validUntil: validUntil ?? this.validUntil,
        status: status ?? this.status,
        items: items ?? this.items,
        discount: discount ?? this.discount,
        invoiceCurrency: invoiceCurrency ?? this.invoiceCurrency,
        note: note ?? this.note,
        convertedSaleId: convertedSaleId ?? this.convertedSaleId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        deviceId: deviceId ?? this.deviceId,
        syncStatus: syncStatus ?? this.syncStatus,
        storeId: storeId ?? this.storeId,
        branchId: branchId ?? this.branchId,
        version: version ?? this.version,
        lastModifiedByDeviceId: lastModifiedByDeviceId ?? this.lastModifiedByDeviceId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'quotationNo': quotationNo,
        'customerName': customerName,
        'customerId': customerId,
        'date': date.toIso8601String(),
        'validUntil': validUntil?.toIso8601String(),
        'status': status,
        'items': items.map((item) => item.toJson()).toList(),
        'discount': discount,
        'invoiceCurrency': invoiceCurrency,
        'note': note,
        'convertedSaleId': convertedSaleId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'deviceId': deviceId,
        'syncStatus': syncStatus,
        'storeId': storeId,
        'branchId': branchId,
        'version': version,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
      };

  factory SaleQuotation.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now();
    return SaleQuotation(
      id: json['id'] as String? ?? '',
      quotationNo: json['quotationNo'] as String? ?? json['quoteNo'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      customerId: json['customerId'] as String? ?? '',
      date: date,
      validUntil: DateTime.tryParse(json['validUntil'] as String? ?? ''),
      status: json['status'] as String? ?? 'Draft',
      items: ((json['items'] as List<dynamic>?) ?? const []).map((item) => SaleItem.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
      discount: (json['discount'] as num? ?? 0).toDouble(),
      invoiceCurrency: ((json['invoiceCurrency'] as String? ?? 'USD').toUpperCase() == 'LBP') ? 'LBP' : 'USD',
      note: json['note'] as String? ?? '',
      convertedSaleId: json['convertedSaleId'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? date,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? date,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
      deviceId: json['deviceId'] as String? ?? '',
      syncStatus: json['syncStatus'] as String? ?? 'synced',
      storeId: json['storeId'] as String? ?? '',
      branchId: json['branchId'] as String? ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId'] as String? ?? json['deviceId'] as String? ?? '',
    );
  }
}
