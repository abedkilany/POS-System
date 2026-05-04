import 'purchase_item.dart';

class Purchase {
  Purchase({
    required this.id,
    required this.purchaseNo,
    required this.supplierId,
    required this.supplierName,
    required this.date,
    required this.status,
    required this.items,
    this.note = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.storeId = '',
    this.branchId = '',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id, purchaseNo, supplierId, supplierName, status, note;
  final DateTime date, createdAt, updatedAt;
  final DateTime? deletedAt;
  final List<PurchaseItem> items;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  bool get isDeleted => deletedAt != null;
  bool get isReceived => status.toLowerCase() == 'received';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
  double get subtotal => items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  int get totalUnits => items.fold<int>(0, (sum, item) => sum + item.quantity);

  Purchase copyWith({String? purchaseNo, String? supplierId, String? supplierName, DateTime? date, String? status, List<PurchaseItem>? items, String? note, DateTime? createdAt, DateTime? updatedAt, DateTime? deletedAt, bool clearDeletedAt = false, String? deviceId, String? syncStatus, String? storeId, String? branchId, int? version, String? lastModifiedByDeviceId}) => Purchase(
        id: id,
        purchaseNo: purchaseNo ?? this.purchaseNo,
        supplierId: supplierId ?? this.supplierId,
        supplierName: supplierName ?? this.supplierName,
        date: date ?? this.date,
        status: status ?? this.status,
        items: items ?? this.items,
        note: note ?? this.note,
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
        'purchaseNo': purchaseNo,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'date': date.toIso8601String(),
        'status': status,
        'items': items.map((item) => item.toJson()).toList(),
        'note': note,
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

  factory Purchase.fromJson(Map<String, dynamic> json) {
    final updated = DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now();
    return Purchase(
      id: json['id']?.toString() ?? '',
      purchaseNo: json['purchaseNo']?.toString() ?? '',
      supplierId: json['supplierId']?.toString() ?? '',
      supplierName: json['supplierName']?.toString() ?? '',
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? updated,
      status: json['status']?.toString() ?? 'Draft',
      items: (json['items'] as List? ?? const []).map((item) => PurchaseItem.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
      note: json['note']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? updated,
      updatedAt: updated,
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
