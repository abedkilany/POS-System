
class PlatformStore {
  PlatformStore({
    required this.id,
    required this.name,
    this.ownerUserId = '',
    this.phone = '',
    this.address = '',
    this.description = '',
    this.isOnlineEnabled = false,
    this.subscriptionPlan = 'free',
    this.subscriptionStatus = 'trial',
    this.commissionRate = 0,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  final String name;
  final String ownerUserId;
  final String phone;
  final String address;
  final String description;
  final bool isOnlineEnabled;
  final String subscriptionPlan;
  final String subscriptionStatus;
  final double commissionRate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlatformStore copyWith({
    String? name,
    String? ownerUserId,
    String? phone,
    String? address,
    String? description,
    bool? isOnlineEnabled,
    String? subscriptionPlan,
    String? subscriptionStatus,
    double? commissionRate,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PlatformStore(
        id: id,
        name: name ?? this.name,
        ownerUserId: ownerUserId ?? this.ownerUserId,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        description: description ?? this.description,
        isOnlineEnabled: isOnlineEnabled ?? this.isOnlineEnabled,
        subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
        subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
        commissionRate: commissionRate ?? this.commissionRate,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ownerUserId': ownerUserId,
        'phone': phone,
        'address': address,
        'description': description,
        'isOnlineEnabled': isOnlineEnabled,
        'subscriptionPlan': subscriptionPlan,
        'subscriptionStatus': subscriptionStatus,
        'commissionRate': commissionRate,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PlatformStore.fromJson(Map<String, dynamic> json) => PlatformStore(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        ownerUserId: json['ownerUserId']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        isOnlineEnabled: json['isOnlineEnabled'] == true,
        subscriptionPlan: json['subscriptionPlan']?.toString() ?? 'free',
        subscriptionStatus: json['subscriptionStatus']?.toString() ?? 'trial',
        commissionRate: (json['commissionRate'] as num?)?.toDouble() ?? 0,
        isActive: json['isActive'] != false,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

