import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/product.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';

class PriceListPdfService {
  static Future<Uint8List> build({
    required List<Product> products,
    required StoreProfile profile,
    required String title,
    bool arabic = false,
  }) async {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
    String money(double value) => _formatMoney(value, profile);
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (_) => [
        pw.Text(profile.name, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          border: null,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: [arabic ? 'المنتج' : 'Product', arabic ? 'الكود' : 'Code', arabic ? 'الفئة' : 'Category', arabic ? 'الوحدة' : 'Unit', arabic ? 'السعر' : 'Price'],
          data: products.map((p) => [p.name, p.code, p.category, p.unit, money(p.price)]).toList(),
        ),
      ],
    ));
    return pdf.save();
  }

  static Future<void> printPriceList({required List<Product> products, required StoreProfile profile, required String title, bool arabic = false}) async {
    final bytes = await build(products: products, profile: profile, title: title, arabic: arabic);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'price-list');
  }

  static String _formatMoney(double usd, StoreProfile profile) {
    final code = profile.defaultSaleInvoiceCurrency.toUpperCase();
    final definition = profile.currencyByCode(code);
    final amount = code == 'USD' ? usd : usd * (profile.exchangeRateForDate('USD', code)?.rate ?? (code == 'LBP' ? profile.usdToLbpRate : 1));
    final rounded = definition.roundingStep > 0 ? roundCashAmount(amount, definition.roundingStep, method: definition.roundingMethod) : amount;
    return '${definition.symbol} ${definition.decimalPlaces == 0 ? rounded.round() : rounded.toStringAsFixed(definition.decimalPlaces)}';
  }
}
