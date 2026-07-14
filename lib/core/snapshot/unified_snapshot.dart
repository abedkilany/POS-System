class UnifiedSnapshotSection {
  const UnifiedSnapshotSection({
    required this.id,
    required this.labelKey,
    required this.order,
    required this.collections,
  });

  final String id;
  final String labelKey;
  final int order;
  final List<String> collections;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'labelKey': labelKey,
        'order': order,
        'collections': collections,
      };
}

class UnifiedSnapshotManifest {
  const UnifiedSnapshotManifest({
    required this.jobId,
    required this.generatedAt,
    required this.storeId,
    required this.branchId,
    required this.deviceId,
    required this.storeEpoch,
    required this.kind,
    required this.totalChunks,
    required this.sections,
  });

  static const format = 'ventio_unified_snapshot';
  static const version = 1;

  final String jobId;
  final String generatedAt;
  final String storeId;
  final String branchId;
  final String deviceId;
  final String storeEpoch;
  final String kind;
  final int totalChunks;
  final List<UnifiedSnapshotSection> sections;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'format': format,
        'version': version,
        'jobId': jobId,
        'generatedAt': generatedAt,
        'storeId': storeId,
        'branchId': branchId,
        'deviceId': deviceId,
        'storeEpoch': storeEpoch,
        'kind': kind,
        'totalChunks': totalChunks,
        'sections': sections.map((item) => item.toJson()).toList(),
      };
}

class UnifiedSnapshotCatalog {
  const UnifiedSnapshotCatalog._();

  static const loginSettingsAndUsers = UnifiedSnapshotSection(
    id: 'login_settings_users',
    labelKey: 'snapshot_section_login_settings_users',
    order: 10,
    collections: <String>['_meta', 'roles', 'users'],
  );

  static const catalogsAndWarehouses = UnifiedSnapshotSection(
    id: 'catalogs_warehouses',
    labelKey: 'snapshot_section_catalogs_warehouses',
    order: 20,
    collections: <String>['categories', 'brands', 'units', 'warehouses'],
  );

  static const productsCustomersSuppliers = UnifiedSnapshotSection(
    id: 'products_customers_suppliers',
    labelKey: 'snapshot_section_products_customers_suppliers',
    order: 30,
    collections: <String>[
      'products',
      'customers',
      'suppliers',
      'supplierProductPrices',
      'priceLists',
      'productPrices',
      'productPriceOverrides',
      'productCosts',
    ],
  );

  static const inventoryMovements = UnifiedSnapshotSection(
    id: 'inventory_movements',
    labelKey: 'snapshot_section_inventory_movements',
    order: 40,
    collections: <String>[
      'stockMovements',
      'inventoryCounts',
      'warehouseInventory',
      'stockOperations',
      'inventoryReconciliations',
      'inventoryMigrationAdjustments',
      'costingMethodHistory',
      'inventoryCostingMethod',
      'inventoryCostLayers',
    ],
  );

  static const salesAndPurchases = UnifiedSnapshotSection(
    id: 'sales_purchases',
    labelKey: 'snapshot_section_sales_purchases',
    order: 50,
    collections: <String>[
      'sales',
      'saleQuotations',
      'deliveryNotes',
      'purchases',
    ],
  );

  static const accountingAndReports = UnifiedSnapshotSection(
    id: 'accounting_reports',
    labelKey: 'snapshot_section_accounting_reports',
    order: 60,
    collections: <String>[
      'expenses',
      'accountTransactions',
      'billsOfMaterials',
      'manufacturingOrders',
    ],
  );

  static const sections = <UnifiedSnapshotSection>[
    loginSettingsAndUsers,
    catalogsAndWarehouses,
    productsCustomersSuppliers,
    inventoryMovements,
    salesAndPurchases,
    accountingAndReports,
  ];

  static UnifiedSnapshotSection sectionForCollection(String collection) {
    for (final section in sections) {
      if (section.collections.contains(collection)) return section;
    }
    return accountingAndReports;
  }

  static List<UnifiedSnapshotSection> sectionsForCollections(
      Iterable<String> collections) {
    final set = collections.toSet();
    return sections
        .where((section) =>
            section.collections.any((collection) => set.contains(collection)))
        .toList(growable: false);
  }
}
