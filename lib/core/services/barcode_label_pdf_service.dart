import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/product.dart';
import '../../models/store_profile.dart';

class BarcodeLabelItem {
  const BarcodeLabelItem({
    required this.product,
    required this.quantity,
    this.barcode,
    this.unitName,
    this.price,
    this.priceCurrency,
  });

  final Product product;
  final int quantity;
  final String? barcode;
  final String? unitName;
  final double? price;
  final String? priceCurrency;

  String get effectiveBarcode => barcode?.trim().isNotEmpty == true
      ? barcode!.trim()
      : product.barcode.trim();
}

class BarcodeLabelPrintOptions {
  const BarcodeLabelPrintOptions({
    this.labelWidthMm = 58,
    this.labelHeightMm = 40,
    this.marginMm = 0,
    this.fontSize = 8,
    this.barcodeHeight = 14,
    this.barcodeWidth = 50,
    this.logoWidth = 23,
    this.productionDate = '',
    this.expiryDate = '',
    this.weight = '',
    this.showPrice = false,
    this.logoBytes,
    this.elementOffsets = const <String, Offset>{},
  });

  final double labelWidthMm;
  final double labelHeightMm;
  final double marginMm;
  final double fontSize;
  final double barcodeHeight;
  final double barcodeWidth;
  final double logoWidth;
  final String productionDate;
  final String expiryDate;
  final String weight;
  final bool showPrice;
  final Uint8List? logoBytes;
  final Map<String, Offset> elementOffsets;
}

class BarcodeLabelPdfService {
  static Future<Uint8List> buildPdf({
    required List<BarcodeLabelItem> items,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
    BarcodeLabelPrintOptions options = const BarcodeLabelPrintOptions(),
    bool showGuides = false,
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tahoma.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tahoma-Bold.ttf'),
    );

    // Prefer Arial for the product/weight/price block when the app bundle
    // contains it. Older Ventio packages may not include Arial, so keep a
    // safe Tahoma fallback rather than making barcode printing fail.
    pw.Font productBoldFont = boldFont;
    try {
      productBoldFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Arial-Bold.ttf'),
      );
    } catch (_) {
      // Backward-compatible fallback for installations without Arial assets.
    }
    final isArabic = locale.languageCode == 'ar';
    final labels = <BarcodeLabelItem>[];
    for (final item in items) {
      for (var index = 0; index < item.quantity; index++) {
        labels.add(item);
      }
    }

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    // This is label stock, not receipt paper: every label must be a separate
    // PDF page with the physical label dimensions.  Sending one long 58/80mm
    // page makes Xprinter map the content to the wrong label and clip it.
    final pageWidth = options.labelWidthMm * PdfPageFormat.mm;
    final pageHeight = options.labelHeightMm * PdfPageFormat.mm;
    // The page stays at the physical 58 x 40 mm label size.
    // The template itself applies a fixed 2 mm safety inset on every side.
    const margin = 0.0;
    final labelWidth = pageWidth;
    for (final item in labels) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidth, pageHeight),
          margin: pw.EdgeInsets.all(margin),
          textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          build: (_) => _label(
            item,
            width: labelWidth,
            height: pageHeight,
            options: options,
            profile: profile,
            productBoldFont: productBoldFont,
            showGuides: showGuides,
          ),
        ),
      );
    }
    return pdf.save();
  }

  static Future<void> printLabels({
    required BuildContext context,
    required List<BarcodeLabelItem> items,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
    BarcodeLabelPrintOptions options = const BarcodeLabelPrintOptions(),
  }) async {
    await Printing.layoutPdf(
      onLayout: (_) => buildPdf(
        items: items,
        profile: profile,
        locale: locale,
        options: options,
      ),
      name: 'barcode-labels',
      format: PdfPageFormat(
        options.labelWidthMm * PdfPageFormat.mm,
        options.labelHeightMm * PdfPageFormat.mm,
      ),
      dynamicLayout: false,
      usePrinterSettings: false,
    );
  }

  static bool _isValidEan13(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^\d{13}$').hasMatch(normalized)) {
      return false;
    }

    // EAN-13 check digit: apply alternating 1/3 weights to the first
    // 12 digits, then compare the calculated check digit with digit 13.
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = normalized.codeUnitAt(i) - 48;
      sum += i.isEven ? digit : digit * 3;
    }
    final expectedCheckDigit = (10 - (sum % 10)) % 10;
    final actualCheckDigit = normalized.codeUnitAt(12) - 48;
    return expectedCheckDigit == actualCheckDigit;
  }

  static pw.Widget _label(
    BarcodeLabelItem item, {
    required double width,
    required double height,
    required BarcodeLabelPrintOptions options,
    required StoreProfile profile,
    required pw.Font productBoldFont,
    bool showGuides = false,
  }) {
    final product = item.product;
    final barcode = item.effectiveBarcode;
    final barcodeType = _isValidEan13(barcode)
        ? pw.Barcode.ean13()
        : pw.Barcode.code128();
    final hasLogo = options.logoBytes != null && options.logoBytes!.isNotEmpty;
    final hasWeight = options.weight.trim().isNotEmpty;
    final effectivePrice = item.price ?? product.originalPrice;
    final effectiveCurrency = (item.priceCurrency?.trim().isNotEmpty == true)
        ? item.priceCurrency!.trim().toUpperCase()
        : product.originalCurrency.trim().toUpperCase();
    final priceCurrency = effectiveCurrency.isEmpty ? profile.currency : effectiveCurrency;
    final currencySymbol = profile.currencyByCode(priceCurrency).symbol.trim();
    final priceText = _formatPrice(effectivePrice);
    final priceWithCurrency = currencySymbol.isEmpty
        ? priceText
        : '$priceText $currencySymbol';

    final productionDate = options.productionDate.trim();
    final expiryDate = options.expiryDate.trim();

    // Physical label: 58 x 40 mm.
    // A permanent 2 mm safety inset on every side keeps printable content
    // away from the physical edge when the label stock drifts in the printer.
    // The resulting content area is 54 x 36 mm:
    //   top:     23 x 17 mm logo + 31 x 17 mm product/weight
    //   barcode: 54 x 14 mm (50 mm symbol + 2 mm internal quiet space/side)
    //   dates:   54 x 5 mm
    // Section/safety guides are calibration aids only. They are rendered in
    // preview when showGuides=true and are never included in final printing.
    final safetyInset = 2 * PdfPageFormat.mm;
    final contentWidth = 54 * PdfPageFormat.mm;
    final contentHeight = 36 * PdfPageFormat.mm;
    final topHeight = 17 * PdfPageFormat.mm;
    final logoPanelWidth = 23 * PdfPageFormat.mm;
    final infoPanelWidth = 31 * PdfPageFormat.mm;
    final barcodePanelHeight = 14 * PdfPageFormat.mm;
    final datesPanelHeight = 5 * PdfPageFormat.mm;
    final barcodeSideQuietMargin = 2 * PdfPageFormat.mm;
    final actualBarcodeWidth = 50 * PdfPageFormat.mm;

    const guideWidth = 0.35;
    final guideColor = PdfColors.grey600;

    pw.Border? rightGuide() => showGuides
        ? pw.Border(
            right: pw.BorderSide(color: guideColor, width: guideWidth),
          )
        : null;

    pw.Border? topGuide() => showGuides
        ? pw.Border(
            top: pw.BorderSide(color: guideColor, width: guideWidth),
          )
        : null;

    pw.Widget panel({
      required double panelWidth,
      required double panelHeight,
      required pw.Widget child,
      pw.Border? border,
    }) {
      return pw.Container(
        width: panelWidth,
        height: panelHeight,
        decoration: border == null ? null : pw.BoxDecoration(border: border),
        child: child,
      );
    }

    return pw.Container(
      width: width,
      height: height,
      decoration: showGuides
          ? pw.BoxDecoration(
              border: pw.Border.all(color: guideColor, width: guideWidth),
            )
          : null,
      child: pw.Padding(
        padding: pw.EdgeInsets.all(safetyInset),
        child: pw.Container(
          width: contentWidth,
          height: contentHeight,
          decoration: showGuides
              ? pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColors.grey500,
                    width: guideWidth,
                  ),
                )
              : null,
          child: pw.Column(
            children: [
              pw.SizedBox(
                width: contentWidth,
                height: topHeight,
                child: pw.Directionality(
                  textDirection: pw.TextDirection.ltr,
                  child: pw.Row(
                    children: [
                      panel(
                        panelWidth: logoPanelWidth,
                        panelHeight: topHeight,
                        border: rightGuide(),
                        child: pw.Padding(
                          padding: pw.EdgeInsets.all(1.0 * PdfPageFormat.mm),
                          child: hasLogo
                              ? _positioned(
                                  options,
                                  'logo',
                                  pw.Image(
                                    pw.MemoryImage(options.logoBytes!),
                                    fit: pw.BoxFit.contain,
                                  ),
                                )
                              : pw.SizedBox(),
                        ),
                      ),
                      panel(
                        panelWidth: infoPanelWidth,
                        panelHeight: topHeight,
                        child: pw.Padding(
                          padding: pw.EdgeInsets.symmetric(
                            horizontal: 1.2 * PdfPageFormat.mm,
                            vertical: 1.0 * PdfPageFormat.mm,
                          ),
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              _positioned(
                                options,
                                'productName',
                                pw.Directionality(
                                  textDirection: pw.TextDirection.rtl,
                                  child: pw.Text(
                                    product.name,
                                    maxLines: 2,
                                    overflow: pw.TextOverflow.clip,
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(
                                      font: productBoldFont,
                                      fontSize: options.fontSize + 1.5,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              _positioned(
                                options,
                                'weight',
                                pw.Directionality(
                                  textDirection: pw.TextDirection.rtl,
                                  child: pw.Column(
                                    mainAxisSize: pw.MainAxisSize.min,
                                    children: [
                                      if (hasWeight)
                                        pw.Text(
                                          'الوزن: ${options.weight.trim()}',
                                          maxLines: 1,
                                          overflow: pw.TextOverflow.clip,
                                          textAlign: pw.TextAlign.center,
                                          style: pw.TextStyle(
                                            font: productBoldFont,
                                            fontSize: options.fontSize,
                                            fontWeight: pw.FontWeight.bold,
                                          ),
                                        ),
                                      if (hasWeight && options.showPrice)
                                        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
                                      if (options.showPrice)
                                        pw.Text(
                                          'السعر: $priceWithCurrency',
                                          maxLines: 1,
                                          overflow: pw.TextOverflow.clip,
                                          textAlign: pw.TextAlign.center,
                                          style: pw.TextStyle(
                                            font: productBoldFont,
                                            fontSize: options.fontSize + 2.5,
                                            fontWeight: pw.FontWeight.bold,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Container(
                width: contentWidth,
                height: barcodePanelHeight,
                decoration: topGuide() == null
                    ? null
                    : pw.BoxDecoration(border: topGuide()),
                child: pw.Padding(
                  padding: pw.EdgeInsets.symmetric(
                    horizontal: barcodeSideQuietMargin,
                    vertical: 0.65 * PdfPageFormat.mm,
                  ),
                  child: _positioned(
                    options,
                    'barcode',
                    pw.Center(
                      child: pw.Directionality(
                        textDirection: pw.TextDirection.ltr,
                        child: pw.BarcodeWidget(
                          // Auto retail mode: valid 13-digit EAN codes use
                          // native EAN-13 rendering (guard bars + integrated
                          // human-readable digits). Everything else falls back
                          // to Code 128 to preserve existing/internal barcodes.
                          barcode: barcodeType,
                          data: barcode,
                          width: actualBarcodeWidth,
                          height:
                              barcodePanelHeight - (1.3 * PdfPageFormat.mm),
                          drawText: true,
                          textStyle: const pw.TextStyle(
                            fontSize: 6.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textPadding: 0.55 * PdfPageFormat.mm,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              pw.Container(
                width: contentWidth,
                height: datesPanelHeight,
                decoration: topGuide() == null
                    ? null
                    : pw.BoxDecoration(border: topGuide()),
                child: _positioned(
                  options,
                  'dates',
                  pw.Directionality(
                    textDirection: pw.TextDirection.ltr,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        if (productionDate.isNotEmpty)
                          pw.Text(
                            'MFG: $productionDate',
                            maxLines: 1,
                            style: const pw.TextStyle(
                              fontSize: 6.2,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (productionDate.isNotEmpty && expiryDate.isNotEmpty)
                          pw.SizedBox(width: 2.5 * PdfPageFormat.mm),
                        if (expiryDate.isNotEmpty)
                          pw.Text(
                            'EXP: $expiryDate',
                            maxLines: 1,
                            style: const pw.TextStyle(
                              fontSize: 6.2,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  static String _formatPrice(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static pw.Widget _positioned(
    BarcodeLabelPrintOptions options,
    String element,
    pw.Widget child,
  ) {
    final offset = options.elementOffsets[element] ?? Offset.zero;
    if (offset == Offset.zero) return child;
    return pw.Transform.translate(
      offset: PdfPoint(offset.dx, -offset.dy),
      child: child,
    );
  }
}
