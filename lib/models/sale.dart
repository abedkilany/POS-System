import 'sale_item.dart';

class Sale {
  Sale({
    required this.id,
    required this.invoiceNo,
    required this.customerName,
    required this.date,
    required this.status,
    required this.items,
    required this.discount,
    this.paymentMethod = 'Cash',
    this.note = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
  })  : createdAt = createdAt ?? updatedAt ?? date,
        updatedAt = updatedAt ?? createdAt ?? date;

  final String id;
  final String invoiceNo;
  final String customerName;
  final DateTime date;
  final String status;
  final List<SaleItem> items;
  final double discount;
  final String paymentMethod;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final String syncStatus;

  bool get isDeleted => deletedAt != null;

  bool get isCancelled => status.toLowerCase() == 'cancelled' || status.toLowerCase() == 'returned';
  double get subtotal => items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  double get total => isCancelled ? 0 : (subtotal - discount).clamp(0, double.infinity).toDouble();
  double get grossProfit => isCancelled ? 0 : items.fold<double>(0, (sum, item) => sum + item.lineProfit) - discount;

  Sale copyWith({
    String? id,
    String? invoiceNo,
    String? customerName,
    DateTime? date,
    String? status,
    List<SaleItem>? items,
    double? discount,
    String? paymentMethod,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    String? deviceId,
    String? syncStatus,
  }) {
    return Sale(
      id: id ?? this.id,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      customerName: customerName ?? this.customerName,
      date: date ?? this.date,
      status: status ?? this.status,
      items: items ?? this.items,
      discount: discount ?? this.discount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      deviceId: deviceId ?? this.deviceId,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoiceNo': invoiceNo,
        'customerName': customerName,
        'date': date.toIso8601String(),
        'status': status,
        'discount': discount,
        'paymentMethod': paymentMethod,
        'note': note,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'deviceId': deviceId,
        'syncStatus': syncStatus,
      };

  factory Sale.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now();
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? date;
    return Sale(
      id: json['id'] as String,
      invoiceNo: json['invoiceNo'] as String,
      customerName: json['customerName'] as String,
      date: date,
      status: json['status'] as String? ?? 'Paid',
      discount: (json['discount'] as num? ?? 0).toDouble(),
      paymentMethod: json['paymentMethod'] as String? ?? 'Cash',
      note: json['note'] as String? ?? '',
      items: (json['items'] as List<dynamic>)
          .map((item) => SaleItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? date,
      updatedAt: updated,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
      deviceId: json['deviceId'] as String? ?? '',
      syncStatus: json['syncStatus'] as String? ?? 'synced',
    );
  }
}
