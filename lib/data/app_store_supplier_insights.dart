part of 'app_store.dart';

extension _AppStoreSplitSupplierInsights on AppStore {
ExpensesOverview get expensesOverview {
    if (_cachedExpensesOverviewRevision == _expensesRevision &&
        _cachedExpensesOverview != null) {
      return _cachedExpensesOverview!;
    }
    var totalCount = 0;
    var totalExpensesAmount = 0.0;
    var draftCount = 0;
    var postedCount = 0;
    var cancelledCount = 0;
    final categories = <String>{};
    for (final expense in _expenses) {
      if (expense.isDeleted) continue;
      totalCount += 1;
      final category = expense.category.trim();
      if (category.isNotEmpty) categories.add(category);
      if (expense.isDraft) draftCount += 1;
      if (expense.isPosted) {
        postedCount += 1;
        totalExpensesAmount += expense.amount;
      }
      if (expense.isCancelled) cancelledCount += 1;
    }
    _cachedExpensesOverview = ExpensesOverview(
      totalCount: totalCount,
      totalExpensesAmount: totalExpensesAmount,
      draftCount: draftCount,
      postedCount: postedCount,
      cancelledCount: cancelledCount,
      categoryCount: categories.length,
    );
    _cachedExpensesOverviewRevision = _expensesRevision;
    return _cachedExpensesOverview!;
  }

void _seedSupplierProductPricesFromPurchaseHistory() {
    final latestByProductSupplier = <String, SupplierProductPrice>{};
    final sortedPurchases = _purchases
        .where((item) => !item.isDeleted && !item.isCancelled)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final purchase in sortedPurchases) {
      final supplierId = purchase.supplierId.trim();
      if (supplierId.isEmpty) continue;
      for (final item in purchase.items) {
        final productId = item.productId.trim();
        if (productId.isEmpty) continue;
        final key = '$productId::$supplierId';
        latestByProductSupplier[key] = SupplierProductPrice(
          id: _supplierProductPriceId(productId, supplierId),
          productId: productId,
          supplierId: supplierId,
          cost: item.unitCostPerBase,
          currency: 'USD',
          createdAt: purchase.date,
          updatedAt: purchase.date,
          deviceId: purchase.deviceId,
          syncStatus: 'synced',
          storeId: purchase.storeId,
          branchId: purchase.branchId,
          version: 1,
          lastModifiedByDeviceId: purchase.lastModifiedByDeviceId,
        );
      }
    }
    if (latestByProductSupplier.isEmpty) return;
    _supplierProductPrices
      ..clear()
      ..addAll(latestByProductSupplier.values);
    _markSingleSupplierPerProductAsPreferred();
  }

int _seedSupplierProductPricesFromLegacyProductSuppliers({
    bool recordSyncChanges = false,
  }) {
    final supplierByLegacyName = <String, Supplier>{};
    for (final supplier in _suppliers.where((item) => !item.isDeleted)) {
      for (final name in <String>[
        supplier.name,
        supplier.nameEn,
        supplier.nameAr,
        supplier.id,
      ]) {
        final key = _normalizeLegacySupplierName(name);
        if (key.isNotEmpty) {
          supplierByLegacyName.putIfAbsent(key, () => supplier);
        }
      }
    }

    final existingPairs = _supplierProductPrices
        .where((item) => !item.isDeleted)
        .map((item) => '${item.productId}::${item.supplierId}')
        .toSet();
    var added = 0;
    final now = DateTime.now();

    for (final product in _products.where((item) => !item.isDeleted)) {
      final legacySupplierName = product.supplier.trim();
      if (legacySupplierName.isEmpty) continue;
      final supplier = supplierByLegacyName[_normalizeLegacySupplierName(
        legacySupplierName,
      )];
      if (supplier == null) continue;
      final pairKey = '${product.id}::${supplier.id}';
      if (existingPairs.contains(pairKey)) continue;

      final price = SupplierProductPrice(
        id: _supplierProductPriceId(product.id, supplier.id),
        productId: product.id,
        supplierId: supplier.id,
        cost: _safeUsdCost(product),
        currency: 'USD',
        isPreferred: true,
        createdAt: product.createdAt,
        updatedAt: now,
        deviceId: product.deviceId.isNotEmpty ? product.deviceId : _deviceId,
        syncStatus: recordSyncChanges ? 'pending' : 'synced',
        storeId:
            product.storeId.isNotEmpty ? product.storeId : appIdentity.storeId,
        branchId: product.branchId.isNotEmpty
            ? product.branchId
            : appIdentity.branchId,
        version: 1,
        lastModifiedByDeviceId: product.lastModifiedByDeviceId.isNotEmpty
            ? product.lastModifiedByDeviceId
            : _deviceId,
      );
      _supplierProductPrices.add(price);
      existingPairs.add(pairKey);
      added += 1;
      if (recordSyncChanges) {
        _recordSyncChange(
          entityType: 'supplier_product_price',
          entityId: price.id,
          operation: 'create',
          payload: price.toJson(),
        );
      }
    }

    if (added > 0) {
      _markSingleSupplierPerProductAsPreferred();
    }
    return added;
  }

void _markSingleSupplierPerProductAsPreferred() {
    final productSupplierCounts = <String, int>{};
    for (final item in _supplierProductPrices.where(
      (item) => !item.isDeleted,
    )) {
      productSupplierCounts[item.productId] =
          (productSupplierCounts[item.productId] ?? 0) + 1;
    }
    for (var i = 0; i < _supplierProductPrices.length; i++) {
      final item = _supplierProductPrices[i];
      if (!item.isDeleted &&
          productSupplierCounts[item.productId] == 1 &&
          !item.isPreferred) {
        _supplierProductPrices[i] = item.copyWith(isPreferred: true);
      }
    }
  }

String _supplierProductPriceId(String productId, String supplierId) {
    final cleanProductId = productId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final cleanSupplierId = supplierId.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    return 'spp_${cleanProductId}_$cleanSupplierId';
  }

int supplierCountForProduct(String productId) {
    _ensurePurchaseInsightsCache();
    return _purchaseMetricsByProductCache[productId]?.supplierCount ?? 0;
  }

List<SupplierProductPrice> supplierProductPricesForProduct(String productId) {
    final rows = _supplierProductPrices
        .where((item) => !item.isDeleted && item.productId == productId)
        .toList()
      ..sort((a, b) {
        if (a.isPreferred != b.isPreferred) return a.isPreferred ? -1 : 1;
        return a.cost.compareTo(b.cost);
      });
    return List.unmodifiable(rows);
  }

List<SupplierProductPrice> supplierProductPricesForSupplier(
    String supplierId,
  ) {
    final rows = _supplierProductPrices
        .where((item) => !item.isDeleted && item.supplierId == supplierId)
        .toList()
      ..sort((a, b) => a.productId.compareTo(b.productId));
    return List.unmodifiable(rows);
  }

SupplierProductPrice? supplierProductPriceFor({
    required String productId,
    required String supplierId,
  }) {
    for (final item in _supplierProductPrices) {
      if (!item.isDeleted &&
          item.productId == productId &&
          item.supplierId == supplierId) {
        return item;
      }
    }
    return null;
  }

SupplierProductPrice? preferredSupplierProductPriceForProduct(
    String productId,
  ) {
    final rows = supplierProductPricesForProduct(productId);
    for (final item in rows) {
      if (item.isPreferred) return item;
    }
    return rows.isEmpty ? null : rows.first;
  }

SupplierProductPrice? bestPriceSupplierProductPriceForProduct(
    String productId,
  ) {
    final rows = supplierProductPricesForProduct(productId);
    if (rows.isEmpty) return null;
    final sorted = rows.toList()..sort((a, b) => a.cost.compareTo(b.cost));
    return sorted.first;
  }

SupplierProductPrice? fastestSupplierProductPriceForProduct(
    String productId,
  ) {
    final rows = supplierProductPricesForProduct(
      productId,
    ).where((item) => item.leadTimeDays != null).toList();
    if (rows.isEmpty) return null;
    rows.sort((a, b) => a.leadTimeDays!.compareTo(b.leadTimeDays!));
    return rows.first;
  }

Future<void> addOrUpdateSupplierProductPrice(
    SupplierProductPrice price,
  ) async {
    requirePermission(AppPermission.suppliersManage);
    final cleanProductId = price.productId.trim();
    final cleanSupplierId = price.supplierId.trim();
    if (cleanProductId.isEmpty || cleanSupplierId.isEmpty) {
      throw ArgumentError(
        'Product and supplier are required for supplier price.',
      );
    }
    if (price.cost < 0) {
      throw ArgumentError('Supplier price cannot be negative.');
    }
    final now = DateTime.now();
    final existingIndex = _supplierProductPrices.indexWhere(
      (item) => item.id == price.id,
    );
    final duplicateIndex = _supplierProductPrices.indexWhere(
      (item) =>
          item.id != price.id &&
          !item.isDeleted &&
          item.productId == cleanProductId &&
          item.supplierId == cleanSupplierId,
    );
    final id = price.id.trim().isNotEmpty
        ? price.id.trim()
        : 'spp_${cleanProductId}_${cleanSupplierId}_${now.microsecondsSinceEpoch}';
    final previous = existingIndex != -1
        ? _supplierProductPrices[existingIndex]
        : (duplicateIndex != -1
            ? _supplierProductPrices[duplicateIndex]
            : null);
    final nextCurrency = price.currency.toUpperCase() == 'LBP' ? 'LBP' : 'USD';
    final history = List<SupplierProductPriceHistoryEntry>.from(
      price.priceHistory,
    );
    if (previous != null &&
        ((previous.cost - price.cost).abs() > 0.0001 ||
            previous.currency.toUpperCase() != nextCurrency)) {
      history.add(
        SupplierProductPriceHistoryEntry(
          oldCost: previous.cost,
          newCost: price.cost,
          currency: nextCurrency,
          changedAt: now,
          source: 'manual',
        ),
      );
      if (history.length > 50) {
        history.removeRange(0, history.length - 50);
      }
    }
    var normalized = price.copyWith(
      id: id,
      productId: cleanProductId,
      supplierId: cleanSupplierId,
      currency: nextCurrency,
      supplierSku: price.supplierSku.trim(),
      minOrderQty: price.minOrderQty,
      clearMinOrderQty: price.minOrderQty == null,
      leadTimeDays: price.leadTimeDays,
      clearLeadTimeDays: price.leadTimeDays == null,
      priceHistory: history,
      createdAt: previous == null ? now : previous.createdAt,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: previous == null ? price.version : previous.version + 1,
      lastModifiedByDeviceId: _deviceId,
      clearDeletedAt: true,
    );
    final changedPreferredRows = <SupplierProductPrice>[];
    if (normalized.isPreferred) {
      for (var i = 0; i < _supplierProductPrices.length; i++) {
        final item = _supplierProductPrices[i];
        if (!item.isDeleted &&
            item.productId == cleanProductId &&
            item.id != normalized.id &&
            item.isPreferred) {
          final updated = item.copyWith(
            isPreferred: false,
            updatedAt: now,
            syncStatus: 'pending',
            lastModifiedByDeviceId: _deviceId,
          );
          _supplierProductPrices[i] = updated;
          changedPreferredRows.add(updated);
        }
      }
    }
    final isCreate = existingIndex == -1 && duplicateIndex == -1;
    if (existingIndex != -1) {
      _supplierProductPrices[existingIndex] = normalized;
    } else if (duplicateIndex != -1) {
      normalized = normalized.copyWith(
        id: _supplierProductPrices[duplicateIndex].id,
        createdAt: _supplierProductPrices[duplicateIndex].createdAt,
      );
      _supplierProductPrices[duplicateIndex] = normalized;
    } else {
      _supplierProductPrices.add(normalized);
    }
    for (final changed in changedPreferredRows) {
      _recordSyncChange(
        entityType: 'supplier_product_price',
        entityId: changed.id,
        operation: 'update',
        payload: changed.toJson(),
      );
    }
    _recordSyncChange(
      entityType: 'supplier_product_price',
      entityId: normalized.id,
      operation: isCreate ? 'create' : 'update',
      payload: normalized.toJson(),
    );
    await _saveDirty(supplierProductPrices: true, sync: true);
    notifyListeners();
  }

Future<void> deleteSupplierProductPrice(String id) async {
    requirePermission(AppPermission.suppliersManage);
    final index = _supplierProductPrices.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _supplierProductPrices[index] = _supplierProductPrices[index].copyWith(
      deletedAt: DateTime.now(),
      syncStatus: 'pending',
      lastModifiedByDeviceId: _deviceId,
    );
    _recordSyncChange(
      entityType: 'supplier_product_price',
      entityId: id,
      operation: 'delete',
      payload: _supplierProductPrices[index].toJson(),
    );
    await _saveDirty(supplierProductPrices: true, sync: true);
    notifyListeners();
  }

}
