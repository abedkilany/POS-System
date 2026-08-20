import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/store_profile.dart';
import '../../models/warehouse_transfer_order.dart';

class WarehouseTransferPdfService {
  static Future<Uint8List> buildTransferOrderPdf({
    required WarehouseTransferOrder order,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
    );
    final labels = _WarehouseTransferPdfLabels(locale.languageCode);
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

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
                    labels.transferOrder,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text('${labels.no}: ${order.orderNo}'),
                  pw.Text('${labels.date}: ${_formatDateTime(order.date)}'),
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
                pw.Text('${labels.from}: ${order.fromWarehouseName}'),
                pw.SizedBox(height: 4),
                pw.Text('${labels.to}: ${order.toWarehouseName}'),
                if (order.createdByUserName.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('${labels.createdBy}: ${order.createdByUserName}'),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: [labels.item, labels.quantity, labels.unit],
            data: order.items
                .map(
                  (item) => [
                    item.productName,
                    _formatQuantity(item.quantity),
                    item.unitName.trim().isEmpty ? '-' : item.unitName,
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
              child: pw.Column(
                children: [
                  _summaryLine(labels.products, '${order.items.length}'),
                  pw.SizedBox(height: 6),
                  _summaryLine(labels.totalBaseUnits, _formatQuantity(order.totalUnits)),
                ],
              ),
            ),
          ),
          if (order.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text(
              '${labels.notes}: ${order.notes.trim()}',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ],
          if (profile.footerNote.trim().isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(profile.footerNote),
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
    final bytes = await buildTransferOrderPdf(
      order: order,
      profile: profile,
      locale: locale,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: order.orderNo.isEmpty ? 'warehouse-transfer' : order.orderNo,
    );
  }

  static pw.Widget _summaryLine(String title, String value) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      );

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
