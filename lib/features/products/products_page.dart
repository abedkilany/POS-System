import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../models/catalog_item.dart';
import '../../models/product.dart';
import '../../models/supplier.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String query = '';
  String categoryFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final currency = widget.store.storeProfile.currency;
    final products = _filteredProducts(widget.store.products);
    final categories = <String>{'All', ...widget.store.products.map((p) => p.category).where((e) => e.trim().isNotEmpty)}.toList()..sort();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          AppSectionHeader(
            title: tr.text('products'),
            subtitle: tr.text('products_page_desc'),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.store.canManageProducts ? () => _openCatalogManager(context, 'category') : null,
                  icon: const Icon(Icons.category_outlined),
                  label: Text(tr.text('manage_categories')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.store.canManageProducts ? () => _openCatalogManager(context, 'unit') : null,
                  icon: const Icon(Icons.straighten_outlined),
                  label: Text(tr.text('manage_units')),
                ),
                FilledButton.icon(
                  onPressed: widget.store.canManageProducts ? () => _openProductForm(context) : null,
                  icon: const Icon(Icons.add),
                  label: Text(tr.text('add_product')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final searchField = TextField(
                decoration: InputDecoration(hintText: tr.text('search_products_pro'), prefixIcon: const Icon(Icons.search)),
                onChanged: (value) => setState(() => query = value),
              );
              final categoryField = DropdownButtonFormField<String>(
                value: categoryFilter,
                decoration: InputDecoration(labelText: tr.text('category')),
                items: categories.map((item) => DropdownMenuItem(value: item, child: Text(item == 'All' ? tr.text('all') : item))).toList(),
                onChanged: (value) => setState(() => categoryFilter = value ?? 'All'),
              );
              if (constraints.maxWidth < 620) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [searchField, const SizedBox(height: 12), categoryField]);
              }
              return Row(children: [Expanded(child: searchField), const SizedBox(width: 12), SizedBox(width: 220, child: categoryField)]);
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: products.isEmpty
                ? EmptyStateCard(icon: Icons.inventory_2_outlined, title: tr.text('no_products'), subtitle: tr.text('no_products_desc'))
                : ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return _ProductTile(
                        product: product,
                        currency: currency,
                        onEdit: widget.store.canManageProducts ? () => _openProductForm(context, product: product) : null,
                        onDelete: widget.store.canDeleteOrCancel ? () => _deleteProduct(context, product) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<Product> _filteredProducts(List<Product> source) {
    final value = query.trim().toLowerCase();
    return source.where((product) {
      final matchesQuery = value.isEmpty ||
          product.name.toLowerCase().contains(value) ||
          product.nameEn.toLowerCase().contains(value) ||
          product.nameAr.toLowerCase().contains(value) ||
          product.code.toLowerCase().contains(value) ||
          product.barcode.toLowerCase().contains(value) ||
          product.category.toLowerCase().contains(value) ||
          product.brand.toLowerCase().contains(value) ||
          product.supplier.toLowerCase().contains(value);
      final matchesCategory = categoryFilter == 'All' || product.category == categoryFilter;
      return matchesQuery && matchesCategory;
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _deleteProduct(BuildContext context, Product product) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr.text('confirm_delete')),
        content: Text('${tr.text('delete_confirm_message')} ${product.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirmed == true) await widget.store.deleteProduct(product.id);
  }


  Future<void> _openCatalogManager(BuildContext context, String type) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CatalogManagerDialog(store: widget.store, type: type),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openProductForm(BuildContext context, {Product? product}) async {
    final tr = AppLocalizations.of(context);
    final result = await showDialog<Product>(
      context: context,
      builder: (_) => _ProductDialog(store: widget.store, product: product),
    );
    if (result == null) return;
    try {
      await widget.store.addOrUpdateProduct(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(product == null ? tr.text('product_saved') : tr.text('product_updated'))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Invalid argument(s): ', ''))));
      }
    }
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.currency, this.onEdit, this.onDelete});

  final Product product;
  final String currency;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [product.code, product.barcode, product.category, product.brand, product.supplier].where((e) => e.trim().isNotEmpty).join(' • ');
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(product.isActive ? Icons.inventory_2_outlined : Icons.block_outlined)),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Text('${product.stock} ${product.unit} • ${formatCurrency(product.price, currency: currency)}'),
            ),
            IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
            IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
          ],
        ),
      ),
    );
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({required this.store, this.product});

  final AppStore store;
  final Product? product;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController barcodeController;
  late final TextEditingController codeController;
  late final TextEditingController nameEnController;
  late final TextEditingController nameArController;
  late final TextEditingController descriptionController;
  late final TextEditingController priceController;
  late final TextEditingController costController;
  late final TextEditingController stockController;
  late final TextEditingController lowStockController;
  String category = '';
  String brand = '';
  String supplier = '';
  String unit = 'pcs';
  bool trackStock = true;
  bool isActive = true;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    barcodeController = TextEditingController(text: product?.barcode ?? '');
    codeController = TextEditingController(text: product?.code ?? _generateUniqueSku());
    nameEnController = TextEditingController(text: product?.nameEn.isNotEmpty == true ? product!.nameEn : product?.name ?? '');
    nameArController = TextEditingController(text: product?.nameAr ?? '');
    descriptionController = TextEditingController(text: product?.description ?? '');
    priceController = TextEditingController(text: product?.price.toString() ?? '');
    costController = TextEditingController(text: product?.cost.toString() ?? '');
    stockController = TextEditingController(text: product?.stock.toString() ?? '');
    lowStockController = TextEditingController(text: (product?.lowStockThreshold ?? 5).toString());
    category = product?.category ?? (widget.store.categories.isNotEmpty ? widget.store.categories.first.code.isNotEmpty ? widget.store.categories.first.code : widget.store.categories.first.nameEn : 'General');
    brand = product?.brand ?? '';
    supplier = product?.supplier ?? '';
    unit = product?.unit ?? (widget.store.units.isNotEmpty ? widget.store.units.first.code : 'pcs');
    trackStock = product?.trackStock ?? true;
    isActive = product?.isActive ?? true;
  }

  @override
  void dispose() {
    barcodeController.dispose();
    codeController.dispose();
    nameEnController.dispose();
    nameArController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    costController.dispose();
    stockController.dispose();
    lowStockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final width = math.min(MediaQuery.sizeOf(context).width - 32, 760).toDouble();
    return AlertDialog(
      title: Text(widget.product == null ? tr.text('add_product') : tr.text('edit_product')),
      content: SizedBox(
        width: width,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ResponsiveFields(children: [
                  TextFormField(controller: barcodeController, decoration: InputDecoration(labelText: tr.text('barcode'))),
                  TextFormField(controller: codeController, decoration: InputDecoration(labelText: tr.text('sku_code')), validator: _uniqueSku),
                  TextFormField(controller: nameEnController, decoration: InputDecoration(labelText: tr.text('product_name_en')), validator: _nameRequired),
                  TextFormField(controller: nameArController, decoration: InputDecoration(labelText: tr.text('product_name_ar'))),
                  _CatalogDropdown(
                    label: tr.text('category'),
                    value: category,
                    items: widget.store.categories,
                    onChanged: (value) => setState(() => category = value),
                    onAdd: () => _addCatalogItem(context, 'category'),
                    onManage: () => _manageCatalogItems(context, 'category'),
                  ),
                  _CatalogDropdown(
                    label: tr.text('brand'),
                    value: brand,
                    items: widget.store.brands,
                    onChanged: (value) => setState(() => brand = value),
                    onAdd: () => _addCatalogItem(context, 'brand'),
                    onManage: () => _manageCatalogItems(context, 'brand'),
                  ),
                  _SupplierDropdown(
                    value: supplier,
                    suppliers: widget.store.suppliers,
                    onChanged: (value) => setState(() => supplier = value),
                    onAdd: () => _addSupplier(context),
                    onManage: () {},
                  ),
                  _CatalogDropdown(
                    label: tr.text('unit'),
                    value: unit,
                    items: widget.store.units,
                    onChanged: (value) => setState(() => unit = value),
                    onAdd: () => _addCatalogItem(context, 'unit'),
                    onManage: () => _manageCatalogItems(context, 'unit'),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(controller: descriptionController, decoration: InputDecoration(labelText: tr.text('description')), minLines: 2, maxLines: 3),
                const SizedBox(height: 12),
                _ResponsiveFields(children: [
                  TextFormField(controller: priceController, decoration: InputDecoration(labelText: tr.text('sale_price')), keyboardType: TextInputType.number, validator: _nonNegativeNumber),
                  TextFormField(controller: costController, decoration: InputDecoration(labelText: tr.text('cost_price')), keyboardType: TextInputType.number, validator: _nonNegativeNumber),
                  TextFormField(controller: stockController, decoration: InputDecoration(labelText: tr.text('opening_stock')), keyboardType: TextInputType.number, validator: _nonNegativeInteger),
                  TextFormField(controller: lowStockController, decoration: InputDecoration(labelText: tr.text('low_stock_alert')), keyboardType: TextInputType.number, validator: _nonNegativeInteger),
                ]),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr.text('track_stock')), value: trackStock, onChanged: (value) => setState(() => trackStock = value)),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr.text('active_product')), value: isActive, onChanged: (value) => setState(() => isActive = value)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
        FilledButton(onPressed: _save, child: Text(tr.text('save'))),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final nameEn = nameEnController.text.trim();
    final nameAr = nameArController.text.trim();
    Navigator.pop(
      context,
      Product(
        id: widget.product?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: nameEn.isNotEmpty ? nameEn : nameAr,
        nameEn: nameEn,
        nameAr: nameAr,
        code: _resolvedSku(),
        barcode: barcodeController.text.trim(),
        category: category.trim(),
        brand: brand.trim(),
        supplier: supplier.trim(),
        description: descriptionController.text.trim(),
        price: double.tryParse(priceController.text.trim()) ?? 0,
        cost: double.tryParse(costController.text.trim()) ?? 0,
        stock: int.tryParse(stockController.text.trim()) ?? 0,
        lowStockThreshold: int.tryParse(lowStockController.text.trim()) ?? 5,
        unit: unit.trim().isEmpty ? 'pcs' : unit.trim(),
        trackStock: trackStock,
        isActive: isActive,
      ),
    );
  }

  Future<void> _addCatalogItem(BuildContext context, String type) async {
    final item = await showDialog<CatalogItem>(context: context, builder: (_) => _CatalogItemDialog(type: type));
    if (item == null) return;
    if (type == 'category') {
      await widget.store.addOrUpdateCategory(item);
      setState(() => category = item.nameEn.trim().isNotEmpty ? item.nameEn.trim() : item.nameAr.trim());
    } else if (type == 'brand') {
      await widget.store.addOrUpdateBrand(item);
      setState(() => brand = item.nameEn.trim().isNotEmpty ? item.nameEn.trim() : item.nameAr.trim());
    } else {
      await widget.store.addOrUpdateUnit(item);
      setState(() => unit = item.code.trim().isNotEmpty ? item.code.trim() : item.nameEn.trim());
    }
  }

  Future<void> _manageCatalogItems(BuildContext context, String type) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CatalogManagerDialog(store: widget.store, type: type),
    );
    setState(() {});
  }

  Future<void> _addSupplier(BuildContext context) async {
    final supplierName = await showDialog<String>(context: context, builder: (_) => const _QuickSupplierDialog());
    if (supplierName == null || supplierName.trim().isEmpty) return;
    await widget.store.addOrUpdateSupplier(
      Supplier(id: DateTime.now().microsecondsSinceEpoch.toString(), name: supplierName.trim(), nameEn: supplierName.trim(), nameAr: '', phone: '', address: '', notes: ''),
    );
    setState(() => supplier = supplierName.trim());
  }

  String _resolvedSku() => codeController.text.trim().isEmpty ? _generateUniqueSku() : codeController.text.trim();

  String _generateUniqueSku() {
    final used = widget.store.products.where((item) => item.id != widget.product?.id).map((item) => item.code.trim().toUpperCase()).toSet();
    var counter = widget.store.products.length + 1;
    while (true) {
      final candidate = 'PRD-${counter.toString().padLeft(5, '0')}';
      if (!used.contains(candidate)) return candidate;
      counter++;
    }
  }

  String? _uniqueSku(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final exists = widget.store.products.any((item) => item.id != widget.product?.id && item.code.trim().toLowerCase() == normalized);
    return exists ? AppLocalizations.of(context).text('sku_already_exists') : null;
  }

  String? _nameRequired(String? value) {
    if ((value ?? '').trim().isNotEmpty || nameArController.text.trim().isNotEmpty) return null;
    return AppLocalizations.of(context).text('required');
  }

  String? _nonNegativeNumber(String? value) {
    final number = double.tryParse((value ?? '').trim());
    return number == null || number < 0 ? AppLocalizations.of(context).text('invalid_number') : null;
  }

  String? _nonNegativeInteger(String? value) {
    final number = int.tryParse((value ?? '').trim());
    return number == null || number < 0 ? AppLocalizations.of(context).text('invalid_number') : null;
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 620) {
        return Column(children: children.map((child) => Padding(padding: const EdgeInsets.only(bottom: 12), child: child)).toList());
      }
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children.map((child) => SizedBox(width: (constraints.maxWidth - 12) / 2, child: child)).toList(),
      );
    });
  }
}

class _CatalogDropdown extends StatelessWidget {
  const _CatalogDropdown({required this.label, required this.value, required this.items, required this.onChanged, required this.onAdd, required this.onManage});
  final String label;
  final String value;
  final List<CatalogItem> items;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final language = AppLocalizations.of(context).locale.languageCode;
    final values = <String>{...items.map((item) => item.code.isNotEmpty ? item.code : item.nameEn).where((e) => e.trim().isNotEmpty), if (value.trim().isNotEmpty) value}.toList();
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: value.trim().isEmpty ? null : value,
            decoration: InputDecoration(labelText: label),
            items: values.map((raw) {
              CatalogItem? match;
              for (final item in items) {
                if (item.code == raw || item.nameEn == raw || item.nameAr == raw) {
                  match = item;
                  break;
                }
              }
              return DropdownMenuItem(value: raw, child: Text(match?.displayName(language) ?? raw));
            }).toList(),
            onChanged: (newValue) => onChanged(newValue ?? ''),
          ),
        ),
        IconButton(onPressed: onAdd, icon: const Icon(Icons.add_circle_outline)),
        IconButton(onPressed: onManage, icon: const Icon(Icons.tune_outlined)),
      ],
    );
  }
}

class _SupplierDropdown extends StatelessWidget {
  const _SupplierDropdown({required this.value, required this.suppliers, required this.onChanged, required this.onAdd, required this.onManage});
  final String value;
  final List<Supplier> suppliers;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final values = <String>{...suppliers.map((item) => item.name as String).where((e) => e.trim().isNotEmpty), if (value.trim().isNotEmpty) value}.toList();
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: value.trim().isEmpty ? null : value,
            decoration: InputDecoration(labelText: tr.text('supplier')),
            items: values.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (newValue) => onChanged(newValue ?? ''),
          ),
        ),
        IconButton(onPressed: onAdd, icon: const Icon(Icons.add_circle_outline)),
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
          TextField(controller: enController, decoration: InputDecoration(labelText: tr.text('name_en'))),
          const SizedBox(height: 12),
          TextField(controller: arController, decoration: InputDecoration(labelText: tr.text('name_ar'))),
          const SizedBox(height: 12),
          TextField(controller: codeController, decoration: InputDecoration(labelText: tr.text('code_optional'))),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, CatalogItem(id: widget.item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(), nameEn: enController.text.trim(), nameAr: arController.text.trim(), code: codeController.text.trim()));
          },
          child: Text(tr.text('save')),
        ),
      ],
    );
  }
}


class _CatalogManagerDialog extends StatefulWidget {
  const _CatalogManagerDialog({required this.store, required this.type});
  final AppStore store;
  final String type;

  @override
  State<_CatalogManagerDialog> createState() => _CatalogManagerDialogState();
}

class _CatalogManagerDialogState extends State<_CatalogManagerDialog> {
  List<CatalogItem> get _items {
    if (widget.type == 'category') return widget.store.categories;
    if (widget.type == 'brand') return widget.store.brands;
    return widget.store.units;
  }

  Future<void> _saveItem(CatalogItem item) async {
    if (widget.type == 'category') {
      await widget.store.addOrUpdateCategory(item);
    } else if (widget.type == 'brand') {
      await widget.store.addOrUpdateBrand(item);
    } else {
      await widget.store.addOrUpdateUnit(item);
    }
    setState(() {});
  }

  Future<void> _add(BuildContext context) async {
    final result = await showDialog<CatalogItem>(context: context, builder: (_) => _CatalogItemDialog(type: widget.type));
    if (result == null) return;
    await _saveItem(result);
  }

  Future<void> _edit(BuildContext context, CatalogItem item) async {
    final result = await showDialog<CatalogItem>(context: context, builder: (_) => _CatalogItemDialog(type: widget.type, item: item));
    if (result == null) return;
    await _saveItem(result);
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final language = tr.locale.languageCode;
    return AlertDialog(
      title: Text(widget.type == 'category' ? tr.text('manage_categories') : widget.type == 'unit' ? tr.text('manage_units') : tr.text('manage_lookup_items')),
      content: SizedBox(
        width: 520,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = _items[index];
            return ListTile(
              title: Text(item.displayName(language)),
              subtitle: Text([item.nameEn, item.nameAr, item.code].where((value) => value.trim().isNotEmpty).join(' • ')),
              trailing: IconButton(onPressed: () => _edit(context, item), icon: const Icon(Icons.edit_outlined)),
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add), label: Text(tr.text('add_lookup_item'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('close'))),
      ],
    );
  }
}

class _QuickSupplierDialog extends StatefulWidget {
  const _QuickSupplierDialog();
  @override
  State<_QuickSupplierDialog> createState() => _QuickSupplierDialogState();
}


class _QuickSupplierDialogState extends State<_QuickSupplierDialog> {
  final controller = TextEditingController();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(tr.text('add_supplier')),
      content: TextField(controller: controller, decoration: InputDecoration(labelText: tr.text('supplier_name'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr.text('save'))),
      ],
    );
  }
}
