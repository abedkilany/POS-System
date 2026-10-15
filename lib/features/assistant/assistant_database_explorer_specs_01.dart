part of 'assistant_database_explorer_service.dart';

const Map<String, _TableSpec> _assistantDatabaseExplorerSpecsPart01 =
    <String, _TableSpec>{
  'sales': _TableSpec(
    domain: _Domain.sales,
    title: 'Sales invoices',
    description:
        'Sales invoice headers. Cancelled and returned invoices are excluded from analysis.',
    baseTable: 'sales',
    source: 'sales s',
    scope: 's.store_id = ?',
    softDelete: "s.deleted_at = ''",
    dateExpression: 's.document_date',
    searchExpressions: <String>[
      's.invoice_no',
      's.customer_name',
      's.branch_id',
    ],
    dimensions: <String, _DimensionSpec>{
      'invoice_no': _DimensionSpec('s.invoice_no', 'Invoice number', 'text'),
      'customer_name': _DimensionSpec('s.customer_name', 'Customer', 'text'),
      'document_date':
          _DimensionSpec('s.document_date', 'Invoice date', 'date'),
      'status': _DimensionSpec('s.status', 'Invoice status', 'text'),
      'branch_id': _DimensionSpec('s.branch_id', 'Branch', 'text'),
      'invoice_currency':
          _DimensionSpec('s.invoice_currency', 'Invoice currency', 'currency'),
      'base_currency':
          _DimensionSpec('s.base_currency', 'Base currency', 'currency'),
    },
    measures: <String, _MeasureSpec>{
      'invoice_count': _MeasureSpec('COUNT(*)', 'Invoice count', 'documents'),
      'base_amount': _MeasureSpec('SUM(s.base_amount)', 'Base amount', 'money',
          currencyExpression: 's.base_currency'),
      'paid_base_amount': _MeasureSpec(
          'SUM(s.paid_base_amount)', 'Paid base amount', 'money',
          currencyExpression: 's.base_currency'),
      'transaction_amount': _MeasureSpec(
          'SUM(s.transaction_amount)', 'Invoice amount', 'money',
          currencyExpression: 's.invoice_currency'),
      'outstanding_base_amount': _MeasureSpec(
          'SUM(MAX(s.base_amount - s.paid_base_amount, 0))',
          'Outstanding base amount',
          'money',
          currencyExpression: 's.base_currency'),
    },
    defaultFilter: "lower(s.status) NOT IN ('cancelled', 'returned')",
    defaultFilterDescription: 'Cancelled and returned invoices are excluded.',
    relationships: <String>[
      'sales.id = sale_items.sale_id',
      'sales.id = receipt_vouchers reference_id when the reference type is a sale',
    ],
  ),
  'sale_items': _TableSpec(
    domain: _Domain.sales,
    title: 'Sales invoice lines',
    description:
        'Products and quantities on sales invoices. Amounts are line-level and exclude invoice discounts and returns.',
    baseTable: 'sale_items',
    source: 'sale_items si JOIN sales s ON s.id = si.sale_id',
    scope: 's.store_id = ?',
    softDelete: "s.deleted_at = ''",
    dateExpression: 's.document_date',
    searchExpressions: <String>[
      'si.product_name',
      's.customer_name',
      's.invoice_no',
    ],
    dimensions: <String, _DimensionSpec>{
      'product_name': _DimensionSpec('si.product_name', 'Product', 'text'),
      'customer_name': _DimensionSpec('s.customer_name', 'Customer', 'text'),
      'document_date':
          _DimensionSpec('s.document_date', 'Invoice date', 'date'),
      'invoice_no': _DimensionSpec('s.invoice_no', 'Invoice number', 'text'),
      'branch_id': _DimensionSpec('s.branch_id', 'Branch', 'text'),
      'unit_name': _DimensionSpec('si.unit_name', 'Sales unit', 'unit'),
      'invoice_currency':
          _DimensionSpec('s.invoice_currency', 'Invoice currency', 'currency'),
      'cost_currency': _DimensionSpec(
          'si.cost_currency', 'Recorded cost currency', 'currency'),
    },
    measures: <String, _MeasureSpec>{
      'line_count': _MeasureSpec('COUNT(*)', 'Sales line count', 'lines'),
      'quantity': _MeasureSpec('SUM(si.quantity)', 'Sold quantity', 'quantity',
          contextExpression: 'si.product_name', contextLabel: 'product'),
      'base_quantity': _MeasureSpec(
          'SUM(si.base_quantity)', 'Sold base quantity', 'quantity',
          contextExpression: 'si.product_name', contextLabel: 'product'),
      'line_sales_amount': _MeasureSpec('SUM(si.quantity * si.unit_price)',
          'Line sales amount before invoice discounts', 'money',
          currencyExpression: 's.invoice_currency'),
      'recorded_line_cost': _MeasureSpec(
          'SUM(si.base_quantity * si.unit_cost)', 'Recorded line cost', 'money',
          currencyExpression: 'si.cost_currency'),
    },
    defaultFilter: "lower(s.status) NOT IN ('cancelled', 'returned')",
    relationships: <String>[
      'sale_items.sale_id = sales.id',
      'sale_items.product_id = products.id',
    ],
  ),
  'product_sale_units': _TableSpec(
    domain: _Domain.sales,
    title: 'Product sales units',
    description:
        'Sales units and their conversion factors to each product base unit. Conversion values must be compared within the same product.',
    baseTable: 'product_sale_units',
    source: 'product_sale_units psu JOIN products pr ON pr.id = psu.product_id',
    scope: 'pr.store_id = ?',
    softDelete: "pr.deleted_at = ''",
    searchExpressions: <String>['pr.name', 'psu.name', 'psu.barcode'],
    dimensions: <String, _DimensionSpec>{
      'product_name': _DimensionSpec('pr.name', 'Product', 'text'),
      'unit_name': _DimensionSpec('psu.name', 'Sales unit', 'text'),
      'unit_id': _DimensionSpec('psu.unit_id', 'Unit ID', 'identifier'),
      'is_default':
          _DimensionSpec('psu.is_default', 'Default unit status', 'boolean'),
    },
    measures: <String, _MeasureSpec>{
      'unit_count': _MeasureSpec('COUNT(*)', 'Sales unit count', 'records'),
      'average_conversion_to_base': _MeasureSpec('AVG(psu.conversion_to_base)',
          'Average conversion to product base unit', 'conversion',
          contextExpression: 'pr.name',
          contextLabel: 'product',
          additionalContextExpression: 'psu.name',
          additionalContextLabel: 'sales unit'),
    },
    relationships: <String>[
      'product_sale_units.product_id = products.id',
      'product_sale_units.unit_id = catalog_units.id',
      'sale_items.product_id and unit_name identify the unit used on an invoice line',
    ],
  ),
  'sale_item_cost_layer_consumptions': _TableSpec(
    domain: _Domain.accounting,
    title: 'Sales cost layer consumptions',
    description:
        'Recorded cost-layer quantities consumed by sales invoice lines. Cost values are grouped by their recorded cost currency and product; this source is a cost detail, not an official profit report.',
    baseTable: 'sale_item_cost_layer_consumptions',
    source:
        'sale_item_cost_layer_consumptions slc JOIN sale_items si ON si.id = slc.sale_item_id JOIN sales s ON s.id = si.sale_id',
    scope: 's.store_id = ?',
    softDelete: "s.deleted_at = ''",
    dateExpression: 's.document_date',
    defaultFilter: "lower(s.status) NOT IN ('cancelled', 'returned')",
    defaultFilterDescription: 'Cancelled and returned invoices are excluded.',
    searchExpressions: <String>[
      'si.product_name',
      's.invoice_no',
      's.customer_name'
    ],
    dimensions: <String, _DimensionSpec>{
      'product_name': _DimensionSpec('si.product_name', 'Product', 'text'),
      'invoice_no': _DimensionSpec('s.invoice_no', 'Invoice number', 'text'),
      'customer_name': _DimensionSpec('s.customer_name', 'Customer', 'text'),
      'document_date':
          _DimensionSpec('s.document_date', 'Invoice date', 'date'),
      'currency_code':
          _DimensionSpec('slc.currency_code', 'Cost currency', 'currency'),
      'branch_id': _DimensionSpec('s.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'consumption_count':
          _MeasureSpec('COUNT(*)', 'Cost layer consumption count', 'records'),
      'quantity': _MeasureSpec(
          'SUM(slc.quantity)', 'Consumed quantity', 'quantity',
          contextExpression: 'si.product_name', contextLabel: 'product'),
      'recorded_cost': _MeasureSpec('SUM(slc.quantity * slc.unit_cost)',
          'Recorded consumed cost', 'money',
          currencyExpression: 'slc.currency_code',
          contextExpression: 'si.product_name',
          contextLabel: 'product'),
    },
    relationships: <String>[
      'sale_item_cost_layer_consumptions.sale_item_id = sale_items.id',
      'sale_item_cost_layer_consumptions.layer_id = inventory_cost_layers.id',
      'sale_items.sale_id = sales.id',
    ],
  ),
  'sale_item_batch_allocations': _TableSpec(
    domain: _Domain.inventory,
    title: 'Sales batch allocations',
    description:
        'Batch and expiry allocations for sales invoice lines, scoped through the parent invoice. Unit cost has no currency column here, so only quantities are aggregated.',
    baseTable: 'sale_item_batch_allocations',
    source:
        'sale_item_batch_allocations saba JOIN sale_items si ON si.id = saba.sale_item_id JOIN sales s ON s.id = si.sale_id',
    scope: 's.store_id = ?',
    softDelete: "s.deleted_at = ''",
    dateExpression: 's.document_date',
    defaultFilter: "lower(s.status) NOT IN ('cancelled', 'returned')",
    defaultFilterDescription: 'Cancelled and returned invoices are excluded.',
    searchExpressions: <String>['si.product_name', 's.invoice_no'],
    dimensions: <String, _DimensionSpec>{
      'product_name': _DimensionSpec('si.product_name', 'Product', 'text'),
      'invoice_no': _DimensionSpec('s.invoice_no', 'Invoice number', 'text'),
      'expiration_date': _DimensionSpec(
          'saba.expiration_date', 'Batch expiration date', 'date'),
      'document_date':
          _DimensionSpec('s.document_date', 'Invoice date', 'date'),
      'branch_id': _DimensionSpec('s.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'allocation_count':
          _MeasureSpec('COUNT(*)', 'Batch allocation count', 'records'),
      'quantity': _MeasureSpec(
          'SUM(saba.quantity)', 'Allocated batch quantity', 'quantity',
          contextExpression: 'si.product_name', contextLabel: 'product'),
    },
    relationships: <String>[
      'sale_item_batch_allocations.sale_item_id = sale_items.id',
      'sale_item_batch_allocations.batch_id = inventory_batches.id',
      'sale_items.sale_id = sales.id',
    ],
  ),
  'purchases': _TableSpec(
    domain: _Domain.purchases,
    title: 'Purchase documents',
    description:
        'Purchase document headers. Only received documents are included; purchase returns are a separate document type.',
    baseTable: 'purchases',
    source: 'purchases p',
    scope: 'p.store_id = ?',
    softDelete: "p.deleted_at = ''",
    dateExpression: 'p.document_date',
    searchExpressions: <String>[
      'p.purchase_no',
      'p.supplier_name',
      'p.branch_id',
    ],
    dimensions: <String, _DimensionSpec>{
      'purchase_no': _DimensionSpec('p.purchase_no', 'Purchase number', 'text'),
      'supplier_name': _DimensionSpec('p.supplier_name', 'Supplier', 'text'),
      'document_date':
          _DimensionSpec('p.document_date', 'Purchase date', 'date'),
      'status': _DimensionSpec('p.status', 'Purchase status', 'text'),
      'document_type':
          _DimensionSpec('p.document_type', 'Document type', 'text'),
      'branch_id': _DimensionSpec('p.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'document_count':
          _MeasureSpec('COUNT(*)', 'Purchase document count', 'documents'),
    },
    defaultFilter: "lower(p.status) = 'received'",
    defaultFilterDescription: 'Only received purchase documents are included.',
    relationships: <String>[
      'purchases.id = purchase_items.purchase_id',
      'purchases.supplier_id = suppliers.id',
    ],
  ),
  'purchase_items': _TableSpec(
    domain: _Domain.purchases,
    title: 'Purchase document lines',
    description:
        'Product quantities and recorded unit costs from received purchase documents. Purchase-return amounts and quantities are negative in the signed measures.',
    baseTable: 'purchase_items',
    source: 'purchase_items pi JOIN purchases p ON p.id = pi.purchase_id',
    scope: 'p.store_id = ?',
    softDelete: "p.deleted_at = ''",
    dateExpression: 'p.document_date',
    searchExpressions: <String>[
      'pi.product_name',
      'p.supplier_name',
      'p.purchase_no',
    ],
    dimensions: <String, _DimensionSpec>{
      'product_name': _DimensionSpec('pi.product_name', 'Product', 'text'),
      'supplier_name': _DimensionSpec('p.supplier_name', 'Supplier', 'text'),
      'document_date':
          _DimensionSpec('p.document_date', 'Purchase date', 'date'),
      'purchase_no': _DimensionSpec('p.purchase_no', 'Purchase number', 'text'),
      'document_type':
          _DimensionSpec('p.document_type', 'Document type', 'text'),
      'branch_id': _DimensionSpec('p.branch_id', 'Branch', 'text'),
      'purchase_unit_name':
          _DimensionSpec('pi.purchase_unit_name', 'Purchase unit', 'unit'),
      'unit_cost_currency':
          _DimensionSpec('pi.unit_cost_currency', 'Cost currency', 'currency'),
    },
    measures: <String, _MeasureSpec>{
      'line_count': _MeasureSpec('COUNT(*)', 'Purchase line count', 'lines'),
      'signed_quantity': _MeasureSpec(
          'SUM(pi.quantity * CASE WHEN lower(p.document_type) = \'purchase_return\' THEN -1 ELSE 1 END)',
          'Quantity (returns negative)',
          'quantity',
          contextExpression: 'pi.product_name',
          contextLabel: 'product'),
      'signed_line_amount': _MeasureSpec(
          'SUM(pi.quantity * pi.unit_cost * CASE WHEN lower(p.document_type) = \'purchase_return\' THEN -1 ELSE 1 END)',
          'Line amount (returns negative)',
          'money',
          currencyExpression: 'pi.unit_cost_currency'),
    },
    defaultFilter: "lower(p.status) = 'received'",
    relationships: <String>[
      'purchase_items.purchase_id = purchases.id',
      'purchase_items.product_id = products.id',
    ],
  ),
  'product_purchase_units': _TableSpec(
    domain: _Domain.purchases,
    title: 'Product purchase units',
    description:
        'Purchase units and their conversion factors to each product base unit. Conversion values must be compared within the same product.',
    baseTable: 'product_purchase_units',
    source:
        'product_purchase_units ppu JOIN products pr ON pr.id = ppu.product_id',
    scope: 'pr.store_id = ?',
    softDelete: "pr.deleted_at = ''",
    searchExpressions: <String>['pr.name', 'ppu.name', 'ppu.barcode'],
    dimensions: <String, _DimensionSpec>{
      'product_name': _DimensionSpec('pr.name', 'Product', 'text'),
      'unit_name': _DimensionSpec('ppu.name', 'Purchase unit', 'text'),
      'unit_id': _DimensionSpec('ppu.unit_id', 'Unit ID', 'identifier'),
      'is_default':
          _DimensionSpec('ppu.is_default', 'Default unit status', 'boolean'),
    },
    measures: <String, _MeasureSpec>{
      'unit_count': _MeasureSpec('COUNT(*)', 'Purchase unit count', 'records'),
      'average_conversion_to_base': _MeasureSpec('AVG(ppu.conversion_to_base)',
          'Average conversion to product base unit', 'conversion',
          contextExpression: 'pr.name',
          contextLabel: 'product',
          additionalContextExpression: 'ppu.name',
          additionalContextLabel: 'purchase unit'),
    },
    relationships: <String>[
      'product_purchase_units.product_id = products.id',
      'product_purchase_units.unit_id = catalog_units.id',
      'purchase_items.product_id and purchase_unit_name identify the unit used on a purchase line',
    ],
  ),
  'purchase_item_batch_allocations': _TableSpec(
    domain: _Domain.inventory,
    title: 'Purchase batch allocations',
    description:
        'Batch numbers, quantities, and expiry details assigned to purchase lines, scoped through the parent purchase document.',
    baseTable: 'purchase_item_batch_allocations',
    source:
        'purchase_item_batch_allocations piba JOIN purchase_items pi ON pi.id = piba.purchase_item_id JOIN purchases p ON p.id = pi.purchase_id',
    scope: 'p.store_id = ?',
    softDelete: "p.deleted_at = ''",
    dateExpression: 'p.document_date',
    defaultFilter: "lower(p.status) = 'received'",
    defaultFilterDescription: 'Only received purchase documents are included.',
    searchExpressions: <String>[
      'pi.product_name',
      'p.purchase_no',
      'piba.supplier_batch_number'
    ],
    dimensions: <String, _DimensionSpec>{
      'product_name': _DimensionSpec('pi.product_name', 'Product', 'text'),
      'purchase_no': _DimensionSpec('p.purchase_no', 'Purchase number', 'text'),
      'supplier_batch_number': _DimensionSpec(
          'piba.supplier_batch_number', 'Supplier batch number', 'text'),
      'expiration_date': _DimensionSpec(
          'piba.expiration_date', 'Batch expiration date', 'date'),
      'document_date':
          _DimensionSpec('p.document_date', 'Purchase date', 'date'),
      'branch_id': _DimensionSpec('p.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'allocation_count': _MeasureSpec(
          'COUNT(*)', 'Purchase batch allocation count', 'records'),
      'quantity': _MeasureSpec(
          'SUM(piba.quantity)', 'Allocated purchase quantity', 'quantity',
          contextExpression: 'pi.product_name', contextLabel: 'product'),
    },
    relationships: <String>[
      'purchase_item_batch_allocations.purchase_item_id = purchase_items.id',
      'purchase_item_batch_allocations.batch_id = inventory_batches.id',
      'purchase_items.purchase_id = purchases.id',
    ],
  ),
  'customers': _TableSpec(
    domain: _Domain.customers,
    title: 'Customers',
    description:
        'Customer directory records. Contact details are not exposed to the assistant.',
    baseTable: 'customers',
    source: 'customers c',
    scope: 'c.store_id = ?',
    softDelete: "c.deleted_at = ''",
    searchExpressions: <String>['c.name'],
    dimensions: <String, _DimensionSpec>{
      'name': _DimensionSpec('c.name', 'Customer name', 'text'),
      'branch_id': _DimensionSpec('c.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'customer_count': _MeasureSpec('COUNT(*)', 'Customer count', 'records'),
    },
    relationships: <String>[
      'customers.id = sales.customer_id',
      'customers.id = receipt_vouchers.customer_id',
    ],
  ),
  'suppliers': _TableSpec(
    domain: _Domain.suppliers,
    title: 'Suppliers',
    description:
        'Supplier directory records. Contact details are not exposed to the assistant.',
    baseTable: 'suppliers',
    source: 'suppliers sp',
    scope: 'sp.store_id = ?',
    softDelete: "sp.deleted_at = ''",
    searchExpressions: <String>['sp.name', 'sp.name_en', 'sp.name_ar'],
    dimensions: <String, _DimensionSpec>{
      'name': _DimensionSpec('sp.name', 'Supplier name', 'text'),
      'branch_id': _DimensionSpec('sp.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'supplier_count': _MeasureSpec('COUNT(*)', 'Supplier count', 'records'),
    },
    relationships: <String>[
      'suppliers.id = purchases.supplier_id',
      'suppliers.id = payment_vouchers.supplier_id',
    ],
  ),
  'products': _TableSpec(
    domain: _Domain.inventory,
    title: 'Products',
    description:
        'Product catalog. The legacy quantity and cost columns are not treated as current inventory balances.',
    baseTable: 'products',
    source: 'products pr',
    scope: 'pr.store_id = ?',
    softDelete: "pr.deleted_at = ''",
    searchExpressions: <String>['pr.name', 'pr.code', 'pr.category'],
    dimensions: <String, _DimensionSpec>{
      'name': _DimensionSpec('pr.name', 'Product', 'text'),
      'category': _DimensionSpec('pr.category', 'Category', 'text'),
      'brand': _DimensionSpec('pr.brand', 'Brand', 'text'),
      'is_active': _DimensionSpec('pr.is_active', 'Active status', 'boolean'),
      'track_stock':
          _DimensionSpec('pr.track_stock', 'Stock tracking status', 'boolean'),
      'branch_id': _DimensionSpec('pr.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'product_count': _MeasureSpec('COUNT(*)', 'Product count', 'records'),
    },
    relationships: <String>[
      'products.id = sale_items.product_id',
      'products.id = purchase_items.product_id',
      'products.id = stock_movements.product_id',
      'products.id = warehouse_inventory.product_id',
    ],
  ),
  'price_lists': _TableSpec(
    domain: _Domain.sales,
    title: 'Price lists',
    description: 'Sales price list definitions and active or default status.',
    baseTable: 'price_lists',
    source: 'price_lists pl',
    scope: 'pl.store_id = ?',
    softDelete: "pl.deleted_at = ''",
    searchExpressions: <String>['pl.name', 'pl.code'],
    dimensions: <String, _DimensionSpec>{
      'name': _DimensionSpec('pl.name', 'Price list name', 'text'),
      'code': _DimensionSpec('pl.code', 'Price list code', 'text'),
      'is_default':
          _DimensionSpec('pl.is_default', 'Default status', 'boolean'),
      'is_active': _DimensionSpec('pl.is_active', 'Active status', 'boolean'),
      'branch_id': _DimensionSpec('pl.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'price_list_count':
          _MeasureSpec('COUNT(*)', 'Price list count', 'records'),
    },
    relationships: <String>[
      'price_lists.id = product_prices.price_list_id',
      'price_lists.id = product_price_history.price_list_id',
    ],
  ),
  'product_prices': _TableSpec(
    domain: _Domain.sales,
    title: 'Product prices',
    description:
        'Configured selling prices by product, price list, unit, and base currency. The average measure is descriptive, not a total sales amount.',
    baseTable: 'product_prices',
    source: 'product_prices pp',
    scope: 'pp.store_id = ?',
    softDelete: "pp.deleted_at = ''",
    searchExpressions: <String>[
      'pp.product_id',
      'pp.price_list_id',
      'pp.unit_id'
    ],
    dimensions: <String, _DimensionSpec>{
      'product_id': _DimensionSpec('pp.product_id', 'Product ID', 'identifier'),
      'price_list_id':
          _DimensionSpec('pp.price_list_id', 'Price list ID', 'identifier'),
      'unit_id': _DimensionSpec('pp.unit_id', 'Sales unit ID', 'identifier'),
      'base_currency_code':
          _DimensionSpec('pp.base_currency_code', 'Currency', 'currency'),
      'is_active': _DimensionSpec('pp.is_active', 'Active status', 'boolean'),
      'branch_id': _DimensionSpec('pp.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'price_rows': _MeasureSpec('COUNT(*)', 'Product price rows', 'records'),
      'average_price': _MeasureSpec(
          'AVG(pp.base_amount)', 'Average configured price', 'money_unit',
          currencyExpression: 'pp.base_currency_code',
          contextExpression: 'pp.product_id',
          contextLabel: 'product',
          additionalContextExpression: 'pp.unit_id',
          additionalContextLabel: 'unit',
          tertiaryContextExpression: 'pp.price_list_id',
          tertiaryContextLabel: 'price list'),
    },
    relationships: <String>[
      'product_prices.product_id = products.id',
      'product_prices.price_list_id = price_lists.id',
      'product_prices.unit_id = product_sale_units.unit_id',
    ],
  ),
  'product_price_overrides': _TableSpec(
    domain: _Domain.sales,
    title: 'Product price overrides',
    description:
        'Currency-specific price overrides for a configured product price. The parent product price is used to enforce store scope.',
    baseTable: 'product_price_overrides',
    source:
        'product_price_overrides ppo JOIN product_prices pp ON pp.id = ppo.product_price_id',
    scope: 'pp.store_id = ?',
    softDelete: "pp.deleted_at = ''",
    searchExpressions: <String>[
      'pp.product_id',
      'pp.price_list_id',
      'ppo.currency_code'
    ],
    dimensions: <String, _DimensionSpec>{
      'product_id': _DimensionSpec('pp.product_id', 'Product ID', 'identifier'),
      'price_list_id':
          _DimensionSpec('pp.price_list_id', 'Price list ID', 'identifier'),
      'unit_id': _DimensionSpec('pp.unit_id', 'Sales unit ID', 'identifier'),
      'currency_code':
          _DimensionSpec('ppo.currency_code', 'Currency', 'currency'),
      'mode': _DimensionSpec('ppo.mode', 'Override mode', 'text'),
      'is_active': _DimensionSpec('ppo.is_active', 'Active status', 'boolean'),
      'branch_id': _DimensionSpec('pp.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'override_count':
          _MeasureSpec('COUNT(*)', 'Price override count', 'records'),
      'average_amount': _MeasureSpec(
          'AVG(ppo.amount)', 'Average override amount', 'money_unit',
          currencyExpression: 'ppo.currency_code',
          contextExpression: 'pp.product_id',
          contextLabel: 'product',
          additionalContextExpression: 'ppo.mode',
          additionalContextLabel: 'override mode',
          tertiaryContextExpression: 'pp.price_list_id',
          tertiaryContextLabel: 'price list'),
    },
    relationships: <String>[
      'product_price_overrides.product_price_id = product_prices.id',
      'product_prices.product_id = products.id',
    ],
  ),
  'product_price_history': _TableSpec(
    domain: _Domain.sales,
    title: 'Product price history',
    description:
        'Historical product price changes, with old and new amounts stored by currency.',
    baseTable: 'product_price_history',
    source: 'product_price_history pph',
    scope: 'pph.store_id = ?',
    softDelete: "pph.deleted_at = ''",
    dateExpression: 'pph.changed_at',
    searchExpressions: <String>[
      'pph.product_id',
      'pph.change_type',
      'pph.user_name'
    ],
    dimensions: <String, _DimensionSpec>{
      'product_id':
          _DimensionSpec('pph.product_id', 'Product ID', 'identifier'),
      'price_list_id':
          _DimensionSpec('pph.price_list_id', 'Price list ID', 'identifier'),
      'currency_code':
          _DimensionSpec('pph.currency_code', 'Currency', 'currency'),
      'change_type': _DimensionSpec('pph.change_type', 'Change type', 'text'),
      'changed_at': _DimensionSpec('pph.changed_at', 'Change date', 'date'),
      'branch_id': _DimensionSpec('pph.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'change_count': _MeasureSpec('COUNT(*)', 'Price change count', 'records'),
      'average_new_amount': _MeasureSpec(
          'AVG(pph.new_amount)', 'Average new unit price', 'money_unit',
          currencyExpression: 'pph.currency_code',
          contextExpression: 'pph.product_id',
          contextLabel: 'product',
          additionalContextExpression: 'pph.price_list_id',
          additionalContextLabel: 'price list'),
      'average_change_percent': _MeasureSpec('AVG(pph.change_percent)',
          'Average recorded percentage change', 'percent',
          contextExpression: 'pph.product_id', contextLabel: 'product'),
    },
    relationships: <String>[
      'product_price_history.product_id = products.id',
      'product_price_history.price_list_id = price_lists.id',
    ],
  ),
  'catalog_categories': _TableSpec(
    domain: _Domain.inventory,
    title: 'Product categories',
    description: 'Product category directory.',
    baseTable: 'catalog_categories',
    source: 'catalog_categories cat',
    scope: 'cat.store_id = ?',
    softDelete: "cat.deleted_at = ''",
    searchExpressions: <String>['cat.name_en', 'cat.name_ar', 'cat.code'],
    dimensions: <String, _DimensionSpec>{
      'name_en':
          _DimensionSpec('cat.name_en', 'Category name (English)', 'text'),
      'name_ar':
          _DimensionSpec('cat.name_ar', 'Category name (Arabic)', 'text'),
      'code': _DimensionSpec('cat.code', 'Category code', 'text'),
      'branch_id': _DimensionSpec('cat.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'category_count': _MeasureSpec('COUNT(*)', 'Category count', 'records'),
    },
    relationships: <String>[
      'products.category records product classification as text'
    ],
  ),
  'catalog_brands': _TableSpec(
    domain: _Domain.inventory,
    title: 'Product brands',
    description: 'Product brand directory.',
    baseTable: 'catalog_brands',
    source: 'catalog_brands cb',
    scope: 'cb.store_id = ?',
    softDelete: "cb.deleted_at = ''",
    searchExpressions: <String>['cb.name_en', 'cb.name_ar', 'cb.code'],
    dimensions: <String, _DimensionSpec>{
      'name_en': _DimensionSpec('cb.name_en', 'Brand name (English)', 'text'),
      'name_ar': _DimensionSpec('cb.name_ar', 'Brand name (Arabic)', 'text'),
      'code': _DimensionSpec('cb.code', 'Brand code', 'text'),
      'branch_id': _DimensionSpec('cb.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'brand_count': _MeasureSpec('COUNT(*)', 'Brand count', 'records'),
    },
    relationships: <String>['products.brand stores the product brand name'],
  ),
  'catalog_units': _TableSpec(
    domain: _Domain.inventory,
    title: 'Product units',
    description: 'Unit of measure directory for products.',
    baseTable: 'catalog_units',
    source: 'catalog_units cu',
    scope: 'cu.store_id = ?',
    softDelete: "cu.deleted_at = ''",
    searchExpressions: <String>['cu.name_en', 'cu.name_ar', 'cu.code'],
    dimensions: <String, _DimensionSpec>{
      'name_en': _DimensionSpec('cu.name_en', 'Unit name (English)', 'text'),
      'name_ar': _DimensionSpec('cu.name_ar', 'Unit name (Arabic)', 'text'),
      'code': _DimensionSpec('cu.code', 'Unit code', 'text'),
      'branch_id': _DimensionSpec('cu.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'unit_count': _MeasureSpec('COUNT(*)', 'Unit count', 'records'),
    },
    relationships: <String>[
      'catalog_units.id = product_sale_units.unit_id',
      'catalog_units.id = product_purchase_units.unit_id',
    ],
  ),
};
