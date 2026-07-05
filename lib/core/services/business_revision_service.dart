class BusinessRevisionService {
  BusinessRevisionService._();

  static final BusinessRevisionService instance = BusinessRevisionService._();

  int _storeRevision = 0;
  int _productsRevision = 0;
  int _customersRevision = 0;
  int _salesRevision = 0;
  int _deliveryNotesRevision = 0;
  int _suppliersRevision = 0;
  int _supplierProductPricesRevision = 0;
  int _purchasesRevision = 0;
  int _expensesRevision = 0;
  int _stockMovementsRevision = 0;
  int _warehousesRevision = 0;
  int _accountTransactionsRevision = 0;
  int _storeProfileRevision = 0;
  int _syncSequence = 0;

  int get storeRevision => _storeRevision;
  int get productsRevision => _productsRevision;
  int get customersRevision => _customersRevision;
  int get salesRevision => _salesRevision;
  int get deliveryNotesRevision => _deliveryNotesRevision;
  int get suppliersRevision => _suppliersRevision;
  int get supplierProductPricesRevision => _supplierProductPricesRevision;
  int get purchasesRevision => _purchasesRevision;
  int get expensesRevision => _expensesRevision;
  int get stockMovementsRevision => _stockMovementsRevision;
  int get warehousesRevision => _warehousesRevision;
  int get accountTransactionsRevision => _accountTransactionsRevision;
  int get storeProfileRevision => _storeProfileRevision;

  int get accountingRevision => Object.hashAll(<Object?>[
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
      ]);

  int get dashboardRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _stockMovementsRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
        _syncSequence,
      ]);

  int get reportsRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _customersRevision,
        _suppliersRevision,
        _salesRevision,
        _purchasesRevision,
        _expensesRevision,
        _stockMovementsRevision,
        _accountTransactionsRevision,
        _storeProfileRevision,
      ]);

  int get inventoryRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _stockMovementsRevision,
        _warehousesRevision,
      ]);

  int get salesPageRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _customersRevision,
        _salesRevision,
        _deliveryNotesRevision,
        _storeProfileRevision,
      ]);

  int get productsPageRevision => Object.hashAll(<Object?>[
        _productsRevision,
        _purchasesRevision,
        _storeProfileRevision,
      ]);

  void reset() {
    _storeRevision = 0;
    _productsRevision = 0;
    _customersRevision = 0;
    _salesRevision = 0;
    _deliveryNotesRevision = 0;
    _suppliersRevision = 0;
    _supplierProductPricesRevision = 0;
    _purchasesRevision = 0;
    _expensesRevision = 0;
    _stockMovementsRevision = 0;
    _warehousesRevision = 0;
    _accountTransactionsRevision = 0;
    _storeProfileRevision = 0;
    _syncSequence = 0;
  }

  void touchAll() {
    _storeRevision += 1;
    _productsRevision += 1;
    _customersRevision += 1;
    _salesRevision += 1;
    _deliveryNotesRevision += 1;
    _suppliersRevision += 1;
    _supplierProductPricesRevision += 1;
    _purchasesRevision += 1;
    _expensesRevision += 1;
    _stockMovementsRevision += 1;
    _warehousesRevision += 1;
    _accountTransactionsRevision += 1;
    _storeProfileRevision += 1;
    _syncSequence += 1;
  }

  void touchSyncSequence() {
    _syncSequence += 1;
  }

  void touchForKey(String key) {
    switch (key) {
      case 'products_v4':
      case 'product_prices_v1':
      case 'product_price_overrides_v1':
      case 'product_costs_v1':
      case 'costing_method_history_v1':
      case 'inventory_cost_layers_v1':
      case 'product_categories_v1':
      case 'product_brands_v1':
      case 'product_units_v1':
        _productsRevision += 1;
        break;
      case 'customers_v4':
        _customersRevision += 1;
        break;
      case 'sales_v4':
      case 'sale_quotations_v1':
      case 'delivery_notes_v1':
        _salesRevision += 1;
        _deliveryNotesRevision += 1;
        break;
      case 'suppliers_v4':
      case 'supplier_product_prices_v1':
        _suppliersRevision += 1;
        _supplierProductPricesRevision += 1;
        break;
      case 'purchases_v1':
        _purchasesRevision += 1;
        break;
      case 'expenses_v1':
        _expensesRevision += 1;
        break;
      case 'stock_movements_v1':
        _stockMovementsRevision += 1;
        break;
      case 'warehouses_v1':
        _warehousesRevision += 1;
        break;
      case 'account_transactions_v1':
        _accountTransactionsRevision += 1;
        break;
      case 'store_profile_v5':
        _storeProfileRevision += 1;
        break;
      case 'sync_sequence_v1':
        _syncSequence += 1;
        break;
      default:
        _storeRevision += 1;
        break;
    }
  }
}
