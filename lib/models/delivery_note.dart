import 'sale_item.dart';

class DeliveryNote {
  DeliveryNote({
    required this.id,
    required this.deliveryNo,
    required this.saleId,
    required this.invoiceNo,
    required this.customerName,
    required this.date,
    required this.status,
    required this.items,
    this.customerId = '',
    this.note = '',
    this.deliveredAt,
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

  final String id, deliveryNo, saleId, invoiceNo, customerName, customerId, status, note;
  final DateTime date, createdAt, updatedAt;
  final DateTime? deliveredAt, deletedAt;
  final List<SaleItem> items;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  bool get isDeleted => deletedAt != null;
  bool get isDelivered => status.toLowerCase() == 'delivered';
  double get totalQuantity => items.fold<double>(0, (sum, item) => sum + item.quantity);

  DeliveryNote copyWith({
    String? id,
    String? deliveryNo,
    String? saleId,
    String? invoiceNo,
    String? customerName,
    String? customerId,
    DateTime? date,
    String? status,
    List<SaleItem>? items,
    String? note,
    DateTime? deliveredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    String? deviceId,
    String? syncStatus,
    String? storeId,
    String? branchId,
    int? version,
    String? lastModifiedByDeviceId,
  }) =>
      DeliveryNote(
        id: id ?? this.id,
        deliveryNo: deliveryNo ?? this.deliveryNo,
        saleId: saleId ?? this.saleId,
        invoiceNo: invoiceNo ?? this.invoiceNo,
        customerName: customerName ?? this.customerName,
        customerId: customerId ?? this.customerId,
        date: date ?? this.date,
        status: status ?? this.status,
        items: items ?? this.items,
        note: note ?? this.note,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        deviceId: deviceId ?? this.deviceId,
        syncStatus: syncStatus ?? this.syncStatus,
        storeId: storeId ?? this.storeId,
        branchId: branchId ?? this.branchId,
        version: version ?? this.version,
        lastModifiedByDeviceId: lastModifiedByDeviceId ?? this.lastModifiedByDeviceId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deliveryNo': deliveryNo,
        'saleId': saleId,
        'invoiceNo': invoiceNo,
        'customerName': customerName,
        'customerId': customerId,
        'date': date.toIso8601String(),
        'status': status,
        'items': items.map((item) => item.toJson()).toList(),
        'note': note,
        'deliveredAt': deliveredAt?.toIso8601String(),
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

  factory DeliveryNote.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now();
    return DeliveryNote(
      id: json['id']?.toString() ?? '',
      deliveryNo: json['deliveryNo']?.toString() ?? json['noteNo']?.toString() ?? '',
      saleId: json['saleId']?.toString() ?? '',
      invoiceNo: json['invoiceNo']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? '',
      customerId: json['customerId']?.toString() ?? '',
      date: date,
      status: json['status']?.toString() ?? 'Draft',
      items: ((json['items'] as List<dynamic>?) ?? const []).map((item) => SaleItem.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
      note: json['note']?.toString() ?? '',
      deliveredAt: DateTime.tryParse(json['deliveredAt']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? date,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? date,
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
      deviceId: json['deviceId']?.toString() ?? '',
      syncStatus: json['syncStatus']?.toString() ?? 'synced',
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId']?.toString() ?? json['deviceId']?.toString() ?? '',
    );
  }
}
