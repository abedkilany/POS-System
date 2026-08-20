import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/cash_ledger_transaction.dart';
import '../../models/store_profile.dart';

class CashReceiptPdfService {
  static Future<Uint8List> buildReceiptPdf({
    required CashLedgerTransaction transaction,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
    );
    final ar = locale.languageCode == 'ar';
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );
    final reference = [
      transaction.referenceNumber,
      transaction.referenceId,
    ].where((value) => value.trim().isNotEmpty).join(' • ');

    String typeLabel() {
      switch (transaction.type) {
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

    String dateText() {
      final date = transaction.occurredAt.toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
    }

    pw.Widget row(String label, String value) {
      if (value.trim().isEmpty) return pw.SizedBox.shrink();
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 92,
              child: pw.Text(label,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
            pw.Expanded(child: pw.Text(value)),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, 160 * PdfPageFormat.mm),
        margin: const pw.EdgeInsets.all(12),
        textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                profile.name,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
              ),
            ),
            if (profile.phone.trim().isNotEmpty)
              pw.Center(child: pw.Text(profile.phone, textAlign: pw.TextAlign.center)),
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.Center(
              child: pw.Text(
                typeLabel(),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 8),
            row(ar ? 'رقم الحركة' : 'Transaction', transaction.id),
            row(ar ? 'التاريخ' : 'Date', dateText()),
            row(ar ? 'الطرف' : 'Party', transaction.partyName),
            row(ar ? 'المرجع' : 'Reference', reference),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border.symmetric(
                  horizontal: pw.BorderSide(width: .6),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(ar ? 'المبلغ' : 'Amount',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    '${transaction.amount.toStringAsFixed(2)} ${transaction.currency}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            row(ar ? 'الاتجاه' : 'Direction',
                transaction.isCashIn ? (ar ? 'داخل' : 'In') : (ar ? 'خارج' : 'Out')),
            row(ar ? 'وسيلة الدفع' : 'Payment method', transaction.paymentMethod),
            row(ar ? 'المستخدم' : 'User', transaction.createdBy),
            row(ar ? 'الملاحظات' : 'Notes', transaction.notes),
            pw.SizedBox(height: 10),
            if (profile.footerNote.trim().isNotEmpty)
              pw.Center(child: pw.Text(profile.footerNote, textAlign: pw.TextAlign.center)),
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
}
