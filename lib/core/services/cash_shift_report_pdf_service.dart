import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/cash_ledger_transaction.dart';
import '../../models/store_profile.dart';
import 'accounting_service.dart';

class CashShiftReportPdfService {
  static Future<void> printShift({
    required CashShiftReportSession session,
    required List<CashLedgerTransaction> movements,
    required bool detailed,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildShiftPdf(
      session: session,
      movements: movements,
      detailed: detailed,
      profile: profile,
      locale: locale,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'shift-${session.drawerNo.isEmpty ? session.id : session.drawerNo}',
    );
  }

  static Future<Uint8List> buildShiftPdf({
    required CashShiftReportSession session,
    required List<CashLedgerTransaction> movements,
    required bool detailed,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final baseFont = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final boldFont = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    final ar = locale.languageCode == 'ar';
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont));

    final cashIn = movements.where((m) => m.isCashIn).fold<double>(0, (s, m) => s + m.amount);
    final cashOut = movements.where((m) => !m.isCashIn).fold<double>(0, (s, m) => s + m.amount);
    String money(double value) => value.toStringAsFixed(2);
    String date(DateTime? value) {
      if (value == null) return '—';
      final d = value.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
    }
    pw.Widget info(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(children: [
        pw.SizedBox(width: 110, child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        pw.Expanded(child: pw.Text(value)),
      ]),
    );

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (_) => [
        pw.Center(child: pw.Text(profile.name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text(detailed ? (ar ? 'تقرير تفاصيل الوردية' : 'Shift details report') : (ar ? 'ملخص الوردية' : 'Shift summary'))),
        pw.Divider(height: 22),
        info(ar ? 'رقم الوردية' : 'Shift no.', session.drawerNo.isEmpty ? session.id : session.drawerNo),
        info(ar ? 'الصندوق' : 'Cash drawer', session.cashLocationName),
        info(ar ? 'وقت الفتح' : 'Opened at', date(session.openedAt)),
        info(ar ? 'وقت الإغلاق' : 'Closed at', date(session.closedAt)),
        info(ar ? 'فتح بواسطة' : 'Opened by', session.openedBy),
        info(ar ? 'أغلق بواسطة' : 'Closed by', session.closedBy),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ar
              ? ['رصيد الافتتاح', 'إجمالي الداخل', 'إجمالي الخارج', 'المتوقع', 'المعدود', 'الفرق']
              : ['Opening', 'Cash in', 'Cash out', 'Expected', 'Counted', 'Difference'],
          data: [[
            money(session.openingBalance), money(cashIn), money(cashOut),
            money(session.expectedCash), money(session.countedCash), money(session.difference),
          ]],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.center,
        ),
        if (session.notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 10),
          info(ar ? 'الملاحظات' : 'Notes', session.notes),
        ],
        if (detailed) ...[
          pw.SizedBox(height: 16),
          pw.Text(ar ? 'حركات الوردية' : 'Shift movements', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (movements.isEmpty)
            pw.Text(ar ? 'لا توجد حركات مرتبطة بهذه الوردية.' : 'No movements are linked to this shift.')
          else
            pw.TableHelper.fromTextArray(
              headers: ar
                  ? ['التاريخ', 'النوع', 'الاتجاه', 'الطرف / المرجع', 'المبلغ', 'المستخدم']
                  : ['Date', 'Type', 'Direction', 'Party / reference', 'Amount', 'User'],
              data: movements.map((m) {
                final reference = [m.partyName, m.referenceNumber].where((v) => v.trim().isNotEmpty).join(' • ');
                return [
                  date(m.occurredAt),
                  m.type,
                  m.isCashIn ? (ar ? 'داخل' : 'In') : (ar ? 'خارج' : 'Out'),
                  reference,
                  '${money(m.amount)} ${m.currency}',
                  m.createdBy,
                ];
              }).toList(growable: false),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.center,
              columnWidths: const {
                0: pw.FlexColumnWidth(1.4),
                1: pw.FlexColumnWidth(1.1),
                2: pw.FlexColumnWidth(.8),
                3: pw.FlexColumnWidth(1.8),
                4: pw.FlexColumnWidth(1.1),
                5: pw.FlexColumnWidth(1.1),
              },
            ),
        ],
      ],
    ));
    return pdf.save();
  }
}
