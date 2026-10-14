import 'package:drift/drift.dart';

import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../core/storage/sqlite/ventio_drift_database.dart';
import '../../data/app_store.dart';
import 'assistant_provider.dart';

/// Read-only, permission-scoped access to the business schema.
///
/// The assistant receives a schema catalog and can request bounded aggregate
/// queries over the explicitly described tables below. SQL sources,
/// expressions, and scope predicates are fixed here; model-supplied values are
/// always bound parameters.
class AssistantDatabaseExplorerService {
  AssistantDatabaseExplorerService._();

  static const int _maximumGroups = 50;
  static const int _maximumSearchCharacters = 120;

  static const Map<String, _TableSpec> _specs = <String, _TableSpec>{
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
        'invoice_currency': _DimensionSpec(
            's.invoice_currency', 'Invoice currency', 'currency'),
        'base_currency':
            _DimensionSpec('s.base_currency', 'Base currency', 'currency'),
      },
      measures: <String, _MeasureSpec>{
        'invoice_count': _MeasureSpec('COUNT(*)', 'Invoice count', 'documents'),
        'base_amount': _MeasureSpec(
            'SUM(s.base_amount)', 'Base amount', 'money',
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
        'invoice_currency': _DimensionSpec(
            's.invoice_currency', 'Invoice currency', 'currency'),
        'cost_currency': _DimensionSpec(
            'si.cost_currency', 'Recorded cost currency', 'currency'),
      },
      measures: <String, _MeasureSpec>{
        'line_count': _MeasureSpec('COUNT(*)', 'Sales line count', 'lines'),
        'quantity': _MeasureSpec(
            'SUM(si.quantity)', 'Sold quantity', 'quantity',
            contextExpression: 'si.product_name', contextLabel: 'product'),
        'base_quantity': _MeasureSpec(
            'SUM(si.base_quantity)', 'Sold base quantity', 'quantity',
            contextExpression: 'si.product_name', contextLabel: 'product'),
        'line_sales_amount': _MeasureSpec('SUM(si.quantity * si.unit_price)',
            'Line sales amount before invoice discounts', 'money',
            currencyExpression: 's.invoice_currency'),
        'recorded_line_cost': _MeasureSpec(
            'SUM(si.base_quantity * si.unit_cost)',
            'Recorded line cost',
            'money',
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
      source:
          'product_sale_units psu JOIN products pr ON pr.id = psu.product_id',
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
        'average_conversion_to_base': _MeasureSpec(
            'AVG(psu.conversion_to_base)',
            'Average conversion to product base unit',
            'conversion',
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
        'purchase_no':
            _DimensionSpec('p.purchase_no', 'Purchase number', 'text'),
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
      defaultFilterDescription:
          'Only received purchase documents are included.',
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
        'purchase_no':
            _DimensionSpec('p.purchase_no', 'Purchase number', 'text'),
        'document_type':
            _DimensionSpec('p.document_type', 'Document type', 'text'),
        'branch_id': _DimensionSpec('p.branch_id', 'Branch', 'text'),
        'purchase_unit_name':
            _DimensionSpec('pi.purchase_unit_name', 'Purchase unit', 'unit'),
        'unit_cost_currency': _DimensionSpec(
            'pi.unit_cost_currency', 'Cost currency', 'currency'),
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
        'unit_count':
            _MeasureSpec('COUNT(*)', 'Purchase unit count', 'records'),
        'average_conversion_to_base': _MeasureSpec(
            'AVG(ppu.conversion_to_base)',
            'Average conversion to product base unit',
            'conversion',
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
      defaultFilterDescription:
          'Only received purchase documents are included.',
      searchExpressions: <String>[
        'pi.product_name',
        'p.purchase_no',
        'piba.supplier_batch_number'
      ],
      dimensions: <String, _DimensionSpec>{
        'product_name': _DimensionSpec('pi.product_name', 'Product', 'text'),
        'purchase_no':
            _DimensionSpec('p.purchase_no', 'Purchase number', 'text'),
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
        'track_stock': _DimensionSpec(
            'pr.track_stock', 'Stock tracking status', 'boolean'),
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
        'product_id':
            _DimensionSpec('pp.product_id', 'Product ID', 'identifier'),
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
        'product_id':
            _DimensionSpec('pp.product_id', 'Product ID', 'identifier'),
        'price_list_id':
            _DimensionSpec('pp.price_list_id', 'Price list ID', 'identifier'),
        'unit_id': _DimensionSpec('pp.unit_id', 'Sales unit ID', 'identifier'),
        'currency_code':
            _DimensionSpec('ppo.currency_code', 'Currency', 'currency'),
        'mode': _DimensionSpec('ppo.mode', 'Override mode', 'text'),
        'is_active':
            _DimensionSpec('ppo.is_active', 'Active status', 'boolean'),
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
        'change_count':
            _MeasureSpec('COUNT(*)', 'Price change count', 'records'),
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
    'product_costs': _TableSpec(
      domain: _Domain.accounting,
      title: 'Product costs',
      description:
          'Stored average and last cost by product. Costs are kept separate by currency and product.',
      baseTable: 'product_costs',
      source: 'product_costs pc',
      scope: 'pc.store_id = ?',
      softDelete: "pc.deleted_at = ''",
      searchExpressions: <String>['pc.product_id', 'pc.currency_code'],
      dimensions: <String, _DimensionSpec>{
        'product_id':
            _DimensionSpec('pc.product_id', 'Product ID', 'identifier'),
        'currency_code':
            _DimensionSpec('pc.currency_code', 'Currency', 'currency'),
        'branch_id': _DimensionSpec('pc.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'product_count':
            _MeasureSpec('COUNT(*)', 'Product cost rows', 'records'),
        'average_cost': _MeasureSpec(
            'AVG(pc.average_cost)', 'Average recorded unit cost', 'money_unit',
            currencyExpression: 'pc.currency_code',
            contextExpression: 'pc.product_id',
            contextLabel: 'product'),
        'last_cost': _MeasureSpec(
            'AVG(pc.last_cost)', 'Last recorded unit cost', 'money_unit',
            currencyExpression: 'pc.currency_code',
            contextExpression: 'pc.product_id',
            contextLabel: 'product'),
      },
      relationships: <String>['product_costs.product_id = products.id'],
    ),
    'inventory_cost_layers': _TableSpec(
      domain: _Domain.accounting,
      title: 'Inventory cost layers',
      description:
          'Inventory valuation layers with received and remaining quantities. Remaining value is calculated from remaining quantity and the layer unit cost, grouped by product and currency; use the inventory valuation report for the official valuation total.',
      baseTable: 'inventory_cost_layers',
      source: 'inventory_cost_layers icl',
      scope: 'icl.store_id = ?',
      softDelete: "icl.deleted_at = ''",
      dateExpression: 'icl.created_at',
      searchExpressions: <String>[
        'icl.product_name',
        'icl.source_type',
        'icl.currency_code'
      ],
      dimensions: <String, _DimensionSpec>{
        'product_name': _DimensionSpec('icl.product_name', 'Product', 'text'),
        'source_type':
            _DimensionSpec('icl.source_type', 'Layer source type', 'text'),
        'currency_code':
            _DimensionSpec('icl.currency_code', 'Currency', 'currency'),
        'is_closed':
            _DimensionSpec('icl.is_closed', 'Closed status', 'boolean'),
        'branch_id': _DimensionSpec('icl.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'layer_count': _MeasureSpec('COUNT(*)', 'Cost layer count', 'records'),
        'remaining_quantity': _MeasureSpec('SUM(icl.quantity_remaining)',
            'Remaining layer quantity', 'quantity',
            contextExpression: 'icl.product_name', contextLabel: 'product'),
        'remaining_value': _MeasureSpec(
            'SUM(icl.quantity_remaining * icl.unit_cost)',
            'Recorded remaining layer value',
            'money',
            currencyExpression: 'icl.currency_code',
            contextExpression: 'icl.product_name',
            contextLabel: 'product'),
      },
      relationships: <String>[
        'inventory_cost_layers.product_id = products.id',
        'inventory_cost_layers.purchase_id = purchases.id',
        'inventory_cost_layers.purchase_item_id = purchase_items.id',
      ],
    ),
    'supplier_product_prices': _TableSpec(
      domain: _Domain.purchases,
      title: 'Supplier product prices',
      description:
          'Supplier-specific product cost records and lead-time terms. Costs are kept separate by currency and product.',
      baseTable: 'supplier_product_prices',
      source: 'supplier_product_prices spp',
      scope: 'spp.store_id = ?',
      softDelete: "spp.deleted_at = ''",
      searchExpressions: <String>[
        'spp.product_id',
        'spp.supplier_id',
        'spp.supplier_sku'
      ],
      dimensions: <String, _DimensionSpec>{
        'product_id':
            _DimensionSpec('spp.product_id', 'Product ID', 'identifier'),
        'supplier_id':
            _DimensionSpec('spp.supplier_id', 'Supplier ID', 'identifier'),
        'currency': _DimensionSpec('spp.currency', 'Currency', 'currency'),
        'is_preferred': _DimensionSpec(
            'spp.is_preferred', 'Preferred supplier status', 'boolean'),
        'branch_id': _DimensionSpec('spp.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'price_rows':
            _MeasureSpec('COUNT(*)', 'Supplier price rows', 'records'),
        'average_cost': _MeasureSpec(
            'AVG(spp.cost)', 'Average supplier unit cost', 'money_unit',
            currencyExpression: 'spp.currency',
            contextExpression: 'spp.product_id',
            contextLabel: 'product',
            additionalContextExpression: 'spp.supplier_id',
            additionalContextLabel: 'supplier'),
        'average_lead_time_days': _MeasureSpec(
            'AVG(spp.lead_time_days)', 'Average lead time', 'days',
            contextExpression: 'spp.product_id', contextLabel: 'product'),
      },
      relationships: <String>[
        'supplier_product_prices.product_id = products.id',
        'supplier_product_prices.supplier_id = suppliers.id',
      ],
    ),
    'expenses': _TableSpec(
      domain: _Domain.expenses,
      title: 'Expenses',
      description:
          'Posted expenses. Amount follows Ventio’s stored USD-reference amount; original currency is not inferred as the reporting currency.',
      baseTable: 'expenses',
      source: 'expenses e',
      scope: 'e.store_id = ?',
      softDelete: "e.deleted_at = ''",
      dateExpression: 'e.expense_date',
      searchExpressions: <String>['e.title', 'e.category', 'e.branch_id'],
      dimensions: <String, _DimensionSpec>{
        'title': _DimensionSpec('e.title', 'Expense title', 'text'),
        'category': _DimensionSpec('e.category', 'Category', 'text'),
        'expense_date':
            _DimensionSpec('e.expense_date', 'Expense date', 'date'),
        'expense_status': _DimensionSpec('e.expense_status', 'Status', 'text'),
        'original_currency': _DimensionSpec(
            'e.original_currency', 'Original currency', 'currency'),
        'branch_id': _DimensionSpec('e.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'expense_count': _MeasureSpec('COUNT(*)', 'Expense count', 'records'),
        'amount': _MeasureSpec('SUM(e.amount)',
            'Expense amount (USD reference as stored)', 'money',
            currencyLabel: 'USD reference as stored'),
      },
      defaultFilter: "lower(e.expense_status) = 'posted'",
      relationships: <String>['expenses.branch_id = accounting_branches.id'],
    ),
    'stock_movements': _TableSpec(
      domain: _Domain.inventory,
      title: 'Stock movements',
      description:
          'Inventory ledger movements. A positive quantity increases stock and a negative quantity decreases it; movement quantity is grouped by product to avoid adding unlike units. The movement row does not record a currency for unit cost.',
      baseTable: 'stock_movements',
      source: 'stock_movements sm',
      scope: 'sm.store_id = ?',
      softDelete: "sm.deleted_at = ''",
      dateExpression: 'sm.movement_date',
      searchExpressions: <String>[
        'sm.product_name',
        'sm.movement_type',
        'sm.reference_no',
        'sm.warehouse_name',
      ],
      dimensions: <String, _DimensionSpec>{
        'product_name': _DimensionSpec('sm.product_name', 'Product', 'text'),
        'movement_type':
            _DimensionSpec('sm.movement_type', 'Movement type', 'text'),
        'movement_date':
            _DimensionSpec('sm.movement_date', 'Movement date', 'date'),
        'reference_no':
            _DimensionSpec('sm.reference_no', 'Reference number', 'text'),
        'warehouse_name':
            _DimensionSpec('sm.warehouse_name', 'Warehouse', 'text'),
        'branch_id': _DimensionSpec('sm.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'movement_count': _MeasureSpec('COUNT(*)', 'Movement count', 'records'),
        'net_quantity': _MeasureSpec(
            'SUM(sm.quantity)', 'Net quantity', 'quantity',
            contextExpression: 'sm.product_name', contextLabel: 'product'),
        'recorded_value_change': _MeasureSpec(
            'SUM(sm.quantity * COALESCE(sm.unit_cost, 0))',
            'Recorded value change',
            'recorded_value',
            contextExpression: 'sm.product_name',
            contextLabel: 'product',
            currencyLabel: 'Currency is not stored on the movement row.'),
      },
      relationships: <String>[
        'stock_movements.product_id = products.id',
        'stock_movements.warehouse_id = warehouses.id',
      ],
    ),
    'warehouse_inventory': _TableSpec(
      domain: _Domain.inventory,
      title: 'Warehouse stock balances',
      description:
          'Current quantity snapshots by product and warehouse. Quantities are never added across different products.',
      baseTable: 'warehouse_inventory',
      source: 'warehouse_inventory wi',
      scope: 'wi.store_id = ?',
      searchExpressions: <String>[],
      dimensions: <String, _DimensionSpec>{
        'product_id':
            _DimensionSpec('wi.product_id', 'Product ID', 'identifier'),
        'warehouse_id':
            _DimensionSpec('wi.warehouse_id', 'Warehouse ID', 'identifier'),
        'branch_id': _DimensionSpec('wi.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'balance_rows':
            _MeasureSpec('COUNT(*)', 'Product-warehouse rows', 'records'),
        'quantity': _MeasureSpec(
            'SUM(wi.quantity)', 'Current stock quantity', 'quantity',
            contextExpression: 'wi.product_id', contextLabel: 'product'),
      },
      relationships: <String>[
        'warehouse_inventory.product_id = products.id',
        'warehouse_inventory.warehouse_id = warehouses.id',
      ],
    ),
    'warehouses': _TableSpec(
      domain: _Domain.inventory,
      title: 'Warehouses',
      description: 'Warehouse directory and active status.',
      baseTable: 'warehouses',
      source: 'warehouses wh',
      scope: 'wh.store_id = ?',
      softDelete: "wh.deleted_at = ''",
      searchExpressions: <String>['wh.name', 'wh.code', 'wh.location'],
      dimensions: <String, _DimensionSpec>{
        'name': _DimensionSpec('wh.name', 'Warehouse', 'text'),
        'code': _DimensionSpec('wh.code', 'Warehouse code', 'text'),
        'is_active': _DimensionSpec('wh.is_active', 'Active status', 'boolean'),
        'branch_id': _DimensionSpec('wh.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'warehouse_count':
            _MeasureSpec('COUNT(*)', 'Warehouse count', 'records'),
      },
      relationships: <String>[
        'warehouses.id = warehouse_inventory.warehouse_id',
        'warehouses.id = stock_movements.warehouse_id',
      ],
    ),
    'inventory_batches': _TableSpec(
      domain: _Domain.inventory,
      title: 'Inventory batches',
      description:
          'Received and manufactured batches, including expiry and supplier batch references. Initial quantity is historical receipt quantity, not current stock.',
      baseTable: 'inventory_batches',
      source: 'inventory_batches ib',
      scope: 'ib.store_id = ?',
      dateExpression: 'ib.received_at',
      searchExpressions: <String>[
        'ib.product_name',
        'ib.supplier_batch_number',
        'ib.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'product_name': _DimensionSpec('ib.product_name', 'Product', 'text'),
        'status': _DimensionSpec('ib.status', 'Batch status', 'text'),
        'source_type':
            _DimensionSpec('ib.source_type', 'Batch source type', 'text'),
        'expiration_date':
            _DimensionSpec('ib.expiration_date', 'Expiration date', 'date'),
        'branch_id': _DimensionSpec('ib.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'batch_count': _MeasureSpec('COUNT(*)', 'Batch count', 'records'),
        'initial_quantity': _MeasureSpec(
            'SUM(ib.initial_quantity)', 'Initial batch quantity', 'quantity',
            contextExpression: 'ib.product_name', contextLabel: 'product'),
      },
      relationships: <String>[
        'inventory_batches.product_id = products.id',
        'inventory_batches.id = inventory_batch_balances.batch_id',
        'inventory_batches.id = purchase_item_batch_allocations.batch_id',
      ],
    ),
    'inventory_batch_balances': _TableSpec(
      domain: _Domain.inventory,
      title: 'Batch stock balances',
      description:
          'Current quantity by product, batch, and warehouse. Quantities are separated by product.',
      baseTable: 'inventory_batch_balances',
      source: 'inventory_batch_balances ibb',
      scope: 'ibb.store_id = ?',
      searchExpressions: <String>[],
      dimensions: <String, _DimensionSpec>{
        'product_id':
            _DimensionSpec('ibb.product_id', 'Product ID', 'identifier'),
        'batch_id': _DimensionSpec('ibb.batch_id', 'Batch ID', 'identifier'),
        'warehouse_id':
            _DimensionSpec('ibb.warehouse_id', 'Warehouse ID', 'identifier'),
        'branch_id': _DimensionSpec('ibb.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'balance_rows':
            _MeasureSpec('COUNT(*)', 'Batch balance rows', 'records'),
        'quantity': _MeasureSpec(
            'SUM(ibb.quantity)', 'Batch quantity', 'quantity',
            contextExpression: 'ibb.product_id', contextLabel: 'product'),
      },
      relationships: <String>[
        'inventory_batch_balances.batch_id = inventory_batches.id',
        'inventory_batch_balances.product_id = products.id',
      ],
    ),
    'inventory_stock_deficits': _TableSpec(
      domain: _Domain.inventory,
      title: 'Inventory stock deficits',
      description:
          'Tracked negative-stock deficits and their remaining open quantity.',
      baseTable: 'inventory_stock_deficits',
      source: 'inventory_stock_deficits isd',
      scope: 'isd.store_id = ?',
      dateExpression: 'isd.created_at',
      searchExpressions: <String>[
        'isd.product_id',
        'isd.warehouse_id',
        'isd.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'product_id':
            _DimensionSpec('isd.product_id', 'Product ID', 'identifier'),
        'warehouse_id':
            _DimensionSpec('isd.warehouse_id', 'Warehouse ID', 'identifier'),
        'status': _DimensionSpec('isd.status', 'Status', 'text'),
        'branch_id': _DimensionSpec('isd.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'deficit_count': _MeasureSpec('COUNT(*)', 'Deficit records', 'records'),
        'open_quantity': _MeasureSpec(
            'SUM(isd.quantity_open)', 'Open deficit quantity', 'quantity',
            contextExpression: 'isd.product_id', contextLabel: 'product'),
      },
      relationships: <String>[
        'inventory_stock_deficits.product_id = products.id',
        'inventory_stock_deficits.deficit_batch_id = inventory_batches.id',
        'inventory_stock_deficits.id = inventory_deficit_settlements.deficit_id',
      ],
    ),
    'inventory_deficit_settlements': _TableSpec(
      domain: _Domain.inventory,
      title: 'Inventory deficit settlements',
      description:
          'Incoming stock used to settle tracked negative-stock deficits. Quantities are grouped by product; recorded cost adjustments have no currency column on this table.',
      baseTable: 'inventory_deficit_settlements',
      source:
          'inventory_deficit_settlements ids JOIN inventory_stock_deficits isd ON isd.id = ids.deficit_id',
      scope: 'isd.store_id = ?',
      dateExpression: 'ids.settled_at',
      searchExpressions: <String>['isd.product_id', 'ids.status'],
      dimensions: <String, _DimensionSpec>{
        'product_id':
            _DimensionSpec('isd.product_id', 'Product ID', 'identifier'),
        'status': _DimensionSpec('ids.status', 'Settlement status', 'text'),
        'settled_at':
            _DimensionSpec('ids.settled_at', 'Settlement date', 'date'),
        'branch_id': _DimensionSpec('isd.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'settlement_count':
            _MeasureSpec('COUNT(*)', 'Settlement count', 'records'),
        'settled_quantity': _MeasureSpec(
            'SUM(ids.quantity - COALESCE(ids.reversed_quantity, 0))',
            'Settled quantity',
            'quantity',
            contextExpression: 'isd.product_id',
            contextLabel: 'product',
            additionalContextExpression: 'ids.status',
            additionalContextLabel: 'settlement status'),
        'cost_adjustment': _MeasureSpec('SUM(ids.cost_adjustment)',
            'Recorded cost adjustment', 'recorded_value',
            contextExpression: 'isd.product_id',
            contextLabel: 'product',
            additionalContextExpression: 'ids.status',
            additionalContextLabel: 'settlement status',
            currencyLabel: 'Currency is not stored on the settlement row.'),
      },
      relationships: <String>[
        'inventory_deficit_settlements.deficit_id = inventory_stock_deficits.id',
        'inventory_deficit_settlements.incoming_batch_id = inventory_batches.id',
      ],
    ),
    'inventory_reconciliations': _TableSpec(
      domain: _Domain.inventory,
      title: 'Inventory reconciliation snapshots',
      description:
          'Recorded comparisons between legacy stock and warehouse ledger balances. These are reconciliation snapshots, not current stock balances.',
      baseTable: 'inventory_reconciliations',
      source: 'inventory_reconciliations ir',
      scope: 'ir.store_id = ?',
      dateExpression: 'ir.created_at',
      searchExpressions: <String>[
        'ir.classification',
        'ir.status',
        'ir.product_id'
      ],
      dimensions: <String, _DimensionSpec>{
        'product_id':
            _DimensionSpec('ir.product_id', 'Product ID', 'identifier'),
        'warehouse_id':
            _DimensionSpec('ir.warehouse_id', 'Warehouse ID', 'identifier'),
        'classification': _DimensionSpec(
            'ir.classification', 'Difference classification', 'text'),
        'status': _DimensionSpec('ir.status', 'Resolution status', 'text'),
        'created_at': _DimensionSpec('ir.created_at', 'Snapshot date', 'date'),
        'branch_id': _DimensionSpec('ir.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'reconciliation_count':
            _MeasureSpec('COUNT(*)', 'Reconciliation rows', 'records'),
        'quantity_difference': _MeasureSpec(
            'SUM(ir.difference)', 'Recorded quantity difference', 'quantity',
            contextExpression: 'ir.product_id',
            contextLabel: 'product',
            additionalContextExpression: 'ir.status',
            additionalContextLabel: 'reconciliation status'),
      },
      relationships: <String>[
        'inventory_reconciliations.product_id = products.id',
        'inventory_reconciliations.warehouse_id = warehouses.id',
      ],
    ),
    'warehouse_transfer_orders': _TableSpec(
      domain: _Domain.inventory,
      title: 'Warehouse transfer orders',
      description:
          'Warehouse transfer order headers. Item details are stored in an internal JSON field and are not exposed by this aggregate.',
      baseTable: 'warehouse_transfer_orders',
      source: 'warehouse_transfer_orders wto',
      scope: 'wto.store_id = ?',
      softDelete: "wto.deleted_at = ''",
      dateExpression: 'wto.document_date',
      searchExpressions: <String>[
        'wto.order_no',
        'wto.status',
        'wto.from_warehouse_name',
        'wto.to_warehouse_name'
      ],
      dimensions: <String, _DimensionSpec>{
        'order_no': _DimensionSpec('wto.order_no', 'Order number', 'text'),
        'document_date':
            _DimensionSpec('wto.document_date', 'Order date', 'date'),
        'status': _DimensionSpec('wto.status', 'Status', 'text'),
        'from_warehouse_name': _DimensionSpec(
            'wto.from_warehouse_name', 'Source warehouse', 'text'),
        'to_warehouse_name': _DimensionSpec(
            'wto.to_warehouse_name', 'Destination warehouse', 'text'),
        'branch_id': _DimensionSpec('wto.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'transfer_count':
            _MeasureSpec('COUNT(*)', 'Transfer order count', 'documents'),
      },
      relationships: <String>[
        'warehouse_transfer_orders.from_warehouse_id = warehouses.id',
        'warehouse_transfer_orders.to_warehouse_id = warehouses.id',
      ],
    ),
    'inventory_counts': _TableSpec(
      domain: _Domain.inventory,
      title: 'Inventory counts',
      description:
          'Inventory count documents, including their approval and reversal status.',
      baseTable: 'inventory_counts',
      source: 'inventory_counts ic',
      scope: 'ic.store_id = ?',
      softDelete: "ic.deleted_at = ''",
      searchExpressions: <String>[
        'ic.count_no',
        'ic.warehouse_name',
        'ic.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'count_no': _DimensionSpec('ic.count_no', 'Count number', 'text'),
        'warehouse_name':
            _DimensionSpec('ic.warehouse_name', 'Warehouse', 'text'),
        'status': _DimensionSpec('ic.status', 'Count status', 'text'),
        'branch_id': _DimensionSpec('ic.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'count_documents':
            _MeasureSpec('COUNT(*)', 'Inventory count documents', 'documents'),
      },
      relationships: <String>[
        'inventory_counts.id = inventory_count_lines.inventory_count_id'
      ],
    ),
    'inventory_count_lines': _TableSpec(
      domain: _Domain.inventory,
      title: 'Inventory count lines',
      description:
          'Counted quantities and recorded differences, scoped through the parent inventory count.',
      baseTable: 'inventory_count_lines',
      source:
          'inventory_count_lines il JOIN inventory_counts ic ON ic.id = il.inventory_count_id',
      scope: 'ic.store_id = ?',
      softDelete: "ic.deleted_at = ''",
      searchExpressions: <String>[
        'il.product_name',
        'il.product_code',
        'ic.warehouse_name'
      ],
      dimensions: <String, _DimensionSpec>{
        'product_name': _DimensionSpec('il.product_name', 'Product', 'text'),
        'product_code':
            _DimensionSpec('il.product_code', 'Product code', 'text'),
        'warehouse_name':
            _DimensionSpec('ic.warehouse_name', 'Warehouse', 'text'),
        'status': _DimensionSpec('ic.status', 'Count status', 'text'),
        'branch_id': _DimensionSpec('ic.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'line_count': _MeasureSpec('COUNT(*)', 'Count line count', 'lines'),
        'quantity_difference': _MeasureSpec('SUM(il.difference_qty)',
            'Recorded quantity difference', 'quantity',
            contextExpression: 'il.product_name',
            contextLabel: 'product',
            additionalContextExpression: 'ic.status',
            additionalContextLabel: 'count status'),
        'value_difference': _MeasureSpec('SUM(il.difference_value)',
            'Recorded value difference', 'recorded_value',
            contextExpression: 'il.product_name',
            contextLabel: 'product',
            additionalContextExpression: 'ic.status',
            additionalContextLabel: 'count status',
            currencyLabel: 'Currency is not stored on the count line.'),
      },
      relationships: <String>[
        'inventory_count_lines.inventory_count_id = inventory_counts.id'
      ],
    ),
    'manufacturing_orders': _TableSpec(
      domain: _Domain.manufacturing,
      title: 'Manufacturing orders',
      description:
          'Manufacturing order headers with output, status, material cost, and recorded waste cost.',
      baseTable: 'manufacturing_orders',
      source: 'manufacturing_orders mo',
      scope: 'mo.store_id = ?',
      softDelete: "mo.deleted_at = ''",
      dateExpression: 'mo.document_date',
      searchExpressions: <String>[
        'mo.order_no',
        'mo.output_product_name',
        'mo.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'order_no': _DimensionSpec('mo.order_no', 'Order number', 'text'),
        'output_product_name':
            _DimensionSpec('mo.output_product_name', 'Output product', 'text'),
        'document_date':
            _DimensionSpec('mo.document_date', 'Order date', 'date'),
        'status': _DimensionSpec('mo.status', 'Order status', 'text'),
        'branch_id': _DimensionSpec('mo.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'order_count':
            _MeasureSpec('COUNT(*)', 'Manufacturing order count', 'documents'),
        'output_quantity': _MeasureSpec('SUM(mo.actual_output_quantity)',
            'Actual output quantity', 'quantity',
            contextExpression: 'mo.output_product_name',
            contextLabel: 'output product',
            additionalContextExpression: 'mo.status',
            additionalContextLabel: 'order status'),
        'material_cost': _MeasureSpec('SUM(mo.total_material_cost)',
            'Recorded material cost (base currency)', 'recorded_value',
            currencyLabel: 'Ventio base currency',
            contextExpression: 'mo.status',
            contextLabel: 'order status'),
        'waste_cost': _MeasureSpec('SUM(mo.total_waste_cost)',
            'Recorded waste cost (base currency)', 'recorded_value',
            currencyLabel: 'Ventio base currency',
            contextExpression: 'mo.status',
            contextLabel: 'order status'),
      },
      relationships: <String>[
        'manufacturing_orders.bom_id = bill_of_materials.id',
        'manufacturing_orders.output_product_id = products.id',
      ],
    ),
    'bill_of_materials': _TableSpec(
      domain: _Domain.manufacturing,
      title: 'Bills of materials',
      description:
          'Manufacturing recipes, their output products, and active status.',
      baseTable: 'bill_of_materials',
      source: 'bill_of_materials bom',
      scope: 'bom.store_id = ?',
      softDelete: "bom.deleted_at = ''",
      searchExpressions: <String>['bom.name', 'bom.output_product_name'],
      dimensions: <String, _DimensionSpec>{
        'name': _DimensionSpec('bom.name', 'Recipe name', 'text'),
        'output_product_name':
            _DimensionSpec('bom.output_product_name', 'Output product', 'text'),
        'is_active':
            _DimensionSpec('bom.is_active', 'Active status', 'boolean'),
        'branch_id': _DimensionSpec('bom.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'recipe_count': _MeasureSpec('COUNT(*)', 'Recipe count', 'records'),
      },
      relationships: <String>[
        'bill_of_materials.id = bill_of_materials_lines.bill_of_material_id',
        'bill_of_materials.output_product_id = products.id',
      ],
    ),
    'bill_of_materials_lines': _TableSpec(
      domain: _Domain.manufacturing,
      title: 'Bill of materials lines',
      description:
          'Recipe component products and required quantities, scoped through the parent recipe.',
      baseTable: 'bill_of_materials_lines',
      source:
          'bill_of_materials_lines bl JOIN bill_of_materials bom ON bom.id = bl.bill_of_material_id',
      scope: 'bom.store_id = ?',
      softDelete: "bom.deleted_at = ''",
      searchExpressions: <String>['bl.product_name', 'bom.name'],
      dimensions: <String, _DimensionSpec>{
        'product_name':
            _DimensionSpec('bl.product_name', 'Component product', 'text'),
        'recipe_name': _DimensionSpec('bom.name', 'Recipe', 'text'),
        'output_product_name':
            _DimensionSpec('bom.output_product_name', 'Output product', 'text'),
        'branch_id': _DimensionSpec('bom.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'component_lines':
            _MeasureSpec('COUNT(*)', 'Component line count', 'lines'),
        'required_quantity': _MeasureSpec(
            'SUM(bl.quantity)', 'Required recipe quantity', 'quantity',
            contextExpression: 'bl.product_name',
            contextLabel: 'component product'),
      },
      relationships: <String>[
        'bill_of_materials_lines.bill_of_material_id = bill_of_materials.id',
        'bill_of_materials_lines.product_id = products.id',
      ],
    ),
    'journal_entries': _TableSpec(
      domain: _Domain.accounting,
      title: 'Journal entries',
      description:
          'Accounting journal entry headers. Posted status is returned as stored; use accounting reports for official financial statement totals.',
      baseTable: 'journal_entries',
      source: 'journal_entries je',
      scope: 'je.store_id = ?',
      softDelete: "je.deleted_at = ''",
      dateExpression: 'je.entry_date',
      searchExpressions: <String>[
        'je.entry_no',
        'je.reference_no',
        'je.description',
        'je.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'entry_no': _DimensionSpec('je.entry_no', 'Entry number', 'text'),
        'entry_date': _DimensionSpec('je.entry_date', 'Entry date', 'date'),
        'reference_type':
            _DimensionSpec('je.reference_type', 'Reference type', 'text'),
        'status': _DimensionSpec('je.status', 'Entry status', 'text'),
        'source': _DimensionSpec('je.source', 'Entry source', 'text'),
        'branch_id': _DimensionSpec('je.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'entry_count':
            _MeasureSpec('COUNT(*)', 'Journal entry count', 'documents'),
      },
      defaultFilter: "lower(je.status) = 'posted'",
      relationships: <String>[
        'journal_entries.id = journal_lines.entry_id',
        'journal_entries.reference_id references the source document identified by reference_type',
      ],
    ),
    'journal_lines': _TableSpec(
      domain: _Domain.accounting,
      title: 'Journal lines',
      description:
          'Posted debit and credit lines. Monetary totals are separated by the line currency; use accounting reports for official statement totals.',
      baseTable: 'journal_lines',
      source: 'journal_lines jl JOIN journal_entries je ON je.id = jl.entry_id',
      scope: 'jl.store_id = ?',
      softDelete: "je.deleted_at = ''",
      dateExpression: 'je.entry_date',
      searchExpressions: <String>[
        'jl.account_name',
        'jl.account_code',
        'jl.party_name',
        'jl.memo'
      ],
      dimensions: <String, _DimensionSpec>{
        'account_name': _DimensionSpec('jl.account_name', 'Account', 'text'),
        'account_code':
            _DimensionSpec('jl.account_code', 'Account code', 'text'),
        'party_name': _DimensionSpec('jl.party_name', 'Party', 'text'),
        'party_type': _DimensionSpec('jl.party_type', 'Party type', 'text'),
        'entry_date': _DimensionSpec('je.entry_date', 'Entry date', 'date'),
        'reference_type':
            _DimensionSpec('je.reference_type', 'Reference type', 'text'),
        'currency': _DimensionSpec('jl.currency', 'Currency', 'currency'),
        'branch_id': _DimensionSpec('jl.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'line_count': _MeasureSpec('COUNT(*)', 'Journal line count', 'lines'),
        'debit': _MeasureSpec('SUM(jl.debit)', 'Debit', 'money',
            currencyExpression: 'jl.currency'),
        'credit': _MeasureSpec('SUM(jl.credit)', 'Credit', 'money',
            currencyExpression: 'jl.currency'),
      },
      defaultFilter: "lower(je.status) = 'posted'",
      relationships: <String>[
        'journal_lines.entry_id = journal_entries.id',
        'journal_lines.account_id = accounts.id',
        'journal_lines.party_id references customers or suppliers according to party_type',
      ],
    ),
    'accounts': _TableSpec(
      domain: _Domain.accounting,
      title: 'Chart of accounts',
      description: 'Accounting account definitions and their classification.',
      baseTable: 'accounts',
      source: 'accounts a',
      scope: 'a.store_id = ?',
      softDelete: "a.deleted_at = ''",
      searchExpressions: <String>['a.code', 'a.name', 'a.type', 'a.subtype'],
      dimensions: <String, _DimensionSpec>{
        'code': _DimensionSpec('a.code', 'Account code', 'text'),
        'name': _DimensionSpec('a.name', 'Account name', 'text'),
        'type': _DimensionSpec('a.type', 'Account type', 'text'),
        'subtype': _DimensionSpec('a.subtype', 'Account subtype', 'text'),
        'normal_balance':
            _DimensionSpec('a.normal_balance', 'Normal balance', 'text'),
        'is_active': _DimensionSpec('a.is_active', 'Active status', 'boolean'),
        'branch_id': _DimensionSpec('a.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'account_count': _MeasureSpec('COUNT(*)', 'Account count', 'records'),
      },
      relationships: <String>['accounts.id = journal_lines.account_id'],
    ),
    'accounting_periods': _TableSpec(
      domain: _Domain.accounting,
      title: 'Accounting periods',
      description: 'Accounting period ranges and their open or closed status.',
      baseTable: 'accounting_periods',
      source: 'accounting_periods ap',
      scope: 'ap.store_id = ?',
      searchExpressions: <String>['ap.name', 'ap.status'],
      dimensions: <String, _DimensionSpec>{
        'name': _DimensionSpec('ap.name', 'Period name', 'text'),
        'start_date': _DimensionSpec('ap.start_date', 'Start date', 'date'),
        'end_date': _DimensionSpec('ap.end_date', 'End date', 'date'),
        'status': _DimensionSpec('ap.status', 'Period status', 'text'),
        'branch_id': _DimensionSpec('ap.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'period_count':
            _MeasureSpec('COUNT(*)', 'Accounting period count', 'records'),
      },
      relationships: <String>[
        'accounting_periods.status determines whether a period is open or closed',
        'accounting_periods.branch_id = accounting_branches.id',
      ],
    ),
    'accounting_branches': _TableSpec(
      domain: _Domain.accounting,
      title: 'Accounting branches',
      description: 'Branch directory used by accounting and business records.',
      baseTable: 'accounting_branches',
      source: 'accounting_branches ab',
      scope: 'ab.store_id = ?',
      softDelete: "ab.deleted_at = ''",
      searchExpressions: <String>['ab.code', 'ab.name'],
      dimensions: <String, _DimensionSpec>{
        'code': _DimensionSpec('ab.code', 'Branch code', 'text'),
        'name': _DimensionSpec('ab.name', 'Branch name', 'text'),
        'is_active': _DimensionSpec('ab.is_active', 'Active status', 'boolean'),
      },
      measures: <String, _MeasureSpec>{
        'branch_count': _MeasureSpec('COUNT(*)', 'Branch count', 'records'),
      },
      relationships: <String>[
        'accounting_branches.id = business record branch_id values',
      ],
    ),
    'costing_method_history': _TableSpec(
      domain: _Domain.accounting,
      title: 'Costing method history',
      description:
          'Historical inventory costing method changes and their effective periods.',
      baseTable: 'costing_method_history',
      source: 'costing_method_history cmh',
      scope: 'cmh.store_id = ?',
      softDelete: "cmh.deleted_at = ''",
      dateExpression: 'cmh.effective_from',
      searchExpressions: <String>['cmh.method', 'cmh.reason'],
      dimensions: <String, _DimensionSpec>{
        'method': _DimensionSpec('cmh.method', 'Costing method', 'text'),
        'effective_from':
            _DimensionSpec('cmh.effective_from', 'Effective from', 'date'),
        'effective_to':
            _DimensionSpec('cmh.effective_to', 'Effective to', 'date'),
        'branch_id': _DimensionSpec('cmh.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'change_count':
            _MeasureSpec('COUNT(*)', 'Costing method history rows', 'records'),
      },
      relationships: <String>[
        'The method applies to inventory cost layers and stock movements from its effective date.',
      ],
    ),
    'cost_centers': _TableSpec(
      domain: _Domain.accounting,
      title: 'Cost centers',
      description: 'Cost center definitions used to classify accounting lines.',
      baseTable: 'cost_centers',
      source: 'cost_centers cc',
      scope: 'cc.store_id = ?',
      softDelete: "cc.deleted_at = ''",
      searchExpressions: <String>['cc.code', 'cc.name'],
      dimensions: <String, _DimensionSpec>{
        'code': _DimensionSpec('cc.code', 'Cost center code', 'text'),
        'name': _DimensionSpec('cc.name', 'Cost center name', 'text'),
        'is_active': _DimensionSpec('cc.is_active', 'Active status', 'boolean'),
        'branch_id': _DimensionSpec('cc.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'cost_center_count':
            _MeasureSpec('COUNT(*)', 'Cost center count', 'records'),
      },
      relationships: <String>['cost_centers.id = journal_lines.cost_center_id'],
    ),
    'account_transactions': _TableSpec(
      domain: _Domain.accounting,
      title: 'Party account transactions',
      description:
          'Stored customer and supplier account movements. Debits and credits are returned separately; use the dedicated party statement for a signed running balance.',
      baseTable: 'account_transactions',
      source: 'account_transactions at',
      scope: 'at.store_id = ?',
      softDelete: "at.deleted_at = ''",
      dateExpression: 'at.transaction_date',
      searchExpressions: <String>[
        'at.account_name',
        'at.reference_no',
        'at.transaction_type',
      ],
      dimensions: <String, _DimensionSpec>{
        'account_type': _DimensionSpec('at.account_type', 'Party type', 'text'),
        'account_name': _DimensionSpec('at.account_name', 'Party', 'text'),
        'transaction_type':
            _DimensionSpec('at.transaction_type', 'Transaction type', 'text'),
        'transaction_date':
            _DimensionSpec('at.transaction_date', 'Transaction date', 'date'),
        'currency': _DimensionSpec('at.currency', 'Currency', 'currency'),
        'branch_id': _DimensionSpec('at.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'transaction_count':
            _MeasureSpec('COUNT(*)', 'Transaction count', 'records'),
        'debit': _MeasureSpec('SUM(at.debit)', 'Debit', 'money',
            currencyExpression: 'at.currency'),
        'credit': _MeasureSpec('SUM(at.credit)', 'Credit', 'money',
            currencyExpression: 'at.currency'),
      },
      relationships: <String>[
        'account_transactions.account_id and account_type identify the party account',
        'account_transactions.reference_id references the source invoice or payment',
      ],
    ),
    'cash_ledger_transactions': _TableSpec(
      domain: _Domain.cash,
      title: 'Cash ledger transactions',
      description:
          'Recorded cash and bank movement events. Amounts are separated by currency and direction; use the cash balance report for current balances.',
      baseTable: 'cash_ledger_transactions',
      source: 'cash_ledger_transactions cl',
      scope: 'cl.store_id = ?',
      softDelete: "cl.deleted_at = ''",
      dateExpression: 'cl.occurred_at',
      searchExpressions: <String>[
        'cl.type',
        'cl.party_name',
        'cl.reference_number',
        'cl.payment_method'
      ],
      dimensions: <String, _DimensionSpec>{
        'type': _DimensionSpec('cl.type', 'Transaction type', 'text'),
        'direction': _DimensionSpec('cl.direction', 'Direction', 'text'),
        'currency': _DimensionSpec('cl.currency', 'Currency', 'currency'),
        'party_name': _DimensionSpec('cl.party_name', 'Party', 'text'),
        'party_type': _DimensionSpec('cl.party_type', 'Party type', 'text'),
        'payment_method':
            _DimensionSpec('cl.payment_method', 'Payment method', 'text'),
        'occurred_at':
            _DimensionSpec('cl.occurred_at', 'Transaction date', 'date'),
        'branch_id': _DimensionSpec('cl.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'transaction_count':
            _MeasureSpec('COUNT(*)', 'Transaction count', 'records'),
        'amount': _MeasureSpec('SUM(cl.amount)', 'Transaction amount', 'money',
            currencyExpression: 'cl.currency',
            contextExpression: 'cl.direction',
            contextLabel: 'direction'),
      },
      defaultFilter: "COALESCE(cl.reversal_of_id, '') = ''",
      defaultFilterDescription: 'Reversal rows are excluded.',
      relationships: <String>[
        'cash_ledger_transactions.cash_location_id = cash_locations.id',
        'cash_ledger_transactions.cash_drawer_session_id = cash_drawer_sessions.id',
        'cash_ledger_transactions.reference_id references its source document by reference_type',
      ],
    ),
    'cash_operations': _TableSpec(
      domain: _Domain.cash,
      title: 'Cash operations',
      description: 'Cash operations and their posting or reversal status.',
      baseTable: 'cash_operations',
      source: 'cash_operations co',
      scope: 'co.store_id = ?',
      softDelete: "co.deleted_at = ''",
      dateExpression: 'co.operation_date',
      searchExpressions: <String>[
        'co.operation_no',
        'co.operation_type',
        'co.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'operation_no':
            _DimensionSpec('co.operation_no', 'Operation number', 'text'),
        'operation_type':
            _DimensionSpec('co.operation_type', 'Operation type', 'text'),
        'operation_date':
            _DimensionSpec('co.operation_date', 'Operation date', 'date'),
        'status': _DimensionSpec('co.status', 'Status', 'text'),
        'branch_id': _DimensionSpec('co.branch_id', 'Branch', 'text'),
        'currency': _DimensionSpec('co.currency', 'Currency', 'currency'),
      },
      measures: <String, _MeasureSpec>{
        'operation_count':
            _MeasureSpec('COUNT(*)', 'Operation count', 'records'),
        'amount': _MeasureSpec('SUM(co.amount)', 'Operation amount', 'money',
            currencyExpression: 'co.currency',
            contextExpression: 'co.operation_type',
            contextLabel: 'operation type',
            additionalContextExpression: 'co.status',
            additionalContextLabel: 'operation status'),
      },
      relationships: <String>[
        'cash_operations.cash_location_id = cash_locations.id'
      ],
    ),
    'receipt_vouchers': _TableSpec(
      domain: _Domain.cash,
      title: 'Receipt vouchers',
      description:
          'Customer receipt vouchers; amounts are grouped by voucher currency.',
      baseTable: 'receipt_vouchers',
      source: 'receipt_vouchers rv',
      scope: 'rv.store_id = ?',
      softDelete: "rv.deleted_at = ''",
      dateExpression: 'rv.voucher_date',
      searchExpressions: <String>[
        'rv.voucher_no',
        'rv.customer_name',
        'rv.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'voucher_no': _DimensionSpec('rv.voucher_no', 'Voucher number', 'text'),
        'customer_name': _DimensionSpec('rv.customer_name', 'Customer', 'text'),
        'voucher_date':
            _DimensionSpec('rv.voucher_date', 'Voucher date', 'date'),
        'status': _DimensionSpec('rv.status', 'Status', 'text'),
        'currency': _DimensionSpec('rv.currency', 'Currency', 'currency'),
        'branch_id': _DimensionSpec('rv.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'voucher_count': _MeasureSpec('COUNT(*)', 'Voucher count', 'records'),
        'amount': _MeasureSpec('SUM(rv.amount)', 'Receipt amount', 'money',
            currencyExpression: 'rv.currency',
            contextExpression: 'rv.status',
            contextLabel: 'voucher status'),
      },
      relationships: <String>[
        'receipt_vouchers.customer_id = customers.id',
        'payment_allocations.voucher_id references receipt_vouchers.id when voucher_type is receipt',
      ],
    ),
    'payment_vouchers': _TableSpec(
      domain: _Domain.cash,
      title: 'Payment vouchers',
      description:
          'Supplier payment vouchers; amounts are grouped by voucher currency.',
      baseTable: 'payment_vouchers',
      source: 'payment_vouchers pv',
      scope: 'pv.store_id = ?',
      softDelete: "pv.deleted_at = ''",
      dateExpression: 'pv.voucher_date',
      searchExpressions: <String>[
        'pv.voucher_no',
        'pv.supplier_name',
        'pv.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'voucher_no': _DimensionSpec('pv.voucher_no', 'Voucher number', 'text'),
        'supplier_name': _DimensionSpec('pv.supplier_name', 'Supplier', 'text'),
        'voucher_date':
            _DimensionSpec('pv.voucher_date', 'Voucher date', 'date'),
        'status': _DimensionSpec('pv.status', 'Status', 'text'),
        'currency': _DimensionSpec('pv.currency', 'Currency', 'currency'),
        'branch_id': _DimensionSpec('pv.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'voucher_count': _MeasureSpec('COUNT(*)', 'Voucher count', 'records'),
        'amount': _MeasureSpec('SUM(pv.amount)', 'Payment amount', 'money',
            currencyExpression: 'pv.currency',
            contextExpression: 'pv.status',
            contextLabel: 'voucher status'),
      },
      relationships: <String>[
        'payment_vouchers.supplier_id = suppliers.id',
        'payment_allocations.voucher_id references payment_vouchers.id when voucher_type is payment',
      ],
    ),
    'payment_allocations': _TableSpec(
      domain: _Domain.cash,
      title: 'Voucher allocations',
      description:
          'Amounts allocated from receipt or payment vouchers to sales or purchase documents. The query scopes each allocation through its parent voucher and keeps voucher and reference currencies separate.',
      baseTable: 'payment_allocations',
      source: '''payment_allocations pa
        LEFT JOIN receipt_vouchers rv
          ON pa.voucher_type = 'receipt' AND rv.id = pa.voucher_id AND rv.deleted_at = ''
        LEFT JOIN payment_vouchers pv
          ON pa.voucher_type = 'payment' AND pv.id = pa.voucher_id AND pv.deleted_at = '''
          '',
      scope: 'COALESCE(rv.store_id, pv.store_id) = ?',
      softDelete: "COALESCE(pa.deleted_at, '') = ''",
      dateExpression: 'COALESCE(rv.voucher_date, pv.voucher_date)',
      searchExpressions: <String>[
        'pa.reference_number',
        'rv.customer_name',
        'pv.supplier_name',
      ],
      dimensions: <String, _DimensionSpec>{
        'voucher_type':
            _DimensionSpec('pa.voucher_type', 'Voucher type', 'text'),
        'reference_type': _DimensionSpec(
            'pa.reference_type', 'Applied document type', 'text'),
        'reference_number': _DimensionSpec(
            'pa.reference_number', 'Applied document number', 'text'),
        'status': _DimensionSpec('pa.status', 'Allocation status', 'text'),
        'allocation_kind':
            _DimensionSpec('pa.allocation_kind', 'Allocation kind', 'text'),
        'currency':
            _DimensionSpec('pa.currency', 'Voucher currency', 'currency'),
        'reference_currency': _DimensionSpec(
            'pa.reference_currency', 'Document currency', 'currency'),
        'voucher_date': _DimensionSpec(
            'COALESCE(rv.voucher_date, pv.voucher_date)',
            'Voucher date',
            'date'),
        'branch_id': _DimensionSpec(
            'COALESCE(rv.branch_id, pv.branch_id)', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'allocation_count':
            _MeasureSpec('COUNT(*)', 'Allocation count', 'records'),
        'voucher_amount': _MeasureSpec(
            'SUM(pa.amount)', 'Amount applied in voucher currency', 'money',
            currencyExpression: 'pa.currency',
            contextExpression: 'pa.voucher_type',
            contextLabel: 'voucher type',
            additionalContextExpression: 'pa.status',
            additionalContextLabel: 'allocation status'),
        'reference_amount': _MeasureSpec('SUM(pa.reference_amount)',
            'Amount applied in document currency', 'money',
            currencyExpression: 'pa.reference_currency',
            contextExpression: 'pa.reference_type',
            contextLabel: 'document type',
            additionalContextExpression: 'pa.status',
            additionalContextLabel: 'allocation status'),
      },
      relationships: <String>[
        'payment_allocations.voucher_type receipt joins receipt_vouchers.id',
        'payment_allocations.voucher_type payment joins payment_vouchers.id',
        'payment_allocations.reference_id identifies a sales or purchase document by reference_type',
      ],
    ),
    'cash_locations': _TableSpec(
      domain: _Domain.cash,
      title: 'Cash and bank locations',
      description:
          'Cash drawers, bank accounts, and other configured payment locations.',
      baseTable: 'cash_locations',
      source: 'cash_locations loc',
      scope: 'loc.store_id = ?',
      softDelete: "loc.deleted_at = ''",
      searchExpressions: <String>['loc.name', 'loc.code', 'loc.type'],
      dimensions: <String, _DimensionSpec>{
        'name': _DimensionSpec('loc.name', 'Location name', 'text'),
        'type': _DimensionSpec('loc.type', 'Location type', 'text'),
        'is_active':
            _DimensionSpec('loc.is_active', 'Active status', 'boolean'),
        'branch_id': _DimensionSpec('loc.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'location_count': _MeasureSpec('COUNT(*)', 'Location count', 'records'),
      },
      relationships: <String>[
        'cash_locations.id = cash_ledger_transactions.cash_location_id',
        'cash_locations.id = cash_operations.cash_location_id',
      ],
    ),
    'payment_accounts': _TableSpec(
      domain: _Domain.cash,
      title: 'Payment accounts',
      description:
          'Configured payment accounts and their active or default status. Account credentials are not exposed by this tool.',
      baseTable: 'payment_accounts',
      source: 'payment_accounts pac',
      scope: 'pac.store_id = ?',
      softDelete: "pac.deleted_at = ''",
      searchExpressions: <String>['pac.name', 'pac.type'],
      dimensions: <String, _DimensionSpec>{
        'name': _DimensionSpec('pac.name', 'Payment account name', 'text'),
        'type': _DimensionSpec('pac.type', 'Payment account type', 'text'),
        'is_default':
            _DimensionSpec('pac.is_default', 'Default status', 'boolean'),
        'is_active':
            _DimensionSpec('pac.is_active', 'Active status', 'boolean'),
        'branch_id': _DimensionSpec('pac.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'account_count':
            _MeasureSpec('COUNT(*)', 'Payment account count', 'records'),
      },
      relationships: <String>[
        'payment_accounts.account_id = accounts.id',
        'cash_locations.payment_account_id = payment_accounts.id',
      ],
    ),
    'cash_drawer_sessions': _TableSpec(
      domain: _Domain.cash,
      title: 'Cash drawer sessions',
      description:
          'Cashier shift sessions and open or closed status. Session totals are not combined because the table does not contain a currency column.',
      baseTable: 'cash_drawer_sessions',
      source: 'cash_drawer_sessions cds',
      scope: 'cds.store_id = ?',
      dateExpression: 'cds.opened_at',
      searchExpressions: <String>[
        'cds.drawer_no',
        'cds.status',
        'cds.opened_by'
      ],
      dimensions: <String, _DimensionSpec>{
        'drawer_no': _DimensionSpec('cds.drawer_no', 'Drawer number', 'text'),
        'status': _DimensionSpec('cds.status', 'Session status', 'text'),
        'branch_id': _DimensionSpec('cds.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'session_count':
            _MeasureSpec('COUNT(*)', 'Drawer session count', 'records'),
      },
      relationships: <String>[
        'cash_drawer_sessions.cash_location_id = cash_locations.id',
        'cash_drawer_sessions.id = receipt_vouchers.cash_drawer_session_id',
        'cash_drawer_sessions.id = payment_vouchers.cash_drawer_session_id',
      ],
    ),
    'cash_transfers': _TableSpec(
      domain: _Domain.cash,
      title: 'Cash transfers',
      description:
          'Transfers between cash or bank locations. Only document counts are aggregated because this table does not store a currency per amount.',
      baseTable: 'cash_transfers',
      source: 'cash_transfers ct',
      scope: 'ct.store_id = ?',
      softDelete: "ct.deleted_at = ''",
      dateExpression: 'ct.transfer_date',
      searchExpressions: <String>[
        'ct.transfer_no',
        'ct.status',
        'ct.transfer_kind'
      ],
      dimensions: <String, _DimensionSpec>{
        'transfer_no':
            _DimensionSpec('ct.transfer_no', 'Transfer number', 'text'),
        'transfer_date':
            _DimensionSpec('ct.transfer_date', 'Transfer date', 'date'),
        'status': _DimensionSpec('ct.status', 'Status', 'text'),
        'transfer_kind':
            _DimensionSpec('ct.transfer_kind', 'Transfer kind', 'text'),
        'branch_id': _DimensionSpec('ct.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'transfer_count':
            _MeasureSpec('COUNT(*)', 'Cash transfer count', 'documents'),
      },
      relationships: <String>[
        'cash_transfers.from_location_id = cash_locations.id',
        'cash_transfers.to_location_id = cash_locations.id',
      ],
    ),
    'cheques': _TableSpec(
      domain: _Domain.cash,
      title: 'Cheques',
      description:
          'Cheque records by direction, party, due date, and settlement status. Amounts are not aggregated because the table has no currency column.',
      baseTable: 'cheques',
      source: 'cheques ch',
      scope: 'ch.store_id = ?',
      dateExpression: 'ch.due_date',
      searchExpressions: <String>[
        'ch.cheque_no',
        'ch.party_name',
        'ch.status',
        'ch.bank_name'
      ],
      dimensions: <String, _DimensionSpec>{
        'direction': _DimensionSpec('ch.direction', 'Cheque direction', 'text'),
        'party_name': _DimensionSpec('ch.party_name', 'Party', 'text'),
        'party_type': _DimensionSpec('ch.party_type', 'Party type', 'text'),
        'status': _DimensionSpec('ch.status', 'Status', 'text'),
        'due_date': _DimensionSpec('ch.due_date', 'Due date', 'date'),
        'branch_id': _DimensionSpec('ch.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'cheque_count': _MeasureSpec('COUNT(*)', 'Cheque count', 'records'),
      },
      relationships: <String>[
        'cheques.party_id refers to a customer or supplier according to party_type',
        'cheques.journal_entry_id = journal_entries.id',
      ],
    ),
    'fixed_assets': _TableSpec(
      domain: _Domain.accounting,
      title: 'Fixed assets',
      description: 'Fixed asset register and acquisition values.',
      baseTable: 'fixed_assets',
      source: 'fixed_assets fa',
      scope: 'fa.store_id = ?',
      softDelete: "fa.deleted_at = ''",
      dateExpression: 'fa.acquisition_date',
      searchExpressions: <String>[
        'fa.code',
        'fa.name',
        'fa.category',
        'fa.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'code': _DimensionSpec('fa.code', 'Asset code', 'text'),
        'name': _DimensionSpec('fa.name', 'Asset name', 'text'),
        'category': _DimensionSpec('fa.category', 'Category', 'text'),
        'acquisition_date':
            _DimensionSpec('fa.acquisition_date', 'Acquisition date', 'date'),
        'status': _DimensionSpec('fa.status', 'Status', 'text'),
        'branch_id': _DimensionSpec('fa.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'asset_count': _MeasureSpec('COUNT(*)', 'Asset count', 'records'),
        'purchase_value': _MeasureSpec('SUM(fa.purchase_value)',
            'Recorded purchase value', 'recorded_value',
            currencyLabel: 'Ventio base currency',
            contextExpression: 'fa.status',
            contextLabel: 'asset status'),
      },
      relationships: <String>[
        'fixed_assets.id = fixed_asset_depreciation.asset_id',
        'fixed_assets.asset_account_id = accounts.id',
      ],
    ),
    'fixed_asset_depreciation': _TableSpec(
      domain: _Domain.accounting,
      title: 'Fixed asset depreciation',
      description: 'Recorded fixed asset depreciation entries and book values.',
      baseTable: 'fixed_asset_depreciation',
      source: 'fixed_asset_depreciation fad',
      scope: 'fad.store_id = ?',
      softDelete: "fad.deleted_at = ''",
      dateExpression: 'fad.depreciation_date',
      searchExpressions: <String>['fad.period_key'],
      dimensions: <String, _DimensionSpec>{
        'period_key':
            _DimensionSpec('fad.period_key', 'Depreciation period', 'text'),
        'depreciation_date': _DimensionSpec(
            'fad.depreciation_date', 'Depreciation date', 'date'),
        'branch_id': _DimensionSpec('fad.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'entry_count':
            _MeasureSpec('COUNT(*)', 'Depreciation entry count', 'records'),
        'amount': _MeasureSpec(
            'SUM(fad.amount)', 'Depreciation amount', 'recorded_value',
            currencyLabel: 'Ventio base currency'),
      },
      relationships: <String>[
        'fixed_asset_depreciation.asset_id = fixed_assets.id'
      ],
    ),
    'sale_quotations': _TableSpec(
      domain: _Domain.sales,
      title: 'Sales quotations',
      description: 'Sales quotation headers and conversion status.',
      baseTable: 'sale_quotations',
      source: 'sale_quotations sq',
      scope: 'sq.store_id = ?',
      softDelete: "sq.deleted_at = ''",
      dateExpression: 'sq.document_date',
      searchExpressions: <String>[
        'sq.quotation_no',
        'sq.customer_name',
        'sq.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'quotation_no':
            _DimensionSpec('sq.quotation_no', 'Quotation number', 'text'),
        'customer_name': _DimensionSpec('sq.customer_name', 'Customer', 'text'),
        'document_date':
            _DimensionSpec('sq.document_date', 'Quotation date', 'date'),
        'valid_until': _DimensionSpec('sq.valid_until', 'Valid until', 'date'),
        'status': _DimensionSpec('sq.status', 'Status', 'text'),
        'invoice_currency':
            _DimensionSpec('sq.invoice_currency', 'Currency', 'currency'),
        'branch_id': _DimensionSpec('sq.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'quotation_count':
            _MeasureSpec('COUNT(*)', 'Quotation count', 'documents'),
      },
      relationships: <String>[
        'sale_quotations.id = sale_quotation_items.sale_quotation_id',
        'sale_quotations.converted_sale_id = sales.id',
      ],
    ),
    'sale_quotation_items': _TableSpec(
      domain: _Domain.sales,
      title: 'Sales quotation lines',
      description:
          'Quoted products and quantities. Line amounts are before any quotation-level discount.',
      baseTable: 'sale_quotation_items',
      source:
          'sale_quotation_items sqi JOIN sale_quotations sq ON sq.id = sqi.sale_quotation_id',
      scope: 'sq.store_id = ?',
      softDelete: "sq.deleted_at = ''",
      dateExpression: 'sq.document_date',
      searchExpressions: <String>[
        'sqi.product_name',
        'sq.customer_name',
        'sq.quotation_no'
      ],
      dimensions: <String, _DimensionSpec>{
        'product_name': _DimensionSpec('sqi.product_name', 'Product', 'text'),
        'customer_name': _DimensionSpec('sq.customer_name', 'Customer', 'text'),
        'quotation_no':
            _DimensionSpec('sq.quotation_no', 'Quotation number', 'text'),
        'document_date':
            _DimensionSpec('sq.document_date', 'Quotation date', 'date'),
        'status': _DimensionSpec('sq.status', 'Quotation status', 'text'),
        'invoice_currency':
            _DimensionSpec('sq.invoice_currency', 'Currency', 'currency'),
        'unit_name': _DimensionSpec('sqi.unit_name', 'Sales unit', 'unit'),
        'branch_id': _DimensionSpec('sq.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'line_count': _MeasureSpec('COUNT(*)', 'Quotation line count', 'lines'),
        'quantity': _MeasureSpec(
            'SUM(sqi.quantity)', 'Quoted quantity', 'quantity',
            contextExpression: 'sqi.product_name', contextLabel: 'product'),
        'line_amount': _MeasureSpec('SUM(sqi.quantity * sqi.unit_price)',
            'Quoted line amount before quotation discount', 'money',
            currencyExpression: 'sq.invoice_currency',
            contextExpression: 'sq.status',
            contextLabel: 'quotation status'),
      },
      relationships: <String>[
        'sale_quotation_items.sale_quotation_id = sale_quotations.id',
        'sale_quotation_items.product_id = products.id',
      ],
    ),
    'delivery_notes': _TableSpec(
      domain: _Domain.sales,
      title: 'Delivery notes',
      description: 'Delivery note headers and delivery status.',
      baseTable: 'delivery_notes',
      source: 'delivery_notes dn',
      scope: 'dn.store_id = ?',
      softDelete: "dn.deleted_at = ''",
      dateExpression: 'dn.document_date',
      searchExpressions: <String>[
        'dn.delivery_no',
        'dn.invoice_no',
        'dn.customer_name',
        'dn.status'
      ],
      dimensions: <String, _DimensionSpec>{
        'delivery_no':
            _DimensionSpec('dn.delivery_no', 'Delivery number', 'text'),
        'invoice_no': _DimensionSpec('dn.invoice_no', 'Invoice number', 'text'),
        'customer_name': _DimensionSpec('dn.customer_name', 'Customer', 'text'),
        'document_date':
            _DimensionSpec('dn.document_date', 'Delivery date', 'date'),
        'status': _DimensionSpec('dn.status', 'Status', 'text'),
        'branch_id': _DimensionSpec('dn.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'delivery_count':
            _MeasureSpec('COUNT(*)', 'Delivery note count', 'documents'),
      },
      relationships: <String>[
        'delivery_notes.id = delivery_note_items.delivery_note_id',
        'delivery_notes.sale_id = sales.id',
      ],
    ),
    'delivery_note_items': _TableSpec(
      domain: _Domain.sales,
      title: 'Delivery note lines',
      description:
          'Products and quantities recorded on delivery notes, scoped through the parent document.',
      baseTable: 'delivery_note_items',
      source:
          'delivery_note_items dni JOIN delivery_notes dn ON dn.id = dni.delivery_note_id',
      scope: 'dn.store_id = ?',
      softDelete: "dn.deleted_at = ''",
      dateExpression: 'dn.document_date',
      searchExpressions: <String>[
        'dni.product_name',
        'dn.customer_name',
        'dn.delivery_no'
      ],
      dimensions: <String, _DimensionSpec>{
        'product_name': _DimensionSpec('dni.product_name', 'Product', 'text'),
        'customer_name': _DimensionSpec('dn.customer_name', 'Customer', 'text'),
        'delivery_no':
            _DimensionSpec('dn.delivery_no', 'Delivery number', 'text'),
        'document_date':
            _DimensionSpec('dn.document_date', 'Delivery date', 'date'),
        'status': _DimensionSpec('dn.status', 'Delivery status', 'text'),
        'unit_name': _DimensionSpec('dni.unit_name', 'Delivery unit', 'unit'),
        'branch_id': _DimensionSpec('dn.branch_id', 'Branch', 'text'),
      },
      measures: <String, _MeasureSpec>{
        'line_count': _MeasureSpec('COUNT(*)', 'Delivery line count', 'lines'),
        'quantity': _MeasureSpec(
            'SUM(dni.quantity)', 'Delivered quantity', 'quantity',
            contextExpression: 'dni.product_name',
            contextLabel: 'product',
            additionalContextExpression: 'dn.status',
            additionalContextLabel: 'delivery status'),
      },
      relationships: <String>[
        'delivery_note_items.delivery_note_id = delivery_notes.id',
        'delivery_note_items.product_id = products.id',
      ],
    ),
  };

  static List<_TableSpec> _availableSpecs(AppStore store) => _specs.values
      .where((spec) => _hasDomainPermission(store, spec.domain))
      .toList(growable: false);

  static List<AssistantJsonMap> definitionsFor(AppStore store) {
    final specs = _availableSpecs(store);
    if (specs.isEmpty) return const <AssistantJsonMap>[];
    final tableNames = specs.map((spec) => spec.baseTable).toList();
    return <AssistantJsonMap>[
      <String, Object?>{
        'name': 'business_schema_catalog',
        'description':
            'List business tables available to the signed-in user and what each table is for. Pass one table name to see its full columns, supported dimensions and measures, search fields, date field, and relationships. This returns schema metadata only, no business records.',
        'parameters': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'table': <String, Object?>{
              'type': 'string',
              'enum': tableNames,
              'description': 'Optional table to inspect in detail.',
            },
          },
          'additionalProperties': false,
        },
      },
      <String, Object?>{
        'name': 'business_table_analysis',
        'description':
            'Run a bounded read-only aggregate query over one permitted business table. Use business_schema_catalog first when unsure about columns or relationships. It returns grouped aggregates only, never raw rows or arbitrary SQL. Dates are inclusive. Different currencies are grouped separately; quantities are grouped by product.',
        'parameters': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'table': <String, Object?>{
              'type': 'string',
              'enum': tableNames,
              'description': 'A business table allowed for the active user.',
            },
            'group_by': <String, Object?>{
              'type': 'string',
              'description':
                  'Optional dimension column from the selected table. Use "none" for an overall aggregate.',
            },
            'measure': <String, Object?>{
              'type': 'string',
              'description':
                  'Aggregate to calculate; choose one listed for the table in the schema catalog. Defaults to the table row count.',
            },
            'from': <String, Object?>{
              'type': 'string',
              'format': 'date',
              'description':
                  'Inclusive start date when the table supports dates.',
            },
            'to': <String, Object?>{
              'type': 'string',
              'format': 'date',
              'description':
                  'Inclusive end date when the table supports dates.',
            },
            'search': <String, Object?>{
              'type': 'string',
              'maxLength': _maximumSearchCharacters,
              'description':
                  'Optional partial match in the table search fields listed in the catalog.',
            },
            'filter_by': <String, Object?>{
              'type': 'string',
              'description':
                  'Optional exact filter dimension from the catalog.',
            },
            'filter_value': <String, Object?>{
              'type': 'string',
              'maxLength': _maximumSearchCharacters,
              'description': 'Required with filter_by.',
            },
            'filter_match': <String, Object?>{
              'type': 'string',
              'enum': <String>['equals', 'contains'],
              'description': 'Filter matching mode; defaults to equals.',
            },
            'limit': <String, Object?>{
              'type': 'integer',
              'description': 'Maximum groups from 1 to 50; defaults to 30.',
            },
          },
          'required': <String>['table'],
          'additionalProperties': false,
        },
      },
    ];
  }

  static bool canUse(AppStore store) => _availableSpecs(store).isNotEmpty;

  static Future<AssistantJsonMap> executeCatalog({
    required AppStore store,
    required Map<String, Object?> arguments,
  }) async {
    _requireOnlyArguments(arguments, const <String>{'table'});
    final db = _requireDatabase();
    final specs = _availableSpecs(store);
    if (specs.isEmpty) _permissionDenied();
    final requestedTable = _stringArgument(arguments, 'table');
    final selectedSpecs = requestedTable.isEmpty
        ? specs
        : specs.where((spec) => spec.baseTable == requestedTable).toList();
    if (selectedSpecs.isEmpty) _permissionDenied();
    final tables = <AssistantJsonMap>[];
    for (final spec in selectedSpecs) {
      if (requestedTable.isEmpty) {
        tables.add(<String, Object?>{
          'table': spec.baseTable,
          'title': spec.title,
          'description': spec.description,
        });
        continue;
      }
      final columns = await db
          .customSelect(
            'PRAGMA table_info("${spec.baseTable}")',
          )
          .get();
      if (columns.isEmpty) continue;
      final documentedColumns = <String, _ColumnDoc>{
        for (final column in spec.documentedColumns) column.name: column,
      };
      tables.add(<String, Object?>{
        'table': spec.baseTable,
        'title': spec.title,
        'description': spec.description,
        if (requestedTable.isNotEmpty)
          'columns': columns.map((row) {
            final name = row.data['name']?.toString() ?? '';
            final documented = documentedColumns[name];
            return <String, Object?>{
              'name': name,
              'type': row.data['type']?.toString() ?? '',
              'description': documented?.description ??
                  'Stored source field; use the documented analysis dimensions and measures.',
              'usableAsDimension': spec.dimensions.containsKey(name),
            };
          }).toList(growable: false),
        'dimensions': spec.dimensions.entries
            .map((entry) => <String, Object?>{
                  'name': entry.key,
                  'description': entry.value.description,
                  'type': entry.value.type,
                })
            .toList(growable: false),
        'measures': spec.measures.entries
            .map((entry) => <String, Object?>{
                  'name': entry.key,
                  'description': entry.value.description,
                  'unit': entry.value.unit,
                  if (entry.value.currencyLabel != null)
                    'currencyBasis': entry.value.currencyLabel,
                  if (entry.value.currencyExpression != null)
                    'currencyColumn':
                        entry.value.currencyExpression!.split('.').last,
                  if (entry.value.contextLabel != null)
                    'groupedByContext': entry.value.contextLabel,
                  if (entry.value.additionalContextLabel != null)
                    'additionalGroupingContext':
                        entry.value.additionalContextLabel,
                  if (entry.value.tertiaryContextLabel != null)
                    'tertiaryGroupingContext': entry.value.tertiaryContextLabel,
                })
            .toList(growable: false),
        'searchColumns': spec.searchExpressions
            .map((expression) => expression.split('.').last)
            .toList(growable: false),
        'dateColumn': spec.dateExpression?.split('.').last,
        'relationships': spec.relationships,
      });
    }
    return <String, Object?>{
      'scope':
          'Active store only; table access also follows the signed-in user permissions.',
      'rowDataIncluded': false,
      'tables': tables,
      'tableCount': tables.length,
      'detailForTable': requestedTable.isEmpty ? null : requestedTable,
      'omittedSchema':
          'Authentication credentials, user permission records, sync payloads, audit logs, app logs, migrations, assistant history, internal configuration, and helper tables without a safe store-scoped analysis definition are not offered for data analysis.',
    };
  }

  static Future<AssistantJsonMap> executeAnalysis({
    required AppStore store,
    required Map<String, Object?> arguments,
  }) async {
    _requireOnlyArguments(arguments);
    final tableName = _stringArgument(arguments, 'table', required: true);
    final spec = _specs[tableName];
    if (spec == null || !_hasDomainPermission(store, spec.domain)) {
      _permissionDenied();
    }
    final groupBy = _stringArgument(arguments, 'group_by', fallback: 'none');
    final measureName = _stringArgument(
      arguments,
      'measure',
      fallback: spec.measures.keys.first,
    );
    final measure = spec.measures[measureName];
    if (measure == null) {
      throw const AssistantDatabaseExplorerException(
        'invalid_measure',
        'Choose a measure listed for this table in the schema catalog.',
      );
    }
    final dimension = groupBy == 'none' ? null : spec.dimensions[groupBy];
    if (groupBy != 'none' && dimension == null) {
      throw const AssistantDatabaseExplorerException(
        'invalid_dimension',
        'Choose a dimension listed for this table in the schema catalog.',
      );
    }
    final from = _parseDate(arguments, 'from');
    final to = _parseDate(arguments, 'to');
    if ((from == null) != (to == null)) {
      throw const AssistantDatabaseExplorerException(
        'invalid_date_range',
        'Provide both start and end dates, or omit both.',
      );
    }
    if (from != null && from.isAfter(to!)) {
      throw const AssistantDatabaseExplorerException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    if (from != null && spec.dateExpression == null) {
      throw const AssistantDatabaseExplorerException(
        'unsupported_date_filter',
        'This table does not have a supported date column.',
      );
    }
    final search = _stringArgument(
      arguments,
      'search',
      maxLength: _maximumSearchCharacters,
    );
    final filterBy = _stringArgument(arguments, 'filter_by');
    final filterValue = _stringArgument(
      arguments,
      'filter_value',
      maxLength: _maximumSearchCharacters,
    );
    final filterMatch = _stringArgument(
      arguments,
      'filter_match',
      fallback: 'equals',
    );
    if (filterMatch != 'equals' && filterMatch != 'contains') {
      throw const AssistantDatabaseExplorerException(
        'invalid_filter',
        'Choose equals or contains for filter_match.',
      );
    }
    if ((filterBy.isEmpty) != (filterValue.isEmpty)) {
      throw const AssistantDatabaseExplorerException(
        'invalid_filter',
        'Provide both filter_by and filter_value, or omit both.',
      );
    }
    final filterDimension = filterBy.isEmpty ? null : spec.dimensions[filterBy];
    if (filterBy.isNotEmpty && filterDimension == null) {
      throw const AssistantDatabaseExplorerException(
        'invalid_filter',
        'Choose a filter dimension listed in the schema catalog.',
      );
    }
    final limit = _integerArgument(arguments, 'limit', fallback: 30);
    if (limit < 1 || limit > _maximumGroups) {
      throw const AssistantDatabaseExplorerException(
        'invalid_limit',
        'Choose a result limit from 1 to 50.',
      );
    }
    final storeId = store.appIdentity.storeId.trim();
    if (storeId.isEmpty) {
      throw const AssistantDatabaseExplorerException(
        'active_store_required',
        'Sign in to Ventio and select a store before analyzing business data.',
      );
    }

    final where = <String>[spec.scope];
    final variables = <Variable<Object>>[Variable<String>(storeId)];
    if (spec.softDelete != null) where.add(spec.softDelete!);
    if (spec.defaultFilter != null) where.add(spec.defaultFilter!);
    if (from != null && spec.dateExpression != null) {
      where.add("date(${spec.dateExpression}) >= date(?)");
      variables.add(Variable<String>(_dateLabel(from)));
      where.add("date(${spec.dateExpression}) <= date(?)");
      variables.add(Variable<String>(_dateLabel(to!)));
    }
    if (search.isNotEmpty && spec.searchExpressions.isNotEmpty) {
      where.add(
          '(${spec.searchExpressions.map((expr) => 'lower($expr) LIKE ?').join(' OR ')})');
      final pattern =
          '%${search.toLowerCase().replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      for (var i = 0; i < spec.searchExpressions.length; i++) {
        variables.add(Variable<String>(pattern));
      }
    } else if (search.isNotEmpty) {
      throw const AssistantDatabaseExplorerException(
        'unsupported_search',
        'This table does not expose searchable text fields.',
      );
    }
    if (filterDimension != null) {
      final expression = filterDimension.expression;
      if (filterMatch == 'contains') {
        where.add('lower(CAST($expression AS TEXT)) LIKE ?');
        variables.add(Variable<String>('%${filterValue.toLowerCase()}%'));
      } else {
        where.add('lower(CAST($expression AS TEXT)) = lower(?)');
        variables.add(Variable<String>(filterValue));
      }
    }

    final groupExpressions = <String>[];
    final selectExpressions = <String>[];
    if (dimension != null) {
      groupExpressions.add(dimension.expression);
      selectExpressions.add('${dimension.expression} AS group_value');
    } else {
      selectExpressions.add("'All records' AS group_value");
    }
    if (measure.currencyExpression != null) {
      groupExpressions.add(measure.currencyExpression!);
      selectExpressions.add('${measure.currencyExpression} AS currency');
    }
    final contexts = <String, String>{
      if (measure.contextExpression != null)
        measure.contextLabel ?? 'context': measure.contextExpression!,
      if (measure.additionalContextExpression != null)
        measure.additionalContextLabel ?? 'additional_context':
            measure.additionalContextExpression!,
      if (measure.tertiaryContextExpression != null)
        measure.tertiaryContextLabel ?? 'tertiary_context':
            measure.tertiaryContextExpression!,
    };
    final contextEntries = contexts.entries.toList(growable: false);
    for (var index = 0; index < contextEntries.length; index++) {
      final entry = contextEntries[index];
      final expression = entry.value;
      if (!groupExpressions.contains(expression)) {
        groupExpressions.add(expression);
      }
      selectExpressions.add('${expression} AS context_$index');
    }
    selectExpressions.add('${measure.expression} AS measure_value');
    final groupBySql = groupExpressions.isEmpty
        ? ''
        : 'GROUP BY ${groupExpressions.join(', ')}';
    final rows = await _requireDatabase().customSelect('''
      SELECT ${selectExpressions.join(', ')}
      FROM ${spec.source}
      WHERE ${where.join(' AND ')}
      $groupBySql
      ORDER BY measure_value DESC
      LIMIT ?
    ''', variables: <Variable<Object>>[
      ...variables,
      Variable<int>(limit + 1),
    ]).get();
    final visibleRows = rows.take(limit).map((row) {
      final data = <String, Object?>{
        'group': row.data['group_value'],
        'value': row.data['measure_value'],
      };
      if (row.data.containsKey('currency')) {
        data['currency'] = row.data['currency'];
      } else if (measure.currencyLabel != null) {
        data['currencyBasis'] = measure.currencyLabel;
      }
      for (var index = 0; index < contextEntries.length; index++) {
        data[contextEntries[index].key] = row.data['context_$index'];
      }
      return data;
    }).toList(growable: false);
    return <String, Object?>{
      'table': spec.baseTable,
      'tableTitle': spec.title,
      'tableMeaning': spec.description,
      'groupedBy': groupBy,
      'measure': measureName,
      'measureMeaning': measure.description,
      'measureUnit': measure.unit,
      'period': from == null
          ? 'all available history'
          : <String, String>{'from': _dateLabel(from), 'to': _dateLabel(to!)},
      'search': search.isEmpty ? null : search,
      'filter': filterDimension == null
          ? null
          : <String, String>{
              'dimension': filterBy,
              'match': filterMatch,
              'value': filterValue,
            },
      'groups': visibleRows,
      'groupLimit': limit,
      'groupsTruncated': rows.length > limit,
      'scope': 'active store only',
      'aggregationOnly': true,
      'notes': <String>[
        if (measure.currencyExpression != null)
          'Money is split by currency; do not combine different currency rows.',
        if (measure.currencyExpression == null && measure.currencyLabel != null)
          measure.currencyLabel!,
        if (contexts.isNotEmpty)
          'The measure is also split by ${contexts.keys.join(' and ')} to preserve its comparison context.',
        if (spec.defaultFilter != null)
          spec.defaultFilterDescription ??
              'A table-specific status or reversal filter is applied.',
      ],
    };
  }

  static bool _hasDomainPermission(AppStore store, _Domain domain) =>
      switch (domain) {
        _Domain.sales => store.canViewSales,
        _Domain.purchases => store.canViewPurchases,
        _Domain.customers => store.canViewCustomers || store.canViewSales,
        _Domain.suppliers => store.canViewSuppliers || store.canViewPurchases,
        _Domain.inventory => store.canViewInventory || store.canViewAccounting,
        _Domain.expenses => store.canViewExpenses,
        _Domain.accounting => store.canViewAccounting,
        _Domain.cash => store.canViewCashBox,
        _Domain.manufacturing =>
          store.canViewInventory || store.canViewAccounting,
      };

  static VentioDriftDatabase _requireDatabase() {
    final db = SqliteMigrationManager.database;
    if (db == null) {
      throw const AssistantDatabaseExplorerException(
        'business_database_unavailable',
        'Ventio business data is not available for a local read right now.',
      );
    }
    return db;
  }

  static void _requireOnlyArguments(
    Map<String, Object?> arguments, [
    Set<String> allowed = const <String>{
      'table',
      'group_by',
      'measure',
      'from',
      'to',
      'search',
      'filter_by',
      'filter_value',
      'filter_match',
      'limit',
    },
  ]) {
    if (arguments.keys.any((key) => !allowed.contains(key))) {
      throw const AssistantDatabaseExplorerException(
        'invalid_arguments',
        'The table analysis contains unsupported arguments.',
      );
    }
  }

  static String _stringArgument(
    Map<String, Object?> arguments,
    String key, {
    bool required = false,
    String fallback = '',
    int? maxLength,
  }) {
    final value = arguments[key];
    if (value == null) {
      if (required) {
        throw AssistantDatabaseExplorerException(
          'invalid_arguments',
          'The $key argument is required.',
        );
      }
      return fallback;
    }
    if (value is! String || (maxLength != null && value.length > maxLength)) {
      throw AssistantDatabaseExplorerException(
        'invalid_arguments',
        'The $key argument must be text${maxLength == null ? '' : ' up to $maxLength characters'}.',
      );
    }
    return value.trim();
  }

  static int _integerArgument(
    Map<String, Object?> arguments,
    String key, {
    required int fallback,
  }) {
    final value = arguments[key];
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw AssistantDatabaseExplorerException(
      'invalid_arguments',
      'The $key argument must be a whole number.',
    );
  }

  static DateTime? _parseDate(Map<String, Object?> arguments, String key) {
    final raw = arguments[key];
    if (raw == null) return null;
    if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      throw AssistantDatabaseExplorerException(
        'invalid_date',
        'Use YYYY-MM-DD for $key.',
      );
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || _dateLabel(parsed) != raw) {
      throw AssistantDatabaseExplorerException(
        'invalid_date',
        'The $key date is not a valid calendar date.',
      );
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _dateLabel(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static Never _permissionDenied() =>
      throw const AssistantDatabaseExplorerException(
        'permission_denied',
        'Your Ventio account does not have permission to analyze this business data.',
      );
}

class AssistantDatabaseExplorerException implements Exception {
  const AssistantDatabaseExplorerException(this.code, this.message);

  final String code;
  final String message;
}

enum _Domain {
  sales,
  purchases,
  customers,
  suppliers,
  inventory,
  expenses,
  accounting,
  cash,
  manufacturing,
}

class _DimensionSpec {
  const _DimensionSpec(this.expression, this.description, this.type);

  final String expression;
  final String description;
  final String type;
}

class _MeasureSpec {
  const _MeasureSpec(
    this.expression,
    this.description,
    this.unit, {
    this.currencyExpression,
    this.currencyLabel,
    this.contextExpression,
    this.contextLabel,
    this.additionalContextExpression,
    this.additionalContextLabel,
    this.tertiaryContextExpression,
    this.tertiaryContextLabel,
  });

  final String expression;
  final String description;
  final String unit;
  final String? currencyExpression;
  final String? currencyLabel;
  final String? contextExpression;
  final String? contextLabel;
  final String? additionalContextExpression;
  final String? additionalContextLabel;
  final String? tertiaryContextExpression;
  final String? tertiaryContextLabel;
}

class _ColumnDoc {
  const _ColumnDoc(this.name, this.type, this.description);

  final String name;
  final String type;
  final String description;
}

class _TableSpec {
  const _TableSpec({
    required this.domain,
    required this.title,
    required this.description,
    required this.baseTable,
    required this.source,
    required this.scope,
    required this.dimensions,
    required this.measures,
    this.softDelete,
    this.dateExpression,
    this.searchExpressions = const <String>[],
    this.defaultFilter,
    this.defaultFilterDescription,
    this.relationships = const <String>[],
  });

  final _Domain domain;
  final String title;
  final String description;
  final String baseTable;
  final String source;
  final String scope;
  final String? softDelete;
  final String? dateExpression;
  final List<String> searchExpressions;
  final String? defaultFilter;
  final String? defaultFilterDescription;
  final Map<String, _DimensionSpec> dimensions;
  final Map<String, _MeasureSpec> measures;
  final List<String> relationships;

  List<_ColumnDoc> get documentedColumns => <_ColumnDoc>[
        const _ColumnDoc('id', 'text', 'Unique record identifier.'),
        const _ColumnDoc('store_id', 'text', 'Owning Ventio store.'),
        const _ColumnDoc('branch_id', 'text', 'Associated branch identifier.'),
        const _ColumnDoc(
            'deleted_at', 'text', 'Soft-delete marker; blank means active.'),
        ...dimensions.entries.map((entry) {
          final name = entry.key;
          final type = entry.value.type;
          return _ColumnDoc(name, type, entry.value.description);
        }),
      ]
          .fold(<String, _ColumnDoc>{}, (map, column) {
            map[column.name] = column;
            return map;
          })
          .values
          .toList(growable: false);
}
