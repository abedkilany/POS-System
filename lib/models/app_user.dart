class AccountType {
  static const String appAdmin = 'app_admin';
  static const String platformUser = 'platform_user';
  static const String merchant = 'merchant';
  static const String customer = 'customer';
  static const String driver = 'driver';

  static const List<String> publicSignupTypes = [platformUser];
  static const List<String> all = [appAdmin, platformUser, merchant, customer, driver];

  static const Map<String, String> labels = {
    appAdmin: 'App administration',
    platformUser: 'Platform account',
    merchant: 'Merchant / store',
    customer: 'Customer',
    driver: 'Delivery driver',
  };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.passwordHash,
    required this.roleId,
    this.accountType = AccountType.merchant,
    this.phone = '',
    this.email = '',
    this.primaryStoreId = '',
    this.extraPermissions = const <String>{},
    this.deniedPermissions = const <String>{},
    this.isActive = true,
    this.isSystem = false,
    this.createdAt,
    this.updatedAt,
    this.lastLoginAt,
  });

  final String id;
  final String fullName;
  final String username;
  final String passwordHash;
  final String roleId;
  final String accountType;
  final String phone;
  final String email;
  final String primaryStoreId;
  final Set<String> extraPermissions;
  final Set<String> deniedPermissions;
  final bool isActive;
  final bool isSystem;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;

  AppUser copyWith({
    String? fullName,
    String? username,
    String? passwordHash,
    String? roleId,
    String? accountType,
    String? phone,
    String? email,
    String? primaryStoreId,
    Set<String>? extraPermissions,
    Set<String>? deniedPermissions,
    bool? isActive,
    bool? isSystem,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
  }) {
    return AppUser(
      id: id,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      roleId: roleId ?? this.roleId,
      accountType: accountType ?? this.accountType,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      primaryStoreId: primaryStoreId ?? this.primaryStoreId,
      extraPermissions: extraPermissions ?? this.extraPermissions,
      deniedPermissions: deniedPermissions ?? this.deniedPermissions,
      isActive: isActive ?? this.isActive,
      isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'username': username,
        'passwordHash': passwordHash,
        'roleId': roleId,
        'accountType': accountType,
        'phone': phone,
        'email': email,
        'primaryStoreId': primaryStoreId,
        'extraPermissions': extraPermissions.toList(),
        'deniedPermissions': deniedPermissions.toList(),
        'isActive': isActive,
        'isSystem': isSystem,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final roleId = json['roleId']?.toString() ?? '';
    final inferredAccountType = switch (roleId) {
      'admin' || 'platform_admin' => AccountType.appAdmin,
      'customer' => AccountType.customer,
      'driver' => AccountType.driver,
      'platform_user' => AccountType.platformUser,
      _ => AccountType.platformUser,
    };
    return AppUser(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      passwordHash: json['passwordHash']?.toString() ?? '',
      roleId: roleId,
      accountType: json['accountType']?.toString() ?? inferredAccountType,
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      primaryStoreId: json['primaryStoreId']?.toString() ?? '',
      extraPermissions: Set<String>.from((json['extraPermissions'] as List? ?? const []).map((e) => e.toString())),
      deniedPermissions: Set<String>.from((json['deniedPermissions'] as List? ?? const []).map((e) => e.toString())),
      isActive: json['isActive'] != false,
      isSystem: json['isSystem'] == true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      lastLoginAt: DateTime.tryParse(json['lastLoginAt']?.toString() ?? ''),
    );
  }
}
