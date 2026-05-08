class StoreMemberRole {
  static const String owner = 'owner';
  static const String manager = 'manager';
  static const String cashier = 'cashier';
  static const String inventoryManager = 'inventory_manager';
  static const String accountant = 'accountant';
  static const String ordersStaff = 'orders_staff';

  static const List<String> all = [owner, manager, cashier, inventoryManager, accountant, ordersStaff];

  static const Map<String, String> labels = {
    owner: 'Owner',
    manager: 'Manager',
    cashier: 'Cashier',
    inventoryManager: 'Inventory manager',
    accountant: 'Accountant',
    ordersStaff: 'Online orders staff',
  };
}

class StoreMember {
  StoreMember({
    required this.id,
    required this.storeId,
    required this.userId,
    required this.role,
    this.permissions = const <String>{},
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  final String storeId;
  final String userId;
  final String role;
  final Set<String> permissions;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  StoreMember copyWith({
    String? storeId,
    String? userId,
    String? role,
    Set<String>? permissions,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      StoreMember(
        id: id,
        storeId: storeId ?? this.storeId,
        userId: userId ?? this.userId,
        role: role ?? this.role,
        permissions: permissions ?? this.permissions,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'storeId': storeId,
        'userId': userId,
        'role': role,
        'permissions': permissions.toList(),
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory StoreMember.fromJson(Map<String, dynamic> json) => StoreMember(
        id: json['id']?.toString() ?? '',
        storeId: json['storeId']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        role: json['role']?.toString() ?? StoreMemberRole.cashier,
        permissions: Set<String>.from((json['permissions'] as List? ?? const []).map((e) => e.toString())),
        isActive: json['isActive'] != false,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );
}
