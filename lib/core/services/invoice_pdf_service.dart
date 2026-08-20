import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/sale.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';

class InvoicePdfService {
  static const PdfColor _navy = PdfColor(0.035, 0.13, 0.25);
  static const PdfColor _gold = PdfColor(0.84, 0.61, 0.10);
  static const PdfColor _ink = PdfColor(0.08, 0.11, 0.17);
  static const PdfColor _muted = PdfColor(0.39, 0.43, 0.50);
  static const PdfColor _line = PdfColor(0.86, 0.88, 0.91);
  static const PdfColor _soft = PdfColor(0.972, 0.976, 0.982);

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
    final labels = _InvoicePdfLabels(locale.languageCode);
    final isArabic = locale.languageCode == 'ar';
    final logoBytes = _logoBytes(profile.logoDataBase64);

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection:
            isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? _buildHeroHeader(
                sale: sale,
                profile: profile,
                logoBytes: logoBytes,
                labels: labels,
                isArabic: isArabic,
              )
            : _buildCompactHeader(
                profile: profile,
                sale: sale,
                labels: labels,
              ),
        footer: (context) => _buildFooter(
          context: context,
          profile: profile,
          labels: labels,
        ),
        build: (_) => <pw.Widget>[
          _buildCustomerPaymentStrip(
            sale: sale,
            labels: labels,
            isArabic: isArabic,
          ),
          pw.SizedBox(height: 14),
          _buildItemsTable(
            sale: sale,
            profile: profile,
            labels: labels,
            isArabic: isArabic,
          ),
          pw.SizedBox(height: 17),
          _buildBottomSection(
            sale: sale,
            profile: profile,
            labels: labels,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> printInvoice({
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildInvoicePdf(
      sale: sale,
      profile: profile,
      locale: locale,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: sale.invoiceNo,
    );
  }

  static Future<void> shareInvoice({
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildInvoicePdf(
      sale: sale,
      profile: profile,
      locale: locale,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${sale.invoiceNo}.pdf',
    );
  }

  static pw.Widget _buildHeroHeader({
    required Sale sale,
    required StoreProfile profile,
    required Uint8List? logoBytes,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Column(
      children: [
        _brandRule(),
        pw.SizedBox(height: 16),
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 31,
              child: _invoiceInfoBlock(
                sale: sale,
                labels: labels,
                isArabic: isArabic,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              flex: 38,
              child: _centerBrandBlock(
                profile: profile,
                logoBytes: logoBytes,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              flex: 31,
              child: _companyInfoBlock(
                profile: profile,
                isArabic: isArabic,
              ),
            ),
          ],
        ),
        ),
        pw.SizedBox(height: 15),
      ],
    );
  }

  static pw.Widget _brandRule() {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
      children: [
        pw.Container(width: 4, height: 4, decoration: const pw.BoxDecoration(color: _gold, shape: pw.BoxShape.circle)),
        pw.SizedBox(width: 5),
        pw.Expanded(flex: 42, child: pw.Container(height: 2.2, color: _navy)),
        pw.Expanded(flex: 18, child: pw.Container(height: 2.2, color: _gold)),
        pw.Expanded(flex: 42, child: pw.Container(height: 2.2, color: _navy)),
        pw.SizedBox(width: 5),
        pw.Container(width: 4, height: 4, decoration: const pw.BoxDecoration(color: _gold, shape: pw.BoxShape.circle)),
      ],
    ),
    );
  }

  static pw.Widget _invoiceInfoBlock({
    required Sale sale,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          labels.salesInvoice,
          textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          style: pw.TextStyle(
            color: _navy,
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'SALES INVOICE',
          textDirection: pw.TextDirection.ltr,
          style: const pw.TextStyle(
            color: _gold,
            fontSize: 7.2,
            letterSpacing: 1.8,
          ),
        ),
        pw.SizedBox(height: 14),
        _metaItem(labels.invoiceNo, sale.invoiceNo),
        pw.SizedBox(height: 8),
        _metaItem(labels.date, _formatDate(sale.date)),
        pw.SizedBox(height: 8),
        _metaItem(labels.time, _formatTime(sale.date)),
      ],
    );
  }

  static pw.Widget _metaItem(String label, String value) {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 17,
          height: 17,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _navy, width: .8),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Text(
            label.isEmpty ? '' : label.substring(0, 1),
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: _navy,
            ),
          ),
        ),
        pw.SizedBox(width: 7),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 6.8, color: _muted),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                value,
                textDirection: pw.TextDirection.ltr,
                style: pw.TextStyle(
                  fontSize: 8.2,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }

  static pw.Widget _centerBrandBlock({
    required StoreProfile profile,
    required Uint8List? logoBytes,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logoBytes != null)
          pw.Container(
            height: 88,
            alignment: pw.Alignment.center,
            child: pw.Image(
              pw.MemoryImage(logoBytes),
              fit: pw.BoxFit.contain,
            ),
          )
        else
          pw.Container(
            height: 74,
            alignment: pw.Alignment.center,
            child: pw.Text(
              profile.name,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: _navy,
              ),
            ),
          ),
      ],
    );
  }

  static pw.Widget _companyInfoBlock({
    required StoreProfile profile,
    required bool isArabic,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          profile.name,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 15.5,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
          ),
        ),
        pw.SizedBox(height: 6),
        if (profile.phone.trim().isNotEmpty)
          _companyLine(
            label: profile.phone.trim(),
            isArabic: false,
          ),
        if (profile.address.trim().isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _companyLine(
            label: profile.address.trim(),
            isArabic: isArabic,
          ),
        ],
      ],
    );
  }

  static pw.Widget _companyLine({
    required String label,
    required bool isArabic,
  }) {
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 5,
          height: 5,
          margin: const pw.EdgeInsets.only(top: 3),
          decoration: const pw.BoxDecoration(color: _gold, shape: pw.BoxShape.circle),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(
            label,
            textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(
              fontSize: 7.4,
              color: _ink,
              lineSpacing: 1.7,
            ),
          ),
        ),
      ],
    ),
    );
  }

  static pw.Widget _buildCompactHeader({
    required StoreProfile profile,
    required Sale sale,
    required _InvoicePdfLabels labels,
  }) {
    return pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                profile.name,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
            ),
            pw.Text(
              '${labels.invoiceNo}: ${sale.invoiceNo}',
              textDirection: pw.TextDirection.ltr,
              style: const pw.TextStyle(fontSize: 7, color: _muted),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 1, color: _navy),
        pw.SizedBox(height: 9),
      ],
    );
  }

  static pw.Widget _buildCustomerPaymentStrip({
    required Sale sale,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 17, vertical: 12),
      decoration: pw.BoxDecoration(
        color: _soft,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Row(
        children: [
          pw.Expanded(
            child: _stripInfo(
              label: labels.customer,
              value: sale.customerName,
              alignRight: false,
              valueDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            ),
          ),
          pw.Container(width: .7, height: 34, color: _line),
          pw.Expanded(
            child: _stripInfo(
              label: labels.paymentMethod,
              value: _paymentMethodLabel(sale.paymentMethod, labels),
              alignRight: true,
              valueDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            ),
          ),
        ],
      ),
      ),
    );
  }

  static pw.Widget _stripInfo({
    required String label,
    required String value,
    required bool alignRight,
    required pw.TextDirection valueDirection,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12),
      child: pw.Column(
        crossAxisAlignment:
            alignRight ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7.6,
              fontWeight: pw.FontWeight.bold,
              color: _navy,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            textDirection: valueDirection,
            textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 10.2,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable({
    required Sale sale,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    final headers = <String>[
      labels.item,
      labels.qty,
      labels.unitPrice,
      labels.lineTotal,
    ];

    final data = sale.items.map((item) {
      final quantity = item.quantity % 1 == 0
          ? item.quantity.toStringAsFixed(0)
          : item.quantity.toStringAsFixed(3);
      return <String>[
        item.productName,
        quantity,
        _formatMoney(item.unitPrice, profile),
        _formatMoney(item.lineTotal, profile),
      ];
    }).toList(growable: false);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerCount: 1,
      border: const pw.TableBorder(
        left: pw.BorderSide(color: _line, width: .55),
        right: pw.BorderSide(color: _line, width: .55),
        bottom: pw.BorderSide(color: _line, width: .55),
        horizontalInside: pw.BorderSide(color: _line, width: .5),
        verticalInside: pw.BorderSide(color: _line, width: .45),
      ),
      headerDecoration: pw.BoxDecoration(
        color: _navy,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 8.1,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8.4, color: _ink),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(5.0),
        1: pw.FlexColumnWidth(1.25),
        2: pw.FlexColumnWidth(2.0),
        3: pw.FlexColumnWidth(2.0),
      },
      headerAlignment: pw.Alignment.center,
      cellAlignments: <int, pw.Alignment>{
        0: isArabic ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
      },
    );
  }

  static pw.Widget _buildBottomSection({
    required Sale sale,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
  }) {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 175,
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: pw.BoxDecoration(
            color: _soft,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 31,
                height: 31,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _gold, width: 1.4),
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Text(
                  '✓',
                  style: pw.TextStyle(
                    color: _gold,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              pw.SizedBox(height: 9),
              pw.Text(
                labels.thankYou,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(width: 38, height: 2, color: _gold),
            ],
          ),
        ),
        pw.SizedBox(width: 30),
        pw.Expanded(
          child: pw.Column(
            children: [
              _totalsLine(
                label: labels.subtotal,
                value: _formatMoney(sale.subtotal, profile),
              ),
              pw.SizedBox(height: 8),
              _totalsLine(
                label: labels.discount,
                value: _formatMoney(sale.discount, profile),
              ),
              pw.SizedBox(height: 10),
              pw.Container(height: .8, color: _line),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 17, vertical: 13),
                decoration: pw.BoxDecoration(
                  color: _navy,
                  borderRadius: pw.BorderRadius.circular(5),
                  border: const pw.Border(
                    right: pw.BorderSide(color: _gold, width: 5),
                  ),
                ),
                child: pw.Directionality(
                  textDirection: pw.TextDirection.ltr,
                  child: pw.Row(
                    children: [
                    pw.Text(
                      _formatMoney(sale.total, profile),
                      textDirection: pw.TextDirection.ltr,
                      style: pw.TextStyle(
                        fontSize: 17.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Spacer(),
                    pw.Text(
                      labels.total,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    ],
                  ),
                ),
              ),
              if (sale.note.trim().isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text(
                  sale.note.trim(),
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
    );
  }

  static pw.Widget _totalsLine({
    required String label,
    required String value,
  }) {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
      children: [
        pw.Text(
          value,
          textDirection: pw.TextDirection.ltr,
          style: pw.TextStyle(
            fontSize: 10.2,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.Spacer(),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 8.2, color: _ink),
        ),
      ],
    ),
    );
  }

  static pw.Widget _buildFooter({
    required pw.Context context,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
  }) {
    final contact = <String>[
      if (profile.phone.trim().isNotEmpty) profile.phone.trim(),
      if (profile.address.trim().isNotEmpty) profile.address.trim(),
    ].join('   |   ');

    return pw.Column(
      children: [
        pw.SizedBox(height: 9),
        _brandRule(),
        pw.SizedBox(height: 7),
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(
          children: [
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 6, color: _muted),
            ),
            pw.Expanded(
              child: pw.Text(
                contact.isEmpty ? profile.name : contact,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 6.3, color: _muted),
              ),
            ),
            pw.SizedBox(width: 38),
          ],
        ),
        ),
      ],
    );
  }

  static String _paymentMethodLabel(
    String raw,
    _InvoicePdfLabels labels,
  ) {
    final value = raw.trim().toLowerCase();
    if (value == 'cash' || value == 'نقد' || value == 'نقداً') {
      return labels.cash;
    }
    if (value == 'card' || value == 'credit card' || value == 'visa') {
      return labels.card;
    }
    if (value == 'credit' || value == 'deferred' || value == 'آجل') {
      return labels.credit;
    }
    return raw.trim().isEmpty ? labels.cash : raw.trim();
  }

  static Uint8List? _logoBytes(String rawBase64) {
    final value = rawBase64.trim();
    if (value.isEmpty) return null;
    try {
      final normalized = value.startsWith('data:image/')
          ? value.substring(value.indexOf(',') + 1)
          : value;
      return base64Decode(normalized);
    } catch (_) {
      return null;
    }
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year}';
  }

  static String _formatTime(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  static String _formatMoney(double usdAmount, StoreProfile profile) {
    String formatAs(String currency) {
      final code = currency.toUpperCase();
      final definition = profile.currencyByCode(code);
      final amount = code == 'USD'
          ? usdAmount
          : usdAmount *
              (profile.exchangeRateForDate('USD', code)?.rate ??
                  (code == 'LBP' ? profile.usdToLbpRate : 1));
      final rounded = definition.roundingStep > 0
          ? roundCashAmount(
              amount,
              definition.roundingStep,
              method: definition.roundingMethod,
            )
          : amount;
      final decimals = definition.decimalPlaces;
      final value = decimals == 0
          ? rounded.round().toString()
          : rounded.toStringAsFixed(decimals);
      return '${definition.symbol} $value';
    }

    switch (profile.priceDisplayMode) {
      case 'multiple':
        final codes = profile.priceDisplayCurrencies.isEmpty
            ? <String>[profile.defaultSaleInvoiceCurrency]
            : profile.priceDisplayCurrencies;
        return codes.map(formatAs).join(' / ');
      case 'selectable':
      case 'default':
      default:
        return formatAs(profile.defaultSaleInvoiceCurrency);
    }
  }
}

class _InvoicePdfLabels {
  const _InvoicePdfLabels(this.languageCode);

  final String languageCode;
  bool get isArabic => languageCode == 'ar';
  bool get isFrench => languageCode == 'fr';

  String get invoiceNo => isArabic
      ? 'رقم الفاتورة'
      : isFrench
          ? 'N° facture'
          : 'Invoice No.';
  String get salesInvoice => isArabic
      ? 'فاتورة مبيعات'
      : isFrench
          ? 'Facture de vente'
          : 'Sales Invoice';
  String get date => isArabic
      ? 'التاريخ'
      : isFrench
          ? 'Date'
          : 'Date';
  String get time => isArabic
      ? 'الوقت'
      : isFrench
          ? 'Heure'
          : 'Time';
  String get customer => isArabic
      ? 'العميل'
      : isFrench
          ? 'Client'
          : 'Customer';
  String get paymentMethod => isArabic
      ? 'طريقة الدفع'
      : isFrench
          ? 'Mode de paiement'
          : 'Payment Method';
  String get cash => isArabic
      ? 'نقداً'
      : isFrench
          ? 'Espèces'
          : 'Cash';
  String get card => isArabic
      ? 'بطاقة'
      : isFrench
          ? 'Carte'
          : 'Card';
  String get credit => isArabic
      ? 'آجل'
      : isFrench
          ? 'À crédit'
          : 'Credit';
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
  String get unitPrice => isArabic
      ? 'سعر الوحدة'
      : isFrench
          ? 'Prix unitaire'
          : 'Unit Price';
  String get lineTotal => isArabic
      ? 'الإجمالي'
      : isFrench
          ? 'Total ligne'
          : 'Line Total';
  String get subtotal => isArabic
      ? 'المجموع الفرعي'
      : isFrench
          ? 'Sous-total'
          : 'Subtotal';
  String get discount => isArabic
      ? 'الخصم'
      : isFrench
          ? 'Remise'
          : 'Discount';
  String get total => isArabic
      ? 'الإجمالي'
      : isFrench
          ? 'Total'
          : 'Total';
  String get thankYou => isArabic
      ? 'شكراً لتسوقكم معنا'
      : isFrench
          ? 'Merci pour votre achat'
          : 'Thank you for shopping with us';
}
