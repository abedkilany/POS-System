part of 'settings_page.dart';

class _SaleWarehouseSettingsCard extends StatefulWidget {
  const _SaleWarehouseSettingsCard({required this.store});

  final AppStore store;

  @override
  State<_SaleWarehouseSettingsCard> createState() =>
      _SaleWarehouseSettingsCardState();
}

class _SaleWarehouseSettingsCardState
    extends State<_SaleWarehouseSettingsCard> {
  late Future<void> _future;
  String _selectedWarehouseId = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    await widget.store.ensureWarehousesLoaded();
    _selectedWarehouseId = widget.store
        .resolveWarehouseForSale(
          warehouseId: widget.store.saleWarehouseId,
        )
        .id;
  }

  Future<void> _save(String? value) async {
    final id = value?.trim() ?? '';
    if (id.isEmpty || _saving) return;
    setState(() {
      _selectedWarehouseId = id;
      _saving = true;
    });
    try {
      await widget.store.setSaleWarehouseId(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).text('saved'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _SectionCard(
      icon: Icons.warehouse_outlined,
      title: tr.text('sale_warehouse'),
      subtitle: tr.text('sale_warehouse_desc'),
      child: FutureBuilder<void>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          final warehouses = widget.store.warehouses;
          if (warehouses.isEmpty) {
            return Text(tr.text('no_warehouses'));
          }
          return DropdownButtonFormField<String>(
            initialValue:
                warehouses.any((item) => item.id == _selectedWarehouseId)
                    ? _selectedWarehouseId
                    : warehouses.first.id,
            decoration: InputDecoration(
              labelText: tr.text('warehouse'),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final warehouse in warehouses)
                DropdownMenuItem<String>(
                  value: warehouse.id,
                  child: Text(
                    warehouse.id == Warehouse.defaultId
                        ? '${warehouse.name} (${tr.text('default')})'
                        : warehouse.name,
                  ),
                ),
            ],
            onChanged: _saving ? null : _save,
          );
        },
      ),
    );
  }
}

class _CurrentDeviceCashDrawerSettingsCard extends StatefulWidget {
  const _CurrentDeviceCashDrawerSettingsCard({required this.store});

  final AppStore store;

  @override
  State<_CurrentDeviceCashDrawerSettingsCard> createState() =>
      _CurrentDeviceCashDrawerSettingsCardState();
}

class _CurrentDeviceCashDrawerSettingsCardState
    extends State<_CurrentDeviceCashDrawerSettingsCard> {
  late Future<List<AdvancedAccountingItem>> _future;
  String _selectedDrawerId = '';
  bool _saving = false;

  String get _deviceId => widget.store.deviceId.trim();
  String get _branchId => widget.store.appIdentity.branchId.trim();

  @override
  void initState() {
    super.initState();
    _future = _loadDrawers();
  }

  Future<List<AdvancedAccountingItem>> _loadDrawers() async {
    final items =
        await AccountingService.listActiveCashLocations(includeBank: false);
    final drawers = items.where((item) => item.type == 'cash_drawer').toList();
    final current = drawers.where((item) => item.referenceId == _deviceId);
    _selectedDrawerId = current.isEmpty ? '' : current.first.id;
    return drawers;
  }

  void _refresh() {
    setState(() {
      _future = _loadDrawers();
    });
  }

  Future<void> _save() async {
    widget.store.requirePermission(AppPermission.cashBoxManage);
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      if (_selectedDrawerId.isEmpty) {
        await AccountingService.unlinkCashDrawerFromDevice(deviceId: _deviceId);
      } else {
        await AccountingService.linkCashDrawerToDevice(
          cashLocationId: _selectedDrawerId,
          deviceId: _deviceId,
          branchId: _branchId,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('saved'))),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canManage = widget.store.hasPermission(AppPermission.cashBoxManage);
    return _SectionCard(
      icon: Icons.point_of_sale_outlined,
      title: tr.text('current_device_cash_drawer'),
      subtitle: tr.text('current_device_cash_drawer_desc'),
      trailing: IconButton(
        tooltip: tr.text('refresh'),
        onPressed: _saving ? null : _refresh,
        icon: const Icon(Icons.refresh_outlined),
      ),
      child: FutureBuilder<List<AdvancedAccountingItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            );
          }
          final drawers = snapshot.data ?? const <AdvancedAccountingItem>[];
          final currentDevice =
              _deviceId.isEmpty ? tr.text('unknown') : _deviceId;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoGrid(
                items: [
                  _InfoGridItem(Icons.devices_outlined, tr.text('device_id'),
                      currentDevice),
                  _InfoGridItem(
                    Icons.storefront_outlined,
                    tr.text('branch'),
                    _branchId.isEmpty ? tr.text('not_set') : _branchId,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue:
                    _selectedDrawerId.isEmpty ? '' : _selectedDrawerId,
                decoration: InputDecoration(
                  labelText: tr.text('linked_cash_drawer'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(tr.text('no_cash_drawer_linked')),
                  ),
                  for (final drawer in drawers)
                    DropdownMenuItem<String>(
                      value: drawer.id,
                      child: Text(
                        drawer.referenceId.isEmpty
                            ? drawer.name
                            : '${drawer.name} • ${drawer.referenceId}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _saving || !canManage
                    ? null
                    : (value) =>
                        setState(() => _selectedDrawerId = value ?? ''),
              ),
              const SizedBox(height: 12),
              Text(
                tr.text('current_device_cash_drawer_hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _saving || _deviceId.isEmpty || !canManage
                        ? null
                        : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(tr.text('save')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving || !canManage
                        ? null
                        : () {
                            setState(() => _selectedDrawerId = '');
                            _save();
                          },
                    icon: const Icon(Icons.link_off_outlined),
                    label: Text(tr.text('unlink_cash_drawer')),
                  ),
                ],
              ),
              if (drawers.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  tr.text('create_cash_drawer_from_accounting_hint'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
