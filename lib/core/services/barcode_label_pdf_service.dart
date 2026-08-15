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
    this.productionDate = '',
    this.expiryDate = '',
    this.weight = '',
    this.logoBytes,
  });

  final double labelWidthMm;
  final double labelHeightMm;
  final double marginMm;
  final double fontSize;
  final double barcodeHeight;
  final String productionDate;
  final String expiryDate;
  final String weight;
  final Uint8List? logoBytes;
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
    final bytes = await buildPdf(
      items: items,
      profile: profile,
      locale: locale,
      options: options,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _BarcodePreviewPage(bytes: bytes, options: options),
      ),
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
    return pw.Container(
      width: width,
      height: height,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            product.name,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
                fontSize: options.fontSize, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: product.barcode,
                        width: width - 62,
                        height: barcodeHeight,
                        drawText: false,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        product.barcode,
                        style: pw.TextStyle(
                          fontSize: options.fontSize - 1,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.SizedBox(
                  width: 48,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      if (hasLogo)
                        pw.Image(
                          pw.MemoryImage(options.logoBytes!),
                          width: 46,
                          height: 30,
                          fit: pw.BoxFit.contain,
                        ),
                      if (hasWeight) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          options.weight.trim(),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                          style: pw.TextStyle(
                            fontSize: options.fontSize,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasDates)
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
        ],
      ),
    );
  }
}

class _BarcodePreviewPage extends StatelessWidget {
  const _BarcodePreviewPage({required this.bytes, required this.options});

  final Uint8List bytes;
  final BarcodeLabelPrintOptions options;

  Future<void> _print(BuildContext context) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    // Let the preview route finish closing before opening the native Windows
    // dialog. Otherwise the dialog can be placed behind the preview window.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'barcode-labels',
      format: PdfPageFormat(
        options.labelWidthMm * PdfPageFormat.mm,
        options.labelHeightMm * PdfPageFormat.mm,
      ),
      dynamicLayout: false,
      usePrinterSettings: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode preview'),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        actions: [
          IconButton(
            tooltip: 'Print',
            onPressed: () => _print(context),
            icon: const Icon(Icons.print),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        pdfFileName: 'barcode-labels.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        useActions: false,
        allowSharing: false,
        allowPrinting: false,
      ),
    );
  }
}
