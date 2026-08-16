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

  List<Product> get _products {
    final query = _query.trim().toLowerCase();
    final result = widget.store.products.where((product) {
      if (product.isDeleted) return false;
      if (query.isEmpty) return true;
      return '${product.name} ${product.nameEn} ${product.nameAr} '
              '${product.code} ${product.barcode}'
          .toLowerCase()
          .contains(query);
    }).toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  bool _isSelected(Product product) => (_quantities[product.id] ?? 0) > 0;

  void _toggle(Product product, bool selected) {
    setState(() {
      _quantities[product.id] = selected ? 1 : 0;
      if (selected) {
        _quantityController(product).text = '1';
      } else {
        _quantityControllers.remove(product.id)?.dispose();
      }
    });
  }

  TextEditingController _quantityController(Product product) {
    return _quantityControllers.putIfAbsent(
      product.id,
      () => TextEditingController(text: '${_quantities[product.id] ?? 1}'),
    );
  }

  void _changeQuantity(Product product, int value) {
    final quantity = value.clamp(0, 999);
    setState(() => _quantities[product.id] = quantity);
    if (quantity > 0) {
      final controller = _quantityController(product);
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

  Future<void> _generateFor(Product product) async {
    if (!widget.store.canManageProducts) return;
    final confirmed = await _confirmGeneration(
      title:
          AppLocalizations.of(context).text('confirm_generate_barcode_title'),
      message:
          AppLocalizations.of(context).text('confirm_generate_barcode_message'),
    );
    if (!confirmed || !mounted) return;
    try {
      final updated = product.copyWith(barcode: _newBarcode());
      await widget.store.addOrUpdateProduct(updated);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                error.toString().replaceFirst('Invalid argument(s): ', ''))),
      );
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
    final selected = widget.store.products
        .where((product) =>
            _isSelected(product) && product.barcode.trim().isNotEmpty)
        .map((product) => BarcodeLabelItem(
              product: product,
              quantity: _quantities[product.id] ?? 1,
            ))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final lastOptions = await _loadLastPrintOptions();
    if (!mounted) return;
    final options = await showDialog<BarcodeLabelPrintOptions>(
      context: context,
      builder: (dialogContext) => _BarcodePrintOptionsDialog(
        initial: lastOptions,
        previewProduct: selected.first.product,
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
      marginMm: prefs.getDouble('barcode_label_margin_mm') ?? 1.5,
      fontSize: prefs.getDouble('barcode_label_font_size') ?? 8,
      barcodeHeight: prefs.getDouble('barcode_label_height') ?? 24,
      barcodeWidth: prefs.getDouble('barcode_label_width') ?? 60,
      logoWidth: prefs.getDouble('barcode_label_logo_width') ?? 60,
      productionDate: prefs.getString('barcode_label_production_date') ?? '',
      expiryDate: prefs.getString('barcode_label_expiry_date') ?? '',
      weight: prefs.getString('barcode_label_weight') ?? '',
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
                      final product = products[index];
                      final hasBarcode = product.barcode.trim().isNotEmpty;
                      final selected = _isSelected(product);
                      return ListTile(
                        leading: Checkbox(
                          value: selected,
                          onChanged: hasBarcode
                              ? (value) => _toggle(product, value == true)
                              : null,
                        ),
                        title: Text(product.name),
                        subtitle: Text(hasBarcode
                            ? '${product.code} • ${product.barcode}'
                            : tr.text('barcode_missing')),
                        trailing: hasBarcode
                            ? SizedBox(
                                width: 170,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: tr.text('generate_barcode'),
                                      onPressed: () => _generateFor(product),
                                      icon: const Icon(Icons.autorenew),
                                    ),
                                    if (selected)
                                      IconButton(
                                        onPressed: () => _changeQuantity(
                                            product,
                                            (_quantities[product.id] ?? 1) - 1),
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                      ),
                                    if (selected)
                                      SizedBox(
                                        width: 44,
                                        child: TextFormField(
                                          controller:
                                              _quantityController(product),
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 10),
                                          ),
                                          onChanged: (value) {
                                            final quantity =
                                                int.tryParse(value);
                                            if (quantity != null &&
                                                quantity >= 1) {
                                              _changeQuantity(
                                                  product, quantity);
                                            }
                                          },
                                        ),
                                      ),
                                    if (selected)
                                      IconButton(
                                        onPressed: () => _changeQuantity(
                                            product,
                                            (_quantities[product.id] ?? 1) + 1),
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                      ),
                                  ],
                                ),
                              )
                            : TextButton.icon(
                                onPressed: widget.store.canManageProducts
                                    ? () => _generateFor(product)
                                    : null,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: Text(tr.text('generate_barcode')),
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

class _BarcodePrintOptionsDialog extends StatefulWidget {
  const _BarcodePrintOptionsDialog(
      {required this.initial,
      required this.previewProduct,
      required this.profile});

  final BarcodeLabelPrintOptions initial;
  final Product previewProduct;
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
          items: [
            BarcodeLabelItem(product: widget.previewProduct, quantity: 1)
          ],
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
            logoBytes: logoBytes,
          ),
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
                  const Text('مقاس الملصق مضبوط على 50 × 30 mm'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          logoName.isEmpty
                              ? 'Optional black & white logo'
                              : logoName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Choose logo'),
                      ),
                      if (logoBytes != null)
                        IconButton(
                          tooltip: 'Remove logo',
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
                    decoration: const InputDecoration(
                      labelText: 'Production date',
                      hintText: 'DD/MM/YYYY',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: expiryDateController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: 'Expiry date',
                      hintText: 'DD/MM/YYYY',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: weightController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Weight',
                      hintText: 'e.g. 250g or 1kg',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _slider('الهامش: ${margin.toStringAsFixed(1)} mm', margin, 0,
                      8, (v) => setState(() => margin = v)),
                  _slider('حجم الخط: ${fontSize.toStringAsFixed(0)}', fontSize,
                      5, 12, (v) => setState(() => fontSize = v)),
                  _slider(
                      'ارتفاع الباركود: ${barcodeHeight.toStringAsFixed(0)}',
                      barcodeHeight,
                      18,
                      40,
                      (v) => setState(() => barcodeHeight = v)),
                  _slider(
                      'Barcode width: ${barcodeWidth.toStringAsFixed(0)}',
                      barcodeWidth,
                      25,
                      110,
                      (v) => setState(() => barcodeWidth = v)),
                  if (logoBytes != null) ...[
                    const SizedBox(height: 8),
                    _slider(
                        'Logo size: ${logoWidth.toStringAsFixed(0)}',
                        logoWidth,
                        25,
                        100,
                        (v) => setState(() => logoWidth = v)),
                  ],
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: positionElement,
                    decoration: const InputDecoration(
                      labelText: 'Move element',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'productName', child: Text('Product name')),
                      DropdownMenuItem(
                          value: 'barcode', child: Text('Barcode')),
                      DropdownMenuItem(value: 'logo', child: Text('Logo')),
                      DropdownMenuItem(value: 'weight', child: Text('Weight')),
                      DropdownMenuItem(value: 'dates', child: Text('Dates')),
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
                const SnackBar(
                  content: Text('Use a valid date, for example DD/MM/YYYY.'),
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
