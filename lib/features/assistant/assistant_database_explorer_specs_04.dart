part of 'assistant_database_explorer_service.dart';

const Map<String, _TableSpec> _assistantDatabaseExplorerSpecsPart04 =
    <String, _TableSpec>{
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
