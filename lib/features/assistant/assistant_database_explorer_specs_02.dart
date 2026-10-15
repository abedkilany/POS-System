part of 'assistant_database_explorer_service.dart';

const Map<String, _TableSpec> _assistantDatabaseExplorerSpecsPart02 =
    <String, _TableSpec>{
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
      'product_id': _DimensionSpec('pc.product_id', 'Product ID', 'identifier'),
      'currency_code':
          _DimensionSpec('pc.currency_code', 'Currency', 'currency'),
      'branch_id': _DimensionSpec('pc.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'product_count': _MeasureSpec('COUNT(*)', 'Product cost rows', 'records'),
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
      'is_closed': _DimensionSpec('icl.is_closed', 'Closed status', 'boolean'),
      'branch_id': _DimensionSpec('icl.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'layer_count': _MeasureSpec('COUNT(*)', 'Cost layer count', 'records'),
      'remaining_quantity': _MeasureSpec(
          'SUM(icl.quantity_remaining)', 'Remaining layer quantity', 'quantity',
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
      'price_rows': _MeasureSpec('COUNT(*)', 'Supplier price rows', 'records'),
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
      'expense_date': _DimensionSpec('e.expense_date', 'Expense date', 'date'),
      'expense_status': _DimensionSpec('e.expense_status', 'Status', 'text'),
      'original_currency': _DimensionSpec(
          'e.original_currency', 'Original currency', 'currency'),
      'branch_id': _DimensionSpec('e.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'expense_count': _MeasureSpec('COUNT(*)', 'Expense count', 'records'),
      'amount': _MeasureSpec(
          'SUM(e.amount)', 'Expense amount (USD reference as stored)', 'money',
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
      'product_id': _DimensionSpec('wi.product_id', 'Product ID', 'identifier'),
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
      'warehouse_count': _MeasureSpec('COUNT(*)', 'Warehouse count', 'records'),
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
      'balance_rows': _MeasureSpec('COUNT(*)', 'Batch balance rows', 'records'),
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
      'settled_at': _DimensionSpec('ids.settled_at', 'Settlement date', 'date'),
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
      'product_id': _DimensionSpec('ir.product_id', 'Product ID', 'identifier'),
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
      'from_warehouse_name':
          _DimensionSpec('wto.from_warehouse_name', 'Source warehouse', 'text'),
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
      'product_code': _DimensionSpec('il.product_code', 'Product code', 'text'),
      'warehouse_name':
          _DimensionSpec('ic.warehouse_name', 'Warehouse', 'text'),
      'status': _DimensionSpec('ic.status', 'Count status', 'text'),
      'branch_id': _DimensionSpec('ic.branch_id', 'Branch', 'text'),
    },
    measures: <String, _MeasureSpec>{
      'line_count': _MeasureSpec('COUNT(*)', 'Count line count', 'lines'),
      'quantity_difference': _MeasureSpec(
          'SUM(il.difference_qty)', 'Recorded quantity difference', 'quantity',
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
      'document_date': _DimensionSpec('mo.document_date', 'Order date', 'date'),
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
      'is_active': _DimensionSpec('bom.is_active', 'Active status', 'boolean'),
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
};
