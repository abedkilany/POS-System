import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';



import '../../models/sale.dart';
import '../../models/store_profile.dart';

class InvoicePdfService {
  static Future<Uint8List> buildInvoicePdf({
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
    );
    final isArabic = locale.languageCode == 'ar';
    final labels = _InvoicePdfLabels(isArabic);
    final textDirection = isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: textDirection,
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(profile.name, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  if (profile.phone.isNotEmpty) pw.Text('${labels.phone}: ${profile.phone}'),
                  if (profile.address.isNotEmpty) pw.Text('${labels.address}: ${profile.address}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(labels.invoice, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${labels.no}: ${sale.invoiceNo}'),
                  pw.Text('${labels.date}: ${sale.date.toLocal()}'.split('.').first),
                  pw.Text('${labels.customer}: ${sale.customerName}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: [labels.item, labels.qty, labels.unitPrice, labels.lineTotal],
            data: sale.items
                .map(
                  (item) => [
                    item.productName,
                    item.quantity % 1 == 0 ? item.quantity.toStringAsFixed(0) : item.quantity.toStringAsFixed(3),
                    _formatMoney(item.unitPrice, profile),
                    _formatMoney(item.lineTotal, profile),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _summaryLine(labels.subtotal, _formatMoney(sale.subtotal, profile)),
                  _summaryLine(labels.discount, _formatMoney(sale.discount, profile)),
                  pw.Divider(),
                  _summaryLine(labels.total, _formatMoney(sale.total, profile), isBold: true),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(profile.footerNote),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> printInvoice({required Sale sale, required StoreProfile profile, Locale locale = const Locale('en')}) async {
    final bytes = await buildInvoicePdf(sale: sale, profile: profile, locale: locale);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: sale.invoiceNo);
  }

  static Future<void> shareInvoice({required Sale sale, required StoreProfile profile, Locale locale = const Locale('en')}) async {
    final bytes = await buildInvoicePdf(sale: sale, profile: profile, locale: locale);
    await Printing.sharePdf(bytes: bytes, filename: '${sale.invoiceNo}.pdf');
  }

  static pw.Widget _summaryLine(String title, String value, {bool isBold = false}) {
    final style = isBold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(title, style: style), pw.Text(value, style: style)],
      ),
    );
  }

  static String _formatMoney(double usdAmount, StoreProfile profile) {
    String usd() => '\$${usdAmount.toStringAsFixed(2)}';
    String lbp() {
      final converted = usdAmount * profile.usdToLbpRate;
      final rounded = profile.lbpRounding <= 0 ? converted : (converted / profile.lbpRounding).round() * profile.lbpRounding;
      return 'LBP ${rounded.round()}';
    }

    switch (profile.priceDisplayMode) {
      case 'lbp':
        return lbp();
      case 'both':
        return '${usd()} (${lbp()})';
      case 'usd':
      default:
        return usd();
    }
  }
}


class _InvoicePdfLabels {
  const _InvoicePdfLabels(this.isArabic);

  final bool isArabic;

  String get invoice => isArabic ? 'فاتورة' : 'Invoice';
  String get phone => isArabic ? 'الهاتف' : 'Phone';
  String get address => isArabic ? 'العنوان' : 'Address';
  String get no => isArabic ? 'الرقم' : 'No';
  String get date => isArabic ? 'التاريخ' : 'Date';
  String get customer => isArabic ? 'العميل' : 'Customer';
  String get item => isArabic ? 'الصنف' : 'Item';
  String get qty => isArabic ? 'الكمية' : 'Qty';
  String get unitPrice => isArabic ? 'سعر الوحدة' : 'Unit Price';
  String get lineTotal => isArabic ? 'الإجمالي' : 'Line Total';
  String get subtotal => isArabic ? 'المجموع الفرعي' : 'Subtotal';
  String get discount => isArabic ? 'الخصم' : 'Discount';
  String get total => isArabic ? 'الإجمالي' : 'Total';
}
