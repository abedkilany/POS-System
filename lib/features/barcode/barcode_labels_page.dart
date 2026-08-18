import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/barcode_label_pdf_service.dart';
import '../../data/app_store.dart';
import '../../models/product.dart';
import '../../models/store_profile.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';

class BarcodeLabelsPage extends StatefulWidget {
  const BarcodeLabelsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<BarcodeLabelsPage> createState() => _BarcodeLabelsPageState();
}

class _BarcodeLabelsPageState extends State<BarcodeLabelsPage> {
  final _searchController = TextEditingController();
  final _quantities = <String, int>{};
  final _quantityControllers = <String, TextEditingController>{};
  String _query = '';
  bool _generating = false;

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<_BarcodeTarget> get _products {
    final query = _query.trim().toLowerCase();
    final targets = <_BarcodeTarget>[];
    final seen = <String>{};
    for (final product in widget.store.products) {
      if (product.isDeleted) continue;
      final units = <ProductSaleUnit>[
        ProductSaleUnit(
          id: 'base',
          name: product.unit,
          conversionToBase: 1,
          price: product.price,
          originalPrice: product.originalPrice,
          originalCurrency: product.originalCurrency,
          barcode: product.barcode,
          isDefault: true,
        ),
        ...product.saleUnits,
        ...product.purchaseUnits,
      ];
      for (final unit in units) {
        final barcode = unit.barcode.trim();
        if (barcode.isEmpty || !seen.add(barcode.toLowerCase())) continue;
        targets.add(_BarcodeTarget(product: product, unit: unit));
      }
    }
    final result = targets.where((target) {
      final product = target.product;
      final unit = target.unit;
      if (query.isEmpty) return true;
      return '${product.name} ${product.nameEn} ${product.nameAr} '
              '${product.code} ${product.barcode} ${unit.name} ${unit.barcode}'
          .toLowerCase()
          .contains(query);
    }).toList();
    result.sort((a, b) => '${a.product.name} ${a.unit.name}'
        .toLowerCase()
        .compareTo('${b.product.name} ${b.unit.name}'.toLowerCase()));
    return result;
  }

  bool _isSelected(_BarcodeTarget target) => (_quantities[target.key] ?? 0) > 0;

  void _toggle(_BarcodeTarget target, bool selected) {
    setState(() {
      _quantities[target.key] = selected ? 1 : 0;
      if (selected) {
        _quantityController(target).text = '1';
      } else {
        _quantityControllers.remove(target.key)?.dispose();
      }
    });
  }

  TextEditingController _quantityController(_BarcodeTarget target) {
    return _quantityControllers.putIfAbsent(
      target.key,
      () => TextEditingController(text: '${_quantities[target.key] ?? 1}'),
    );
  }

  void _changeQuantity(_BarcodeTarget target, int value) {
    final quantity = value.clamp(0, 999);
    setState(() => _quantities[target.key] = quantity);
    if (quantity > 0) {
      final controller = _quantityController(target);
      final text = '$quantity';
      if (controller.text != text) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  String _newBarcode() {
    final used = widget.store.products
        .map((item) => item.barcode.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    var seed = DateTime.now().microsecondsSinceEpoch % 1000000000000;
    while (true) {
      final body = seed.toString().padLeft(12, '0');
      var sum = 0;
      for (var index = 0; index < body.length; index++) {
        sum += int.parse(body[index]) * (index.isEven ? 1 : 3);
      }
      final value = '$body${(10 - sum % 10) % 10}';
      if (!used.contains(value)) return value;
      seed = (seed + 1) % 1000000000000;
    }
  }

  Future<void> _generateMissing() async {
    if (!widget.store.canManageProducts || _generating) return;
    final confirmed = await _confirmGeneration(
      title:
          AppLocalizations.of(context).text('confirm_generate_missing_title'),
      message:
          AppLocalizations.of(context).text('confirm_generate_missing_message'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _generating = true);
    try {
      for (final product in widget.store.products) {
        if (!product.isDeleted && product.barcode.trim().isEmpty) {
          await widget.store.addOrUpdateProduct(
            product.copyWith(barcode: _newBarcode()),
          );
        }
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<bool> _confirmGeneration({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context).text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(context).text('confirm')),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _print() async {
    final selected = _products
        .where(_isSelected)
        .map((target) => BarcodeLabelItem(
              product: target.product,
              barcode: target.unit.barcode,
              unitName: target.unit.name,
              price: target.unit.originalPrice,
              priceCurrency: target.unit.originalCurrency,
              quantity: _quantities[target.key] ?? 1,
            ))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final lastOptions = await _loadLastPrintOptions();
    if (!mounted) return;
    final options = await showDialog<BarcodeLabelPrintOptions>(
      context: context,
      builder: (dialogContext) => _BarcodePrintOptionsDialog(
        initial: lastOptions,
        previewItem: selected.first,
        profile: widget.store.storeProfile,
      ),
    );
    if (!mounted || options == null) return;
    final locale = Localizations.localeOf(context);
    await _saveLastPrintOptions(options);
    if (!mounted) return;
    await BarcodeLabelPdfService.printLabels(
      context: context,
      items: selected,
      profile: widget.store.storeProfile,
      locale: locale,
      options: options,
    );
  }

  Future<BarcodeLabelPrintOptions> _loadLastPrintOptions() async {
    final prefs = await SharedPreferences.getInstance();
    Uint8List? logoBytes;
    try {
      final directory = await getApplicationSupportDirectory();
      final logoFile =
          File(path.join(directory.path, 'barcode_label_logo.png'));
      if (await logoFile.exists()) {
        logoBytes = await logoFile.readAsBytes();
      }
    } catch (_) {
      logoBytes = null;
    }
    if (logoBytes == null) {
      try {
        final encodedLogo = prefs.getString('barcode_label_logo_base64');
        if (encodedLogo != null && encodedLogo.isNotEmpty) {
          // Migrate logos saved by older builds, if the old value fits.
          logoBytes = Uint8List.fromList(base64Decode(encodedLogo));
        }
      } catch (_) {
        logoBytes = null;
      }
    }
    final savedOffsets = <String, Offset>{};
    try {
      final rawOffsets = prefs.getString('barcode_label_element_offsets');
      if (rawOffsets != null) {
        final decoded = jsonDecode(rawOffsets) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final value = entry.value as Map<String, dynamic>;
          savedOffsets[entry.key] = Offset(
            (value['dx'] as num).toDouble(),
            (value['dy'] as num).toDouble(),
          );
        }
      }
    } catch (_) {}
    return BarcodeLabelPrintOptions(
      marginMm: 0,
      fontSize: prefs.getDouble('barcode_label_font_size') ?? 8,
      barcodeHeight: 14,
      barcodeWidth: 50,
      logoWidth: 23,
      productionDate: prefs.getString('barcode_label_production_date') ?? '',
      expiryDate: prefs.getString('barcode_label_expiry_date') ?? '',
      weight: prefs.getString('barcode_label_weight') ?? '',
      showPrice: prefs.getBool('barcode_label_show_price') ?? false,
      logoBytes: logoBytes,
      elementOffsets: savedOffsets,
    );
  }

  Future<void> _saveLastPrintOptions(BarcodeLabelPrintOptions options) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'barcode_label_production_date', options.productionDate);
    await prefs.setDouble('barcode_label_margin_mm', options.marginMm);
    await prefs.setDouble('barcode_label_font_size', options.fontSize);
    await prefs.setDouble('barcode_label_height', options.barcodeHeight);
    await prefs.setDouble('barcode_label_width', options.barcodeWidth);
    await prefs.setDouble('barcode_label_logo_width', options.logoWidth);
    await prefs.setString(
      'barcode_label_element_offsets',
      jsonEncode(options.elementOffsets.map(
        (key, value) =>
            MapEntry(key, <String, double>{'dx': value.dx, 'dy': value.dy}),
      )),
    );
    await prefs.setString('barcode_label_expiry_date', options.expiryDate);
    await prefs.setString('barcode_label_weight', options.weight);
    await prefs.setBool('barcode_label_show_price', options.showPrice);
    if (options.logoBytes != null && options.logoBytes!.isNotEmpty) {
      final directory = await getApplicationSupportDirectory();
      await Directory(directory.path).create(recursive: true);
      final logoFile =
          File(path.join(directory.path, 'barcode_label_logo.png'));
      await logoFile.writeAsBytes(options.logoBytes!, flush: true);
    } else {
      final directory = await getApplicationSupportDirectory();
      final logoFile =
          File(path.join(directory.path, 'barcode_label_logo.png'));
      if (await logoFile.exists()) await logoFile.delete();
    }
    await prefs.remove('barcode_label_logo_base64');
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final products = _products;
    final selectedCount =
        _quantities.values.fold<int>(0, (sum, value) => sum + value);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AppSectionHeader(
            title: tr.text('barcode_labels'),
            subtitle: tr.text('barcode_labels_desc'),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.store.canManageProducts && !_generating
                      ? _generateMissing
                      : null,
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_outlined),
                  label: Text(tr.text('generate_missing_barcodes')),
                ),
                FilledButton.icon(
                  onPressed: selectedCount == 0 ? null : _print,
                  icon: const Icon(Icons.print_outlined),
                  label: Text('${tr.text('print_barcodes')} ($selectedCount)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: tr.text('search_products'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: products.isEmpty
                ? EmptyStateCard(
                    icon: Icons.qr_code_2_outlined,
                    title: tr.text('no_products'),
                    subtitle: tr.text('no_products_desc'),
                  )
                : ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final target = products[index];
                      final product = target.product;
                      final selected = _isSelected(target);
                      return ListTile(
                        leading: Checkbox(
                          value: selected,
                          onChanged: (value) => _toggle(target, value == true),
                        ),
                        title: Text('${product.name} • ${target.unit.name}'),
                        subtitle:
                            Text('${product.code} • ${target.unit.barcode}'),
                        trailing: SizedBox(
                          width: 170,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (selected)
                                IconButton(
                                  onPressed: () => _changeQuantity(target,
                                      (_quantities[target.key] ?? 1) - 1),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                              if (selected)
                                SizedBox(
                                  width: 44,
                                  child: TextFormField(
                                    controller: _quantityController(target),
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 10),
                                    ),
                                    onChanged: (value) {
                                      final quantity = int.tryParse(value);
                                      if (quantity != null && quantity >= 1) {
                                        _changeQuantity(target, quantity);
                                      }
                                    },
                                  ),
                                ),
                              if (selected)
                                IconButton(
                                  onPressed: () => _changeQuantity(target,
                                      (_quantities[target.key] ?? 1) + 1),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeTarget {
  const _BarcodeTarget({required this.product, required this.unit});

  final Product product;
  final ProductSaleUnit unit;

  String get key => '${product.id}:${unit.id}:${unit.barcode}';
}

class _BarcodePrintOptionsDialog extends StatefulWidget {
  const _BarcodePrintOptionsDialog(
      {required this.initial,
      required this.previewItem,
      required this.profile});

  final BarcodeLabelPrintOptions initial;
  final BarcodeLabelItem previewItem;
  final StoreProfile profile;

  @override
  State<_BarcodePrintOptionsDialog> createState() =>
      _BarcodePrintOptionsDialogState();
}

String? _normalizeManualDate(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';

  int? day;
  int? month;
  int? year;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  final parts =
      raw.split(RegExp(r'[/\-.]')).where((part) => part.isNotEmpty).toList();

  if (parts.length == 3) {
    day = int.tryParse(parts[0]);
    month = int.tryParse(parts[1]);
    year = int.tryParse(parts[2]);
  } else if (digits.length == 6) {
    day = int.tryParse(digits.substring(0, 2));
    month = int.tryParse(digits.substring(2, 4));
    year = int.tryParse(digits.substring(4, 6));
  } else if (digits.length == 8) {
    day = int.tryParse(digits.substring(0, 2));
    month = int.tryParse(digits.substring(2, 4));
    year = int.tryParse(digits.substring(4, 8));
  } else {
    return null;
  }

  if (day == null || month == null || year == null) return null;
  if (year < 100) year += 2000;
  if (day < 1 || month < 1 || month > 12 || year < 2000) return null;

  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return '${day.toString().padLeft(2, '0')}/'
      '${month.toString().padLeft(2, '0')}/$year';
}

class _BarcodePrintOptionsDialogState
    extends State<_BarcodePrintOptionsDialog> {
  late double margin;
  late double fontSize;
  late double barcodeHeight;
  late double barcodeWidth;
  late double logoWidth;
  String positionElement = 'barcode';
  late Map<String, Offset> elementOffsets;
  Uint8List? logoBytes;
  String logoName = '';
  late final TextEditingController productionDateController;
  late final TextEditingController expiryDateController;
  late final TextEditingController weightController;
  late bool showPrice;

  @override
  void initState() {
    super.initState();
    margin = widget.initial.marginMm;
    fontSize = widget.initial.fontSize;
    barcodeHeight = widget.initial.barcodeHeight;
    barcodeWidth = widget.initial.barcodeWidth;
    logoWidth = widget.initial.logoWidth;
    elementOffsets = Map<String, Offset>.from(widget.initial.elementOffsets);
    logoBytes = widget.initial.logoBytes;
    if (logoBytes != null && logoBytes!.isNotEmpty) {
      logoName = 'Saved logo';
    }
    productionDateController =
        TextEditingController(text: widget.initial.productionDate);
    expiryDateController =
        TextEditingController(text: widget.initial.expiryDate);
    weightController = TextEditingController(text: widget.initial.weight);
    showPrice = widget.initial.showPrice;
  }

  @override
  void dispose() {
    productionDateController.dispose();
    expiryDateController.dispose();
    weightController.dispose();
    super.dispose();
  }

  Widget _buildInlinePreview() {
    return SizedBox(
      height: 235,
      child: PdfPreview(
        build: (_) => BarcodeLabelPdfService.buildPdf(
          items: [widget.previewItem],
          profile: widget.profile,
          locale: Localizations.localeOf(context),
          options: BarcodeLabelPrintOptions(
            marginMm: margin,
            fontSize: fontSize,
            barcodeHeight: barcodeHeight,
            barcodeWidth: barcodeWidth,
            logoWidth: logoWidth,
            elementOffsets: elementOffsets,
            productionDate: productionDateController.text.trim(),
            expiryDate: expiryDateController.text.trim(),
            weight: weightController.text.trim(),
            showPrice: showPrice,
            logoBytes: logoBytes,
          ),
          showGuides: true,
        ),
        canChangePageFormat: false,
        canChangeOrientation: false,
        useActions: false,
        allowSharing: false,
        allowPrinting: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return AlertDialog(
      title: const Text('إعدادات ملصق الباركود'),
      content: SizedBox(
        width: 420,
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            _buildInlinePreview(),
            Expanded(
              child: ListView(
                children: [
                  const Text('مقاس الملصق مضبوط على 58 × 40 mm'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          logoName.isEmpty
                              ? tr.text('barcode_optional_logo')
                              : logoName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(tr.text('barcode_choose_logo')),
                      ),
                      if (logoBytes != null)
                        IconButton(
                          tooltip: tr.text('barcode_remove_logo'),
                          onPressed: () => setState(() {
                            logoBytes = null;
                            logoName = '';
                          }),
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: productionDateController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(
                      labelText: tr.text('barcode_production_date'),
                      hintText: tr.text('barcode_date_hint'),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: expiryDateController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(
                      labelText: tr.text('barcode_expiry_date'),
                      hintText: tr.text('barcode_date_hint'),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: weightController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'الوزن والسعر',
                      hintText: 'أدخل الوزن؛ السعر يُقرأ تلقائيًا من وحدة المنتج',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('إظهار السعر'),
                    value: showPrice,
                    onChanged: (value) => setState(() => showPrice = value),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'حواف أمان ثابتة 2 mm من كل الجهات. داخلها: الشعار 23×17 mm، '
                    'الاسم/الوزن 31×17 mm، الباركود 54×14 mm (عرض فعلي 50 mm)، '
                    'والصلاحية 54×5 mm. خطوط التقسيم للمعاينة فقط ولن تُطبع.',
                  ),
                  const SizedBox(height: 8),
                  _slider('حجم الخط: ${fontSize.toStringAsFixed(0)}', fontSize,
                      5, 12, (v) => setState(() => fontSize = v)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: positionElement,
                    decoration: InputDecoration(
                      labelText: tr.text('barcode_move_element'),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'productName',
                          child: Text(tr.text('product_name'))),
                      DropdownMenuItem(
                          value: 'barcode', child: Text(tr.text('barcode'))),
                      DropdownMenuItem(
                          value: 'logo', child: Text(tr.text('barcode_logo'))),
                      DropdownMenuItem(
                          value: 'weight',
                          child: const Text('الوزن والسعر')),
                      DropdownMenuItem(
                          value: 'dates',
                          child: Text(tr.text('barcode_dates'))),
                    ],
                    onChanged: (value) =>
                        setState(() => positionElement = value ?? 'barcode'),
                  ),
                  _slider(
                      'Move right / left: ${_elementOffset.dx.toStringAsFixed(0)}',
                      _elementOffset.dx + 20,
                      0,
                      40,
                      (value) => _setElementOffset(dx: value - 20)),
                  _slider(
                      'Move up / down: ${_elementOffset.dy.toStringAsFixed(0)}',
                      _elementOffset.dy + 20,
                      0,
                      40,
                      (value) => _setElementOffset(dy: value - 20)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final productionDate =
                _normalizeManualDate(productionDateController.text);
            final expiryDate = _normalizeManualDate(expiryDateController.text);
            if (productionDate == null || expiryDate == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(tr.text('barcode_invalid_date')),
                ),
              );
              return;
            }
            Navigator.of(context).pop(
              BarcodeLabelPrintOptions(
                marginMm: margin,
                fontSize: fontSize,
                barcodeHeight: barcodeHeight,
                barcodeWidth: barcodeWidth,
                logoWidth: logoWidth,
                elementOffsets: elementOffsets,
                productionDate: productionDate,
                expiryDate: expiryDate,
                weight: weightController.text.trim(),
                showPrice: showPrice,
                logoBytes: logoBytes,
              ),
            );
          },
          child: const Text('طباعة'),
        ),
      ],
    );
  }

  Offset get _elementOffset => elementOffsets[positionElement] ?? Offset.zero;

  void _setElementOffset({double? dx, double? dy}) {
    final current = _elementOffset;
    setState(() {
      elementOffsets[positionElement] =
          Offset(dx ?? current.dx, dy ?? current.dy);
    });
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (!mounted || result == null || result.files.single.bytes == null) return;
    setState(() {
      logoBytes = result.files.single.bytes;
      logoName = result.files.single.name;
    });
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        Slider(
            value: value,
            min: min,
            max: max,
            divisions: 20,
            onChanged: onChanged),
      ],
    );
  }
}
