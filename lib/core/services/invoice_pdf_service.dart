import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/sale.dart';
import '../../models/store_profile.dart';

class InvoicePdfService {
  static Future<Uint8List> buildInvoicePdf({
    required Sale sale,
    required StoreProfile profile,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(profile.name, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  if (profile.phone.isNotEmpty) pw.Text('Phone: ${profile.phone}'),
                  if (profile.address.isNotEmpty) pw.Text('Address: ${profile.address}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Invoice', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text('No: ${sale.invoiceNo}'),
                  pw.Text('Date: ${sale.date.toLocal()}'.split('.').first),
                  pw.Text('Customer: ${sale.customerName}'),
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
            headers: const ['Item', 'Qty', 'Unit Price', 'Line Total'],
            data: sale.items
                .map(
                  (item) => [
                    item.productName,
                    '${item.quantity}',
                    _formatMoney(item.unitPrice, profile.currency),
                    _formatMoney(item.lineTotal, profile.currency),
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
                  _summaryLine('Subtotal', _formatMoney(sale.subtotal, profile.currency)),
                  _summaryLine('Discount', _formatMoney(sale.discount, profile.currency)),
                  pw.Divider(),
                  _summaryLine('Total', _formatMoney(sale.total, profile.currency), isBold: true),
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

  static Future<void> printInvoice({required Sale sale, required StoreProfile profile}) async {
    final bytes = await buildInvoicePdf(sale: sale, profile: profile);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: sale.invoiceNo);
  }

  static Future<void> shareInvoice({required Sale sale, required StoreProfile profile}) async {
    final bytes = await buildInvoicePdf(sale: sale, profile: profile);
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

  static String _formatMoney(double amount, String currency) {
    final prefix = switch (currency.toUpperCase()) {
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      'LBP' => 'LBP ',
      'SAR' => 'SAR ',
      'AED' => 'AED ',
      _ => '${currency.toUpperCase()} ',
    };
    return '$prefix${amount.toStringAsFixed(2)}';
  }
}
