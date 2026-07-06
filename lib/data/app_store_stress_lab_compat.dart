import 'dart:convert';

import 'package:ventio/core/repositories/business_repositories.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/storage/sqlite/business_sqlite_store.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/account_transaction.dart';
import 'package:ventio/models/catalog_item.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/delivery_note.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/inventory_count.dart';
import 'package:ventio/models/manufacturing.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/sale_quotation.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/supplier.dart';
import 'package:ventio/models/supplier_product_price.dart';
import 'package:ventio/models/user_role.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/sync_queue_item.dart';
import 'package:ventio/models/warehouse.dart';

class _CachedEntityList {
  const _CachedEntityList(this.raw, this.items);

  final String raw;
  final Object items;
}

final Map<String, _CachedEntityList> _entityListCache =
    <String, _CachedEntityList>{};

List<T> _decodeEntityList<T>(
  String? raw,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (raw == null || raw.trim().isEmpty) return <T>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <T>[];
    return decoded
        .map((item) => fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  } catch (_) {
    return <T>[];
  }
}

List<T> _decodeCachedEntityList<T>(
  String cacheKey,
  String? raw,
  T Function(Map<String, dynamic>) fromJson, {
  bool Function(T item)? include,
  List<T> Function(List<T> items)? sort,
}) {
  final resolvedRaw = raw ?? '';
  final cached = _entityListCache[cacheKey];
  if (cached != null && cached.raw == resolvedRaw) {
    return cached.items as List<T>;
  }
  var items = _decodeEntityList(resolvedRaw, fromJson);
  if (include != null) {
    items = items.where(include).toList(growable: false);
  }
  if (sort != null) {
    items = sort(items);
  }
  final result = List<T>.unmodifiable(items);
  _entityListCache[cacheKey] = _CachedEntityList(resolvedRaw, result);
  return result;
}

List<Product> _sortProducts(List<Product> items) {
  final sorted = List<Product>.from(items);
  sorted.sort((a, b) {
    final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (nameCompare != 0) return nameCompare;
    final codeCompare = a.code.toLowerCase().compareTo(b.code.toLowerCase());
    if (codeCompare != 0) return codeCompare;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

extension AppStoreStressLabCompat on AppStore {
  List<Product> get products => _decodeCachedEntityList(
        'products',
        LocalDatabaseService.getString(BusinessSqliteStore.productsKey),
        (json) => Product.fromJson(json),
        include: (product) => !product.isDeleted,
        sort: _sortProducts,
      );

  List<Product> get allProductsForDiagnostics => _decodeEntityList(
        LocalDatabaseService.getString(BusinessSqliteStore.productsKey),
        (json) => Product.fromJson(json),
      );

  List<Product> get stockTrackedProducts => _decodeCachedEntityList(
        'stockTrackedProducts',
        LocalDatabaseService.getString(BusinessSqliteStore.productsKey),
        (json) => Product.fromJson(json),
        include: (product) => !product.isDeleted && product.trackStock,
        sort: _sortProducts,
      );

  List<Customer> get customers => _decodeCachedEntityList(
        'customers',
        LocalDatabaseService.getString(BusinessSqliteStore.customersKey),
        (json) => Customer.fromJson(json),
        include: (customer) => !customer.isDeleted,
      );

  List<CatalogItem> get categories => _decodeCachedEntityList(
        'categories',
        LocalDatabaseService.getString(BusinessSqliteStore.categoriesKey),
        (json) => CatalogItem.fromJson(json),
        include: (item) => !item.isDeleted,
      );

  List<CatalogItem> get brands => _decodeCachedEntityList(
        'brands',
        LocalDatabaseService.getString(BusinessSqliteStore.brandsKey),
        (json) => CatalogItem.fromJson(json),
        include: (item) => !item.isDeleted,
      );

  List<CatalogItem> get units => _decodeCachedEntityList(
        'units',
        LocalDatabaseService.getString(BusinessSqliteStore.unitsKey),
        (json) => CatalogItem.fromJson(json),
        include: (item) => !item.isDeleted,
      );

  List<Sale> get sales => _decodeCachedEntityList(
        'sales',
        LocalDatabaseService.getString(BusinessSqliteStore.salesKey),
        (json) => Sale.fromJson(json),
        include: (sale) => !sale.isDeleted,
      );

  List<Supplier> get suppliers => _decodeCachedEntityList(
        'suppliers',
        LocalDatabaseService.getString(BusinessSqliteStore.suppliersKey),
        (json) => Supplier.fromJson(json),
        include: (supplier) => !supplier.isDeleted,
      );

  List<Expense> get expenses => _decodeCachedEntityList(
        'expenses',
        LocalDatabaseService.getString(BusinessSqliteStore.expensesKey),
        (json) => Expense.fromJson(json),
        include: (expense) => !expense.isDeleted,
      );

  List<Purchase> get purchases => _decodeCachedEntityList(
        'purchases',
        LocalDatabaseService.getString(BusinessSqliteStore.purchasesKey),
        (json) => Purchase.fromJson(json),
        include: (purchase) => !purchase.isDeleted,
      );

  List<StockMovement> get stockMovements => _decodeEntityList(
        LocalDatabaseService.getString(BusinessSqliteStore.stockMovementsKey),
        (json) => StockMovement.fromJson(json),
      );

  List<AccountTransaction> get accountTransactions => _decodeCachedEntityList(
        'accountTransactions',
        LocalDatabaseService.getString(
          BusinessSqliteStore.accountTransactionsKey,
        ),
        (json) => AccountTransaction.fromJson(json),
        include: (transaction) => !transaction.isDeleted,
      );

  List<UserRole> get roles => _decodeCachedEntityList(
        'roles',
        LocalDatabaseService.getString(BusinessSqliteStore.rolesKey),
        (json) => UserRole.fromJson(json),
      );

  List<AppUser> get users => _decodeCachedEntityList(
        'users',
        LocalDatabaseService.getString(BusinessSqliteStore.usersKey),
        (json) => AppUser.fromJson(json),
      );

  List<SaleQuotation> get saleQuotations => _decodeEntityList(
        LocalDatabaseService.getString(BusinessSqliteStore.saleQuotationsKey),
        (json) => SaleQuotation.fromJson(json),
      );

  List<DeliveryNote> get deliveryNotes => _decodeEntityList(
        LocalDatabaseService.getString(BusinessSqliteStore.deliveryNotesKey),
        (json) => DeliveryNote.fromJson(json),
      );

  List<ManufacturingOrder> get manufacturingOrders => _decodeEntityList(
        LocalDatabaseService.getString(BusinessSqliteStore.manufacturingOrdersKey),
        (json) => ManufacturingOrder.fromJson(json),
      );

  List<InventoryCountSession> get inventoryCountSessions => _decodeEntityList(
        LocalDatabaseService.getString(BusinessSqliteStore.inventoryCountsKey),
        (json) => InventoryCountSession.fromJson(json),
      );

  List<Warehouse> get warehouses => _decodeEntityList(
        LocalDatabaseService.getString(BusinessSqliteStore.warehousesKey),
        (json) => Warehouse.fromJson(json),
      );

  List<BillOfMaterials> get billOfMaterials => _decodeEntityList(
        LocalDatabaseService.getString(BusinessSqliteStore.billsOfMaterialsKey),
        (json) => BillOfMaterials.fromJson(json),
      );

  List<SyncQueueItem> get pendingSyncQueue => syncQueue
      .where((item) =>
          item.isPending || item.isInProgress || item.isFailed || item.isRejected)
      .toList(growable: false);

  Warehouse get defaultWarehouse {
    final current = warehouses;
    if (current.isNotEmpty) {
      return current.firstWhere(
        (item) => item.isDefault && !item.isDeleted,
        orElse: () => current.first,
      );
    }
    return Warehouse(
      id: Warehouse.defaultId,
      name: Warehouse.defaultName,
      isDefault: true,
    );
  }

  bool isProductReferenced(String productId) {
    if (productId.trim().isEmpty) return false;
    final normalized = productId.trim();
    final inSales = sales.any(
      (sale) => sale.items.any((item) => item.productId == normalized),
    );
    if (inSales) return true;
    final inPurchases = purchases.any(
      (purchase) => purchase.items.any((item) => item.productId == normalized),
    );
    if (inPurchases) return true;
    final inMovements = stockMovements.any((movement) => movement.productId == normalized);
    if (inMovements) return true;
    final inBoms = billOfMaterials.any((bom) =>
        bom.outputProductId == normalized ||
        bom.components.any((line) => line.productId == normalized));
    return inBoms;
  }

  Future<Product> addOrUpdateProduct(Product product) =>
      ProductRepository.addOrUpdateProduct(this, product);

  Future<Customer> addOrUpdateCustomer(Customer customer) =>
      CustomerRepository.addOrUpdateCustomer(this, customer);

  Future<Supplier> addOrUpdateSupplier(Supplier supplier) =>
      SupplierRepository.addOrUpdateSupplier(this, supplier);

  Future<Expense> addOrUpdateExpense(Expense expense) =>
      ExpenseRepository.addOrUpdateExpense(this, expense);

  Future<void> postExpense(String id) => ExpenseRepository.postExpense(this, id);

  Future<void> cancelExpense(String id, {String reason = ''}) =>
      ExpenseRepository.cancelExpense(this, id, reason: reason);

  Future<void> addOrUpdateCategory(CatalogItem item) =>
      ProductRepository.addOrUpdateCategory(this, item);

  Future<void> addOrUpdateBrand(CatalogItem item) =>
      ProductRepository.addOrUpdateBrand(this, item);

  Future<void> addOrUpdateUnit(CatalogItem item) =>
      ProductRepository.addOrUpdateUnit(this, item);

  Future<SupplierProductPrice> addOrUpdateSupplierProductPrice(
    SupplierProductPrice price,
  ) =>
      InventoryRepository.addOrUpdateSupplierProductPrice(this, price);

  Future<Warehouse> createWarehouse({
    required String name,
    String code = '',
    String location = '',
  }) =>
      InventoryRepository.createWarehouse(
        context: this,
        name: name,
        code: code,
        location: location,
      );

  Future<void> adjustStock({
    required String productId,
    required double quantityDelta,
    required String reason,
    String adjustmentCategory = 'other',
    String notes = '',
    String evidenceRef = '',
  }) =>
      InventoryRepository.adjustStock(
        context: this,
        productId: productId,
        quantityDelta: quantityDelta,
        reason: reason,
        adjustmentCategory: adjustmentCategory,
        notes: notes,
        evidenceRef: evidenceRef,
      );

  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String notes = '',
  }) =>
      InventoryRepository.transferStock(
        context: this,
        productId: productId,
        fromWarehouseId: fromWarehouseId,
        toWarehouseId: toWarehouseId,
        quantity: quantity,
        notes: notes,
      );

  Future<InventoryCountSession> createInventoryCountSession({
    String notes = '',
  }) async {
    final session = await InventoryRepository.createInventoryCountSession(
      notes: notes,
    );
    if (session == null) {
      throw StateError('Could not create inventory count session.');
    }
    return session;
  }

  Future<InventoryCountSession?> approveInventoryCount(String id) =>
      InventoryRepository.approveInventoryCount(id);

  Future<InventoryCountSession?> countInventoryLine({
    required String sessionId,
    required String productId,
    required double countedQty,
    String note = '',
  }) =>
      InventoryRepository.countInventoryLine(
        sessionId: sessionId,
        productId: productId,
        countedQty: countedQty,
        note: note,
      );

  Future<BillOfMaterials> createBillOfMaterials({
    required String name,
    required String outputProductId,
    required double outputQuantity,
    required List<BillOfMaterialsLine> components,
    String notes = '',
  }) =>
      InventoryRepository.createBillOfMaterials(
        context: this,
        name: name,
        outputProductId: outputProductId,
        outputQuantity: outputQuantity,
        components: components,
        notes: notes,
      );

  Future<ManufacturingOrder> completeManufacturingOrder({
    required String bomId,
    required double quantity,
    String warehouseId = '',
    String notes = '',
  }) =>
      InventoryRepository.completeManufacturingOrder(
        context: this,
        bomId: bomId,
        quantity: quantity,
        warehouseId: warehouseId,
        notes: notes,
      );

  Future<Sale> createSale({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
    String invoiceCurrency = 'USD',
    String paymentCurrency = 'USD',
  }) =>
      SaleRepository.createSale(
        context: this,
        customerName: customerName,
        customerId: customerId,
        items: items,
        discount: discount,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        invoiceCurrency: invoiceCurrency,
        paymentCurrency: paymentCurrency,
      );

  Future<Purchase> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    bool receiveNow = true,
    String note = '',
    String paymentStatus = 'paid',
    String paymentMethod = 'Cash',
    double? paidAmount,
  }) =>
      PurchaseRepository.createPurchase(
        context: this,
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        receiveNow: receiveNow,
        note: note,
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
      );

  Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  }) =>
      SaleRepository.createSaleQuotation(
        context: this,
        customerName: customerName,
        customerId: customerId,
        items: items,
        discount: discount,
        invoiceCurrency: invoiceCurrency,
        note: note,
        validUntil: validUntil,
      );

  Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  }) async {
    final sale = await SaleRepository.convertSaleQuotationToSale(
      this,
      quotationId,
    );
    return sale;
  }

  Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  }) =>
      SaleRepository.createDeliveryNoteFromSale(this, saleId);

  Future<void> markDeliveryNoteDelivered(String id) =>
      SaleRepository.markDeliveryNoteDelivered(this, id);

  Future<void> returnSale(String id, {bool restoreStock = true}) =>
      SaleRepository.returnSale(this, id, restoreStock: restoreStock);

  Future<void> cancelSale(String id, {bool restoreStock = true}) =>
      SaleRepository.cancelSale(this, id, restoreStock: restoreStock);

  Future<void> deleteProduct(String productId) =>
      ProductRepository.deleteProduct(this, productId);

  Future<UserRole> addOrUpdateRole(UserRole role) =>
      RoleRepository.addOrUpdateRole(this, role);

  Future<AppUser> addOrUpdateUser(
    AppUser user, {
    String? password,
  }) =>
      UserRepository.addOrUpdateUser(this, user, password: password);

  Future<List<SupplierProductPrice>> supplierProductPricesForProduct(
    String productId,
  ) =>
      PurchaseRepository.supplierProductPricesForProduct(productId);

  double stockForWarehouse(String productId, String warehouseId) {
    final normalizedProductId = productId.trim();
    final normalizedWarehouseId = warehouseId.trim();
    if (normalizedProductId.isEmpty) return 0;
    return stockMovements
        .where((movement) {
          if (movement.productId != normalizedProductId) return false;
          if (normalizedWarehouseId.isEmpty) return true;
          return movement.warehouseId == normalizedWarehouseId;
        })
        .fold<double>(0, (sum, movement) => sum + movement.quantity);
  }

  Future<void> deleteDraftExpense(String id) =>
      ExpenseRepository.deleteDraftExpense(this, id);

}
