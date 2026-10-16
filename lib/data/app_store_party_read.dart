part of 'app_store.dart';

extension _AppStorePartyRead on AppStore {
  static const CommerceReadService _commerceReadService = CommerceReadService();

  List<Customer> get _customersReadImpl {
    unawaited(_ensureCustomersLoaded());
    return _commerceReadService.activeCustomers(_customers);
  }

  List<Supplier> get _suppliersReadImpl {
    unawaited(_ensureSuppliersLoaded());
    _ensureSuppliersCacheReadImpl();
    return _cachedSuppliers!;
  }

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
    if (normalized == null || normalized.isEmpty) {
      return AppStore.walkInCustomerId;
    }
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
      _commerceReadService.activeSuppliers(_suppliers),
    );
    _cachedSuppliersGeneration = _suppliersRevision;
  }
}
