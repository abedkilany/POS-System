import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/cash_ledger_transaction.dart';
import '../../models/store_profile.dart';

class CashReceiptPdfService {
  static const PdfColor _navy = PdfColor(0.035, 0.13, 0.25);
  static const PdfColor _gold = PdfColor(0.84, 0.61, 0.10);
  static const PdfColor _ink = PdfColor(0.08, 0.11, 0.17);
  static const PdfColor _muted = PdfColor(0.39, 0.43, 0.50);
  static const PdfColor _line = PdfColor(0.86, 0.88, 0.91);
  static const PdfColor _soft = PdfColor(0.972, 0.976, 0.982);

  static Future<Uint8List> buildReceiptPdf({
    required CashLedgerTransaction transaction,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tahoma.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Tahoma-Bold.ttf'),
    );
    final ar = locale.languageCode == 'ar';
    final logoBytes = _logoBytes(profile.logoDataBase64);
    final reference = [
      transaction.referenceNumber,
      transaction.referenceId,
    ].where((value) => value.trim().isNotEmpty).join(' • ');

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          80 * PdfPageFormat.mm,
          180 * PdfPageFormat.mm,
        ),
        margin: const pw.EdgeInsets.fromLTRB(13, 12, 13, 12),
        textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _brandRule(),
            pw.SizedBox(height: 10),
            _brandHeader(
              profile: profile,
              logoBytes: logoBytes,
              ar: ar,
            ),
            pw.SizedBox(height: 10),
            _receiptTitle(
              transaction: transaction,
              ar: ar,
            ),
            pw.SizedBox(height: 10),
            _partyCard(transaction: transaction, ar: ar),
            pw.SizedBox(height: 10),
            _amountBlock(transaction: transaction, ar: ar),
            pw.SizedBox(height: 10),
            _detailsBlock(
              transaction: transaction,
              reference: reference,
              ar: ar,
            ),
            pw.Spacer(),
            _footer(profile: profile, ar: ar),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  static Future<void> printReceipt({
    required CashLedgerTransaction transaction,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildReceiptPdf(
      transaction: transaction,
      profile: profile,
      locale: locale,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: transaction.referenceNumber.trim().isNotEmpty
          ? transaction.referenceNumber.trim()
          : transaction.id,
    );
  }

  static pw.Widget _brandRule() {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
        children: [
          pw.Container(
            width: 3.5,
            height: 3.5,
            decoration: const pw.BoxDecoration(
              color: _gold,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(
            flex: 44,
            child: pw.Container(height: 2, color: _navy),
          ),
          pw.Expanded(
            flex: 18,
            child: pw.Container(height: 2, color: _gold),
          ),
          pw.Expanded(
            flex: 44,
            child: pw.Container(height: 2, color: _navy),
          ),
          pw.SizedBox(width: 4),
          pw.Container(
            width: 3.5,
            height: 3.5,
            decoration: const pw.BoxDecoration(
              color: _gold,
              shape: pw.BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _brandHeader({
    required StoreProfile profile,
    required Uint8List? logoBytes,
    required bool ar,
  }) {
    return pw.Column(
      children: [
        if (logoBytes != null)
          pw.Container(
            height: 54,
            alignment: pw.Alignment.center,
            child: pw.Image(
              pw.MemoryImage(logoBytes),
              fit: pw.BoxFit.contain,
            ),
          )
        else
          pw.Text(
            profile.name,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              color: _navy,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        if (logoBytes != null && profile.name.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            profile.name,
            textAlign: pw.TextAlign.center,
            textDirection: _directionFor(profile.name, ar),
            style: pw.TextStyle(
              color: _navy,
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
        if (profile.address.trim().isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            profile.address.trim(),
            textAlign: pw.TextAlign.center,
            textDirection: _directionFor(profile.address, ar),
            style: const pw.TextStyle(
              color: _muted,
              fontSize: 7.2,
            ),
          ),
        ],
        if (profile.phone.trim().isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            profile.phone.trim(),
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.ltr,
            style: const pw.TextStyle(
              color: _ink,
              fontSize: 7.4,
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _receiptTitle({
    required CashLedgerTransaction transaction,
    required bool ar,
  }) {
    final title = _typeLabel(transaction.type, ar);
    final english = _typeLabel(transaction.type, false).toUpperCase();
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _line, width: .7),
          bottom: pw.BorderSide(color: _line, width: .7),
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            style: pw.TextStyle(
              color: _navy,
              fontSize: 13.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (ar) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              english,
              textAlign: pw.TextAlign.center,
              textDirection: pw.TextDirection.ltr,
              style: const pw.TextStyle(
                color: _gold,
                fontSize: 6.2,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _partyCard({
    required CashLedgerTransaction transaction,
    required bool ar,
  }) {
    final party = transaction.partyName.trim().isEmpty
        ? (ar ? 'غير محدد' : 'Not specified')
        : transaction.partyName.trim();
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: pw.BoxDecoration(
        color: _soft,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment:
            ar ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            ar ? 'الحساب / الطرف' : 'ACCOUNT / PARTY',
            textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            style: const pw.TextStyle(
              color: _muted,
              fontSize: 6.7,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            party,
            textDirection: _directionFor(party, ar),
            style: pw.TextStyle(
              color: _ink,
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _amountBlock({
    required CashLedgerTransaction transaction,
    required bool ar,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _navy,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: pw.Text(
                  '${transaction.amount.toStringAsFixed(2)} ${transaction.currency}',
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
            pw.Container(
              width: 3,
              height: 42,
              color: _gold,
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(8, 10, 12, 10),
              child: pw.Text(
                ar ? 'المبلغ' : 'AMOUNT',
                textDirection:
                    ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _detailsBlock({
    required CashLedgerTransaction transaction,
    required String reference,
    required bool ar,
  }) {
    final rows = <pw.Widget>[
      _detailRow(
        ar ? 'رقم الحركة' : 'Transaction',
        transaction.id,
        ar: ar,
      ),
      _detailRow(
        ar ? 'التاريخ' : 'Date',
        _dateText(transaction.occurredAt),
        ar: ar,
        forceValueLtr: true,
      ),
      if (reference.trim().isNotEmpty)
        _detailRow(
          ar ? 'المرجع' : 'Reference',
          reference,
          ar: ar,
        ),
      _detailRow(
        ar ? 'وسيلة الدفع' : 'Payment method',
        _paymentMethodLabel(transaction.paymentMethod, ar),
        ar: ar,
      ),
      _detailRow(
        ar ? 'الاتجاه' : 'Direction',
        transaction.isCashIn ? (ar ? 'قبض' : 'In') : (ar ? 'دفع' : 'Out'),
        ar: ar,
      ),
      if (transaction.createdBy.trim().isNotEmpty)
        _detailRow(
          ar ? 'المستخدم' : 'User',
          transaction.createdBy.trim(),
          ar: ar,
        ),
      if (transaction.notes.trim().isNotEmpty)
        _detailRow(
          ar ? 'ملاحظات' : 'Notes',
          transaction.notes.trim(),
          ar: ar,
        ),
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Column(children: rows),
    );
  }

  static pw.Widget _detailRow(
    String label,
    String value, {
    required bool ar,
    bool forceValueLtr = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _line, width: .45),
        ),
      ),
      child: pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 58,
              child: pw.Text(
                value,
                textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
                textDirection: forceValueLtr
                    ? pw.TextDirection.ltr
                    : _directionFor(value, ar),
                style: const pw.TextStyle(
                  color: _ink,
                  fontSize: 7.8,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 42,
              child: pw.Text(
                label,
                textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
                textDirection:
                    ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                style: pw.TextStyle(
                  color: _muted,
                  fontSize: 7.2,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _footer({
    required StoreProfile profile,
    required bool ar,
  }) {
    final note = profile.footerNote.trim();
    return pw.Column(
      children: [
        pw.SizedBox(height: 8),
        _brandRule(),
        pw.SizedBox(height: 7),
        if (note.isNotEmpty)
          pw.Text(
            note,
            textAlign: pw.TextAlign.center,
            textDirection: _directionFor(note, ar),
            style: pw.TextStyle(
              color: _navy,
              fontSize: 7.4,
              fontWeight: pw.FontWeight.bold,
            ),
          )
        else
          pw.Text(
            ar ? 'شكراً لتعاملكم معنا' : 'Thank you for your business',
            textAlign: pw.TextAlign.center,
            textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            style: pw.TextStyle(
              color: _navy,
              fontSize: 7.4,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
      ],
    );
  }

  static String _typeLabel(String type, bool ar) {
    switch (type) {
      case 'receipt':
        return ar ? 'إيصال قبض' : 'Receipt voucher';
      case 'supplier_payment':
        return ar ? 'إيصال دفع لمورد' : 'Supplier payment receipt';
      case 'sale_payment':
        return ar ? 'إيصال دفعة بيع' : 'Sale payment receipt';
      case 'purchase_payment':
        return ar ? 'إيصال دفعة شراء' : 'Purchase payment receipt';
      case 'cash_in':
        return ar ? 'إيصال إدخال نقدي' : 'Cash-in receipt';
      case 'cash_out':
        return ar ? 'إيصال إخراج نقدي' : 'Cash-out receipt';
      case 'cash_deposit':
        return ar ? 'إيصال إيداع نقدي' : 'Cash deposit receipt';
      case 'cash_withdrawal':
        return ar ? 'إيصال سحب نقدي' : 'Cash withdrawal receipt';
      case 'expense':
        return ar ? 'إيصال مصروف' : 'Expense receipt';
      case 'reversal':
        return ar ? 'إيصال عكس حركة' : 'Reversal receipt';
      default:
        return ar ? 'إيصال حركة صندوق' : 'Cash receipt';
    }
  }

  static String _paymentMethodLabel(String raw, bool ar) {
    final value = raw.trim();
    if (!ar || value.isEmpty) return value;
    switch (value.toLowerCase()) {
      case 'cash':
        return 'نقداً';
      case 'card':
        return 'بطاقة';
      case 'bank':
      case 'bank transfer':
      case 'transfer':
        return 'تحويل';
      default:
        return value;
    }
  }

  static String _dateText(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year}  ${two(local.hour)}:${two(local.minute)}';
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

  static pw.TextDirection _directionFor(String value, bool ar) {
    if (_containsArabic(value)) return pw.TextDirection.rtl;
    return ar ? pw.TextDirection.ltr : pw.TextDirection.ltr;
  }

  static bool _containsArabic(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }
}
