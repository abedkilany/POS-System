import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/product.dart';
import '../../models/store_profile.dart';
import '../../models/warehouse.dart';

class WarehouseInventoryPdfRow {
  const WarehouseInventoryPdfRow({
    required this.product,
    required this.stock,
  });

  final Product product;
  final double stock;
}

class WarehouseInventoryPdfService {
  static Future<Uint8List> buildWarehouseInventoryPdf({
    required Warehouse warehouse,
    required List<WarehouseInventoryPdfRow> rows,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
    );
    final labels = _WarehouseInventoryPdfLabels(locale.languageCode);
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    final printableRows = rows
        .where((row) => row.stock.abs() > 0.000001)
        .toList(growable: false);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection:
            labels.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    profile.name,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (profile.phone.isNotEmpty)
                    pw.Text('${labels.phone}: ${profile.phone}'),
                  if (profile.address.isNotEmpty)
                    pw.Text('${labels.address}: ${profile.address}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    labels.inventoryReport,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text('${labels.date}: ${_formatDateTime(DateTime.now())}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${labels.warehouse}: ${warehouse.name}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                if (warehouse.code.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('${labels.code}: ${warehouse.code.trim()}'),
                ],
                if (warehouse.location.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('${labels.location}: ${warehouse.location.trim()}'),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          if (printableRows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 24),
              child: pw.Center(child: pw.Text(labels.noItems)),
            )
          else
            pw.TableHelper.fromTextArray(
              border: null,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: [
                labels.item,
                labels.code,
                labels.quantity,
                labels.unit,
              ],
              data: printableRows
                  .map(
                    (row) => [
                      row.product.name,
                      row.product.code.trim().isEmpty
                          ? '-'
                          : row.product.code.trim(),
                      _formatQuantity(row.stock),
                      row.product.unit.trim().isEmpty
                          ? '-'
                          : row.product.unit.trim(),
                    ],
                  )
                  .toList(growable: false),
            ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 250,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    labels.products,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    '${printableRows.length}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          if (profile.footerNote.trim().isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(profile.footerNote),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> printWarehouseInventory({
    required Warehouse warehouse,
    required List<WarehouseInventoryPdfRow> rows,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildWarehouseInventoryPdf(
      warehouse: warehouse,
      rows: rows,
      profile: profile,
      locale: locale,
    );
    final safeName = warehouse.code.trim().isNotEmpty
        ? warehouse.code.trim()
        : warehouse.name.trim();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: safeName.isEmpty ? 'warehouse-inventory' : 'inventory-$safeName',
    );
  }

  static String _formatQuantity(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.toStringAsFixed(0);
    }
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _formatDateTime(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _WarehouseInventoryPdfLabels {
  const _WarehouseInventoryPdfLabels(this.languageCode);

  final String languageCode;

  bool get isArabic => languageCode == 'ar';
  bool get isFrench => languageCode == 'fr';

  String get inventoryReport => isArabic
      ? 'محتوى المستودع'
      : isFrench
          ? 'Contenu de l’entrepôt'
          : 'Warehouse Inventory';
  String get warehouse => isArabic
      ? 'المستودع'
      : isFrench
          ? 'Entrepôt'
          : 'Warehouse';
  String get phone => isArabic
      ? 'الهاتف'
      : isFrench
          ? 'Téléphone'
          : 'Phone';
  String get address => isArabic
      ? 'العنوان'
      : isFrench
          ? 'Adresse'
          : 'Address';
  String get date => isArabic
      ? 'التاريخ'
      : isFrench
          ? 'Date'
          : 'Date';
  String get code => isArabic
      ? 'الكود'
      : isFrench
          ? 'Code'
          : 'Code';
  String get location => isArabic
      ? 'الموقع'
      : isFrench
          ? 'Emplacement'
          : 'Location';
  String get item => isArabic
      ? 'الصنف'
      : isFrench
          ? 'Article'
          : 'Item';
  String get quantity => isArabic
      ? 'الكمية'
      : isFrench
          ? 'Quantité'
          : 'Quantity';
  String get unit => isArabic
      ? 'الوحدة'
      : isFrench
          ? 'Unité'
          : 'Unit';
  String get products => isArabic
      ? 'عدد الأصناف'
      : isFrench
          ? 'Nombre d’articles'
          : 'Products';
  String get noItems => isArabic
      ? 'لا توجد أصناف في هذا المستودع.'
      : isFrench
          ? 'Aucun article dans cet entrepôt.'
          : 'No items in this warehouse.';
}
