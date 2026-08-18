import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/purchase.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';

class PurchasePdfService {
  static Future<Uint8List> buildPurchasePdf({
    required Purchase purchase,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
    );
    final labels = _PurchasePdfLabels(locale.languageCode);
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
                  pw.Text(profile.name,
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  if (profile.phone.isNotEmpty)
                    pw.Text('${labels.phone}: ${profile.phone}'),
                  if (profile.address.isNotEmpty)
                    pw.Text('${labels.address}: ${profile.address}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(labels.invoice,
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${labels.no}: ${purchase.purchaseNo}'),
                  pw.Text('${labels.date}: ${_formatDate(purchase.date)}'),
                  pw.Text(
                      '${labels.supplier}: ${purchase.supplierName.isEmpty ? '-' : purchase.supplierName}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: [labels.item, labels.qty, labels.unitCost, labels.total],
            data: purchase.items
                .map((item) => [
                      item.productName,
                      _formatQuantity(item.quantity),
                      formatCurrency(item.originalUnitCost ?? item.unitCost,
                          currency: item.unitCostCurrency),
                      _formatMoney(item.lineTotal, profile),
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400)),
              child: _summaryLine(
                  labels.total, _formatMoney(purchase.subtotal, profile)),
            ),
          ),
          if (purchase.note.trim().isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text('${labels.notes}: ${purchase.note.trim()}'),
          ],
          pw.SizedBox(height: 24),
          pw.Text(profile.footerNote),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> printPurchase({
    required Purchase purchase,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildPurchasePdf(
        purchase: purchase, profile: profile, locale: locale);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: purchase.purchaseNo,
    );
  }

  static pw.Widget _summaryLine(String title, String value) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      );

  static String _formatQuantity(double value) => value % 1 == 0
      ? value.toStringAsFixed(0)
      : value
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  static String _formatMoney(double amount, StoreProfile profile) =>
      formatUsdReferenceAmount(amount, profile);
}

class _PurchasePdfLabels {
  const _PurchasePdfLabels(this.languageCode);
  final String languageCode;
  bool get isArabic => languageCode == 'ar';
  bool get isFrench => languageCode == 'fr';
  String get invoice => isArabic
      ? 'فاتورة شراء'
      : isFrench
          ? 'Facture d’achat'
          : 'Purchase Invoice';
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
  String get supplier => isArabic
      ? 'المورد'
      : isFrench
          ? 'Fournisseur'
          : 'Supplier';
  String get item => isArabic
      ? 'الصنف'
      : isFrench
          ? 'Article'
          : 'Item';
  String get qty => isArabic
      ? 'الكمية'
      : isFrench
          ? 'Qté'
          : 'Qty';
  String get unitCost => isArabic
      ? 'تكلفة الوحدة'
      : isFrench
          ? 'Coût unitaire'
          : 'Unit Cost';
  String get total => isArabic
      ? 'الإجمالي'
      : isFrench
          ? 'Total'
          : 'Total';
  String get notes => isArabic
      ? 'ملاحظات'
      : isFrench
          ? 'Notes'
          : 'Notes';
}
