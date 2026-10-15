part of 'ventio_drift_database.dart';

extension VentioDriftDatabaseMethods2 on VentioDriftDatabase {
  /// Permanently removes the retired `products.stock` persistence column.
  ///
  /// Call this only after legacy inventory has been migrated into
  /// `warehouse_inventory`. Runtime inventory reads/writes never depend on this
  /// column anymore; this migration only removes obsolete storage.
  Future<void> dropLegacyProductStockColumn() async {
    if (!await _tableHasColumn('products', 'stock')) return;
    await customStatement(
      'DROP INDEX IF EXISTS idx_products_deleted_track_stock_stock_name;',
    );
    await customStatement('ALTER TABLE products DROP COLUMN stock;');
  }

  Future<void> _ensureProductColumns() async {
    await _ensureColumn('products', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'code', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'name_en', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'name_ar', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'price', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('products', 'cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('products', 'original_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'cost_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn('products', 'usd_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'cost_exchange_rate_at_entry', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'original_price', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'original_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn('products', 'usd_price', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'exchange_rate_at_entry', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'category', "TEXT NOT NULL DEFAULT 'General'");
    await _ensureColumn('products', 'barcode', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'brand', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'supplier', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'description', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('products', 'unit', "TEXT NOT NULL DEFAULT 'pcs'");
    await _ensureColumn(
        'products', 'quantity_type', "TEXT NOT NULL DEFAULT 'countable'");
    await _ensureColumn(
        'products', 'low_stock_threshold', 'INTEGER NOT NULL DEFAULT 5');
    await _ensureColumn(
        'products', 'track_stock', 'INTEGER NOT NULL DEFAULT 1');
    await _ensureColumn('products', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
    await _ensureColumn('products', 'image_path', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'products', 'tax_profile_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'products', 'expiry_tracking_enabled', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(
        'products', 'expiry_entry_required', 'INTEGER NOT NULL DEFAULT 1');
    // Unified Batch has one unambiguous expiry contract: enabling expiry
    // tracking means every received batch must have an expiration date.
    // Repair legacy rows created while expiry_entry_required could be false.
    await customStatement('''
      UPDATE products
      SET expiry_entry_required = 1
      WHERE expiry_tracking_enabled = 1 AND expiry_entry_required <> 1;
    ''');
    await _ensureColumn(
        'products', 'expiry_alert_days', 'INTEGER NOT NULL DEFAULT 30');
    await _ensureColumn(
        'products', 'default_shelf_life_days', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn('products', 'minimum_receipt_shelf_life_days',
        'INTEGER NOT NULL DEFAULT 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);');
  }

  Future<void> _ensureProductUnitTables() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS product_sale_units (
        id TEXT PRIMARY KEY NOT NULL,
        product_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        unit_id TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        conversion_to_base REAL NOT NULL DEFAULT 1,
        price REAL NOT NULL DEFAULT 0,
        original_price REAL NOT NULL DEFAULT 0,
        original_currency TEXT NOT NULL DEFAULT 'USD',
        barcode TEXT NOT NULL DEFAULT '',
        is_default INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        CHECK (is_default IN (0, 1))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_sale_units_product_line ON product_sale_units(product_id, line_no);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS product_purchase_units (
        id TEXT PRIMARY KEY NOT NULL,
        product_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        unit_id TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        conversion_to_base REAL NOT NULL DEFAULT 1,
        price REAL NOT NULL DEFAULT 0,
        original_price REAL NOT NULL DEFAULT 0,
        original_currency TEXT NOT NULL DEFAULT 'USD',
        barcode TEXT NOT NULL DEFAULT '',
        is_default INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        CHECK (is_default IN (0, 1))
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_purchase_units_product_line ON product_purchase_units(product_id, line_no);');
  }

  Future<void> _ensureSaleColumns() async {
    await _ensureColumn('sales', 'invoice_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('sales', 'customer_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('sales', 'customer_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('sales', 'document_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('sales', 'status', "TEXT NOT NULL DEFAULT 'Paid'");
    await _ensureColumn('sales', 'discount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'original_discount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'discount_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'sales', 'discount_exchange_rate_at_entry', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'payment_method', "TEXT NOT NULL DEFAULT 'Cash'");
    await _ensureColumn(
        'sales', 'payment_status', "TEXT NOT NULL DEFAULT 'paid'");
    await _ensureColumn(
        'sales', 'invoice_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'sales', 'payment_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'sales', 'exchange_rate_at_payment', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'base_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'sales', 'exchange_rate_at_invoice', 'REAL NOT NULL DEFAULT 1');
    await _ensureColumn(
        'sales', 'transaction_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'base_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'paid_base_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'exchange_difference_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'paid_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'cash_received_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sales', 'paid_amount_in_payment_currency', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'cash_received_amount_in_payment_currency',
        'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sales', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sales', 'warehouse_id', "TEXT NOT NULL DEFAULT 'main'");
    await _ensureColumn(
        'sales', 'warehouse_name', "TEXT NOT NULL DEFAULT 'Main warehouse'");
    await _ensureColumn(
        'sales', 'posted_snapshot_json', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(document_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id, document_date);');
  }

  Future<void> _ensureSaleItemTables() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS sale_items (
        id TEXT PRIMARY KEY NOT NULL,
        sale_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        unit_price REAL NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 0,
        unit_name TEXT NOT NULL DEFAULT '',
        base_quantity REAL NOT NULL DEFAULT 0,
        conversion_to_base REAL NOT NULL DEFAULT 1,
        unit_cost REAL NOT NULL DEFAULT 0,
        costing_method_at_sale TEXT NOT NULL DEFAULT 'weighted_average',
        cost_currency TEXT NOT NULL DEFAULT 'USD',
        cost_exchange_rate REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_line ON sale_items(sale_id, line_no);');

    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS sale_item_cost_layer_consumptions (
        id TEXT PRIMARY KEY NOT NULL,
        sale_item_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        layer_id TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        currency_code TEXT NOT NULL DEFAULT 'USD',
        FOREIGN KEY (sale_item_id) REFERENCES sale_items(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_item_consumptions_item_line ON sale_item_cost_layer_consumptions(sale_item_id, line_no);');
  }

  Future<void> _ensureSaleQuotationColumns() async {
    await _ensureColumn(
        'sale_quotations', 'quotation_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'customer_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'customer_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'document_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'valid_until', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'status', "TEXT NOT NULL DEFAULT 'Draft'");
    await _ensureColumn(
        'sale_quotations', 'discount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'sale_quotations', 'invoice_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn('sale_quotations', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'sale_quotations', 'converted_sale_id', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureSaleQuotationItemTables() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS sale_quotation_items (
        id TEXT PRIMARY KEY NOT NULL,
        sale_quotation_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        unit_price REAL NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 0,
        unit_name TEXT NOT NULL DEFAULT '',
        base_quantity REAL NOT NULL DEFAULT 0,
        conversion_to_base REAL NOT NULL DEFAULT 1,
        unit_cost REAL NOT NULL DEFAULT 0,
        costing_method_at_sale TEXT NOT NULL DEFAULT 'weighted_average',
        cost_currency TEXT NOT NULL DEFAULT 'USD',
        cost_exchange_rate REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (sale_quotation_id) REFERENCES sale_quotations(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_quotation_items_quote_line ON sale_quotation_items(sale_quotation_id, line_no);');
  }

  Future<void> _ensureDeliveryNoteColumns() async {
    await _ensureColumn(
        'delivery_notes', 'delivery_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'sale_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'invoice_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'customer_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'customer_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'document_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'status', "TEXT NOT NULL DEFAULT 'Draft'");
    await _ensureColumn('delivery_notes', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'delivery_notes', 'delivered_at', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureDeliveryNoteItemTables() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS delivery_note_items (
        id TEXT PRIMARY KEY NOT NULL,
        delivery_note_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        unit_price REAL NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 0,
        unit_name TEXT NOT NULL DEFAULT '',
        base_quantity REAL NOT NULL DEFAULT 0,
        conversion_to_base REAL NOT NULL DEFAULT 1,
        unit_cost REAL NOT NULL DEFAULT 0,
        costing_method_at_sale TEXT NOT NULL DEFAULT 'weighted_average',
        cost_currency TEXT NOT NULL DEFAULT 'USD',
        cost_exchange_rate REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (delivery_note_id) REFERENCES delivery_notes(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_delivery_note_items_note_line ON delivery_note_items(delivery_note_id, line_no);');
  }

  Future<void> _ensurePurchaseColumns() async {
    await _ensureColumn('purchases', 'purchase_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('purchases', 'supplier_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'supplier_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'document_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('purchases', 'status', "TEXT NOT NULL DEFAULT 'Draft'");
    await _ensureColumn('purchases', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'payment_status', "TEXT NOT NULL DEFAULT 'paid'");
    await _ensureColumn(
        'purchases', 'payment_method', "TEXT NOT NULL DEFAULT 'Cash'");
    await _ensureColumn('purchases', 'paid_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'purchases', 'warehouse_id', "TEXT NOT NULL DEFAULT 'main'");
    await _ensureColumn('purchases', 'warehouse_name',
        "TEXT NOT NULL DEFAULT 'Main warehouse'");
    await _ensureColumn(
        'purchases', 'document_type', "TEXT NOT NULL DEFAULT 'purchase'");
    await _ensureColumn(
        'purchases', 'source_purchase_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'source_purchase_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'cancel_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'cancelled_by_device_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'reversal_applied', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(
        'purchases', 'cancelled_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchases', 'posted_snapshot_json', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_date ON purchases(document_date);');
  }

  Future<void> _ensurePurchaseItemTable() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS purchase_items (
        id TEXT PRIMARY KEY NOT NULL,
        purchase_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        purchase_unit_id TEXT NOT NULL DEFAULT 'base',
        purchase_unit_name TEXT NOT NULL DEFAULT '',
        conversion_to_base REAL NOT NULL DEFAULT 1,
        original_unit_cost REAL NOT NULL DEFAULT 0,
        unit_cost_currency TEXT NOT NULL DEFAULT 'USD',
        exchange_rate_at_entry REAL NOT NULL DEFAULT 0,
        requested_supplier_batch_number TEXT NOT NULL DEFAULT '',
        requested_manufacturing_date TEXT NOT NULL DEFAULT '',
        requested_expiration_date TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE
      );
    ''');
    await _ensureColumn('purchase_items', 'requested_supplier_batch_number',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'purchase_items', 'source_line_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('purchase_items', 'requested_manufacturing_date',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('purchase_items', 'requested_expiration_date',
        "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase_line ON purchase_items(purchase_id, line_no);');
  }

  Future<void> _ensureInventoryCountColumns() async {
    await _ensureColumn(
        'inventory_counts', 'count_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'created_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'warehouse_id', "TEXT NOT NULL DEFAULT 'main'");
    await _ensureColumn('inventory_counts', 'warehouse_name',
        "TEXT NOT NULL DEFAULT 'Main warehouse'");
    await _ensureColumn(
        'inventory_counts', 'status', "TEXT NOT NULL DEFAULT 'open'");
    await _ensureColumn(
        'inventory_counts', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'approved_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'approved_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'journal_entry_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('inventory_counts', 'reversal_journal_entry_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'reversed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'reversed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'inventory_counts', 'reversal_reason', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureInventoryCountLineTable() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS inventory_count_lines (
        id TEXT PRIMARY KEY NOT NULL,
        inventory_count_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        product_code TEXT NOT NULL DEFAULT '',
        snapshot_stock REAL NOT NULL DEFAULT 0,
        counted_qty REAL,
        counted_at TEXT NOT NULL DEFAULT '',
        counted_by TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        system_qty_at_approval REAL,
        difference_qty REAL,
        unit_cost REAL,
        difference_value REAL,
        stock_movement_id TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (inventory_count_id) REFERENCES inventory_counts(id) ON DELETE CASCADE
      );
    ''');
    await _ensureColumn(
        'inventory_count_lines', 'system_qty_at_approval', 'REAL');
    await _ensureColumn('inventory_count_lines', 'difference_qty', 'REAL');
    await _ensureColumn('inventory_count_lines', 'unit_cost', 'REAL');
    await _ensureColumn('inventory_count_lines', 'difference_value', 'REAL');
    await _ensureColumn('inventory_count_lines', 'stock_movement_id',
        "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_count_lines_count_line ON inventory_count_lines(inventory_count_id, line_no);');
  }

  Future<void> _ensureBillOfMaterialsColumns() async {
    await _ensureColumn(
        'bill_of_materials', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'bill_of_materials', 'output_product_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'bill_of_materials', 'output_product_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'bill_of_materials', 'output_quantity', 'REAL NOT NULL DEFAULT 1');
    await _ensureColumn(
        'bill_of_materials', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'bill_of_materials', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
  }

  Future<void> _ensureBillOfMaterialsLineTable() async {
    await customStatement(r'''
      CREATE TABLE IF NOT EXISTS bill_of_materials_lines (
        id TEXT PRIMARY KEY NOT NULL,
        bill_of_material_id TEXT NOT NULL,
        line_no INTEGER NOT NULL DEFAULT 0,
        product_id TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (bill_of_material_id) REFERENCES bill_of_materials(id) ON DELETE CASCADE
      );
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_bom_lines_bom_line ON bill_of_materials_lines(bill_of_material_id, line_no);');
  }

  Future<void> _ensureManufacturingOrderColumns() async {
    await _ensureColumn(
        'manufacturing_orders', 'order_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'bom_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'bom_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('manufacturing_orders', 'output_product_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('manufacturing_orders', 'output_product_name',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'quantity', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('manufacturing_orders', 'raw_materials_warehouse_id',
        "TEXT NOT NULL DEFAULT 'main'");
    await _ensureColumn('manufacturing_orders', 'raw_materials_warehouse_name',
        "TEXT NOT NULL DEFAULT 'Main warehouse'");
    await _ensureColumn('manufacturing_orders', 'finished_goods_warehouse_id',
        "TEXT NOT NULL DEFAULT 'main'");
    await _ensureColumn('manufacturing_orders', 'finished_goods_warehouse_name',
        "TEXT NOT NULL DEFAULT 'Main warehouse'");
    await _ensureColumn(
        'manufacturing_orders', 'status', "TEXT NOT NULL DEFAULT 'completed'");
    await _ensureColumn(
        'manufacturing_orders', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'document_date', "TEXT NOT NULL DEFAULT ''");
    // Phase 5 accounting snapshots. These nullable/defaulted columns make the
    // migration safe for legacy completed orders while keeping manufacturing
    // detail inside the already synced/backed-up manufacturing entity.
    await _ensureColumn('manufacturing_orders', 'actual_output_quantity',
        'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('manufacturing_orders', 'total_material_cost',
        'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'manufacturing_orders', 'total_waste_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('manufacturing_orders', 'total_eligible_cost',
        'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'manufacturing_orders', 'actual_unit_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('manufacturing_orders', 'material_costs_json',
        "TEXT NOT NULL DEFAULT '[]'");
    await _ensureColumn('manufacturing_orders', 'waste_lines_json',
        "TEXT NOT NULL DEFAULT '[]'");
    await _ensureColumn(
        'manufacturing_orders', 'journal_entry_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('manufacturing_orders', 'reversal_journal_entry_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'completed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'completed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'reversed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'reversed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'manufacturing_orders', 'reversal_reason', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_manufacturing_orders_status_date ON manufacturing_orders(status, document_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_manufacturing_orders_output ON manufacturing_orders(output_product_id, status);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_manufacturing_orders_journal ON manufacturing_orders(journal_entry_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_manufacturing_orders_reversal_journal ON manufacturing_orders(reversal_journal_entry_id);');
  }

  Future<void> _ensureStockMovementColumns() async {
    await _ensureColumn(
        'stock_movements', 'product_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'product_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'movement_type', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'quantity', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'stock_movements', 'movement_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reference_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reference_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'adjustment_category', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('stock_movements', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'evidence_ref', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'warehouse_id', "TEXT NOT NULL DEFAULT 'main'");
    await _ensureColumn('stock_movements', 'warehouse_name',
        "TEXT NOT NULL DEFAULT 'Main warehouse'");
    await _ensureColumn(
        'stock_movements', 'movement_group_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'document_line_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'source_movement_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('stock_movements', 'reversal_of_movement_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'idempotency_key', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'unit_cost', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('stock_movements', 'last_modified_by_device_id',
        "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reviewed_at', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'reviewed_by', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'stock_movements', 'review_note', "TEXT NOT NULL DEFAULT ''");

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_product_date ON stock_movements(product_id, movement_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_product ON stock_movements(product_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_type_date ON stock_movements(movement_type, movement_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_warehouse_date ON stock_movements(warehouse_id, movement_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_group_id ON stock_movements(movement_group_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_document_line_id ON stock_movements(document_line_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_source_movement_id ON stock_movements(source_movement_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_reversal_of_movement_id ON stock_movements(reversal_of_movement_id);');
    await customStatement(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_movements_idempotency_key ON stock_movements(idempotency_key) WHERE trim(idempotency_key) <> '';");
  }

  Future<void> _ensureBusinessQueryIndexes() async {
    // Older installs may carry a products table that predates the
    // track_stock column. Re-assert the column here so any product indexes that
    // depend on it cannot abort startup.
    await _ensureProductColumns();

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_active_stock_name ON products(is_active, track_stock, name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_category_name ON products(category, name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_code ON products(code);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_deleted_track_lower_name_updated ON products(deleted_at, track_stock, lower(name), updated_at, id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_lower_code ON products(lower(code));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_lower_barcode ON products(lower(barcode));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_lower_name ON products(lower(name));');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_customers_deleted_name ON customers(deleted_at, name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_status_date ON sales(status, document_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_date_updated ON sales(document_date, updated_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_deleted_status_date ON sales(deleted_at, lower(status), document_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_deleted_date_updated_id ON sales(deleted_at, document_date DESC, updated_at DESC, id DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_invoice_no ON sales(invoice_no);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_customer_name ON sales(customer_name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_lower_invoice_no ON sales(lower(invoice_no));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_lower_customer_name ON sales(lower(customer_name));');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_product_name ON sale_items(product_name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON sale_items(product_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_product_name ON sale_items(sale_id, product_name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_lower_product_unit ON sale_items(sale_id, lower(product_name), lower(unit_name));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_sale_units_product_lower_name_barcode ON product_sale_units(product_id, lower(name), lower(barcode));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_purchase_units_product_lower_name_barcode ON product_purchase_units(product_id, lower(name), lower(barcode));');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_status_date ON purchases(status, document_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_supplier_date ON purchases(supplier_id, document_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_date_updated ON purchases(document_date, updated_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_purchase_no ON purchases(purchase_no);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_supplier_name ON purchases(supplier_name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_deleted_date_updated ON purchases(deleted_at, document_date, updated_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_deleted_status_date ON purchases(deleted_at, lower(status), document_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_lower_purchase_no ON purchases(lower(purchase_no));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_lower_supplier_name ON purchases(lower(supplier_name));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchases_lower_status ON purchases(lower(status));');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchase_items_product_name ON purchase_items(product_name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchase_items_product_id ON purchase_items(product_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase_product_name ON purchase_items(purchase_id, lower(product_name));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase_cost_qty ON purchase_items(purchase_id, unit_cost, quantity);');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_status_date ON expenses(expense_status, expense_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_category_date ON expenses(category, expense_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_title ON expenses(title);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_deleted_date_updated_id ON expenses(deleted_at, expense_date DESC, updated_at DESC, id ASC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_deleted_status_date_updated ON expenses(deleted_at, lower(expense_status), expense_date DESC, updated_at DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_deleted_status_amount ON expenses(deleted_at, lower(expense_status), amount);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_lower_title ON expenses(lower(title));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_lower_category ON expenses(lower(category));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_lower_status ON expenses(lower(expense_status));');

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_date_updated ON stock_movements(movement_date, updated_at);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_deleted_date_updated_id ON stock_movements(deleted_at, movement_date DESC, updated_at DESC, id ASC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_deleted_type_date_updated ON stock_movements(deleted_at, movement_type, movement_date DESC, updated_at DESC);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_reference_no ON stock_movements(reference_no);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_product_name ON stock_movements(product_name);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_lower_product_name ON stock_movements(lower(product_name));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_lower_reference_no ON stock_movements(lower(reference_no));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_lower_type ON stock_movements(lower(movement_type));');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_lower_warehouse_name ON stock_movements(lower(warehouse_name));');
  }

  Future<void> _ensureAccountTransactionColumns() async {
    // Product query indexes below depend on track_stock. Some legacy installs
    // reach this stage before the product column backfill has run, so make the
    // column available here as well.
    await _ensureProductColumns();

    await _ensureColumn(
        'account_transactions', 'account_type', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'account_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'account_name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'transaction_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'transaction_type', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'reference_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'reference_no', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'debit', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'account_transactions', 'credit', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
        'account_transactions', 'currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'account_transactions', 'payment_method', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'account_transactions', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('account_transactions', 'last_modified_by_device_id',
        "TEXT NOT NULL DEFAULT ''");

    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_account_transactions_account_date ON account_transactions(account_type, account_id, transaction_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_account_transactions_lower_account ON account_transactions(lower(account_type), account_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_account_transactions_deleted_date ON account_transactions(deleted_at, transaction_date);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_account_transactions_deleted_lower_account_id ON account_transactions(deleted_at, lower(account_type), account_id);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_account_transactions_reference ON account_transactions(reference_id, reference_no);');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_account_transactions_type_date ON account_transactions(transaction_type, transaction_date);');
  }

  Future<void> _ensureCustomerColumns() async {
    await _ensureColumn('customers', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('customers', 'phone', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('customers', 'address', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureSupplierColumns() async {
    await _ensureColumn('suppliers', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'name_en', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'name_ar', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'phone', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'address', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('suppliers', 'notes', "TEXT NOT NULL DEFAULT ''");
  }

  Future<void> _ensureExpenseColumns() async {
    await _ensureColumn('expenses', 'title', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('expenses', 'category', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('expenses', 'amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('expenses', 'original_amount', 'REAL');
    await _ensureColumn(
        'expenses', 'original_currency', "TEXT NOT NULL DEFAULT 'USD'");
    await _ensureColumn(
        'expenses', 'exchange_rate_at_entry', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('expenses', 'expense_date', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('expenses', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'expenses', 'expense_status', "TEXT NOT NULL DEFAULT 'Draft'");
    await _ensureColumn(
        'expenses', 'cancel_reason', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'expenses', 'cancelled_by_device_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('expenses', 'cancelled_at', "TEXT NOT NULL DEFAULT ''");
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(expense_date);');
  }

  Future<void> _ensureWarehouseColumns() async {
    await _ensureColumn('warehouses', 'name', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouses', 'code', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn('warehouses', 'location', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
        'warehouses', 'is_default', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(
        'warehouses', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
  }

  Future<void> _ensureWarehouseInventoryTable() async {
    await _ensureWarehouseInventoryColumns();
  }
}
