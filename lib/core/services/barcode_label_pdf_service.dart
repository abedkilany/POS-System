import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/product.dart';
import '../../models/store_profile.dart';

class BarcodeLabelItem {
  const BarcodeLabelItem({required this.product, required this.quantity});

  final Product product;
  final int quantity;
}

class BarcodeLabelPrintOptions {
  const BarcodeLabelPrintOptions({
    this.labelWidthMm = 50,
    this.labelHeightMm = 30,
    this.marginMm = 1.5,
    this.fontSize = 8,
    this.barcodeHeight = 24,
    this.barcodeWidth = 60,
    this.logoWidth = 60,
    this.productionDate = '',
    this.expiryDate = '',
    this.weight = '',
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
  final Uint8List? logoBytes;
  final Map<String, Offset> elementOffsets;
}

class BarcodeLabelPdfService {
  static Future<Uint8List> buildPdf({
    required List<BarcodeLabelItem> items,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
    BarcodeLabelPrintOptions options = const BarcodeLabelPrintOptions(),
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tahoma.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tahoma-Bold.ttf'),
    );
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
    final margin = options.marginMm * PdfPageFormat.mm;
    final labelWidth = pageWidth - (margin * 2);
    for (final item in labels) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidth, pageHeight),
          margin: pw.EdgeInsets.all(margin),
          textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          build: (_) => _label(
            item,
            width: labelWidth,
            height: pageHeight - (margin * 2),
            options: options,
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

  static pw.Widget _label(
    BarcodeLabelItem item, {
    required double width,
    required double height,
    required BarcodeLabelPrintOptions options,
  }) {
    final product = item.product;
    final hasDates = options.productionDate.trim().isNotEmpty ||
        options.expiryDate.trim().isNotEmpty;
    final hasLogo = options.logoBytes != null && options.logoBytes!.isNotEmpty;
    final hasWeight = options.weight.trim().isNotEmpty;
    final dateText = [
      if (options.productionDate.trim().isNotEmpty)
        'MFG: ${options.productionDate.trim()}',
      if (options.expiryDate.trim().isNotEmpty)
        'EXP: ${options.expiryDate.trim()}',
    ].join('  ');
    final barcodeHeight = hasDates
        ? options.barcodeHeight.clamp(18.0, 22.0).toDouble()
        : options.barcodeHeight;
    final barcodeWidth = options.barcodeWidth
        .clamp(24.0, (width - options.logoWidth - 16).clamp(24.0, 130.0))
        .toDouble();
    return pw.Container(
      width: width,
      height: height,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
      ),
      child: pw.Column(
        children: [
          _positioned(
            options,
            'productName',
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                product.name,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: options.fontSize, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Expanded(
            child: pw.Directionality(
              textDirection: pw.TextDirection.ltr,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(
                    width: options.logoWidth,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        if (hasLogo)
                          _positioned(
                            options,
                            'logo',
                            pw.Container(
                              width: options.logoWidth,
                              height: options.logoWidth * 2 / 3,
                              alignment: pw.Alignment.center,
                              child: pw.Image(
                                pw.MemoryImage(options.logoBytes!),
                                width: options.logoWidth,
                                height: options.logoWidth * 2 / 3,
                                fit: pw.BoxFit.contain,
                              ),
                            ),
                          ),
                        if (hasWeight) ...[
                          pw.SizedBox(height: 3),
                          _positioned(
                            options,
                            'weight',
                            pw.Text(
                              options.weight.trim(),
                              maxLines: 1,
                              overflow: pw.TextOverflow.clip,
                              style: pw.TextStyle(
                                fontSize: options.fontSize - 1,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        _positioned(
                          options,
                          'barcode',
                          pw.Center(
                            child: pw.BarcodeWidget(
                              barcode: pw.Barcode.code128(),
                              data: product.barcode,
                              width: barcodeWidth,
                              height: barcodeHeight,
                              drawText: false,
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Directionality(
                          textDirection: pw.TextDirection.ltr,
                          child: pw.Text(
                            product.barcode,
                            maxLines: 1,
                            softWrap: false,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: options.fontSize - 1,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasDates)
            _positioned(
              options,
              'dates',
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  dateText,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: const pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
