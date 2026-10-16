part of 'products_page.dart';

class _SaleUnitsEditor extends StatelessWidget {
  const _SaleUnitsEditor(
      {required this.saleUnits,
      required this.storeProfile,
      required this.existingBarcodes,
      required this.onChanged});

  final List<_SaleUnitDraft> saleUnits;
  final StoreProfile storeProfile;
  final Set<String> existingBarcodes;
  final ValueChanged<List<_SaleUnitDraft>> onChanged;

  void _generateUnitBarcode(_SaleUnitDraft unit) {
    final used = <String>{
      ...existingBarcodes.map((value) => value.trim()),
      ...saleUnits.map((item) => item.barcode.trim()),
    }..remove('');
    var seed = DateTime.now().microsecondsSinceEpoch % 1000000000000;
    String value;
    do {
      final body = seed.toString().padLeft(12, '0');
      var sum = 0;
      for (var index = 0; index < body.length; index++) {
        sum += int.parse(body[index]) * (index.isEven ? 1 : 3);
      }
      value = '$body${(10 - (sum % 10)) % 10}';
      seed = (seed + 1) % 1000000000000;
    } while (used.contains(value));
    unit.barcode = value;
    onChanged(List<_SaleUnitDraft>.from(saleUnits));
  }

  Future<void> _scanUnitBarcode(
      BuildContext context, _SaleUnitDraft unit) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const PageTimingScope(
          pageKey: 'BarcodeScannerPage',
          pageLabel: 'Barcode scanner',
          child: BarcodeScannerPage(),
        ),
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    unit.barcode = code.trim();
    onChanged(List<_SaleUnitDraft>.from(saleUnits));
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(tr.text('sale_units'),
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                TextButton.icon(
                  onPressed: () {
                    final next = List<_SaleUnitDraft>.from(saleUnits)
                      ..add(_SaleUnitDraft(
                          id: DateTime.now()
                              .microsecondsSinceEpoch
                              .toString()));
                    onChanged(next);
                  },
                  icon: const Icon(Icons.add),
                  label: Text(tr.text('add_unit')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(tr.text('base_unit_help')),
            const SizedBox(height: 8),
            if (saleUnits.isEmpty)
              Text(tr.text('no_extra_sale_units'))
            else
              ...saleUnits.asMap().entries.map((entry) {
                final index = entry.key;
                final unit = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(
                                  tr.format(
                                      'unit_number', {'number': index + 1}),
                                  style:
                                      Theme.of(context).textTheme.labelLarge)),
                          IconButton(
                            onPressed: () {
                              final next = List<_SaleUnitDraft>.from(saleUnits)
                                ..removeAt(index);
                              onChanged(next);
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      _ResponsiveFields(children: [
                        TextFormField(
                          initialValue: unit.name,
                          decoration:
                              InputDecoration(labelText: tr.text('unit_name')),
                          onChanged: (value) => unit.name = value,
                        ),
                        TextFormField(
                          initialValue: unit.conversionToBase,
                          decoration: InputDecoration(
                              labelText: tr.text('conversion_to_base')),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (value) {
                            final number =
                                double.tryParse((value ?? '').trim());
                            return number == null || number <= 0
                                ? tr.text('invalid_number')
                                : null;
                          },
                          onChanged: (value) => unit.conversionToBase = value,
                        ),
                        TextFormField(
                          initialValue: unit.price,
                          decoration: InputDecoration(
                              labelText: tr.text('unit_sale_price')),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (value) {
                            final number =
                                double.tryParse((value ?? '').trim());
                            return number == null || number < 0
                                ? tr.text('invalid_number')
                                : null;
                          },
                          onChanged: (value) => unit.price = value,
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: unit.priceCurrency,
                          decoration: InputDecoration(
                              labelText: tr.text('price_currency')),
                          items: const [
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                            DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                          ],
                          onChanged: (value) =>
                              unit.priceCurrency = value ?? 'USD',
                        ),
                        TextFormField(
                          key: ValueKey(
                              'unit-barcode-${unit.id}-${unit.barcode}'),
                          initialValue: unit.barcode,
                          decoration: InputDecoration(
                            labelText: tr.text('unit_barcode'),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: tr.text('generate_barcode'),
                                  onPressed: () => _generateUnitBarcode(unit),
                                  icon: const Icon(Icons.qr_code_2_outlined),
                                ),
                                IconButton(
                                  tooltip: tr.text('scan_with_camera'),
                                  onPressed: () =>
                                      _scanUnitBarcode(context, unit),
                                  icon: const Icon(Icons.camera_alt_outlined),
                                ),
                              ],
                            ),
                          ),
                          onChanged: (value) => unit.barcode = value,
                        ),
                      ]),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ProductFormSection extends StatelessWidget {
  const _ProductFormSection(
      {required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: children,
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField(
      {required this.controller,
      required this.currency,
      required this.label,
      required this.currencyLabel,
      required this.validator,
      this.onChanged,
      required this.onCurrencyChanged});

  final TextEditingController controller;
  final String currency;
  final String label;
  final String currencyLabel;
  final FormFieldValidator<String> validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currency,
              hint: Text(currencyLabel),
              items: const [
                DropdownMenuItem(value: 'USD', child: Text('USD')),
                DropdownMenuItem(value: 'LBP', child: Text('LBP')),
              ],
              onChanged: (value) => onCurrencyChanged(value ?? 'USD'),
            ),
          ),
        ),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: validator,
      onChanged: onChanged,
    );
  }
}

class _MarginField extends StatelessWidget {
  const _MarginField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          suffixText: '%',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (value) {
          if ((value ?? '').trim().isEmpty) return null;
          final number = double.tryParse((value ?? '').trim());
          return number == null || number < 0
              ? AppLocalizations.of(context).text('invalid_number')
              : null;
        },
        onChanged: onChanged,
      );
}

class _ProductImagePicker extends StatelessWidget {
  const _ProductImagePicker(
      {required this.imagePath, required this.onPick, this.onClear});

  final String imagePath;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final hasImage = imagePath.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
            children: [
              CircleAvatar(
                radius: 28,
                child: Icon(hasImage
                    ? Icons.image_outlined
                    : Icons.add_photo_alternate_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.text('product_image'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        hasImage
                            ? imagePath.split('/').last
                            : tr.text('product_image_help'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(tr.text('choose'))),
              if (onClear != null)
                IconButton(onPressed: onClear, icon: const Icon(Icons.close)),
            ],
          );
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 8), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 8),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 620) {
        return Column(
            children: children
                .map((child) => Padding(
                    padding: const EdgeInsets.only(bottom: 12), child: child))
                .toList());
      }
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map((child) =>
                SizedBox(width: (constraints.maxWidth - 12) / 2, child: child))
            .toList(),
      );
    });
  }
}

class _CatalogDropdown extends StatelessWidget {
  const _CatalogDropdown(
      {required this.label,
      required this.value,
      required this.items,
      required this.onChanged,
      required this.onAdd,
      required this.onManage,
      this.validator});
  final String label;
  final String value;
  final List<CatalogItem> items;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;
  final VoidCallback onManage;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final language = AppLocalizations.of(context).locale.languageCode;
    final values = <String>{
      ...items
          .map((item) => item.code.isNotEmpty ? item.code : item.nameEn)
          .where((e) => e.trim().isNotEmpty),
      if (value.trim().isNotEmpty) value
    }.toList();
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value.trim().isEmpty ? null : value,
            decoration: InputDecoration(labelText: label),
            items: values.map((raw) {
              CatalogItem? match;
              for (final item in items) {
                if (item.code == raw ||
                    item.nameEn == raw ||
                    item.nameAr == raw) {
                  match = item;
                  break;
                }
              }
              return DropdownMenuItem(
                  value: raw, child: Text(match?.displayName(language) ?? raw));
            }).toList(),
            onChanged: (newValue) => onChanged(newValue ?? ''),
            validator: validator,
          ),
        ),
        IconButton(
            onPressed: onAdd, icon: const Icon(Icons.add_circle_outline)),
        IconButton(onPressed: onManage, icon: const Icon(Icons.tune_outlined)),
      ],
    );
  }
}

class _CatalogItemDialog extends StatefulWidget {
  const _CatalogItemDialog({required this.type, this.item});
  final String type;
  final CatalogItem? item;
  @override
  State<_CatalogItemDialog> createState() => _CatalogItemDialogState();
}

class _CatalogItemDialogState extends State<_CatalogItemDialog> {
  late final TextEditingController enController;
  late final TextEditingController arController;
  late final TextEditingController codeController;

  @override
  void initState() {
    super.initState();
    enController = TextEditingController(text: widget.item?.nameEn ?? '');
    arController = TextEditingController(text: widget.item?.nameAr ?? '');
    codeController = TextEditingController(text: widget.item?.code ?? '');
  }

  @override
  void dispose() {
    enController.dispose();
    arController.dispose();
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(tr.text('add_lookup_item')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: enController,
              decoration: InputDecoration(labelText: tr.text('name_en'))),
          const SizedBox(height: 12),
          TextField(
              controller: arController,
              decoration: InputDecoration(labelText: tr.text('name_ar'))),
          const SizedBox(height: 12),
          TextField(
              controller: codeController,
              decoration: InputDecoration(labelText: tr.text('code_optional'))),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr.text('cancel'))),
        FilledButton(
          onPressed: () {
            Navigator.pop(
                context,
                CatalogItem(
                    id: widget.item?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    nameEn: enController.text.trim(),
                    nameAr: arController.text.trim(),
                    code: codeController.text.trim()));
          },
          child: Text(tr.text('save')),
        ),
      ],
    );
  }
}

class _CatalogManagerDialog extends StatefulWidget {
  const _CatalogManagerDialog({required this.store, required this.type});
  final ApplicationSession store;
  final String type;

  @override
  State<_CatalogManagerDialog> createState() => _CatalogManagerDialogState();
}

class _CatalogManagerDialogState extends State<_CatalogManagerDialog> {
  List<CatalogItem> get _items {
    if (widget.type == 'category') return widget.store.catalog.categories;
    if (widget.type == 'brand') return widget.store.catalog.brands;
    return widget.store.catalog.units;
  }

  Future<void> _saveItem(CatalogItem item) async {
    if (widget.type == 'category') {
      await widget.store.catalog.addOrUpdateCategory(item);
    } else if (widget.type == 'brand') {
      await widget.store.catalog.addOrUpdateBrand(item);
    } else {
      await widget.store.catalog.addOrUpdateUnit(item);
    }
    setState(() {});
  }

  Future<void> _add(BuildContext context) async {
    final result = await showDialog<CatalogItem>(
        context: context,
        builder: (_) => _CatalogItemDialog(type: widget.type));
    if (result == null) return;
    await _saveItem(result);
  }

  Future<void> _edit(BuildContext context, CatalogItem item) async {
    final result = await showDialog<CatalogItem>(
        context: context,
        builder: (_) => _CatalogItemDialog(type: widget.type, item: item));
    if (result == null) return;
    await _saveItem(result);
  }

  bool get _supportsDelete =>
      widget.type == 'category' || widget.type == 'unit';

  Future<void> _delete(BuildContext context, CatalogItem item) async {
    if (!_supportsDelete) return;
    final tr = AppLocalizations.of(context);
    final language = tr.locale.languageCode;
    final usageCount = widget.store.catalog.productsUsingCatalogItem(widget.type, item);
    final alternatives = _items.where((entry) => entry.id != item.id).toList();

    if (alternatives.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('catalog_delete_last_item_error'))),
      );
      return;
    }

    CatalogItem? replacement =
        alternatives.isNotEmpty ? alternatives.first : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr.text('confirm_delete')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                usageCount == 0
                    ? tr
                        .text('catalog_delete_unused_confirm')
                        .replaceAll('{name}', item.displayName(language))
                    : tr
                        .text('catalog_replace_delete_confirm')
                        .replaceAll('{name}', item.displayName(language))
                        .replaceAll('{count}', usageCount.toString()),
              ),
              if (usageCount > 0) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<CatalogItem>(
                  initialValue: replacement,
                  decoration: InputDecoration(
                    labelText: tr.text('catalog_replacement_item'),
                  ),
                  items: alternatives
                      .map(
                        (entry) => DropdownMenuItem<CatalogItem>(
                          value: entry,
                          child: Text(entry.displayName(language)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => replacement = value),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton.icon(
              onPressed: usageCount > 0 && replacement == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline),
              label: Text(usageCount > 0
                  ? tr.text('replace_and_delete')
                  : tr.text('delete')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.store.catalog.replaceAndDeleteCatalogItem(
        type: widget.type,
        item: item,
        replacement: usageCount > 0 ? replacement : null,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(tr.text('catalog_item_deleted'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final language = tr.locale.languageCode;
    final dialogWidth = VentioResponsive.modalMaxWidth(context, 840);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: VentioResponsive.pagePadding(context),
        vertical: 24,
      ),
      constraints: BoxConstraints(maxWidth: dialogWidth),
      title: Text(widget.type == 'category'
          ? tr.text('manage_categories')
          : widget.type == 'unit'
              ? tr.text('manage_units')
              : tr.text('manage_lookup_items')),
      content: SizedBox(
        width: dialogWidth,
        child: ResponsiveDialogBox(
          maxWidth: dialogWidth,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _items[index];
              return ListTile(
                title: Text(item.displayName(language)),
                subtitle: Text([item.nameEn, item.nameAr, item.code]
                    .where((value) => value.trim().isNotEmpty)
                    .join(' • ')),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: tr.text('edit'),
                      onPressed: () => _edit(context, item),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    if (_supportsDelete)
                      IconButton(
                        tooltip: tr.text('delete'),
                        onPressed: () => _delete(context, item),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton.icon(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: Text(tr.text('add_lookup_item'))),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr.text('close'))),
      ],
    );
  }
}
