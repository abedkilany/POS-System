import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../models/catalog_item.dart';
import '../../models/product.dart';
import '../../models/store_profile.dart';
import '../../models/supplier.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';
import '../barcode/barcode_scanner_page.dart';

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
    final products = _filteredProducts(widget.store.products);
    final categories = <String>{'All', ...widget.store.products.map((p) => p.category).where((e) => e.trim().isNotEmpty)}.toList()..sort();

    return Padding(
      padding: VentioResponsive.pageInsets(context),
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
                initialValue: categoryFilter,
                decoration: InputDecoration(labelText: tr.text('category')),
                items: categories.map((item) => DropdownMenuItem(value: item, child: Text(item == 'All' ? tr.text('all') : item))).toList(),
                onChanged: (value) => setState(() => categoryFilter = value ?? 'All'),
              );
              if (constraints.maxWidth < 620) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [searchField, const SizedBox(height: 12), categoryField]);
              }
              return Row(children: [Expanded(child: searchField), const SizedBox(width: 12), SizedBox(width: VentioResponsive.adaptiveWidth(context, mobile: 160, tablet: 200, desktop: 220), child: categoryField)]);
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
                        store: widget.store,
                        storeProfile: widget.store.storeProfile,
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
    final result = await showDialog<_ProductFormResult>(
      context: context,
      builder: (_) => _ProductDialog(store: widget.store, product: product),
    );
    if (result == null) return;
    try {
      await widget.store.addOrUpdateProduct(result.product);
      if (result.addToQuickProducts) {
        await _addProductToQuickProducts(result.product, tr);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(product == null ? tr.text('product_saved') : tr.text('product_updated'))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Invalid argument(s): ', ''))));
      }
    }
  }

  Future<void> _addProductToQuickProducts(Product product, AppLocalizations tr) async {
    const storageKey = 'sale_quick_product_pages_v1';
    List<dynamic> pages;
    try {
      final raw = LocalDatabaseService.getString(storageKey);
      pages = raw == null || raw.trim().isEmpty ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      pages = <dynamic>[];
    }
    if (pages.isEmpty) {
      pages = [
        {
          'name': tr.text('page') == 'page' ? 'Page 1' : '${tr.text('page')} 1',
          'slots': List.generate(12, (_) => {'productId': null, 'shortName': null}),
        }
      ];
    }
    final shortName = (product.nameAr.trim().isNotEmpty ? product.nameAr.trim() : product.name.trim()).trim();
    for (final page in pages) {
      if (page is! Map) continue;
      final slots = page['slots'];
      if (slots is! List) continue;
      for (var i = 0; i < slots.length; i++) {
        final slot = slots[i];
        if (slot is Map && slot['productId'] == product.id) return;
      }
    }
    for (final page in pages) {
      if (page is! Map) continue;
      final slots = page['slots'];
      if (slots is! List) continue;
      for (var i = 0; i < slots.length; i++) {
        final slot = slots[i];
        final isEmpty = slot is! Map || (slot['productId'] as String?)?.trim().isEmpty != false;
        if (isEmpty) {
          slots[i] = {'productId': product.id, 'shortName': shortName.length > 14 ? shortName.substring(0, 14) : shortName};
          await LocalDatabaseService.setString(storageKey, jsonEncode(pages));
          return;
        }
      }
    }
    final first = pages.first;
    if (first is Map) {
      final slots = first['slots'];
      if (slots is List) {
        slots.add({'productId': product.id, 'shortName': shortName.length > 14 ? shortName.substring(0, 14) : shortName});
      }
    }
    await LocalDatabaseService.setString(storageKey, jsonEncode(pages));
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.store, required this.storeProfile, this.onEdit, this.onDelete});

  final Product product;
  final AppStore store;
  final StoreProfile storeProfile;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [product.code, product.barcode, product.category, product.brand, product.supplier].where((e) => e.trim().isNotEmpty).join(' • ');
    final lastPurchase = store.lastPurchasePriceForProduct(product.id);
    final avgPurchase = store.averagePurchaseCostForProduct(product.id);
    final supplierCount = store.supplierCountForProduct(product.id);
    final meta = product.trackStock
        ? '${product.stock} ${product.unit} • ${formatUsdReferenceAmount(product.price, storeProfile)}'
        : 'Non-stock / service • ${formatUsdReferenceAmount(product.price, storeProfile)}';
    final purchaseMeta = [
      if (lastPurchase != null) 'Last cost ${formatUsdReferenceAmount(lastPurchase, storeProfile)}',
      if (avgPurchase > 0) 'Avg cost ${formatUsdReferenceAmount(avgPurchase, storeProfile)}',
      if (supplierCount > 0) '$supplierCount suppliers',
    ].join(' • ');
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Padding(
              padding: VentioResponsive.cardInsets(context),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(child: Icon(product.isActive ? Icons.inventory_2_outlined : Icons.block_outlined)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 8),
                        Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                        if (purchaseMeta.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(purchaseMeta, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          children: [
                            IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), tooltip: AppLocalizations.of(context).text('edit')),
                            IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline), tooltip: AppLocalizations.of(context).text('delete')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListTile(
            leading: CircleAvatar(child: Icon(product.isActive ? Icons.inventory_2_outlined : Icons.block_outlined)),
            title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([subtitle, purchaseMeta].where((item) => item.trim().isNotEmpty).join('\n'), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  child: Text(meta),
                ),
                IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
                IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProductFormResult {
  const _ProductFormResult({required this.product, required this.addToQuickProducts});

  final Product product;
  final bool addToQuickProducts;
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
  String priceCurrency = 'USD';
  String costCurrency = 'USD';
  String brand = '';
  String supplier = '';
  String unit = 'pcs';
  ProductQuantityType quantityType = ProductQuantityType.countable;
  late List<_SaleUnitDraft> saleUnitDrafts;
  bool trackStock = true;
  bool isActive = true;
  bool addToQuickProducts = false;
  String imagePath = '';

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    barcodeController = TextEditingController(text: product?.barcode ?? '');
    codeController = TextEditingController(text: product?.code ?? _generateUniqueSku());
    nameEnController = TextEditingController(text: product?.nameEn.isNotEmpty == true ? product!.nameEn : product?.name ?? '');
    nameArController = TextEditingController(text: product?.nameAr ?? '');
    descriptionController = TextEditingController(text: product?.description ?? '');
    priceCurrency = product?.originalCurrency ?? widget.store.storeProfile.defaultProductCurrency;
    costCurrency = product?.costCurrency ?? widget.store.storeProfile.defaultProductCurrency;
    priceController = TextEditingController(text: product?.originalPrice.toString() ?? '');
    costController = TextEditingController(text: product?.originalCost.toString() ?? '');
    stockController = TextEditingController(text: product?.stock.toString() ?? '');
    lowStockController = TextEditingController(text: (product?.lowStockThreshold ?? 5).toString());
    imagePath = product?.imagePath ?? '';
    category = product?.category ?? (widget.store.categories.isNotEmpty ? widget.store.categories.first.code.isNotEmpty ? widget.store.categories.first.code : widget.store.categories.first.nameEn : 'General');
    brand = product?.brand ?? '';
    supplier = product?.supplier ?? '';
    unit = product?.unit ?? (widget.store.units.isNotEmpty ? widget.store.units.first.code : 'pcs');
    quantityType = product?.quantityType ?? ProductQuantityType.countable;
    saleUnitDrafts = (product?.saleUnits ?? const []).map(_SaleUnitDraft.fromSaleUnit).toList();
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

  bool get _canUseCameraScanner =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _scanBarcodeWithCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    setState(() => barcodeController.text = code.trim());
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
                _ProductFormSection(
                  icon: Icons.inventory_2_outlined,
                  title: tr.text('basic_information'),
                  children: [
                    _ProductImagePicker(
                      imagePath: imagePath,
                      onPick: _pickProductImage,
                      onClear: imagePath.trim().isEmpty ? null : () => setState(() => imagePath = ''),
                    ),
                    const SizedBox(height: 12),
                    _ResponsiveFields(children: [
                      TextFormField(
                        controller: barcodeController,
                        decoration: InputDecoration(
                          labelText: tr.text('barcode'),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: tr.text('generate_barcode'),
                                onPressed: _generateBarcode,
                                icon: const Icon(Icons.qr_code_2_outlined),
                              ),
                              IconButton(
                                tooltip: tr.text('copy_barcode'),
                                onPressed: _copyBarcode,
                                icon: const Icon(Icons.copy_outlined),
                              ),
                              if (_canUseCameraScanner)
                                IconButton(
                                  tooltip: tr.text('scan_with_camera'),
                                  onPressed: _scanBarcodeWithCamera,
                                  icon: const Icon(Icons.camera_alt_outlined),
                                ),
                            ],
                          ),
                        ),
                      ),
                      TextFormField(controller: nameEnController, decoration: InputDecoration(labelText: '${tr.text('product_name_en')} *'), validator: (_) => _nameRequired()),
                      TextFormField(controller: nameArController, decoration: InputDecoration(labelText: '${tr.text('product_name_ar')} *'), validator: (_) => _nameRequired()),
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
                      DropdownButtonFormField<ProductQuantityType>(
                        initialValue: quantityType,
                        decoration: InputDecoration(labelText: tr.text('quantity_type')),
                        items: [
                          DropdownMenuItem(value: ProductQuantityType.countable, child: Text(tr.text('quantity_type_countable'))),
                          DropdownMenuItem(value: ProductQuantityType.measurable, child: Text(tr.text('quantity_type_measurable'))),
                        ],
                        onChanged: (value) => setState(() => quantityType = value ?? ProductQuantityType.countable),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(tr.text('advanced_sku')),
                      subtitle: Text('${tr.text('auto_generated')}: ${codeController.text}'),
                      children: [
                        TextFormField(controller: codeController, decoration: InputDecoration(labelText: tr.text('sku_code')), validator: _uniqueSku),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(controller: descriptionController, decoration: InputDecoration(labelText: tr.text('description')), minLines: 2, maxLines: 3),
                  ],
                ),
                const SizedBox(height: 12),
                _ProductFormSection(
                  icon: Icons.payments_outlined,
                  title: tr.text('pricing'),
                  initiallyExpanded: true,
                  children: [
                    _ResponsiveFields(children: [
                      _MoneyField(controller: priceController, currency: priceCurrency, label: tr.text('sale_price'), currencyLabel: tr.text('price_currency'), validator: _nonNegativeNumber, onCurrencyChanged: (value) => setState(() => priceCurrency = value)),
                      _MoneyField(controller: costController, currency: costCurrency, label: tr.text('cost_price'), currencyLabel: tr.text('cost_currency'), validator: _nonNegativeNumber, onCurrencyChanged: (value) => setState(() => costCurrency = value)),
                    ]),
                  ],
                ),
                const SizedBox(height: 12),
                _ProductFormSection(
                  icon: Icons.warehouse_outlined,
                  title: tr.text('inventory_stock'),
                  children: [
                    SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr.text('track_quantity')), subtitle: Text(tr.text('track_quantity_help')), value: trackStock, onChanged: (value) => setState(() => trackStock = value)),
                    _ResponsiveFields(children: [
                      TextFormField(enabled: trackStock, controller: stockController, decoration: InputDecoration(labelText: tr.text('opening_stock'), helperText: trackStock ? null : tr.text('stock_ignored_non_stock')), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: trackStock ? (quantityType == ProductQuantityType.measurable ? _nonNegativeNumber : _nonNegativeInteger) : null),
                      TextFormField(enabled: trackStock, controller: lowStockController, decoration: InputDecoration(labelText: tr.text('low_stock_alert'), helperText: trackStock ? null : tr.text('no_low_stock_alerts_non_stock')), keyboardType: TextInputType.number, validator: trackStock ? _nonNegativeInteger : null),
                    ]),
                  ],
                ),
                const SizedBox(height: 12),
                _ProductFormSection(
                  icon: Icons.view_module_outlined,
                  title: tr.text('sale_units'),
                  children: [
                    _SaleUnitsEditor(
                      saleUnits: saleUnitDrafts,
                      storeProfile: widget.store.storeProfile,
                      onChanged: (items) => setState(() => saleUnitDrafts = items),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr.text('add_to_quick_products')), subtitle: Text(tr.text('add_to_quick_products_help')), value: addToQuickProducts, onChanged: (value) => setState(() => addToQuickProducts = value)),
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


  Future<void> _pickProductImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    final file = result?.files.single;
    if (file == null) return;
    setState(() => imagePath = file.path ?? file.name);
  }

  Future<void> _copyBarcode() async {
    final tr = AppLocalizations.of(context);
    final code = barcodeController.text.trim();
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('barcode_copied'))));
  }

  void _generateBarcode() {
    final value = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() => barcodeController.text = value);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final nameEn = nameEnController.text.trim();
    final nameAr = nameArController.text.trim();
    final originalPrice = double.tryParse(priceController.text.trim()) ?? 0;
    final originalCost = double.tryParse(costController.text.trim()) ?? 0;
    final rate = widget.store.storeProfile.usdToLbpRate;
    final usdPrice = toUsdReferencePrice(originalPrice, priceCurrency, widget.store.storeProfile);
    final usdCost = toUsdReferencePrice(originalCost, costCurrency, widget.store.storeProfile);
    Navigator.pop(
      context,
      _ProductFormResult(
        addToQuickProducts: addToQuickProducts,
        product: Product(
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
        price: usdPrice,
        originalPrice: originalPrice,
        originalCurrency: priceCurrency,
        usdPrice: usdPrice,
        exchangeRateAtEntry: rate,
        cost: usdCost,
        originalCost: originalCost,
        costCurrency: costCurrency,
        usdCost: usdCost,
        costExchangeRateAtEntry: rate,
        stock: trackStock ? (double.tryParse(stockController.text.trim()) ?? 0) : 0,
        lowStockThreshold: trackStock ? (int.tryParse(lowStockController.text.trim()) ?? 5) : 0,
        unit: unit.trim().isEmpty ? 'pcs' : unit.trim(),
        quantityType: quantityType,
        saleUnits: saleUnitDrafts.map((item) => item.toSaleUnit(widget.store.storeProfile)).where((item) => item.name.trim().isNotEmpty && item.conversionToBase > 0).toList(),
        trackStock: trackStock,
        isActive: isActive,
        createdAt: widget.product?.createdAt,
        updatedAt: widget.product?.updatedAt,
        deletedAt: widget.product?.deletedAt,
        deviceId: widget.product?.deviceId ?? '',
        syncStatus: widget.product?.syncStatus ?? 'pending',
        storeId: widget.product?.storeId ?? '',
        branchId: widget.product?.branchId ?? '',
        version: widget.product?.version ?? 1,
        lastModifiedByDeviceId: widget.product?.lastModifiedByDeviceId ?? '',
        imagePath: imagePath.trim(),
      ),
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

  String? _nameRequired() {
    if (nameEnController.text.trim().isNotEmpty || nameArController.text.trim().isNotEmpty) return null;
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

class _SaleUnitDraft {
  _SaleUnitDraft({required this.id, this.name = '', this.conversionToBase = '1', this.price = '', this.priceCurrency = 'USD', this.barcode = ''});

  final String id;
  String name;
  String conversionToBase;
  String price;
  String priceCurrency;
  String barcode;

  factory _SaleUnitDraft.fromSaleUnit(ProductSaleUnit unit) => _SaleUnitDraft(
        id: unit.id.trim().isNotEmpty ? unit.id : DateTime.now().microsecondsSinceEpoch.toString(),
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

class _SaleUnitsEditor extends StatelessWidget {
  const _SaleUnitsEditor({required this.saleUnits, required this.storeProfile, required this.onChanged});

  final List<_SaleUnitDraft> saleUnits;
  final StoreProfile storeProfile;
  final ValueChanged<List<_SaleUnitDraft>> onChanged;

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
                Expanded(child: Text(tr.text('sale_units'), style: const TextStyle(fontWeight: FontWeight.w700))),
                TextButton.icon(
                  onPressed: () {
                    final next = List<_SaleUnitDraft>.from(saleUnits)
                      ..add(_SaleUnitDraft(id: DateTime.now().microsecondsSinceEpoch.toString()));
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
                          Expanded(child: Text(tr.format('unit_number', {'number': index + 1}), style: Theme.of(context).textTheme.labelLarge)),
                          IconButton(
                            onPressed: () {
                              final next = List<_SaleUnitDraft>.from(saleUnits)..removeAt(index);
                              onChanged(next);
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      _ResponsiveFields(children: [
                        TextFormField(
                          initialValue: unit.name,
                          decoration: InputDecoration(labelText: tr.text('unit_name')),
                          onChanged: (value) => unit.name = value,
                        ),
                        TextFormField(
                          initialValue: unit.conversionToBase,
                          decoration: InputDecoration(labelText: tr.text('conversion_to_base')),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            final number = double.tryParse((value ?? '').trim());
                            return number == null || number <= 0 ? tr.text('invalid_number') : null;
                          },
                          onChanged: (value) => unit.conversionToBase = value,
                        ),
                        TextFormField(
                          initialValue: unit.price,
                          decoration: InputDecoration(labelText: tr.text('unit_sale_price')),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            final number = double.tryParse((value ?? '').trim());
                            return number == null || number < 0 ? tr.text('invalid_number') : null;
                          },
                          onChanged: (value) => unit.price = value,
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: unit.priceCurrency,
                          decoration: InputDecoration(labelText: tr.text('price_currency')),
                          items: const [
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                            DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                          ],
                          onChanged: (value) => unit.priceCurrency = value ?? 'USD',
                        ),
                        TextFormField(
                          initialValue: unit.barcode,
                          decoration: InputDecoration(labelText: tr.text('unit_barcode')),
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
  const _ProductFormSection({required this.icon, required this.title, required this.children, this.initiallyExpanded = false});

  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: children,
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.currency, required this.label, required this.currencyLabel, required this.validator, required this.onCurrencyChanged});

  final TextEditingController controller;
  final String currency;
  final String label;
  final String currencyLabel;
  final FormFieldValidator<String> validator;
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
    );
  }
}

class _ProductImagePicker extends StatelessWidget {
  const _ProductImagePicker({required this.imagePath, required this.onPick, this.onClear});

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
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            child: Icon(hasImage ? Icons.image_outlined : Icons.add_photo_alternate_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('product_image'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(hasImage ? imagePath.split('/').last : tr.text('product_image_help'), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton.icon(onPressed: onPick, icon: const Icon(Icons.photo_camera_outlined), label: Text(tr.text('choose'))),
          if (onClear != null) IconButton(onPressed: onClear, icon: const Icon(Icons.close)),
        ],
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
            initialValue: value.trim().isEmpty ? null : value,
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
    final values = <String>{...suppliers.map((item) => item.name).where((e) => e.trim().isNotEmpty), if (value.trim().isNotEmpty) value}.toList();
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value.trim().isEmpty ? null : value,
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
      content: ResponsiveDialogBox(
        maxWidth: VentioResponsive.modalMaxWidth(context, 520),
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

