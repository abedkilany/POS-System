part of 'local_database_service.dart';

extension _LocalDatabaseServiceImplPart2
    on _LocalDatabaseServiceImplementation {
  Future<void> replaceInventoryBatchRowsImmediate({
    required List<Map<String, dynamic>> batches,
    required List<Map<String, dynamic>> balances,
  }) async {
    final db = SqliteMigrationManager.database;
    if (_memoryStore != null ||
        _webStore != null ||
        !_sqliteReady ||
        db == null) {
      return;
    }
    await db.transaction(() async {
      await db.customStatement('DELETE FROM inventory_batch_balances');
      await db.customStatement('DELETE FROM inventory_batches');
      for (final row in batches) {
        await db.customStatement('''
          INSERT OR REPLACE INTO inventory_batches
            (id, product_id, product_name, supplier_batch_number,
             manufacturing_date, expiration_date, status, source_type,
             source_id, source_line_id, unit_cost, initial_quantity,
             cost_currency, exchange_rate, received_at, store_id, branch_id,
             created_at, updated_at, device_id,
             last_modified_by_device_id, sync_status, version)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', <Object?>[
          row['id']?.toString() ?? '',
          row['productId']?.toString() ?? '',
          row['productName']?.toString() ?? '',
          row['supplierBatchNumber']?.toString() ?? '',
          row['manufacturingDate']?.toString() ?? '',
          row['expirationDate']?.toString() ?? '',
          row['status']?.toString() ?? 'active',
          row['sourceType']?.toString() ?? '',
          row['sourceId']?.toString() ?? '',
          row['sourceLineId']?.toString() ?? '',
          (row['unitCost'] as num? ?? 0).toDouble(),
          (row['initialQuantity'] as num? ?? 0).toDouble(),
          row['costCurrency']?.toString() ?? 'USD',
          (row['exchangeRate'] as num? ?? 1).toDouble(),
          row['receivedAt']?.toString() ?? row['createdAt']?.toString() ?? '',
          row['storeId']?.toString() ?? '',
          row['branchId']?.toString() ?? 'main',
          row['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
          row['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
          row['deviceId']?.toString() ?? '',
          row['lastModifiedByDeviceId']?.toString() ?? '',
          row['syncStatus']?.toString() ?? 'synced',
          (row['version'] as num? ?? 1).toInt(),
        ]);
      }
      for (final row in balances) {
        await db.customStatement('''
          INSERT OR REPLACE INTO inventory_batch_balances
            (id, batch_id, product_id, warehouse_id, store_id, branch_id,
             quantity, reserved_quantity, version, created_at, updated_at,
             device_id, last_modified_by_device_id, sync_status)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', <Object?>[
          row['id']?.toString() ?? '',
          row['batchId']?.toString() ?? '',
          row['productId']?.toString() ?? '',
          row['warehouseId']?.toString() ?? 'main',
          row['storeId']?.toString() ?? '',
          row['branchId']?.toString() ?? 'main',
          (row['quantity'] as num? ?? 0).toDouble(),
          (row['reservedQuantity'] as num? ?? 0).toDouble(),
          (row['version'] as num? ?? 1).toInt(),
          row['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
          row['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
          row['deviceId']?.toString() ?? '',
          row['lastModifiedByDeviceId']?.toString() ?? '',
          row['syncStatus']?.toString() ?? 'synced',
        ]);
      }
    });
  }

  Future<List<Map<String, dynamic>>?>
      getInventoryMigrationAdjustmentsFromSqlite() async {
    if (_webStore != null) {
      final raw = _webStore![_webInventoryMigrationAdjustmentsKey];
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }
    if (_memoryStore != null || !_sqliteReady) {
      return null;
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return null;
    final rows = await db.customSelect('''
      SELECT id, migration_batch_id AS migrationBatchId, store_id AS storeId,
             branch_id AS branchId, warehouse_id AS warehouseId,
             product_id AS productId, legacy_product_stock AS legacyProductStock,
             ledger_balance AS ledgerBalance, applied_delta AS appliedDelta,
             created_at AS createdAt, updated_at AS updatedAt, notes
      FROM inventory_migration_adjustments
      ORDER BY migration_batch_id ASC, store_id ASC, warehouse_id ASC, product_id ASC
    ''').get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  Future<Map<String, List<Map<String, dynamic>>>>
      getPhase8AccountingSnapshotRows() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return const <String, List<Map<String, dynamic>>>{};
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return const <String, List<Map<String, dynamic>>>{};
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in phase8AccountingSnapshotTables.entries) {
      final rows = await db.customSelect('SELECT * FROM ${entry.value}').get();
      result[entry.key] = rows
          .map((row) => Map<String, dynamic>.from(row.data))
          .toList(growable: false);
    }
    return result;
  }

  Future<void> replacePhase8AccountingSnapshotRowsImmediate(
    Map<String, List<Map<String, dynamic>>> collections,
  ) async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) return;
    final db = SqliteMigrationManager.database;
    if (db == null) return;
    const deleteOrder = <String>[
      'accounting_audit_log',
      'journal_lines',
      'payment_allocations',
      'cash_refund_allocations',
      'cash_ledger_transactions',
      'cash_operations',
      'cash_transfers',
      'receipt_vouchers',
      'payment_vouchers',
      'cash_drawer_sessions',
      'payment_accounts',
      'cash_locations',
      'journal_entries',
      'accounting_periods',
      'accounting_settings',
      'accounts',
    ];
    final tableToCollection = <String, String>{
      for (final entry in phase8AccountingSnapshotTables.entries)
        entry.value: entry.key,
    };
    for (final table in deleteOrder) {
      final key = tableToCollection[table]!;
      if (!collections.containsKey(key)) continue;
      await db.customStatement('DELETE FROM $table');
    }
    for (final table in deleteOrder.reversed) {
      final key = tableToCollection[table]!;
      final rows = collections[key];
      if (rows == null) continue;
      for (final row in rows) {
        if (row.isEmpty) continue;
        final columns = row.keys.toList(growable: false);
        final placeholders =
            List<String>.filled(columns.length, '?').join(', ');
        await db.customStatement(
          'INSERT INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
          columns.map((column) => row[column]).toList(growable: false),
        );
      }
    }
    // Older accounting snapshots do not contain Phase 1 chart rows or the
    // is_postable column. Re-applying the idempotent foundation preserves the
    // restored data while backfilling protected system accounts and flags.
    await db.initializeFoundation();
  }

  Future<Map<String, List<Map<String, dynamic>>>> getPhase8AccountingDeltaRows(
      DateTime since) async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return const <String, List<Map<String, dynamic>>>{};
    }
    final db = SqliteMigrationManager.database;
    if (db == null) return const <String, List<Map<String, dynamic>>>{};
    final threshold = since.toUtc().toIso8601String();
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in phase8AccountingSnapshotTables.entries) {
      final rows = entry.value == 'cash_drawer_sessions'
          ? await db.customSelect(
              'SELECT * FROM cash_drawer_sessions WHERE updated_at >= ?',
              variables: <Variable<Object>>[Variable<String>(threshold)],
            ).get()
          : entry.value == 'accounting_audit_log'
              ? await db.customSelect(
                  'SELECT * FROM accounting_audit_log WHERE created_at >= ?',
                  variables: <Variable<Object>>[Variable<String>(threshold)],
                ).get()
              : await db.customSelect(
                  'SELECT * FROM ${entry.value} WHERE updated_at >= ?',
                  variables: <Variable<Object>>[Variable<String>(threshold)],
                ).get();
      if (rows.isEmpty) continue;
      result[entry.key] = rows
          .map((row) => Map<String, dynamic>.from(row.data))
          .toList(growable: false);
    }
    return result;
  }

  Future<void> upsertPhase8AccountingSnapshotRowsImmediate(
    Map<String, List<Map<String, dynamic>>> collections,
  ) async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) return;
    final db = SqliteMigrationManager.database;
    if (db == null) return;
    const insertOrder = <String>[
      'accounts',
      'accounting_audit_log',
      'accounting_settings',
      'accounting_periods',
      'journal_entries',
      'cash_locations',
      'payment_accounts',
      'cash_drawer_sessions',
      'receipt_vouchers',
      'payment_vouchers',
      'cash_transfers',
      'cash_operations',
      'cash_ledger_transactions',
      'payment_allocations',
      'cash_refund_allocations',
      'journal_lines',
    ];
    final tableToCollection = <String, String>{
      for (final entry in phase8AccountingSnapshotTables.entries)
        entry.value: entry.key,
    };
    for (final table in insertOrder) {
      final key = tableToCollection[table]!;
      final rows = collections[key];
      if (rows == null) continue;
      for (final row in rows) {
        if (row.isEmpty) continue;
        final columns = row.keys.toList(growable: false);
        final primaryKey = table == 'accounting_settings' ? 'key' : 'id';
        if (!columns.contains(primaryKey)) continue;
        final placeholders =
            List<String>.filled(columns.length, '?').join(', ');
        final updates = columns
            .where((column) => column != primaryKey)
            .map((column) => '$column = excluded.$column')
            .join(', ');
        final conflict = updates.isEmpty
            ? 'ON CONFLICT($primaryKey) DO NOTHING'
            : table == 'cash_drawer_sessions'
                ? 'ON CONFLICT($primaryKey) DO UPDATE SET $updates '
                    "WHERE NOT (cash_drawer_sessions.status IN ('closed', 'void') AND excluded.status = 'open') "
                    'AND (excluded.revision > cash_drawer_sessions.revision '
                    'OR (excluded.revision = cash_drawer_sessions.revision '
                    'AND excluded.updated_at > cash_drawer_sessions.updated_at))'
                : 'ON CONFLICT($primaryKey) DO UPDATE SET $updates';
        await db.customStatement(
          'INSERT INTO $table (${columns.join(', ')}) VALUES ($placeholders) $conflict',
          columns.map((column) => row[column]).toList(growable: false),
        );
      }
    }
  }

  Future<List<AccountTransaction>?> getAccountTransactionsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return AccountingRepository.getAccountTransactions();
  }

  Future<List<Customer>?> getCustomersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return CustomerRepository.getAll();
  }

  Future<List<Product>?> getProductsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return ProductRepository.getAll();
  }

  Future<List<Sale>?> getSalesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SaleRepository.getAll();
  }

  Future<BusinessQueryPage<Sale>?> querySalesFromSqlite({
    String query = '',
    String status = 'all',
    String customerId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return SaleRepository.queryPage(
      query: query,
      status: status,
      customerId: customerId,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
      sortMode: sortMode,
    );
  }

  Future<BusinessQueryPage<SaleSummary>?> querySaleSummariesFromSqlite({
    String query = '',
    String status = 'all',
    String customerId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return SaleRepository.querySummaryPage(
      query: query,
      status: status,
      customerId: customerId,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
      sortMode: sortMode,
    );
  }

  Future<Map<String, Object?>?> assistantSalesSummaryFromSqlite({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return SaleRepository.assistantSummary(from: from, to: to);
  }

  Future<Sale?> getSaleFromSqliteById(String id) async {
    if (!canQueryBusinessSqlite) return null;
    return SaleRepository.getById(id);
  }

  Future<List<Sale>?> queryEligibleDeliveryNoteSalesFromSqlite({
    int limit = 100,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return SaleRepository.queryEligibleDeliveryNoteSales(limit: limit);
  }

  Future<List<SaleQuotation>?> getSaleQuotationsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SaleRepository.getQuotations();
  }

  Future<List<DeliveryNote>?> getDeliveryNotesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SaleRepository.getDeliveryNotes();
  }

  Future<List<Supplier>?> getSuppliersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return SupplierRepository.getAll();
  }

  Future<Expense?> getExpenseFromSqliteById(String id) async {
    if (!canQueryBusinessSqlite) return null;
    return ExpenseRepository.getById(id);
  }

  Future<List<Expense>?> getExpensesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return ExpenseRepository.getAll();
  }

  Future<List<Warehouse>?> getWarehousesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getWarehouses();
  }

  Future<List<Purchase>?> getPurchasesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return PurchaseRepository.getAll();
  }

  Future<BusinessQueryPage<Purchase>?> queryPurchasesFromSqlite({
    String query = '',
    String status = 'all',
    String supplierId = '',
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return PurchaseRepository.queryPage(
      query: query,
      status: status,
      supplierId: supplierId,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
      sortMode: sortMode,
    );
  }

  Future<Map<String, Object?>?> assistantPurchaseSummaryFromSqlite({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return PurchaseRepository.assistantSummary(from: from, to: to);
  }

  Future<Map<String, Object?>?> buildPurchasesOverviewFromSqlite({
    DateTime? reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return PurchaseRepository.buildOverview(
      reference: reference ?? DateTime.now(),
    );
  }

  Future<Purchase?> getPurchaseFromSqliteById(String id) async {
    if (!canQueryBusinessSqlite) return null;
    return PurchaseRepository.getById(id);
  }

  Future<List<InventoryCountSession>?> getInventoryCountsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getInventoryCounts();
  }

  Future<Map<String, Object?>?> assistantStockBalancesFromSqlite({
    required String storeId,
    String productQuery = '',
    String warehouseQuery = '',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return InventoryRepository.assistantStockBalances(
      storeId: storeId,
      productQuery: productQuery,
      warehouseQuery: warehouseQuery,
    );
  }

  Future<Map<String, Object?>?> assistantStockMovementSummaryFromSqlite({
    required String storeId,
    required DateTime from,
    required DateTime to,
    String productQuery = '',
    String warehouseQuery = '',
    String type = 'all',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return InventoryRepository.assistantStockMovementSummary(
      from: from,
      to: to,
      storeId: storeId,
      productQuery: productQuery,
      warehouseQuery: warehouseQuery,
      type: type,
    );
  }

  Future<BusinessQueryPage<StockMovement>?> queryStockMovementsFromSqlite({
    String query = '',
    String type = 'all',
    String productId = '',
    String warehouseId = '',
    DateTime? from,
    DateTime? to,
    bool? reviewed,
    int limit = 50,
    int offset = 0,
    String sortMode = 'newest',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return InventoryRepository.queryStockMovementsPage(
      query: query,
      type: type,
      productId: productId,
      warehouseId: warehouseId,
      from: from,
      to: to,
      reviewed: reviewed,
      limit: limit,
      offset: offset,
      sortMode: sortMode,
    );
  }

  Future<BusinessQueryPage<StockMovement>?> queryWasteLossFromSqlite({
    int limit = 50,
    int offset = 0,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return InventoryRepository.queryWasteLossPage(
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, int>?> countStockMovementsAfterByProductFromSqlite(
    Map<String, DateTime> countedAtByProduct,
  ) async {
    if (!canQueryBusinessSqlite) return null;
    return InventoryRepository.countStockMovementsAfterByProduct(
      countedAtByProduct,
    );
  }

  Future<List<BillOfMaterials>?> getBillOfMaterialsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getBillOfMaterials();
  }

  Future<List<ManufacturingOrder>?> getManufacturingOrdersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getManufacturingOrders();
  }

  Future<List<CatalogItem>?> getCatalogItemsFromSqlite(String key) async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getCatalogItems(key);
  }

  Future<List<SupplierProductPrice>?>
      getSupplierProductPricesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getSupplierProductPrices();
  }

  Future<List<PriceList>?> getPriceListsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getPriceLists();
  }

  Future<List<ProductPrice>?> getProductPricesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getProductPrices();
  }

  Future<List<ProductPriceHistoryEntry>?> getProductPriceHistoryFromSqlite({
    String productId = '',
    int limit = 200,
  }) async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) return null;
    return InventoryRepository.getProductPriceHistory(
      productId: productId,
      limit: limit,
    );
  }

  Future<List<ProductPriceOverride>?>
      getProductPriceOverridesFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getProductPriceOverrides();
  }

  Future<List<ProductCost>?> getProductCostsFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getProductCosts();
  }

  Future<List<CostingMethodHistory>?>
      getCostingMethodHistoryFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getCostingMethodHistory();
  }

  Future<List<InventoryCostLayer>?> getInventoryCostLayersFromSqlite() async {
    if (_memoryStore != null || _webStore != null || !_sqliteReady) {
      return null;
    }
    return InventoryRepository.getInventoryCostLayers();
  }

  Future<BusinessQueryPage<Customer>?> queryCustomersFromSqlite({
    String query = '',
    int limit = 50,
    int offset = 0,
    bool includeWalkIn = false,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return CustomerRepository.queryPage(
      query: query,
      limit: limit,
      offset: offset,
      includeWalkIn: includeWalkIn,
    );
  }

  Future<BusinessQueryPage<Supplier>?> querySuppliersFromSqlite({
    String query = '',
    int limit = 50,
    int offset = 0,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return SupplierRepository.queryPage(
      query: query,
      limit: limit,
      offset: offset,
    );
  }

  Future<BusinessQueryPage<Expense>?> queryExpensesFromSqlite({
    String query = '',
    String status = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return ExpenseRepository.queryPage(
      query: query,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  Future<double?> sumPostedExpensesFromSqlite({
    String query = '',
    String status = 'all',
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return ExpenseRepository.sumPosted(
      query: query,
      status: status,
    );
  }

  Future<Map<String, Object?>?> assistantExpenseSummaryFromSqlite({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return ExpenseRepository.assistantSummary(from: from, to: to);
  }

  Future<BusinessQueryPage<Product>?> queryProductsFromSqlite({
    String query = '',
    String category = '',
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
    bool stockTrackedOnly = false,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return ProductRepository.queryPage(
      query: query,
      category: category,
      limit: limit,
      offset: offset,
      activeOnly: activeOnly,
      stockTrackedOnly: stockTrackedOnly,
    );
  }

  Future<Map<String, Object?>?> findSaleBarcodeProductFromSqlite(
    String code,
  ) async {
    if (!canQueryBusinessSqlite) return null;
    return ProductRepository.findSaleBarcodeProduct(code);
  }

  Future<List<String>?> queryProductCategoriesFromSqlite() async {
    if (!canQueryBusinessSqlite) return null;
    return ProductRepository.getCategories();
  }

  Future<Map<String, Object?>?> buildDashboardSummaryFromSqlite({
    required DateTime reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return AccountingRepository.buildDashboardSummary(
      reference: reference,
    );
  }

  Future<Map<String, Object?>?> buildReportsSummaryFromSqlite({
    required DateTime reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return AccountingRepository.buildReportsSummary(
      reference: reference,
    );
  }

  Future<Map<String, Object?>?> buildAccountingMetricsFromSqlite({
    required DateTime reference,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return AccountingRepository.buildMetrics(
      reference: reference,
    );
  }

  Future<List<Map<String, Object?>>?> queryAccountingAccountRowsFromSqlite({
    required String accountType,
    String query = '',
    int limit = 200,
  }) async {
    if (!canQueryBusinessSqlite) return null;
    return AccountingRepository.queryAccountRows(
      accountType: accountType,
      query: query,
      limit: limit,
    );
  }
}
