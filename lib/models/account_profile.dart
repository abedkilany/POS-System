class CustomerProfile {
  CustomerProfile({required this.userId, this.defaultAddress = '', this.phone = '', DateTime? createdAt, DateTime? updatedAt})
      : createdAt = createdAt ?? updatedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String userId;
  final String defaultAddress;
  final String phone;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'defaultAddress': defaultAddress,
        'phone': phone,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CustomerProfile.fromJson(Map<String, dynamic> json) => CustomerProfile(
        userId: json['userId']?.toString() ?? '',
        defaultAddress: json['defaultAddress']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

class DriverProfile {
  DriverProfile({required this.userId, this.phone = '', this.zone = '', this.isAvailable = false, DateTime? createdAt, DateTime? updatedAt})
      : createdAt = createdAt ?? updatedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String userId;
  final String phone;
  final String zone;
  final bool isAvailable;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'phone': phone,
        'zone': zone,
        'isAvailable': isAvailable,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
        userId: json['userId']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        zone: json['zone']?.toString() ?? '',
        isAvailable: json['isAvailable'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );
}
