class AppPermissionPage {
  const AppPermissionPage({
    required this.id,
    required this.title,
    required this.order,
    required this.accessPermission,
    required this.permissions,
    this.navigationPermissions = const <String>[],
  });

  final String id;
  final String title;
  final int order;
  final String accessPermission;
  final List<String> permissions;
  final List<String> navigationPermissions;
}

class AppPermission {
  static const String dashboardView = 'dashboard.view';
  static const String settingsView = 'settings.view';
  static const String usersManage = 'users.manage';
  static const String rolesManage = 'roles.manage';
  static const String permissionsManage = 'permissions.manage';
  static const String usersView = 'users.view';
  static const String rolesView = 'roles.view';
  static const String productsView = 'products.view';
  static const String productsManage = 'products.manage';
  static const String salesCreate = 'sales.create';
  static const String salesView = 'sales.view';
  static const String salesEdit = 'sales.edit';
  static const String salesCancel = 'sales.cancel';
  static const String salesPrint = 'sales.print';
  static const String salesExport = 'sales.export';
  static const String quotationsManage = 'sales.quotations.manage';
  static const String deliveryNotesManage = 'sales.delivery_notes.manage';
  static const String purchasesView = 'purchases.view';
  static const String purchasesManage = 'purchases.manage';
  static const String purchasesCancel = 'purchases.cancel';
  static const String purchasesPrint = 'purchases.print';
  static const String purchasesExport = 'purchases.export';
  static const String productsCreate = 'products.create';
  static const String productsEdit = 'products.edit';
  static const String productsDelete = 'products.delete';
  static const String catalogManage = 'catalog.manage';
  static const String customersView = 'customers.view';
  static const String customersManage = 'customers.manage';
  static const String customersLedgerView = 'customers.ledger.view';
  static const String customersPaymentManage = 'customers.payment.manage';
  static const String suppliersView = 'suppliers.view';
  static const String suppliersManage = 'suppliers.manage';
  static const String suppliersLedgerView = 'suppliers.ledger.view';
  static const String suppliersPaymentManage = 'suppliers.payment.manage';
  static const String expensesView = 'expenses.view';
  static const String expensesManage = 'expenses.manage';
  static const String expensesApprove = 'expenses.approve';
  static const String expensesCancel = 'expenses.cancel';
  static const String expensesDelete = 'expenses.delete';
  static const String reportsView = 'reports.view';
  static const String reportsExport = 'reports.export';
  static const String accountingView = 'accounting.view';
  static const String accountingManage = 'accounting.manage';
  static const String inventoryView = 'inventory.view';
  static const String inventoryWarehousesManage = 'inventory.warehouses.manage';
  static const String inventoryMovementsView = 'inventory.movements.view';
  static const String inventoryCorrectionsManage =
      'inventory.corrections.manage';
  static const String inventoryCountsManage = 'inventory.counts.manage';
  static const String inventoryWasteView = 'inventory.waste.view';
  static const String inventoryWasteManage = 'inventory.waste.manage';
  static const String inventoryManufacturingManage =
      'inventory.manufacturing.manage';
  static const String backupExport = 'backup.export';
  static const String backupRestore = 'backup.restore';
  static const String backupManage = 'backup.manage';
  static const String settingsManage = 'settings.manage';
  static const String syncView = 'sync.view';
  static const String syncManage = 'sync.manage';
  static const String databaseView = 'database.view';
  static const String databaseManage = 'database.manage';
  static const String maintenanceView = 'maintenance.view';
  static const String maintenanceManage = 'maintenance.manage';

  static const List<String> all = [
    dashboardView,
    settingsView,
    usersManage,
    rolesManage,
    permissionsManage,
    usersView,
    rolesView,
    productsView,
    productsManage,
    salesView,
    salesCreate,
    salesEdit,
    salesCancel,
    salesPrint,
    salesExport,
    quotationsManage,
    deliveryNotesManage,
    purchasesView,
    purchasesManage,
    purchasesCancel,
    purchasesPrint,
    purchasesExport,
    productsCreate,
    productsEdit,
    productsDelete,
    catalogManage,
    customersView,
    customersManage,
    customersLedgerView,
    customersPaymentManage,
    suppliersView,
    suppliersManage,
    suppliersLedgerView,
    suppliersPaymentManage,
    expensesView,
    expensesManage,
    expensesApprove,
    expensesCancel,
    expensesDelete,
    reportsView,
    reportsExport,
    accountingView,
    accountingManage,
    inventoryView,
    inventoryWarehousesManage,
    inventoryMovementsView,
    inventoryCorrectionsManage,
    inventoryCountsManage,
    inventoryWasteView,
    inventoryWasteManage,
    inventoryManufacturingManage,
    backupExport,
    backupRestore,
    backupManage,
    settingsManage,
    syncView,
    syncManage,
    databaseView,
    databaseManage,
    maintenanceView,
    maintenanceManage,
  ];

  static const Map<String, String> labels = {
    dashboardView: 'View dashboard',
    settingsView: 'View settings',
    usersManage: 'Manage users',
    rolesManage: 'Manage roles',
    permissionsManage: 'Manage permission catalog',
    usersView: 'View users',
    rolesView: 'View roles',
    productsView: 'View products',
    productsManage: 'Manage products',
    salesView: 'View sales',
    salesCreate: 'Create sales',
    salesEdit: 'Edit sales',
    salesCancel: 'Cancel/refund sales',
    salesPrint: 'Print sales documents',
    salesExport: 'Export sales data',
    quotationsManage: 'Manage quotations',
    deliveryNotesManage: 'Manage delivery notes',
    purchasesView: 'View purchases',
    purchasesManage: 'Manage purchases',
    purchasesCancel: 'Cancel purchases',
    purchasesPrint: 'Print purchases',
    purchasesExport: 'Export purchases',
    productsCreate: 'Create products',
    productsEdit: 'Edit products',
    productsDelete: 'Delete products',
    catalogManage: 'Manage categories/units',
    customersView: 'View customers',
    customersManage: 'Manage customers',
    customersLedgerView: 'View customer ledger',
    customersPaymentManage: 'Manage customer payments',
    suppliersView: 'View suppliers',
    suppliersManage: 'Manage suppliers',
    suppliersLedgerView: 'View supplier ledger',
    suppliersPaymentManage: 'Manage supplier payments',
    expensesView: 'View expenses',
    expensesManage: 'Manage expenses',
    expensesApprove: 'Approve expenses',
    expensesCancel: 'Cancel expenses',
    expensesDelete: 'Delete expenses',
    reportsView: 'View reports',
    reportsExport: 'Export reports',
    accountingView: 'View accounting',
    accountingManage: 'Manage accounting',
    inventoryView: 'View inventory',
    inventoryWarehousesManage: 'Manage warehouses',
    inventoryMovementsView: 'View inventory movements',
    inventoryCorrectionsManage: 'Manage inventory corrections',
    inventoryCountsManage: 'Manage stock counts',
    inventoryWasteView: 'View waste and loss',
    inventoryWasteManage: 'Manage waste and loss',
    inventoryManufacturingManage: 'Manage manufacturing',
    backupExport: 'Export backups',
    backupRestore: 'Restore backups',
    backupManage: 'Manage backups',
    settingsManage: 'Manage store settings',
    syncView: 'View LAN sync',
    syncManage: 'Manage LAN sync',
    databaseView: 'View database',
    databaseManage: 'Manage database',
    maintenanceView: 'View maintenance',
    maintenanceManage: 'Manage maintenance',
  };

  static const List<AppPermissionPage> pages = [
    AppPermissionPage(
      id: 'dashboard',
      title: 'Dashboard',
      order: 0,
      accessPermission: dashboardView,
      permissions: [dashboardView],
    ),
    AppPermissionPage(
      id: 'users',
      title: 'Users',
      order: 1,
      accessPermission: usersView,
      permissions: [
        usersView,
        usersManage,
      ],
    ),
    AppPermissionPage(
      id: 'roles',
      title: 'Roles',
      order: 2,
      accessPermission: rolesView,
      permissions: [
        rolesView,
        rolesManage,
      ],
    ),
    AppPermissionPage(
      id: 'permission_catalog',
      title: 'Permission Catalog',
      order: 3,
      accessPermission: permissionsManage,
      permissions: [
        permissionsManage,
      ],
    ),
    AppPermissionPage(
      id: 'settings',
      title: 'Settings',
      order: 4,
      accessPermission: settingsView,
      navigationPermissions: [
        settingsView,
        settingsManage,
        usersManage,
        rolesManage,
        permissionsManage,
        syncView,
        syncManage,
        backupExport,
        backupRestore,
        backupManage,
      ],
      permissions: [settingsView, settingsManage],
    ),
    AppPermissionPage(
      id: 'products',
      title: 'Products',
      order: 5,
      accessPermission: productsView,
      permissions: [
        productsView,
        productsManage,
        productsCreate,
        productsEdit,
        productsDelete,
      ],
    ),
    AppPermissionPage(
      id: 'catalog',
      title: 'Catalog',
      order: 6,
      accessPermission: catalogManage,
      permissions: [
        catalogManage,
      ],
    ),
    AppPermissionPage(
      id: 'sales',
      title: 'Sales',
      order: 7,
      accessPermission: salesView,
      permissions: [
        salesView,
        salesCreate,
        salesEdit,
        salesCancel,
        salesPrint,
        salesExport,
      ],
    ),
    AppPermissionPage(
      id: 'quotations',
      title: 'Quotations',
      order: 8,
      accessPermission: quotationsManage,
      permissions: [
        quotationsManage,
      ],
    ),
    AppPermissionPage(
      id: 'delivery_notes',
      title: 'Delivery Notes',
      order: 9,
      accessPermission: deliveryNotesManage,
      permissions: [
        deliveryNotesManage,
      ],
    ),
    AppPermissionPage(
      id: 'purchases',
      title: 'Purchases',
      order: 10,
      accessPermission: purchasesView,
      permissions: [
        purchasesView,
        purchasesManage,
        purchasesCancel,
        purchasesPrint,
        purchasesExport,
      ],
    ),
    AppPermissionPage(
      id: 'customers',
      title: 'Customers',
      order: 11,
      accessPermission: customersView,
      permissions: [
        customersView,
        customersManage,
        customersLedgerView,
        customersPaymentManage,
      ],
    ),
    AppPermissionPage(
      id: 'suppliers',
      title: 'Suppliers',
      order: 12,
      accessPermission: suppliersView,
      permissions: [
        suppliersView,
        suppliersManage,
        suppliersLedgerView,
        suppliersPaymentManage,
      ],
    ),
    AppPermissionPage(
      id: 'expenses',
      title: 'Expenses',
      order: 13,
      accessPermission: expensesView,
      permissions: [
        expensesView,
        expensesManage,
        expensesApprove,
        expensesCancel,
        expensesDelete,
      ],
    ),
    AppPermissionPage(
      id: 'reports',
      title: 'Reports',
      order: 14,
      accessPermission: reportsView,
      permissions: [reportsView, reportsExport],
    ),
    AppPermissionPage(
      id: 'accounting',
      title: 'Accounting',
      order: 15,
      accessPermission: accountingView,
      permissions: [accountingView, accountingManage],
    ),
    AppPermissionPage(
      id: 'inventory',
      title: 'Inventory',
      order: 16,
      accessPermission: inventoryView,
      navigationPermissions: [
        inventoryView,
        inventoryWarehousesManage,
        inventoryMovementsView,
        inventoryCorrectionsManage,
        inventoryCountsManage,
        inventoryWasteView,
        inventoryWasteManage,
        inventoryManufacturingManage,
      ],
      permissions: [
        inventoryView,
      ],
    ),
    AppPermissionPage(
      id: 'warehouses',
      title: 'Warehouses',
      order: 17,
      accessPermission: inventoryWarehousesManage,
      permissions: [
        inventoryWarehousesManage,
      ],
    ),
    AppPermissionPage(
      id: 'inventory_movements',
      title: 'Inventory Movements',
      order: 18,
      accessPermission: inventoryMovementsView,
      permissions: [
        inventoryMovementsView,
      ],
    ),
    AppPermissionPage(
      id: 'inventory_corrections',
      title: 'Inventory Corrections',
      order: 19,
      accessPermission: inventoryCorrectionsManage,
      permissions: [
        inventoryCorrectionsManage,
      ],
    ),
    AppPermissionPage(
      id: 'inventory_counts',
      title: 'Stock Counts',
      order: 20,
      accessPermission: inventoryCountsManage,
      permissions: [
        inventoryCountsManage,
      ],
    ),
    AppPermissionPage(
      id: 'inventory_waste',
      title: 'Waste and Loss',
      order: 21,
      accessPermission: inventoryWasteView,
      permissions: [
        inventoryWasteView,
        inventoryWasteManage,
      ],
    ),
    AppPermissionPage(
      id: 'manufacturing',
      title: 'Manufacturing',
      order: 22,
      accessPermission: inventoryManufacturingManage,
      permissions: [
        inventoryManufacturingManage,
      ],
    ),
    AppPermissionPage(
      id: 'backups',
      title: 'Backups',
      order: 23,
      accessPermission: backupManage,
      permissions: [backupExport, backupRestore, backupManage],
    ),
    AppPermissionPage(
      id: 'sync',
      title: 'Sync',
      order: 24,
      accessPermission: syncView,
      permissions: [syncView, syncManage],
    ),
    AppPermissionPage(
      id: 'database',
      title: 'Database',
      order: 25,
      accessPermission: databaseView,
      permissions: [databaseView, databaseManage],
    ),
    AppPermissionPage(
      id: 'maintenance',
      title: 'Maintenance',
      order: 26,
      accessPermission: maintenanceView,
      permissions: [maintenanceView, maintenanceManage],
    ),
  ];

  static AppPermissionPage? pageForPermission(String permission) {
    for (final page in pages) {
      if (page.accessPermission == permission ||
          page.permissions.contains(permission)) {
        return page;
      }
    }
    return null;
  }

  static AppPermissionPage? pageById(String pageId) {
    for (final page in pages) {
      if (page.id == pageId) return page;
    }
    return null;
  }

  static List<String> permissionsForPage(String pageId) {
    return List<String>.unmodifiable(
        pageById(pageId)?.permissions ?? const <String>[]);
  }

  static String pageTitleForPermission(String permission) {
    return pageForPermission(permission)?.title ?? 'Other';
  }
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

  UserRole copyWith(
      {String? name,
      Set<String>? permissions,
      bool? isSystem,
      DateTime? createdAt,
      DateTime? updatedAt}) {
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
        permissions: Set<String>.from((json['permissions'] as List? ?? const [])
            .map((e) => e.toString())),
        isSystem: json['isSystem'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      );
}
