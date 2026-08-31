part of 'app_store.dart';

extension _AppStorePartyRead on AppStore {
  List<Customer> get _allCustomersForDiagnosticsReadImpl =>
      List.unmodifiable(_customers);

  List<Supplier> get _allSuppliersForDiagnosticsReadImpl =>
      List.unmodifiable(_suppliers);

  List<Customer> get _customersReadImpl {
    unawaited(ensureCustomersLoaded());
    return List.unmodifiable(
      _customers.where((item) => !item.isDeleted).toList(growable: false),
    );
  }

  List<Supplier> get _suppliersReadImpl {
    unawaited(ensureSuppliersLoaded());
    _ensureSuppliersCacheReadImpl();
    return _cachedSuppliers!;
  }

  List<SupplierProductPrice> get _supplierProductPricesReadImpl {
    unawaited(ensureSupplierProductPricesLoaded());
    _ensureSupplierProductPricesCacheReadImpl();
    return _cachedSupplierProductPrices!;
  }

  List<SupplierProductPrice> get _allSupplierProductPricesForDiagnosticsReadImpl =>
      List.unmodifiable(_supplierProductPrices);

  String _resolveCustomerNameReadImpl(String? customerId) {
    if (customerId == null ||
        customerId.isEmpty ||
        customerId == AppStore.walkInCustomerId) {
      return AppStore.walkInCustomerName;
    }
    final index = _customerIndexById[customerId];
    if (index == null ||
        index < 0 ||
        index >= _customers.length ||
        _customers[index].isDeleted) {
      return AppStore.walkInCustomerName;
    }
    return _customers[index].name;
  }

  String _sanitizeSelectedCustomerIdReadImpl(String? customerId) {
    final normalized = customerId?.trim();
    if (normalized == null || normalized.isEmpty) return AppStore.walkInCustomerId;
    final index = _customerIndexById[normalized];
    if (index == null || index < 0 || index >= _customers.length) {
      return AppStore.walkInCustomerId;
    }
    return _customers[index].isDeleted ? AppStore.walkInCustomerId : normalized;
  }

  void _ensureSuppliersCacheReadImpl() {
    if (_cachedSuppliersGeneration == _suppliersRevision &&
        _cachedSuppliers != null) {
      return;
    }
    _cachedSuppliers = UnmodifiableListView(
      _suppliers.where((item) => !item.isDeleted).toList(growable: false),
    );
    _cachedSuppliersGeneration = _suppliersRevision;
  }

  void _ensureSupplierProductPricesCacheReadImpl() {
    if (_cachedSupplierProductPricesGeneration ==
            _supplierProductPricesRevision &&
        _cachedSupplierProductPrices != null) {
      return;
    }
    _cachedSupplierProductPrices = UnmodifiableListView(
      _supplierProductPrices
          .where((item) => !item.isDeleted)
          .toList(growable: false),
    );
    _cachedSupplierProductPricesGeneration = _supplierProductPricesRevision;
  }
}
