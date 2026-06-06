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
    this.paymentStatus = 'paid',
    this.paidAmount = 0,
    this.cancelReason = '',
    this.cancelledByDeviceId = '',
    this.reversalApplied = false,
    this.cancelledAt,
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

  final String id, purchaseNo, supplierId, supplierName, status, note, paymentStatus, cancelReason, cancelledByDeviceId;
  final DateTime date, createdAt, updatedAt;
  final DateTime? deletedAt, cancelledAt;
  final bool reversalApplied;
  final double paidAmount;
  final List<PurchaseItem> items;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  bool get isDeleted => deletedAt != null;
  bool get isReceived => status.toLowerCase() == 'received';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
  double get subtotal => isCancelled ? 0 : items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  double get balanceDue => (subtotal - paidAmount).clamp(0, double.infinity).toDouble();
  double get totalUnits => items.fold<double>(0, (sum, item) => sum + item.baseQuantity);

  Purchase copyWith({String? purchaseNo, String? supplierId, String? supplierName, DateTime? date, String? status, List<PurchaseItem>? items, String? note, String? paymentStatus, double? paidAmount, String? cancelReason, String? cancelledByDeviceId, bool? reversalApplied, DateTime? cancelledAt, DateTime? createdAt, DateTime? updatedAt, DateTime? deletedAt, bool clearDeletedAt = false, String? deviceId, String? syncStatus, String? storeId, String? branchId, int? version, String? lastModifiedByDeviceId}) => Purchase(
        id: id,
        purchaseNo: purchaseNo ?? this.purchaseNo,
        supplierId: supplierId ?? this.supplierId,
        supplierName: supplierName ?? this.supplierName,
        date: date ?? this.date,
        status: status ?? this.status,
        items: items ?? this.items,
        note: note ?? this.note,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        paidAmount: paidAmount ?? this.paidAmount,
        cancelReason: cancelReason ?? this.cancelReason,
        cancelledByDeviceId: cancelledByDeviceId ?? this.cancelledByDeviceId,
        reversalApplied: reversalApplied ?? this.reversalApplied,
        cancelledAt: cancelledAt ?? this.cancelledAt,
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
        'paymentStatus': paymentStatus,
        'paidAmount': paidAmount,
        'cancelReason': cancelReason,
        'cancelledByDeviceId': cancelledByDeviceId,
        'reversalApplied': reversalApplied,
        'cancelledAt': cancelledAt?.toIso8601String(),
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
      paymentStatus: json['paymentStatus']?.toString() ?? 'paid',
      paidAmount: (json['paidAmount'] as num? ?? 0).toDouble(),
      cancelReason: json['cancelReason']?.toString() ?? '',
      cancelledByDeviceId: json['cancelledByDeviceId']?.toString() ?? '',
      reversalApplied: json['reversalApplied'] == true,
      cancelledAt: DateTime.tryParse(json['cancelledAt']?.toString() ?? ''),
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
