part of 'products_page.dart';

class _CurrencyPriceOverridesEditor extends StatelessWidget {
  const _CurrencyPriceOverridesEditor({
    required this.drafts,
    required this.baseCurrencyCode,
    required this.availableCurrencyCodes,
    required this.onChanged,
  });

  final List<_CurrencyPriceOverrideDraft> drafts;
  final String baseCurrencyCode;
  final List<String> availableCurrencyCodes;
  final ValueChanged<List<_CurrencyPriceOverrideDraft>> onChanged;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final baseCurrency = baseCurrencyCode.trim().toUpperCase();
    final currencies = <String>{
      ...availableCurrencyCodes
          .map((item) => item.trim().toUpperCase())
          .where((item) => item.isNotEmpty),
      'USD',
      'LBP',
    }.where((item) => item != baseCurrency).toList()
      ..sort();
    final canAdd = currencies.any((currency) => !drafts
        .any((draft) => draft.currencyCode.trim().toUpperCase() == currency));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('currency_price_overrides'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  tr.text('currency_price_overrides_desc'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
            final addButton = OutlinedButton.icon(
              onPressed: canAdd ? () => _addOverride(currencies) : null,
              icon: const Icon(Icons.add),
              label: Text(tr.text('add_override')),
            );
            if (constraints.maxWidth < 460) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 8), addButton],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 8),
                addButton,
              ],
            );
          }),
          const SizedBox(height: 12),
          if (drafts.isEmpty)
            Text(
              tr.text('no_fixed_currency_prices'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ...drafts.asMap().entries.map((entry) {
              final index = entry.key;
              final draft = entry.value;
              final selectedCurrency = currencies.contains(draft.currencyCode)
                  ? draft.currencyCode
                  : (currencies.isNotEmpty
                      ? currencies.first
                      : draft.currencyCode);
              final rowCurrencies = <String>{
                selectedCurrency,
                ...currencies.where((currency) => !drafts.asMap().entries.any(
                      (other) =>
                          other.key != index &&
                          other.value.currencyCode.trim().toUpperCase() ==
                              currency,
                    )),
              }.toList()
                ..sort();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 116,
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedCurrency,
                        decoration:
                            InputDecoration(labelText: tr.text('currency')),
                        items: rowCurrencies
                            .map((currency) => DropdownMenuItem(
                                  value: currency,
                                  child: Text(currency),
                                ))
                            .toList(),
                        onChanged: (value) => _update(
                            index,
                            draft.copyWith(
                                currencyCode: value ?? selectedCurrency)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: draft.amountText,
                        decoration:
                            InputDecoration(labelText: tr.text('fixed_price')),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (value) {
                          final amount = double.tryParse((value ?? '').trim());
                          if (amount == null || amount < 0) {
                            return tr.text('invalid_number');
                          }
                          return null;
                        },
                        onChanged: (value) =>
                            _update(index, draft.copyWith(amountText: value)),
                      ),
                    ),
                    IconButton(
                      tooltip: tr.text('remove_override'),
                      onPressed: () => _remove(index),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _addOverride(List<String> currencies) {
    for (final currency in currencies) {
      if (!drafts.any(
          (draft) => draft.currencyCode.trim().toUpperCase() == currency)) {
        onChanged([
          ...drafts,
          _CurrencyPriceOverrideDraft(currencyCode: currency, amountText: '')
        ]);
        return;
      }
    }
  }

  void _update(int index, _CurrencyPriceOverrideDraft draft) {
    final next = List<_CurrencyPriceOverrideDraft>.from(drafts);
    next[index] =
        draft.copyWith(currencyCode: draft.currencyCode.trim().toUpperCase());
    onChanged(next);
  }

  void _remove(int index) {
    final next = List<_CurrencyPriceOverrideDraft>.from(drafts)
      ..removeAt(index);
    onChanged(next);
  }
}

class _SupplierPricesEditor extends StatelessWidget {
  const _SupplierPricesEditor({
    required this.prices,
    required this.productId,
    required this.suppliers,
    required this.storeProfile,
    required this.onChanged,
  });

  final List<SupplierProductPrice> prices;
  final String productId;
  final List<Supplier> suppliers;
  final StoreProfile storeProfile;
  final ValueChanged<List<SupplierProductPrice>> onChanged;

  String _supplierName(String id) {
    for (final supplier in suppliers) {
      if (supplier.id == id) {
        return supplier.name.trim().isNotEmpty
            ? supplier.name
            : supplier.nameEn;
      }
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canAdd = suppliers.isNotEmpty;
    final rows = prices.where((item) => !item.isDeleted).toList()
      ..sort((a, b) {
        if (a.isPreferred != b.isPreferred) return a.isPreferred ? -1 : 1;
        return _supplierName(a.supplierId)
            .toLowerCase()
            .compareTo(_supplierName(b.supplierId).toLowerCase());
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final description = Text(
              tr.text('supplier_prices_desc'),
              style: Theme.of(context).textTheme.bodySmall,
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: canAdd ? () => _importCsv(context) : null,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(tr.text('csv')),
                ),
                FilledButton.icon(
                  onPressed: canAdd ? () => _openEditor(context) : null,
                  icon: const Icon(Icons.add),
                  label: Text(tr.text('add')),
                ),
              ],
            );
            if (constraints.maxWidth < 460) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [description, const SizedBox(height: 8), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: description),
                const SizedBox(width: 8),
                actions,
              ],
            );
          },
        ),
        if (!canAdd) ...[
          const SizedBox(height: 8),
          Text(tr.text('add_suppliers_first_for_prices')),
        ],
        const SizedBox(height: 12),
        if (rows.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text([
                if (rows.any((item) => item.isPreferred))
                  '${tr.text('preferred_supplier')}: ${_supplierName(rows.firstWhere((item) => item.isPreferred).supplierId)}',
                '${tr.text('best_price')}: ${_supplierName((rows.toList()..sort((a, b) => a.cost.compareTo(b.cost))).first.supplierId)}',
                if (rows.any((item) => item.leadTimeDays != null))
                  '${tr.text('fastest_supplier')}: ${_supplierName((rows.where((item) => item.leadTimeDays != null).toList()..sort((a, b) => a.leadTimeDays!.compareTo(b.leadTimeDays!))).first.supplierId)}',
              ].join(' • ')),
            ),
          ),
        if (rows.isNotEmpty) const SizedBox(height: 8),
        if (rows.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr.text('no_supplier_prices')),
            ),
          )
        else
          ...rows.map((item) => _buildSupplierPriceCard(context, item)),
      ],
    );
  }

  Widget _buildSupplierPriceCard(
      BuildContext context, SupplierProductPrice item) {
    final subtitle = [
      formatCurrency(item.cost, currency: item.currency),
      if (item.isPreferred) AppLocalizations.of(context).text('preferred'),
      if (item.supplierSku.trim().isNotEmpty)
        AppLocalizations.of(context)
            .format('supplier_sku_prefix', {'value': item.supplierSku.trim()}),
      if (item.minOrderQty != null)
        AppLocalizations.of(context)
            .format('min_order_qty_prefix', {'value': item.minOrderQty}),
      if (item.leadTimeDays != null)
        AppLocalizations.of(context)
            .format('lead_time_days', {'count': item.leadTimeDays}),
      if (item.priceHistory.isNotEmpty)
        AppLocalizations.of(context)
            .format('history_count', {'count': item.priceHistory.length}),
      if (item.notes.trim().isNotEmpty) item.notes.trim(),
    ].join(' • ');
    final actions = Wrap(
      spacing: 4,
      children: [
        IconButton(
          tooltip: AppLocalizations.of(context).text('edit'),
          onPressed: () => _openEditor(context, item: item),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).text('delete'),
          onPressed: () {
            onChanged(prices.where((row) => row.id != item.id).toList());
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(item.isPreferred
                          ? Icons.star
                          : Icons.local_shipping_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_supplierName(item.supplierId),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle),
                  const SizedBox(height: 4),
                  Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: actions),
                ],
              ),
            );
          }
          return ListTile(
            leading: Icon(
                item.isPreferred ? Icons.star : Icons.local_shipping_outlined),
            title: Text(_supplierName(item.supplierId)),
            subtitle: Text(subtitle),
            trailing: actions,
          );
        },
      ),
    );
  }

  Future<void> _importCsv(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null || bytes.isEmpty) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter()
        .convert(text)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return;
    final updated = List<SupplierProductPrice>.from(prices);
    final now = DateTime.now();
    for (final rawLine in lines.skip(1)) {
      final cols = rawLine.split(',').map((item) => item.trim()).toList();
      if (cols.length < 2) continue;
      final supplierKey = cols[0].toLowerCase();
      Supplier? supplier;
      for (final candidate in suppliers) {
        final name = (candidate.name.trim().isNotEmpty
                ? candidate.name
                : candidate.nameEn)
            .toLowerCase();
        if (candidate.id.toLowerCase() == supplierKey || name == supplierKey) {
          supplier = candidate;
          break;
        }
      }
      if (supplier == null) continue;
      final supplierRow = supplier;
      final cost = double.tryParse(cols[1]);
      if (cost == null || cost < 0) continue;
      final currency =
          cols.length > 2 && cols[2].toUpperCase() == 'LBP' ? 'LBP' : 'USD';
      final supplierSku = cols.length > 3 ? cols[3] : '';
      final minQty = cols.length > 4 && cols[4].isNotEmpty
          ? double.tryParse(cols[4])
          : null;
      final leadDays =
          cols.length > 5 && cols[5].isNotEmpty ? int.tryParse(cols[5]) : null;
      final notes = cols.length > 6 ? cols.sublist(6).join(',').trim() : '';
      final existingIndex = updated.indexWhere((item) =>
          !item.isDeleted &&
          item.supplierId == supplierRow.id &&
          item.productId == productId);
      final existing = existingIndex == -1 ? null : updated[existingIndex];
      final row = SupplierProductPrice(
        id: existing?.id ??
            'spp_${now.microsecondsSinceEpoch}_${updated.length}',
        productId: productId,
        supplierId: supplierRow.id,
        cost: cost,
        currency: currency,
        isPreferred: existing?.isPreferred ??
            updated.where((item) => !item.isDeleted).isEmpty,
        supplierSku: supplierSku,
        minOrderQty: minQty,
        leadTimeDays: leadDays,
        notes: notes,
        priceHistory: existing?.priceHistory ?? const [],
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deviceId: existing?.deviceId ?? '',
        syncStatus: existing?.syncStatus ?? 'pending',
        storeId: existing?.storeId ?? '',
        branchId: existing?.branchId ?? '',
        version: existing?.version ?? 1,
        lastModifiedByDeviceId: existing?.lastModifiedByDeviceId ?? '',
      );
      if (existingIndex == -1) {
        updated.add(row);
      } else {
        updated[existingIndex] = row;
      }
    }
    onChanged(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).text('csv_import_completed'))));
    }
  }

  Future<void> _openEditor(BuildContext context,
      {SupplierProductPrice? item}) async {
    final result = await showDialog<SupplierProductPrice>(
      context: context,
      builder: (_) => _SupplierPriceDialog(
        suppliers: suppliers,
        productId: productId,
        existingPrices: prices,
        price: item,
      ),
    );
    if (result == null) return;
    final updated = <SupplierProductPrice>[];
    var replaced = false;
    for (final row in prices) {
      if (row.id == result.id) {
        updated.add(result);
        replaced = true;
      } else if (result.isPreferred &&
          row.productId == result.productId &&
          row.id != result.id) {
        updated
            .add(row.copyWith(isPreferred: false, updatedAt: DateTime.now()));
      } else {
        updated.add(row);
      }
    }
    if (!replaced) {
      if (result.isPreferred) {
        for (var i = 0; i < updated.length; i++) {
          updated[i] = updated[i]
              .copyWith(isPreferred: false, updatedAt: DateTime.now());
        }
      }
      updated.add(result);
    }
    onChanged(updated);
  }
}

class _SupplierPriceDialog extends StatefulWidget {
  const _SupplierPriceDialog(
      {required this.suppliers,
      required this.productId,
      required this.existingPrices,
      this.price});

  final List<Supplier> suppliers;
  final String productId;
  final List<SupplierProductPrice> existingPrices;
  final SupplierProductPrice? price;

  @override
  State<_SupplierPriceDialog> createState() => _SupplierPriceDialogState();
}

class _SupplierPriceDialogState extends State<_SupplierPriceDialog> {
  final _formKey = GlobalKey<FormState>();
  late String supplierId;
  late String currency;
  late bool isPreferred;
  late final TextEditingController costController;
  late final TextEditingController supplierSkuController;
  late final TextEditingController minOrderQtyController;
  late final TextEditingController leadTimeDaysController;
  late final TextEditingController notesController;

  @override
  void initState() {
    super.initState();
    supplierId = widget.price?.supplierId ??
        (widget.suppliers.isNotEmpty ? widget.suppliers.first.id : '');
    currency = widget.price?.currency ?? 'USD';
    isPreferred = widget.price?.isPreferred ?? false;
    costController =
        TextEditingController(text: widget.price?.cost.toString() ?? '');
    supplierSkuController =
        TextEditingController(text: widget.price?.supplierSku ?? '');
    minOrderQtyController = TextEditingController(
        text: widget.price?.minOrderQty?.toString() ?? '');
    leadTimeDaysController = TextEditingController(
        text: widget.price?.leadTimeDays?.toString() ?? '');
    notesController = TextEditingController(text: widget.price?.notes ?? '');
  }

  @override
  void dispose() {
    costController.dispose();
    supplierSkuController.dispose();
    minOrderQtyController.dispose();
    leadTimeDaysController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final dialogWidth =
        math.min(MediaQuery.sizeOf(context).width - 32, 420).toDouble();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: Text(tr.text(
          widget.price == null ? 'add_supplier_price' : 'edit_supplier_price')),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: supplierId.isEmpty ? null : supplierId,
                  decoration: InputDecoration(labelText: tr.text('supplier')),
                  items: widget.suppliers
                      .map((supplier) => DropdownMenuItem(
                            value: supplier.id,
                            child: Text(supplier.name.trim().isNotEmpty
                                ? supplier.name
                                : supplier.nameEn),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => supplierId = value ?? ''),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? tr.text('required_field')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: costController,
                  decoration: InputDecoration(labelText: tr.text('cost')),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final number = double.tryParse((value ?? '').trim());
                    return number == null || number < 0
                        ? tr.text('invalid_number')
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: InputDecoration(labelText: tr.text('currency')),
                  items: const [
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                  ],
                  onChanged: (value) =>
                      setState(() => currency = value ?? 'USD'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: supplierSkuController,
                  decoration:
                      InputDecoration(labelText: tr.text('supplier_sku')),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: minOrderQtyController,
                  decoration:
                      InputDecoration(labelText: tr.text('min_order_qty')),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    final number = double.tryParse((value ?? '').trim());
                    return number == null || number < 0
                        ? tr.text('invalid_number')
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: leadTimeDaysController,
                  decoration: InputDecoration(labelText: tr.text('lead_time')),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    final number = int.tryParse((value ?? '').trim());
                    return number == null || number < 0
                        ? tr.text('invalid_number')
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  decoration: InputDecoration(labelText: tr.text('notes')),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr.text('preferred_supplier')),
                  value: isPreferred,
                  onChanged: (value) => setState(() => isPreferred = value),
                ),
                if ((widget.price?.priceHistory.isNotEmpty ?? false)) ...[
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr.text('price_history'),
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  const SizedBox(height: 4),
                  ...widget.price!.priceHistory.reversed
                      .take(5)
                      .map((entry) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${entry.oldCost} → ${entry.newCost} ${entry.currency} • ${entry.source}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          )),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr.text('cancel'))),
        FilledButton(onPressed: _save, child: Text(tr.text('save'))),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    final duplicate = widget.existingPrices.any((item) =>
        item.id != widget.price?.id &&
        !item.isDeleted &&
        item.productId == widget.productId &&
        item.supplierId == supplierId);
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              AppLocalizations.of(context).text('supplier_price_duplicate'))));
      return;
    }
    Navigator.pop(
      context,
      SupplierProductPrice(
        id: widget.price?.id ?? 'spp_${now.microsecondsSinceEpoch}',
        productId: widget.productId,
        supplierId: supplierId,
        cost: double.tryParse(costController.text.trim()) ?? 0,
        currency: currency,
        isPreferred: isPreferred,
        supplierSku: supplierSkuController.text.trim(),
        minOrderQty: minOrderQtyController.text.trim().isEmpty
            ? null
            : double.tryParse(minOrderQtyController.text.trim()),
        leadTimeDays: leadTimeDaysController.text.trim().isEmpty
            ? null
            : int.tryParse(leadTimeDaysController.text.trim()),
        notes: notesController.text.trim(),
        priceHistory: widget.price?.priceHistory ?? const [],
        createdAt: widget.price?.createdAt ?? now,
        updatedAt: now,
        deletedAt: widget.price?.deletedAt,
        deviceId: widget.price?.deviceId ?? '',
        syncStatus: widget.price?.syncStatus ?? 'pending',
        storeId: widget.price?.storeId ?? '',
        branchId: widget.price?.branchId ?? '',
        version: widget.price?.version ?? 1,
        lastModifiedByDeviceId: widget.price?.lastModifiedByDeviceId ?? '',
      ),
    );
  }
}

class _SaleUnitDraft {
  _SaleUnitDraft(
      {required this.id,
      this.name = '',
      this.conversionToBase = '1',
      this.price = '',
      this.priceCurrency = 'USD',
      this.barcode = ''});

  final String id;
  String name;
  String conversionToBase;
  String price;
  String priceCurrency;
  String barcode;

  factory _SaleUnitDraft.fromSaleUnit(ProductSaleUnit unit) => _SaleUnitDraft(
        id: unit.id.trim().isNotEmpty
            ? unit.id
            : DateTime.now().microsecondsSinceEpoch.toString(),
        name: unit.name,
        conversionToBase: unit.conversionToBase.toString(),
        price: unit.originalPrice.toString(),
        priceCurrency: unit.originalCurrency,
        barcode: unit.barcode,
      );

  ProductSaleUnit toSaleUnit(StoreProfile profile) {
    final original = double.tryParse(price.trim()) ?? 0;
    final reference = toUsdReferencePrice(original, priceCurrency, profile);
    return ProductSaleUnit(
      id: id,
      name: name.trim(),
      conversionToBase: double.tryParse(conversionToBase.trim()) ?? 1,
      price: reference,
      originalPrice: original,
      originalCurrency: priceCurrency,
      barcode: barcode.trim(),
    );
  }
}
