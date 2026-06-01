import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/purchase_item.dart';
import '../../models/store_profile.dart';
import '../../models/supplier.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  String _formatQuantity(double value) => value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final purchases = widget.store.purchases;
    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('purchases'), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(tr.text('purchases_desc')),
            ],
          );
          final button = FilledButton.icon(
            onPressed: () => _openPurchaseDialog(context),
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(tr.text('new_purchase')),
          );
          return compact
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), button])
              : Row(children: [Expanded(child: title), button]);
        }),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(label: tr.text('purchase_total'), value: formatUsdReferenceAmount(widget.store.totalPurchasesAmount, widget.store.storeProfile), icon: Icons.shopping_cart_checkout),
            _MetricCard(label: tr.text('pending_purchases'), value: '${widget.store.pendingPurchaseCount}', icon: Icons.pending_actions),
            _MetricCard(label: tr.text('received_purchases'), value: '${purchases.where((p) => p.isReceived).length}', icon: Icons.done_all),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: purchases.isEmpty
              ? Padding(padding: VentioResponsive.pageInsets(context), child: Text(tr.text('no_purchases_yet')))
              : Column(
                  children: [
                    for (final purchase in purchases) ...[
                      _PurchaseTile(
                        purchase: purchase,
                        storeProfile: widget.store.storeProfile,
                        onReceive: purchase.status == 'Draft' ? () => _receivePurchase(context, purchase.id) : null,
                        onCancel: !purchase.isCancelled ? () => _cancelPurchase(context, purchase.id) : null,
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _receivePurchase(BuildContext context, String id) async {
    try {
      await widget.store.receivePurchase(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('purchase_received'))));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _cancelPurchase(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('cancel_purchase')),
        content: Text(AppLocalizations.of(context).text('cancel_purchase_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppLocalizations.of(context).text('confirm'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.store.cancelPurchase(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).text('purchase_cancelled'))));
      setState(() {});
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openPurchaseDialog(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final items = <PurchaseItem>[];
    var purchaseProducts = widget.store.products.where((product) => product.trackStock && product.isActive).toList();
    String supplierId = widget.store.suppliers.isNotEmpty ? widget.store.suppliers.first.id : '';
    String supplierName = widget.store.suppliers.isNotEmpty ? widget.store.suppliers.first.name : '';
    Product? selectedProduct = purchaseProducts.isNotEmpty ? purchaseProducts.first : null;
    ProductSaleUnit? selectedUnit = selectedProduct?.effectivePurchaseUnits.first;
    final qtyController = TextEditingController(text: '1');
    final costController = TextEditingController();
    final barcodeController = TextEditingController();
    final productSearchController = TextEditingController();
    final scannerController = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
    String costCurrency = selectedProduct?.costCurrency ?? widget.store.storeProfile.defaultProductCurrency;
    bool receiveNow = true;
    bool scannerActive = false;
    String productSearchQuery = '';
    String? lastScannedCode;
    DateTime? lastScannedAt;

    PurchaseItem? suggestedPurchaseItem(Product product) {
      return supplierId.isEmpty ? null : widget.store.lastPurchaseItemFor(productId: product.id, supplierId: supplierId);
    }

    double suggestedBaseCost(Product product) {
      return suggestedPurchaseItem(product)?.unitCostPerBase ?? widget.store.lastPurchasePriceForProduct(product.id) ?? product.usdCost;
    }

    String suggestedCostCurrency(Product product) {
      return suggestedPurchaseItem(product)?.unitCostCurrency ?? widget.store.lastPurchaseItemForProduct(product.id)?.unitCostCurrency ?? product.costCurrency;
    }

    void applySuggestedSupplierPrice() {
      final product = selectedProduct;
      final unit = selectedUnit;
      if (product == null || unit == null) {
        costController.text = '0';
        return;
      }
      costCurrency = suggestedCostCurrency(product);
      final suggested = suggestedBaseCost(product) * unit.conversionToBase;
      final displayCost = fromUsdReferencePrice(suggested, costCurrency, widget.store.storeProfile);
      costController.text = displayCost.toStringAsFixed(costCurrency == 'LBP' ? 0 : 2);
    }

    selectedUnit = selectedProduct?.effectivePurchaseUnits.first;
    applySuggestedSupplierPrice();

    String priceHintForSelectedProduct() {
      final product = selectedProduct;
      if (product == null) return '';
      final supplierPrice = supplierId.isEmpty
          ? null
          : widget.store.lastPurchasePriceFor(productId: product.id, supplierId: supplierId);
      final lastGeneral = widget.store.lastPurchasePriceForProduct(product.id);
      final avg = widget.store.averagePurchaseCostForProduct(product.id);
      final supplierCount = widget.store.supplierCountForProduct(product.id);
      final parts = <String>[];
      if (supplierPrice != null) parts.add('${tr.text('supplier_last_base')}: ${formatUsdReferenceAmount(supplierPrice, widget.store.storeProfile)}');
      if (lastGeneral != null) parts.add('${tr.text('last_base')}: ${formatUsdReferenceAmount(lastGeneral, widget.store.storeProfile)}');
      if (avg > 0) parts.add('${tr.text('avg_base')}: ${formatUsdReferenceAmount(avg, widget.store.storeProfile)}');
      if (supplierCount > 0) parts.add('$supplierCount ${tr.text(supplierCount == 1 ? 'supplier' : 'suppliers')}');
      return parts.join(' • ');
    }

    String unitConversionSummary(PurchaseItem item) {
      final unitName = item.purchaseUnitName.isEmpty ? tr.text('unit') : item.purchaseUnitName;
      return '${_formatQuantity(item.quantity)} $unitName = ${_formatQuantity(item.baseQuantity)} ${tr.text('base')} ${tr.text(item.baseQuantity == 1 ? 'unit' : 'units')}';
    }

    String selectedUnitConversionSummary() {
      final unit = selectedUnit;
      final qty = double.tryParse(qtyController.text.trim()) ?? 0;
      if (unit == null || qty <= 0) return '';
      return '${_formatQuantity(qty)} ${unit.name} = ${_formatQuantity(qty * unit.conversionToBase)} ${tr.text('base')} ${tr.text(qty * unit.conversionToBase == 1 ? 'unit' : 'units')}';
    }

    void showPurchaseError(String message) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }

    Future<bool> confirmDiscardIfNeeded(BuildContext confirmContext) async {
      if (items.isEmpty) return true;
      return await showDialog<bool>(
            context: confirmContext,
            builder: (alertContext) => AlertDialog(
              title: Text(tr.text('discard_purchase_title')),
              content: Text(tr.text('discard_purchase_message')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(alertContext, false), child: Text(tr.text('keep_editing'))),
                FilledButton(onPressed: () => Navigator.pop(alertContext, true), child: Text(tr.text('discard'))),
              ],
            ),
          ) ??
          false;
    }

    Future<void> createQuickSupplier(StateSetter setDialogState) async {
      final nameController = TextEditingController();
      final phoneController = TextEditingController();
      final created = await showModalBottomSheet<Supplier>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr.text('add_supplier'), style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(controller: nameController, decoration: InputDecoration(labelText: tr.text('supplier_name')), autofocus: true),
              const SizedBox(height: 12),
              TextField(controller: phoneController, decoration: InputDecoration(labelText: tr.text('phone'))),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: Text(tr.text('save')),
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(sheetContext, Supplier(
                    id: 'supplier_${DateTime.now().microsecondsSinceEpoch}',
                    name: name,
                    phone: phoneController.text.trim(),
                    address: '',
                    notes: '',
                  ));
                },
              ),
            ],
          ),
        ),
      );
      nameController.dispose();
      phoneController.dispose();
      if (created == null) return;
      try {
        await widget.store.addOrUpdateSupplier(created);
        supplierId = created.id;
        supplierName = created.name;
        setDialogState(() {});
      } catch (error) {
        if (mounted) showPurchaseError(error.toString());
      }
    }

    Future<void> createQuickProduct(StateSetter setDialogState) async {
      final nameController = TextEditingController();
      final barcodeQuickController = TextEditingController();
      final created = await showModalBottomSheet<Product>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr.text('add_product'), style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(controller: nameController, decoration: InputDecoration(labelText: tr.text('product_name')), autofocus: true),
              const SizedBox(height: 12),
              TextField(controller: barcodeQuickController, decoration: InputDecoration(labelText: tr.text('barcode'))),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: Text(tr.text('save')),
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final now = DateTime.now().microsecondsSinceEpoch;
                  Navigator.pop(sheetContext, Product(
                    id: 'product_$now',
                    name: name,
                    code: 'PRD-$now',
                    barcode: barcodeQuickController.text.trim(),
                    price: 0,
                    cost: 0,
                    stock: 0,
                    category: 'General',
                    unit: tr.text('unit'),
                    trackStock: true,
                    isActive: true,
                  ));
                },
              ),
            ],
          ),
        ),
      );
      nameController.dispose();
      barcodeQuickController.dispose();
      if (created == null) return;
      try {
        await widget.store.addOrUpdateProduct(created);
        selectedProduct = created;
        selectedUnit = created.effectivePurchaseUnits.first;
        purchaseProducts = widget.store.products.where((product) => product.trackStock && product.isActive).toList();
        applySuggestedSupplierPrice();
        setDialogState(() {});
      } catch (error) {
        if (mounted) showPurchaseError(error.toString());
      }
    }


    Future<void> editPurchaseLine(PurchaseItem item, StateSetter setDialogState) async {
      final productMatches = purchaseProducts.where((p) => p.id == item.productId).toList();
      if (productMatches.isEmpty) return;
      final product = productMatches.first;
      ProductSaleUnit editUnit = product.effectivePurchaseUnits.firstWhere((unit) => unit.id == item.purchaseUnitId, orElse: () => product.effectivePurchaseUnits.first);
      String editCurrency = item.unitCostCurrency;
      final editQtyController = TextEditingController(text: _formatQuantity(item.quantity));
      final editCostController = TextEditingController(text: (item.originalUnitCost ?? fromUsdReferencePrice(item.unitCost, editCurrency, widget.store.storeProfile)).toStringAsFixed(editCurrency == 'LBP' ? 0 : 2));
      final updated = await showModalBottomSheet<PurchaseItem>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        isDismissible: false,
        builder: (editContext) => StatefulBuilder(
          builder: (editContext, setEditState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(editContext).bottom),
              child: Material(
                clipBehavior: Clip.antiAlias,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(tr.text('edit_purchase_line'), style: Theme.of(editContext).textTheme.titleLarge)),
                              IconButton(
                                tooltip: tr.text('cancel'),
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(editContext),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: editUnit.id,
                            decoration: InputDecoration(labelText: tr.text('purchase_unit')),
                            items: product.effectivePurchaseUnits.map((unit) => DropdownMenuItem(value: unit.id, child: Text('${unit.name} × ${_formatQuantity(unit.conversionToBase)}'))).toList(),
                            onChanged: (value) {
                              final matches = product.effectivePurchaseUnits.where((unit) => unit.id == value).toList();
                              if (matches.isNotEmpty) setEditState(() => editUnit = matches.first);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(controller: editQtyController, decoration: InputDecoration(labelText: tr.text('quantity')), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                          const SizedBox(height: 12),
                          TextFormField(controller: editCostController, decoration: InputDecoration(labelText: tr.text('unit_cost')), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: editCurrency,
                            decoration: InputDecoration(labelText: tr.text('currency')),
                            items: const [DropdownMenuItem(value: 'USD', child: Text('USD')), DropdownMenuItem(value: 'LBP', child: Text('LBP'))],
                            onChanged: (value) => setEditState(() => editCurrency = value ?? 'USD'),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(child: TextButton(onPressed: () => Navigator.pop(editContext), child: Text(tr.text('cancel')))),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    final qty = double.tryParse(editQtyController.text.trim()) ?? 0;
                                    final enteredCost = double.tryParse(editCostController.text.trim()) ?? -1;
                                    if (qty <= 0 || enteredCost < 0 || editUnit.conversionToBase <= 0) return;
                                    if (!product.allowsDecimalQuantity && qty % 1 != 0) return;
                                    Navigator.pop(editContext, PurchaseItem(
                                      productId: product.id,
                                      productName: product.name,
                                      quantity: qty,
                                      purchaseUnitId: editUnit.id,
                                      purchaseUnitName: editUnit.name,
                                      conversionToBase: editUnit.conversionToBase,
                                      unitCost: toUsdReferencePrice(enteredCost, editCurrency, widget.store.storeProfile),
                                      originalUnitCost: enteredCost,
                                      unitCostCurrency: editCurrency,
                                      exchangeRateAtEntry: widget.store.storeProfile.usdToLbpRate,
                                    ));
                                  },
                                  child: Text(tr.text('save')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      editQtyController.dispose();
      editCostController.dispose();
      if (updated != null) {
        final index = items.indexOf(item);
        if (index >= 0) setDialogState(() => items[index] = updated);
      }
    }

    void addPurchaseLine(Product product, ProductSaleUnit unit, double qty, double enteredCost, String currency, StateSetter setDialogState) {
      if (qty <= 0) { showPurchaseError(tr.text('invalid_purchase_quantity')); return; }
      if (enteredCost < 0) { showPurchaseError(tr.text('unit_cost_required')); return; }
      if (unit.conversionToBase <= 0) { showPurchaseError(tr.text('invalid_purchase_unit_conversion')); return; }
      if (!product.allowsDecimalQuantity && qty % 1 != 0) {
        showPurchaseError(tr.text('countable_whole_quantity_required'));
        return;
      }
      final cost = toUsdReferencePrice(enteredCost, currency, widget.store.storeProfile);
      items.add(PurchaseItem(
        productId: product.id,
        productName: product.name,
        quantity: qty,
        purchaseUnitId: unit.id,
        purchaseUnitName: unit.name,
        conversionToBase: unit.conversionToBase,
        unitCost: cost,
        originalUnitCost: enteredCost,
        unitCostCurrency: currency,
        exchangeRateAtEntry: widget.store.storeProfile.usdToLbpRate,
      ));
      setDialogState(() {});
    }

    bool handleBarcode(String rawCode, StateSetter setDialogState) {
      final code = rawCode.trim();
      if (code.isEmpty) return false;
      final now = DateTime.now();
      if (lastScannedCode == code && lastScannedAt != null && now.difference(lastScannedAt!) < const Duration(milliseconds: 900)) {
        return true;
      }
      lastScannedCode = code;
      lastScannedAt = now;

      Product? matchedProduct;
      ProductSaleUnit? matchedUnit;
      for (final product in purchaseProducts) {
        final unitMatch = product.purchaseUnitForBarcode(code);
        if (unitMatch != null) {
          matchedProduct = product;
          matchedUnit = unitMatch;
          break;
        }
        if (product.code.trim() == code || product.barcode.trim() == code) {
          matchedProduct = product;
          matchedUnit = product.effectivePurchaseUnits.first;
          break;
        }
      }

      if (matchedProduct == null || matchedUnit == null) {
        BarcodeFeedbackService.playError(force: true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('barcode_not_registered_purchase'))));
        return false;
      }

      selectedProduct = matchedProduct;
      selectedUnit = matchedUnit;
      final currency = suggestedCostCurrency(matchedProduct);
      final suggested = fromUsdReferencePrice(suggestedBaseCost(matchedProduct) * matchedUnit.conversionToBase, currency, widget.store.storeProfile);
      addPurchaseLine(matchedProduct, matchedUnit, 1, suggested, currency, setDialogState);
      costController.text = suggested.toStringAsFixed(currency == 'LBP' ? 0 : 2);
      costCurrency = currency;
      barcodeController.clear();
      BarcodeFeedbackService.play(force: true);
      return true;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      isDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final total = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
          final units = selectedProduct?.effectivePurchaseUnits ?? const <ProductSaleUnit>[];
          final filteredProducts = productSearchQuery.trim().isEmpty
              ? purchaseProducts
              : purchaseProducts.where((product) {
                  final q = productSearchQuery.toLowerCase().trim();
                  return product.name.toLowerCase().contains(q) || product.code.toLowerCase().contains(q) || product.barcode.toLowerCase().contains(q);
                }).toList();
          if (selectedUnit != null && !units.any((unit) => unit.id == selectedUnit!.id)) {
            selectedUnit = units.isNotEmpty ? units.first : null;
            applySuggestedSupplierPrice();
          }
          final dialogWidth = VentioResponsive.modalMaxWidth(context, 1220);
          final dialogHeight = MediaQuery.sizeOf(context).height * 0.88;
          return SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: dialogWidth, maxHeight: dialogHeight),
                child: Material(
                  clipBehavior: Clip.antiAlias,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                    child: Row(
                      children: [
                        Expanded(child: Text(tr.text('new_purchase'), style: Theme.of(context).textTheme.headlineSmall)),
                        IconButton(
                          tooltip: tr.text('cancel'),
                          onPressed: () async {
                            if (await confirmDiscardIfNeeded(dialogContext) && dialogContext.mounted) Navigator.pop(dialogContext);
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.all(VentioResponsive.pagePadding(context)),
                      child: Form(
                        key: formKey,
                        child: LayoutBuilder(
                  builder: (context, constraints) {
                    final desktopLayout = constraints.maxWidth >= 900;
                    final gap = VentioResponsive.gap(context);

                    Widget sectionCard({required String title, required IconData icon, required List<Widget> children}) {
                      return Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        child: Padding(
                          padding: VentioResponsive.cardInsets(context),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...children,
                            ],
                          ),
                        ),
                      );
                    }

                    Widget supplierSection() {
                      return sectionCard(
                        title: tr.text('purchase_details'),
                        icon: Icons.receipt_long_outlined,
                        children: [
                          if (purchaseProducts.isEmpty) ...[
                            Text(tr.text('no_stock_tracked_products')),
                            SizedBox(height: gap),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: supplierId.isEmpty ? null : supplierId,
                                  decoration: InputDecoration(labelText: tr.text('supplier')),
                                  items: widget.store.suppliers.map((supplier) => DropdownMenuItem(value: supplier.id, child: Text(supplier.name))).toList(),
                                  onChanged: (value) {
                                    final matches = widget.store.suppliers.where((s) => s.id == value).toList();
                                    final supplier = matches.isEmpty ? null : matches.first;
                                    supplierId = supplier?.id ?? '';
                                    supplierName = supplier?.name ?? '';
                                    applySuggestedSupplierPrice();
                                    setDialogState(() {});
                                  },
                                  validator: (_) => supplierId.isEmpty ? tr.text('supplier_required') : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: tr.text('add_supplier'),
                                onPressed: () => createQuickSupplier(setDialogState),
                                icon: const Icon(Icons.person_add_alt_1_outlined),
                              ),
                            ],
                          ),
                          SizedBox(height: gap),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: receiveNow,
                            onChanged: (value) => setDialogState(() => receiveNow = value),
                            title: Text(tr.text('receive_now')),
                            subtitle: Text(tr.text('receive_now_desc')),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text('${tr.text('status')}: ${receiveNow ? tr.text('received') : tr.text('draft')}')),
                              Chip(label: Text('${tr.text('items')}: ${items.length}')),
                            ],
                          ),
                        ],
                      );
                    }

                    Widget barcodeSection() {
                      return sectionCard(
                        title: tr.text('scan_purchase_item'),
                        icon: Icons.qr_code_scanner,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: barcodeController,
                                  decoration: InputDecoration(labelText: tr.text('purchase_barcode'), hintText: tr.text('scan_purchase_barcode_hint')),
                                  onFieldSubmitted: (value) => handleBarcode(value, setDialogState),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: scannerActive ? tr.text('stop_scanner') : tr.text('start_scanner'),
                                onPressed: () => setDialogState(() => scannerActive = !scannerActive),
                                icon: Icon(scannerActive ? Icons.videocam_off_outlined : Icons.camera_alt_outlined),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () => handleBarcode(barcodeController.text, setDialogState),
                                icon: const Icon(Icons.keyboard_return),
                                label: Text(tr.text('add')),
                              ),
                            ],
                          ),
                          if (scannerActive) ...[
                            SizedBox(height: gap),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                height: VentioResponsive.adaptiveWidth(context, mobile: 180, tablet: 220, desktop: 240),
                                child: MobileScanner(
                                  controller: scannerController,
                                  onDetect: (capture) {
                                    for (final barcode in capture.barcodes) {
                                      final code = barcode.rawValue?.trim();
                                      if (code != null && code.isNotEmpty) {
                                        handleBarcode(code, setDialogState);
                                        break;
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    }

                    Widget productEntrySection() {
                      final conversion = selectedUnitConversionSummary();
                      return sectionCard(
                        title: tr.text('add_product'),
                        icon: Icons.add_box_outlined,
                        children: [
                          TextFormField(
                            controller: productSearchController,
                            decoration: InputDecoration(labelText: tr.text('search_product'), prefixIcon: const Icon(Icons.search)),
                            onChanged: (value) => setDialogState(() => productSearchQuery = value),
                          ),
                          SizedBox(height: gap),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedProduct != null && filteredProducts.any((p) => p.id == selectedProduct!.id) ? selectedProduct?.id : null,
                                  decoration: InputDecoration(labelText: tr.text('product')),
                                  items: filteredProducts.map((product) => DropdownMenuItem(value: product.id, child: Text(product.name))).toList(),
                                  onChanged: (value) {
                                    final matches = purchaseProducts.where((p) => p.id == value).toList();
                                    selectedProduct = matches.isEmpty ? null : matches.first;
                                    selectedUnit = selectedProduct?.effectivePurchaseUnits.first;
                                    applySuggestedSupplierPrice();
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: tr.text('add_product'),
                                onPressed: () => createQuickProduct(setDialogState),
                                icon: const Icon(Icons.add_box_outlined),
                              ),
                            ],
                          ),
                          SizedBox(height: gap),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: desktopLayout ? 190 : VentioResponsive.clampToScreen(context, 220, min: 150, horizontalPadding: 80),
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedUnit?.id,
                                  decoration: InputDecoration(labelText: tr.text('purchase_unit')),
                                  items: units.map((unit) => DropdownMenuItem(value: unit.id, child: Text('${unit.name} × ${_formatQuantity(unit.conversionToBase)}'))).toList(),
                                  onChanged: (value) {
                                    final matches = units.where((unit) => unit.id == value).toList();
                                    selectedUnit = matches.isEmpty ? null : matches.first;
                                    applySuggestedSupplierPrice();
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                              SizedBox(
                                width: desktopLayout ? 110 : 130,
                                child: TextFormField(
                                  controller: qtyController,
                                  decoration: InputDecoration(labelText: tr.text('quantity')),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                              ),
                              SizedBox(
                                width: desktopLayout ? 180 : VentioResponsive.clampToScreen(context, 220, min: 150, horizontalPadding: 80),
                                child: TextFormField(
                                  controller: costController,
                                  decoration: InputDecoration(labelText: tr.text('unit_cost'), helperText: priceHintForSelectedProduct().isEmpty ? null : priceHintForSelectedProduct()),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: DropdownButtonFormField<String>(
                                  initialValue: costCurrency,
                                  decoration: InputDecoration(labelText: tr.text('currency')),
                                  items: const [
                                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                                    DropdownMenuItem(value: 'LBP', child: Text('LBP')),
                                  ],
                                  onChanged: (value) => setDialogState(() => costCurrency = value ?? 'USD'),
                                ),
                              ),
                            ],
                          ),
                          if (conversion.isNotEmpty) ...[
                            SizedBox(height: gap),
                            Align(alignment: AlignmentDirectional.centerStart, child: Chip(avatar: const Icon(Icons.compare_arrows, size: 18), label: Text(conversion))),
                          ],
                          SizedBox(height: gap),
                          FilledButton.icon(
                            onPressed: selectedProduct == null || selectedUnit == null
                                ? null
                                : () {
                                    final qty = double.tryParse(qtyController.text.trim()) ?? 0;
                                    final enteredCost = double.tryParse(costController.text.trim()) ?? -1;
                                    addPurchaseLine(selectedProduct!, selectedUnit!, qty, enteredCost, costCurrency, setDialogState);
                                  },
                            icon: const Icon(Icons.add),
                            label: Text(tr.text('add_product_to_purchase')),
                          ),
                        ],
                      );
                    }

                    Widget lineActions(PurchaseItem item) => Wrap(
                          spacing: 4,
                          children: [
                            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: tr.text('edit'), onPressed: () => editPurchaseLine(item, setDialogState)),
                            IconButton(icon: const Icon(Icons.delete_outline), tooltip: tr.text('delete'), onPressed: () => setDialogState(() => items.remove(item))),
                          ],
                        );

                    Widget purchaseLinesSection() {
                      if (items.isEmpty) {
                        return sectionCard(
                          title: tr.text('purchase_invoice'),
                          icon: Icons.table_chart_outlined,
                          children: [Text(tr.text('no_items_added'))],
                        );
                      }
                      final table = SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            DataColumn(label: Text(tr.text('product'))),
                            DataColumn(label: Text(tr.text('unit'))),
                            DataColumn(label: Text(tr.text('quantity'))),
                            DataColumn(label: Text(tr.text('unit_cost'))),
                            DataColumn(label: Text(tr.text('total'))),
                            DataColumn(label: Text(tr.text('actions'))),
                          ],
                          rows: items.map((item) => DataRow(cells: [
                                DataCell(SizedBox(width: 180, child: Text(item.productName, overflow: TextOverflow.ellipsis))),
                                DataCell(Text(item.purchaseUnitName)),
                                DataCell(Text(_formatQuantity(item.quantity))),
                                DataCell(Text(formatCurrency(item.originalUnitCost ?? item.unitCost, currency: item.unitCostCurrency))),
                                DataCell(Text(formatUsdReferenceAmount(item.lineTotal, widget.store.storeProfile))),
                                DataCell(lineActions(item)),
                              ])).toList(),
                        ),
                      );
                      final cards = Column(
                        children: items.map((item) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(item.productName),
                                subtitle: Text('${unitConversionSummary(item)} • ${formatCurrency(item.originalUnitCost ?? item.unitCost, currency: item.unitCostCurrency)} • ${formatUsdReferenceAmount(item.lineTotal, widget.store.storeProfile)}'),
                                trailing: lineActions(item),
                              ),
                            )).toList(),
                      );
                      return sectionCard(
                        title: tr.text('purchase_invoice'),
                        icon: Icons.table_chart_outlined,
                        children: [desktopLayout ? table : cards],
                      );
                    }

                    Widget summarySection() {
                      return Card(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Padding(
                          padding: VentioResponsive.cardInsets(context),
                          child: Wrap(
                            spacing: 20,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              Text('${tr.text('supplier')}: ${supplierName.isEmpty ? '-' : supplierName}', style: Theme.of(context).textTheme.bodyMedium),
                              Text('${tr.text('items')}: ${items.length}', style: Theme.of(context).textTheme.bodyMedium),
                              Text('${tr.text('total')}: ${formatUsdReferenceAmount(total, widget.store.storeProfile)}', style: Theme.of(context).textTheme.titleMedium),
                            ],
                          ),
                        ),
                      );
                    }

                    final leftPanel = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [supplierSection(), SizedBox(height: gap), barcodeSection(), SizedBox(height: gap), productEntrySection()],
                    );
                    final rightPanel = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [purchaseLinesSection(), SizedBox(height: gap), summarySection()],
                    );

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (desktopLayout)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 390, child: leftPanel),
                              SizedBox(width: gap),
                              Expanded(child: rightPanel),
                            ],
                          )
                        else ...[
                          leftPanel,
                          SizedBox(height: gap),
                          rightPanel,
                        ],
                      ],
                    );
                          },
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${tr.text('total')}: ${formatUsdReferenceAmount(total, widget.store.storeProfile)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            if (await confirmDiscardIfNeeded(dialogContext) && dialogContext.mounted) Navigator.pop(dialogContext);
                          },
                          child: Text(tr.text('cancel')),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: items.isEmpty ? null : () async {
                            if (!(formKey.currentState?.validate() ?? false)) return;
                            try {
                              await widget.store.createPurchase(supplierId: supplierId, supplierName: supplierName, items: List.of(items), receiveNow: receiveNow);
                              if (dialogContext.mounted) Navigator.pop(dialogContext);
                              if (mounted) setState(() {});
                            } catch (error) {
                              if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString())));
                            }
                          },
                          icon: const Icon(Icons.save_outlined),
                          label: Text(tr.text('save')),
                        ),
                      ],
                    ),
                  ),
                ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    qtyController.dispose();
    costController.dispose();
    barcodeController.dispose();
    productSearchController.dispose();
    scannerController.dispose();
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: VentioResponsive.clampToScreen(
          context,
          VentioResponsive.adaptiveWidth(context, mobile: 190, tablet: 220, desktop: 260),
          min: 160,
        ),
        child: Card(
          child: Padding(
            padding: VentioResponsive.pageInsets(context),
            child: Row(children: [Icon(icon), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), Text(value, style: Theme.of(context).textTheme.titleLarge)]))]),
          ),
        ),
      );
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.purchase, required this.storeProfile, this.onReceive, this.onCancel});
  final Purchase purchase;
  final StoreProfile storeProfile;
  final VoidCallback? onReceive, onCancel;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final statusText = purchase.isCancelled
        ? tr.text('cancelled')
        : purchase.isReceived
            ? tr.text('received')
            : tr.text('draft');
    return ListTile(
      leading: CircleAvatar(child: Icon(purchase.isReceived ? Icons.inventory : purchase.isCancelled ? Icons.cancel_outlined : Icons.pending_actions)),
      title: Text('${purchase.purchaseNo} • ${purchase.supplierName}'),
      subtitle: Text('$statusText • ${purchase.totalUnits} ${tr.text('units')} • ${purchase.date.toLocal().toString().split('.').first}'),
      trailing: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(formatUsdReferenceAmount(purchase.subtotal, storeProfile)),
          if (onReceive != null) IconButton(tooltip: AppLocalizations.of(context).text('receive'), onPressed: onReceive, icon: const Icon(Icons.download_done)),
          if (onCancel != null) IconButton(tooltip: AppLocalizations.of(context).text('cancel'), onPressed: onCancel, icon: const Icon(Icons.cancel_outlined)),
        ],
      ),
    );
  }
}
