class AppPermission {
  static const String usersManage = 'users.manage';
  static const String rolesManage = 'roles.manage';
  static const String salesCreate = 'sales.create';
  static const String salesCancel = 'sales.cancel';
  static const String productsCreate = 'products.create';
  static const String productsEdit = 'products.edit';
  static const String productsDelete = 'products.delete';
  static const String catalogManage = 'catalog.manage';
  static const String customersManage = 'customers.manage';
  static const String suppliersManage = 'suppliers.manage';
  static const String expensesManage = 'expenses.manage';
  static const String reportsView = 'reports.view';
  static const String backupExport = 'backup.export';
  static const String backupRestore = 'backup.restore';
  static const String settingsManage = 'settings.manage';
  static const String syncManage = 'sync.manage';

  static const List<String> all = [
    usersManage,
    rolesManage,
    salesCreate,
    salesCancel,
    productsCreate,
    productsEdit,
    productsDelete,
    catalogManage,
    customersManage,
    suppliersManage,
    expensesManage,
    reportsView,
    backupExport,
    backupRestore,
    settingsManage,
    syncManage,
  ];

  static const Map<String, String> labels = {
    usersManage: 'Manage users',
    rolesManage: 'Manage roles',
    salesCreate: 'Create sales',
    salesCancel: 'Cancel/refund sales',
    productsCreate: 'Create products',
    productsEdit: 'Edit products',
    productsDelete: 'Delete products',
    catalogManage: 'Manage categories/units',
    customersManage: 'Manage customers',
    suppliersManage: 'Manage suppliers',
    expensesManage: 'Manage expenses',
    reportsView: 'View reports',
    backupExport: 'Export backups',
    backupRestore: 'Restore backups',
    settingsManage: 'Manage store settings',
    syncManage: 'Manage LAN sync',
  };
}

class UserRole {
  const UserRole({
    required this.id,
    required this.name,
    required this.permissions,
    this.isSystem = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final Set<String> permissions;
  final bool isSystem;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isAdmin => id == 'admin';

  UserRole copyWith({String? name, Set<String>? permissions, bool? isSystem, DateTime? createdAt, DateTime? updatedAt}) {
    return UserRole(
      id: id,
      name: name ?? this.name,
      permissions: permissions ?? this.permissions,
      isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'permissions': permissions.toList(),
        'isSystem': isSystem,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory UserRole.fromJson(Map<String, dynamic> json) => UserRole(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        permissions: Set<String>.from((json['permissions'] as List? ?? const []).map((e) => e.toString())),
        isSystem: json['isSystem'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      );
}
