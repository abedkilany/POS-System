import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/store_profile.dart';
import '../../models/warehouse_transfer_order.dart';
import 'professional_pdf_theme.dart';

class WarehouseTransferPdfService {
  static Future<Uint8List> buildTransferOrderPdf({
    required WarehouseTransferOrder order,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final labels = _WarehouseTransferPdfLabels(locale.languageCode);
    final isArabic = labels.isArabic;
    final theme = await ProfessionalPdfTheme.loadTheme();
    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: labels.transferOrder,
                englishTitle: 'STOCK TRANSFER ORDER',
                isArabic: isArabic,
                meta: [
                  MapEntry(labels.no, order.orderNo),
                  MapEntry(labels.date, _formatDateTime(order.date)),
                  MapEntry(labels.products, '${order.items.length}'),
                ],
              )
            : ProfessionalPdfTheme.compactHeader(profile: profile, title: labels.transferOrder),
        footer: (context) => ProfessionalPdfTheme.footer(context: context, profile: profile, isArabic: isArabic),
        build: (_) => [
          ProfessionalPdfTheme.infoStrip(
            isArabic: isArabic,
            entries: [
              MapEntry(labels.from, order.fromWarehouseName),
              MapEntry(labels.to, order.toWarehouseName),
              if (order.createdByUserName.trim().isNotEmpty) MapEntry(labels.createdBy, order.createdByUserName.trim()),
            ],
          ),
          pw.SizedBox(height: 14),
          ProfessionalPdfTheme.table(
            headers: [labels.item, labels.quantity, labels.unit],
            data: order.items.map((item) => [
              item.productName,
              _formatQuantity(item.quantity),
              item.unitName.trim().isEmpty ? '-' : item.unitName,
            ]).toList(growable: false),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
            },
          ),
          pw.SizedBox(height: 14),
          ProfessionalPdfTheme.summaryBox(
            isArabic: isArabic,
            highlightIndex: 1,
            rows: [
              MapEntry(labels.products, '${order.items.length}'),
              MapEntry(labels.totalBaseUnits, _formatQuantity(order.totalUnits)),
            ],
          ),
          if (order.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            ProfessionalPdfTheme.note(labels.notes, order.notes.trim(), isArabic: isArabic),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> printTransferOrder({
    required WarehouseTransferOrder order,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildTransferOrderPdf(order: order, profile: profile, locale: locale);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: order.orderNo.isEmpty ? 'warehouse-transfer' : order.orderNo);
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

class _WarehouseTransferPdfLabels {
  const _WarehouseTransferPdfLabels(this.languageCode);

  final String languageCode;

  bool get isArabic => languageCode == 'ar';
  bool get isFrench => languageCode == 'fr';

  String get transferOrder => isArabic
      ? 'أوردر نقل مخزون'
      : isFrench
          ? 'Ordre de transfert de stock'
          : 'Stock Transfer Order';
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
  String get no => isArabic
      ? 'الرقم'
      : isFrench
          ? 'N°'
          : 'No';
  String get date => isArabic
      ? 'التاريخ'
      : isFrench
          ? 'Date'
          : 'Date';
  String get from => isArabic
      ? 'من المستودع'
      : isFrench
          ? 'Depuis l’entrepôt'
          : 'From warehouse';
  String get to => isArabic
      ? 'إلى المستودع'
      : isFrench
          ? 'Vers l’entrepôt'
          : 'To warehouse';
  String get createdBy => isArabic
      ? 'أنشأ بواسطة'
      : isFrench
          ? 'Créé par'
          : 'Created by';
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
  String get totalBaseUnits => isArabic
      ? 'إجمالي الكمية الأساسية'
      : isFrench
          ? 'Quantité de base totale'
          : 'Total base quantity';
  String get notes => isArabic
      ? 'ملاحظات'
      : isFrench
          ? 'Notes'
          : 'Notes';
}
