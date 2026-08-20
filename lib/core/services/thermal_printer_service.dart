import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:thermal_printer_flutter/thermal_printer_flutter.dart';

import '../../models/sale.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';

enum ThermalPaperWidth {
  mm58,
  mm80,
}

class ThermalPrinterService {
  ThermalPrinterService({ThermalPrinterFlutter? printer})
      : _printer = printer ?? ThermalPrinterFlutter();

  final ThermalPrinterFlutter _printer;

  Future<List<Printer>> discoverNetworkPrinters({
    Function(String)? onProgress,
  }) {
    return _printer.discoverNetworkPrinters(
      onProgress: onProgress,
      requireConfirmation: true,
    );
  }

  Future<List<Printer>> listPrinters(PrinterType type) {
    return _printer.getPrinters(printerType: type);
  }

  Future<void> printSale({
    required BuildContext context,
    required Sale sale,
    required StoreProfile profile,
    required Printer printer,
    Locale locale = const Locale('en'),
    ThermalPaperWidth paperWidth = ThermalPaperWidth.mm80,
    int copies = 1,
  }) async {
    late final List<int> bytes;
    try {
      bytes = await buildSaleReceiptBytes(
        context: context,
        sale: sale,
        profile: profile,
        locale: locale,
        paperWidth: paperWidth,
      );
    } catch (_) {
      // The virtual printer must remain usable in headless/test renderers where
      // GPU screenshot capture is unavailable. Real printers still use the
      // image path above so Arabic shaping is preserved.
      bytes = _buildVirtualTextReceiptBytes(
        sale: sale,
        profile: profile,
        paperWidth: paperWidth,
      );
    }

    if (printer.type != PrinterType.usb) {
      final connected = await _printer.connect(printer: printer);
      if (!connected) {
        throw StateError('Could not connect to the selected thermal printer.');
      }
    }

    try {
      await _printer.printBytes(bytes: bytes, printer: printer, copies: copies);
    } finally {
      if (printer.type != PrinterType.usb) {
        await _printer.disconnect(printer: printer);
      }
    }
  }

  Future<VirtualPrinterJob> captureSaleForVirtualPrinter({
    required BuildContext context,
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
    ThermalPaperWidth paperWidth = ThermalPaperWidth.mm80,
  }) async {
    final bytes = await buildSaleReceiptBytes(
      context: context,
      sale: sale,
      profile: profile,
      locale: locale,
      paperWidth: paperWidth,
    );
    return VirtualPrinterStore.instance.capture(
      bytes,
      invoiceNo: sale.invoiceNo,
      paperWidth: paperWidth,
      sale: sale,
      profile: profile,
      locale: locale,
    );
  }

  Future<List<int>> buildSaleReceiptBytes({
    required BuildContext context,
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
    ThermalPaperWidth paperWidth = ThermalPaperWidth.mm80,
  }) async {
    final generator = Generator(
      paperWidth == ThermalPaperWidth.mm58 ? PaperSize.mm58 : PaperSize.mm80,
      await CapabilityProfile.load(),
    );
    if (!context.mounted) {
      throw StateError('The receipt screen is no longer available.');
    }
    final width = paperWidth == ThermalPaperWidth.mm58 ? 384 : 576;
    final image = await _printer.screenShotWidget(
      context,
      widget: ThermalReceiptWidget(
        sale: sale,
        profile: profile,
        locale: locale,
        width: width.toDouble(),
      ),
      width: width,
      pixelRatio: 2,
      dither: true,
    );

    return <int>[
      ...generator.reset(),
      ...generator.imageRaster(image),
      ...generator.feed(3),
      ...generator.cut(),
    ];
  }

  Future<void> dispose() => _printer.dispose();

  List<int> _buildVirtualTextReceiptBytes({
    required Sale sale,
    required StoreProfile profile,
    required ThermalPaperWidth paperWidth,
  }) {
    final lines = <String>[
      profile.name,
      'Invoice: ${sale.invoiceNo}',
      'Date: ${_formatDate(sale.date)}',
      ...sale.items.map((item) =>
          '${item.productName} x ${_formatQuantity(item.quantity)} = ${_formatMoney(item.lineTotal, profile)}'),
      'Subtotal: ${_formatMoney(sale.subtotal, profile)}',
      if (sale.discount > 0)
        'Discount: ${_formatMoney(sale.discount, profile)}',
      'TOTAL: ${_formatMoney(sale.total, profile, forceCurrencies: const [
            'USD',
            'LBP'
          ])}',
      profile.footerNote,
    ];
    final width = paperWidth == ThermalPaperWidth.mm58 ? 32 : 48;
    final output = <int>[0x1b, 0x40, 0x1b, 0x61, 0x01];
    for (final line in lines) {
      final safe = line.length > width ? line.substring(0, width) : line;
      output.addAll(utf8.encode('$safe\n'));
    }
    output
      ..addAll([0x1b, 0x64, 0x03])
      ..addAll([0x1d, 0x56, 0x00]);
    return output;
  }
}

class VirtualPrinterJob {
  const VirtualPrinterJob({
    required this.id,
    required this.invoiceNo,
    required this.bytes,
    required this.paperWidth,
    required this.createdAt,
    required this.sale,
    required this.profile,
    required this.locale,
  });

  final int id;
  final String invoiceNo;
  final Uint8List bytes;
  final ThermalPaperWidth paperWidth;
  final DateTime createdAt;
  final Sale sale;
  final StoreProfile profile;
  final Locale locale;

  bool get hasEscPosHeader =>
      bytes.length >= 3 && bytes[0] == 0x1b && bytes[1] == 0x40;
  bool get hasCutCommand => bytes.contains(0x1d) && bytes.contains(0x56);
}

class VirtualPrinterStore {
  VirtualPrinterStore._();

  static final instance = VirtualPrinterStore._();
  final List<VirtualPrinterJob> _jobs = <VirtualPrinterJob>[];

  List<VirtualPrinterJob> get jobs => List.unmodifiable(_jobs);
  VirtualPrinterJob? get lastJob => _jobs.isEmpty ? null : _jobs.last;

  VirtualPrinterJob capture(
    List<int> bytes, {
    required String invoiceNo,
    required ThermalPaperWidth paperWidth,
    required Sale sale,
    required StoreProfile profile,
    required Locale locale,
  }) {
    final job = VirtualPrinterJob(
      id: DateTime.now().microsecondsSinceEpoch,
      invoiceNo: invoiceNo,
      bytes: Uint8List.fromList(bytes),
      paperWidth: paperWidth,
      createdAt: DateTime.now(),
      sale: sale,
      profile: profile,
      locale: locale,
    );
    _jobs.add(job);
    if (_jobs.length > 20) _jobs.removeAt(0);
    return job;
  }

  void clear() => _jobs.clear();
}

class ThermalReceiptWidget extends StatelessWidget {
  const ThermalReceiptWidget({
    super.key,
    required this.sale,
    required this.profile,
    required this.locale,
    required this.width,
  });

  final Sale sale;
  final StoreProfile profile;
  final Locale locale;
  final double width;

  bool get isArabic => locale.languageCode.toLowerCase() == 'ar';

  Uint8List? get _logoBytes {
    final raw = profile.logoDataBase64.trim();
    if (raw.isEmpty) return null;
    try {
      final comma = raw.indexOf(',');
      final payload = raw.startsWith('data:') && comma >= 0
          ? raw.substring(comma + 1)
          : raw;
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final labels = isArabic
        ? const _ThermalLabels.ar()
        : locale.languageCode.toLowerCase() == 'fr'
            ? const _ThermalLabels.fr()
            : const _ThermalLabels.en();

    return Material(
      color: Colors.white,
      child: Directionality(
        textDirection: textDirection,
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.black,
                fontSize: 22,
                height: 1.15,
                fontFamily: 'DejaVu Sans',
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_logoBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Image.memory(
                        _logoBytes!,
                        height: width >= 500 ? 125 : 96,
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    Text(
                      profile.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (profile.phone.trim().isNotEmpty)
                    Text(profile.phone, textAlign: TextAlign.center),
                  if (profile.address.trim().isNotEmpty)
                    Text(profile.address, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.black, thickness: 2),
                  Text(
                    isArabic ? 'فاتورة مبيعات' : 'SALES INVOICE',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 7),
                  Text('${labels.invoice}: ${sale.invoiceNo}'),
                  Text('${labels.date}: ${_formatDate(sale.date)}'),
                  if (sale.customerName.trim().isNotEmpty)
                    Text('${labels.customer}: ${sale.customerName}'),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.black, thickness: 1),
                  ...sale.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(item.productName),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${_formatQuantity(item.quantity)} x ${_formatMoney(item.unitPrice, profile)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _formatMoney(item.lineTotal, profile),
                                  textAlign: TextAlign.end,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(color: Colors.black, thickness: 1),
                  _summaryRow(
                      labels.subtotal, _formatMoney(sale.subtotal, profile)),
                  if (sale.discount > 0)
                    _summaryRow(
                        labels.discount, _formatMoney(sale.discount, profile)),
                  _summaryRow(
                    labels.total,
                    _formatMoney(sale.total, profile),
                    bold: true,
                  ),
                  if (profile.priceDisplayMode == 'multiple' ||
                      profile.priceDisplayCurrencies.length > 1)
                    Text(
                      '${labels.total}: ${_formatMoney(sale.total, profile, forceCurrencies: const [
                            'USD',
                            'LBP'
                          ])}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (profile.footerNote.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(profile.footerNote, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 18),
                  Text(labels.thankYou, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: style)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _ThermalLabels {
  const _ThermalLabels.en()
      : invoice = 'Invoice',
        date = 'Date',
        customer = 'Customer',
        subtotal = 'Subtotal',
        discount = 'Discount',
        total = 'Total',
        thankYou = 'Thank you';

  const _ThermalLabels.ar()
      : invoice = 'فاتورة',
        date = 'التاريخ',
        customer = 'العميل',
        subtotal = 'المجموع الفرعي',
        discount = 'الخصم',
        total = 'الإجمالي',
        thankYou = 'شكراً لزيارتكم';

  const _ThermalLabels.fr()
      : invoice = 'Facture',
        date = 'Date',
        customer = 'Client',
        subtotal = 'Sous-total',
        discount = 'Remise',
        total = 'Total',
        thankYou = 'Merci de votre visite';

  final String invoice;
  final String date;
  final String customer;
  final String subtotal;
  final String discount;
  final String total;
  final String thankYou;
}

String _formatQuantity(double value) {
  return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(3);
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _formatMoney(
  double usdAmount,
  StoreProfile profile, {
  List<String>? forceCurrencies,
}) {
  String formatAs(String currency) {
    final code = currency.toUpperCase();
    final definition = profile.currencyByCode(code);
    final amount = code == 'USD'
        ? usdAmount
        : usdAmount *
            (profile.exchangeRateForDate('USD', code)?.rate ??
                (code == 'LBP' ? profile.usdToLbpRate : 1));
    final rounded = definition.roundingStep > 0
        ? roundCashAmount(
            amount,
            definition.roundingStep,
            method: definition.roundingMethod,
          )
        : amount;
    final value = definition.decimalPlaces == 0
        ? rounded.round().toString()
        : rounded.toStringAsFixed(definition.decimalPlaces);
    return '${definition.symbol} $value';
  }

  final codes = forceCurrencies ??
      (profile.priceDisplayMode == 'multiple'
          ? profile.priceDisplayCurrencies
          : <String>[profile.defaultSaleInvoiceCurrency]);
  return codes.map(formatAs).join(' / ');
}
