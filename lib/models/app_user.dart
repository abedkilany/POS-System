class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.passwordHash,
    required this.roleId,
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
        'extraPermissions': extraPermissions.toList(),
        'deniedPermissions': deniedPermissions.toList(),
        'isActive': isActive,
        'isSystem': isSystem,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        passwordHash: json['passwordHash']?.toString() ?? '',
        roleId: json['roleId']?.toString() ?? '',
        extraPermissions: Set<String>.from((json['extraPermissions'] as List? ?? const []).map((e) => e.toString())),
        deniedPermissions: Set<String>.from((json['deniedPermissions'] as List? ?? const []).map((e) => e.toString())),
        isActive: json['isActive'] != false,
        isSystem: json['isSystem'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
        lastLoginAt: DateTime.tryParse(json['lastLoginAt']?.toString() ?? ''),
      );
}
