import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/product.dart';
import '../../models/store_profile.dart';
import '../../models/warehouse.dart';
import 'professional_pdf_theme.dart';

class WarehouseInventoryPdfRow {
  const WarehouseInventoryPdfRow({required this.product, required this.stock});
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
    final labels = _WarehouseInventoryPdfLabels(locale.languageCode);
    final isArabic = labels.isArabic;
    final theme = await ProfessionalPdfTheme.loadTheme();
    final pdf = pw.Document(theme: theme);
    final printableRows = rows.where((row) => row.stock.abs() > 0.000001).toList(growable: false);
    final date = _formatDateTime(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: labels.inventoryReport,
                englishTitle: 'WAREHOUSE INVENTORY',
                isArabic: isArabic,
                meta: [
                  MapEntry(labels.warehouse, warehouse.name),
                  MapEntry(labels.date, date),
                  MapEntry(labels.products, '${printableRows.length}'),
                ],
              )
            : ProfessionalPdfTheme.compactHeader(profile: profile, title: labels.inventoryReport),
        footer: (context) => ProfessionalPdfTheme.footer(context: context, profile: profile, isArabic: isArabic),
        build: (_) => [
          ProfessionalPdfTheme.infoStrip(
            isArabic: isArabic,
            entries: [
              MapEntry(labels.warehouse, warehouse.name),
              if (warehouse.code.trim().isNotEmpty) MapEntry(labels.code, warehouse.code.trim()),
              if (warehouse.location.trim().isNotEmpty) MapEntry(labels.location, warehouse.location.trim()),
            ],
          ),
          pw.SizedBox(height: 14),
          if (printableRows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 30),
              child: pw.Center(child: pw.Text(labels.noItems)),
            )
          else
            ProfessionalPdfTheme.table(
              headers: [labels.item, labels.code, labels.quantity, labels.unit],
              data: printableRows.map((row) => [
                row.product.name,
                row.product.code.trim().isEmpty ? '-' : row.product.code.trim(),
                _formatQuantity(row.stock),
                row.product.unit.trim().isEmpty ? '-' : row.product.unit.trim(),
              ]).toList(growable: false),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.7),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1),
                3: pw.FlexColumnWidth(1),
              },
            ),
          pw.SizedBox(height: 14),
          ProfessionalPdfTheme.summaryBox(
            isArabic: isArabic,
            highlightIndex: 0,
            rows: [MapEntry(labels.products, '${printableRows.length}')],
          ),
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
    final bytes = await buildWarehouseInventoryPdf(warehouse: warehouse, rows: rows, profile: profile, locale: locale);
    final safeName = warehouse.code.trim().isNotEmpty ? warehouse.code.trim() : warehouse.name.trim();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: safeName.isEmpty ? 'warehouse-inventory' : 'inventory-$safeName');
  }

  static String _formatQuantity(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) return value.toStringAsFixed(0);
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static String _formatDateTime(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
