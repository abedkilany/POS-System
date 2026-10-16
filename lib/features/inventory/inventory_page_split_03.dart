part of 'inventory_page.dart';

class _WarehousesTabState extends State<_WarehousesTab> {
  Future<Map<String, List<_WarehouseProductStock>>>? _stockRowsFuture;
  String _stockRowsFutureKey = '';

  @override
  void didUpdateWidget(covariant _WarehousesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _stockRowsFuture = null;
      _stockRowsFutureKey = '';
    }
  }

  Future<Map<String, List<_WarehouseProductStock>>>
      _loadStockRowsByWarehouse() async {
    final warehouses = widget.store.inventory.warehouses;
    final products = widget.store.catalog.stockTrackedProducts;
    final productsById = <String, Product>{
      for (final product in products) product.id: product,
    };
    final balances =
        await widget.store.inventory.warehouseStockBalancesFromSqlite();
    final stockRowsByWarehouse = <String, List<_WarehouseProductStock>>{
      for (final warehouse in warehouses)
        warehouse.id: <_WarehouseProductStock>[],
    };

    for (final warehouseEntry in balances.entries) {
      final rows = stockRowsByWarehouse[warehouseEntry.key];
      if (rows == null) continue;
      for (final productEntry in warehouseEntry.value.entries) {
        final product = productsById[productEntry.key];
        if (product == null) continue;
        rows.add(_WarehouseProductStock(
          product: product,
          stock: productEntry.value,
        ));
      }
      rows.sort((a, b) => a.product.name.compareTo(b.product.name));
    }
    return stockRowsByWarehouse;
  }

  Future<Map<String, List<_WarehouseProductStock>>>
      _stockRowsByWarehouseFuture() {
    final key =
        '${widget.store.runtime.identity.storeId}:${widget.store.inventory.revision}';
    if (_stockRowsFuture == null || _stockRowsFutureKey != key) {
      _stockRowsFutureKey = key;
      _stockRowsFuture = _loadStockRowsByWarehouse();
    }
    return _stockRowsFuture!;
  }

  Future<void> _createWarehouse() async {
    final tr = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final locationController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('create_warehouse')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameController,
                decoration:
                    InputDecoration(labelText: tr.text('warehouse_name'))),
            const SizedBox(height: 12),
            TextField(
                controller: codeController,
                decoration:
                    InputDecoration(labelText: tr.text('code_optional'))),
            const SizedBox(height: 12),
            TextField(
                controller: locationController,
                decoration:
                    InputDecoration(labelText: tr.text('location_optional'))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () async {
              try {
                await widget.store.inventory.createWarehouse(
                    name: nameController.text,
                    code: codeController.text,
                    location: locationController.text);
                if (context.mounted) Navigator.pop(context);
                if (mounted) setState(() {});
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(localizedErrorText(
                          AppLocalizations.of(context), error))));
                }
              }
            },
            child: Text(tr.text('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _transferStock() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => WarehouseTransferPage(store: widget.store),
      ),
    );
    if (!mounted) return;
    setState(() {
      _stockRowsFuture = null;
      _stockRowsFutureKey = '';
    });
  }

  Future<void> _printWarehouseInventory(
    Warehouse warehouse,
    List<_WarehouseProductStock> rows,
  ) async {
    try {
      await WarehouseInventoryPdfService.printWarehouseInventory(
        warehouse: warehouse,
        rows: rows
            .map(
              (row) => WarehouseInventoryPdfRow(
                product: row.product,
                stock: row.stock,
              ),
            )
            .toList(growable: false),
        profile: widget.store.runtime.profile,
        context: context,
        locale: Localizations.localeOf(context),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.security.hasPermission(
      AppPermission.inventoryWarehousesManage,
    )) {
      return _InventorySectionDenied(
        title: tr.text('warehouses'),
        message: tr.text('warehouse_management_no_access'),
      );
    }
    final warehouses = widget.store.inventory.warehouses;
    return FutureBuilder<Map<String, List<_WarehouseProductStock>>>(
      future: _stockRowsByWarehouseFuture(),
      builder: (context, snapshot) {
        final stockRowsByWarehouse = snapshot.data;
        return ListView.builder(
          padding: VentioResponsive.pageInsets(context),
          itemCount: warehouses.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  FilledButton.icon(
                      onPressed: _createWarehouse,
                      icon: const Icon(Icons.add_business_outlined),
                      label: Text(tr.text('create_warehouse'))),
                  OutlinedButton.icon(
                      onPressed: warehouses.length < 2 ? null : _transferStock,
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(tr.text('transfer_stock'))),
                ]),
              );
            }
            final warehouse = warehouses[index - 1];
            final rows = stockRowsByWarehouse?[warehouse.id] ??
                const <_WarehouseProductStock>[];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                leading:
                    const CircleAvatar(child: Icon(Icons.warehouse_outlined)),
                title: Row(
                  children: [
                    Expanded(child: Text(warehouse.name)),
                    IconButton(
                      tooltip:
                          Localizations.localeOf(context).languageCode == 'ar'
                              ? 'طباعة محتوى المستودع'
                              : 'Print warehouse inventory',
                      onPressed: stockRowsByWarehouse == null
                          ? null
                          : () => _printWarehouseInventory(warehouse, rows),
                      icon: const Icon(Icons.print_outlined),
                    ),
                  ],
                ),
                subtitle: Text([
                  if (warehouse.code.isNotEmpty) warehouse.code,
                  if (warehouse.location.isNotEmpty) warehouse.location
                ].join(' • ')),
                children: [
                  if (stockRowsByWarehouse == null)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    for (final row in rows.take(100))
                      ListTile(
                        dense: true,
                        title: Text(row.product.name),
                        trailing: Text('${row.stock}'),
                      ),
                    if (rows.isEmpty)
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(tr.text('no_inventory_items'))),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _WarehouseProductStock {
  const _WarehouseProductStock({required this.product, required this.stock});

  final Product product;
  final double stock;
}

class _MovementsList extends StatefulWidget {
  const _MovementsList({required this.store});
  final ApplicationSession store;

  @override
  State<_MovementsList> createState() => _MovementsListState();
}
