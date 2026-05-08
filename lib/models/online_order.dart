
class OnlineOrderStatus {
  static const String draft = 'draft';
  static const String placed = 'placed';
  static const String accepted = 'accepted';
  static const String preparing = 'preparing';
  static const String readyForDelivery = 'ready_for_delivery';
  static const String assignedToDriver = 'assigned_to_driver';
  static const String outForDelivery = 'out_for_delivery';
  static const String delivered = 'delivered';
  static const String cancelled = 'cancelled';

  static const List<String> all = [draft, placed, accepted, preparing, readyForDelivery, assignedToDriver, outForDelivery, delivered, cancelled];
}

class OnlineOrderItem {
  const OnlineOrderItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
  });

  final String productId;
  final String productName;
  final double unitPrice;
  final int quantity;
  double get total => unitPrice * quantity;

  Map<String, dynamic> toJson() => {'productId': productId, 'productName': productName, 'unitPrice': unitPrice, 'quantity': quantity};
  factory OnlineOrderItem.fromJson(Map<String, dynamic> json) => OnlineOrderItem(
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      );
}

class OnlineOrder {
  OnlineOrder({
    required this.id,
    required this.storeId,
    required this.customerUserId,
    required this.customerName,
    this.customerPhone = '',
    this.deliveryAddress = '',
    this.notes = '',
    this.status = OnlineOrderStatus.placed,
    this.items = const <OnlineOrderItem>[],
    this.deliveryFee = 0,
    this.discount = 0,
    this.paymentMethod = 'cash_on_delivery',
    this.paymentStatus = 'unpaid',
    this.assignedDriverUserId = '',
    this.isDeleted = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  final String storeId;
  final String customerUserId;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final String notes;
  final String status;
  final List<OnlineOrderItem> items;
  final double deliveryFee;
  final double discount;
  final String paymentMethod;
  final String paymentStatus;
  final String assignedDriverUserId;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get subtotal => items.fold<double>(0, (sum, item) => sum + item.total);
  double get total => subtotal + deliveryFee - discount;

  OnlineOrder copyWith({String? status, String? assignedDriverUserId, bool? isDeleted, DateTime? updatedAt}) => OnlineOrder(
        id: id,
        storeId: storeId,
        customerUserId: customerUserId,
        customerName: customerName,
        customerPhone: customerPhone,
        deliveryAddress: deliveryAddress,
        notes: notes,
        status: status ?? this.status,
        items: items,
        deliveryFee: deliveryFee,
        discount: discount,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        assignedDriverUserId: assignedDriverUserId ?? this.assignedDriverUserId,
        isDeleted: isDeleted ?? this.isDeleted,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'storeId': storeId,
        'customerUserId': customerUserId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'deliveryAddress': deliveryAddress,
        'notes': notes,
        'status': status,
        'items': items.map((item) => item.toJson()).toList(),
        'deliveryFee': deliveryFee,
        'discount': discount,
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'assignedDriverUserId': assignedDriverUserId,
        'isDeleted': isDeleted,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory OnlineOrder.fromJson(Map<String, dynamic> json) => OnlineOrder(
        id: json['id']?.toString() ?? '',
        storeId: json['storeId']?.toString() ?? '',
        customerUserId: json['customerUserId']?.toString() ?? '',
        customerName: json['customerName']?.toString() ?? '',
        customerPhone: json['customerPhone']?.toString() ?? '',
        deliveryAddress: json['deliveryAddress']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        status: json['status']?.toString() ?? OnlineOrderStatus.placed,
        items: (json['items'] as List<dynamic>? ?? const []).map((item) => OnlineOrderItem.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
        deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        paymentMethod: json['paymentMethod']?.toString() ?? 'cash_on_delivery',
        paymentStatus: json['paymentStatus']?.toString() ?? 'unpaid',
        assignedDriverUserId: json['assignedDriverUserId']?.toString() ?? '',
        isDeleted: json['isDeleted'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

