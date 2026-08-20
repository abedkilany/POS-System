import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/purchase.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';

class PurchasePdfService {
  static const PdfColor _navy = PdfColor(0.035, 0.13, 0.25);
  static const PdfColor _gold = PdfColor(0.84, 0.61, 0.10);
  static const PdfColor _ink = PdfColor(0.08, 0.11, 0.17);
  static const PdfColor _muted = PdfColor(0.39, 0.43, 0.50);
  static const PdfColor _line = PdfColor(0.86, 0.88, 0.91);
  static const PdfColor _soft = PdfColor(0.972, 0.976, 0.982);

  static Future<Uint8List> buildPurchasePdf({
    required Purchase purchase,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tahoma.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tahoma-Bold.ttf'),
    );
    final labels = _PurchasePdfLabels(locale.languageCode);
    final isArabic = labels.isArabic;
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
                purchase: purchase,
                profile: profile,
                logoBytes: logoBytes,
                labels: labels,
                isArabic: isArabic,
              )
            : _buildCompactHeader(
                profile: profile,
                purchase: purchase,
                labels: labels,
              ),
        footer: (context) => _buildFooter(
          context: context,
          profile: profile,
        ),
        build: (_) => <pw.Widget>[
          _buildSupplierPaymentStrip(
            purchase: purchase,
            labels: labels,
            isArabic: isArabic,
          ),
          pw.SizedBox(height: 14),
          _buildItemsTable(
            purchase: purchase,
            profile: profile,
            labels: labels,
            isArabic: isArabic,
          ),
          pw.SizedBox(height: 17),
          _buildBottomSection(
            purchase: purchase,
            profile: profile,
            labels: labels,
            isArabic: isArabic,
          ),
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
      purchase: purchase,
      profile: profile,
      locale: locale,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: purchase.purchaseNo,
    );
  }

  static pw.Widget _buildHeroHeader({
    required Purchase purchase,
    required StoreProfile profile,
    required Uint8List? logoBytes,
    required _PurchasePdfLabels labels,
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
                  purchase: purchase,
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
          pw.Container(
            width: 4,
            height: 4,
            decoration: const pw.BoxDecoration(
              color: _gold,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Expanded(
              flex: 42, child: pw.Container(height: 2.2, color: _navy)),
          pw.Expanded(
              flex: 18, child: pw.Container(height: 2.2, color: _gold)),
          pw.Expanded(
              flex: 42, child: pw.Container(height: 2.2, color: _navy)),
          pw.SizedBox(width: 5),
          pw.Container(
            width: 4,
            height: 4,
            decoration: const pw.BoxDecoration(
              color: _gold,
              shape: pw.BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _invoiceInfoBlock({
    required Purchase purchase,
    required _PurchasePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          labels.invoice,
          textDirection:
              isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          style: pw.TextStyle(
            color: _navy,
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'PURCHASE INVOICE',
          textDirection: pw.TextDirection.ltr,
          style: const pw.TextStyle(
            color: _gold,
            fontSize: 7.2,
            letterSpacing: 1.6,
          ),
        ),
        pw.SizedBox(height: 14),
        _metaItem(labels.no, purchase.purchaseNo, isArabic: isArabic),
        pw.SizedBox(height: 8),
        _metaItem(labels.date, _formatDate(purchase.date),
            isArabic: isArabic),
        pw.SizedBox(height: 8),
        _metaItem(labels.time, _formatTime(purchase.date),
            isArabic: isArabic),
      ],
    );
  }

  static pw.Widget _metaItem(
    String label,
    String value, {
    required bool isArabic,
  }) {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  label,
                  textDirection: isArabic
                      ? pw.TextDirection.rtl
                      : pw.TextDirection.ltr,
                  textAlign:
                      isArabic ? pw.TextAlign.right : pw.TextAlign.left,
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
            height: 108,
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
            fontSize: 13.5,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
          ),
        ),
        pw.SizedBox(height: 6),
        if (profile.phone.trim().isNotEmpty)
          _companyLine(label: profile.phone.trim(), isArabic: false),
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
            decoration: const pw.BoxDecoration(
              color: _gold,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              label,
              textDirection:
                  isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
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
    required Purchase purchase,
    required _PurchasePdfLabels labels,
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
              '${labels.no}: ${purchase.purchaseNo}',
              textDirection: labels.isArabic
                  ? pw.TextDirection.rtl
                  : pw.TextDirection.ltr,
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

  static pw.Widget _buildSupplierPaymentStrip({
    required Purchase purchase,
    required _PurchasePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 15, vertical: 8),
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
                label: labels.supplier,
                value: purchase.supplierName.trim().isEmpty
                    ? '-'
                    : purchase.supplierName.trim(),
                alignRight: false,
                valueDirection: isArabic
                    ? pw.TextDirection.rtl
                    : pw.TextDirection.ltr,
              ),
            ),
            pw.Container(width: .7, height: 26, color: _line),
            pw.Expanded(
              child: _stripInfo(
                label: labels.paymentMethod,
                value: _paymentMethodLabel(purchase.paymentMethod, labels),
                alignRight: true,
                valueDirection: isArabic
                    ? pw.TextDirection.rtl
                    : pw.TextDirection.ltr,
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
      padding: const pw.EdgeInsets.symmetric(horizontal: 10),
      child: pw.Column(
        crossAxisAlignment:
            alignRight ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            textDirection: valueDirection,
            textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
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
    required Purchase purchase,
    required StoreProfile profile,
    required _PurchasePdfLabels labels,
    required bool isArabic,
  }) {
    final headers = <String>[
      labels.item,
      labels.qty,
      labels.unitCost,
      labels.total,
    ];

    final data = purchase.items.map((item) {
      return <String>[
        item.productName,
        _formatQuantity(item.quantity),
        formatCurrency(
          item.originalUnitCost ?? item.unitCost,
          currency: item.unitCostCurrency,
        ),
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
    required Purchase purchase,
    required StoreProfile profile,
    required _PurchasePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 330,
        child: pw.Column(
          children: [
            _totalsLine(
              label: labels.subtotal,
              value: _formatMoney(purchase.subtotal, profile),
              isArabic: isArabic,
            ),
            if (purchase.paidAmount > 0) ...[
              pw.SizedBox(height: 7),
              _totalsLine(
                label: labels.paid,
                value: _formatMoney(purchase.paidAmount, profile),
                isArabic: isArabic,
              ),
            ],
            if (purchase.balanceDue > 0) ...[
              pw.SizedBox(height: 7),
              _totalsLine(
                label: labels.balanceDue,
                value: _formatMoney(purchase.balanceDue, profile),
                isArabic: isArabic,
              ),
            ],
            pw.SizedBox(height: 9),
            pw.Container(height: .8, color: _line),
            pw.SizedBox(height: 9),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      _formatMoney(purchase.subtotal, profile),
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
                      textDirection: isArabic
                          ? pw.TextDirection.rtl
                          : pw.TextDirection.ltr,
                      textAlign: pw.TextAlign.right,
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
            if (purchase.note.trim().isNotEmpty) ...[
              pw.SizedBox(height: 9),
              pw.Text(
                '${labels.notes}: ${purchase.note.trim()}',
                textDirection: isArabic
                    ? pw.TextDirection.rtl
                    : pw.TextDirection.ltr,
                textAlign:
                    isArabic ? pw.TextAlign.right : pw.TextAlign.left,
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static pw.Widget _totalsLine({
    required String label,
    required String value,
    required bool isArabic,
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
            textDirection:
                isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 8.2, color: _ink),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter({
    required pw.Context context,
    required StoreProfile profile,
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
                  textDirection: _containsArabic(contact)
                      ? pw.TextDirection.rtl
                      : pw.TextDirection.ltr,
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
    _PurchasePdfLabels labels,
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

  static bool _containsArabic(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  static String _formatQuantity(double value) => value % 1 == 0
      ? value.toStringAsFixed(0)
      : value
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

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
  String get no => isArabic
      ? 'رقم الفاتورة'
      : isFrench
          ? 'N° facture'
          : 'Invoice No.';
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
  String get supplier => isArabic
      ? 'المورد'
      : isFrench
          ? 'Fournisseur'
          : 'Supplier';
  String get paymentMethod => isArabic
      ? 'طريقة الدفع'
      : isFrench
          ? 'Mode de paiement'
          : 'Payment Method';
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
  String get subtotal => isArabic
      ? 'المجموع الفرعي'
      : isFrench
          ? 'Sous-total'
          : 'Subtotal';
  String get paid => isArabic
      ? 'المدفوع'
      : isFrench
          ? 'Payé'
          : 'Paid';
  String get balanceDue => isArabic
      ? 'الرصيد المستحق'
      : isFrench
          ? 'Solde dû'
          : 'Balance Due';
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
}
