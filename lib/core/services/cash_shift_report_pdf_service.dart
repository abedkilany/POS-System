import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/cash_ledger_transaction.dart';
import '../../models/store_profile.dart';
import 'accounting_service.dart';
import 'professional_pdf_theme.dart';

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
    final ar = locale.languageCode == 'ar';
    final theme = await ProfessionalPdfTheme.loadTheme();
    final pdf = pw.Document(theme: theme);
    final title = detailed
        ? (ar ? 'تقرير تفاصيل الوردية' : 'Shift Details Report')
        : (ar ? 'ملخص الوردية' : 'Shift Summary');

    final cashIn = movements.where((m) => m.isCashIn).fold<double>(0, (s, m) => s + m.amount);
    final cashOut = movements.where((m) => !m.isCashIn).fold<double>(0, (s, m) => s + m.amount);
    String money(double value) => value.toStringAsFixed(2);
    String date(DateTime? value) {
      if (value == null) return '—';
      final d = value.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
    }

    final shiftNo = session.drawerNo.isEmpty ? session.id : session.drawerNo;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: title,
                englishTitle: detailed ? 'SHIFT DETAILS REPORT' : 'SHIFT SUMMARY',
                isArabic: ar,
                meta: [
                  MapEntry(ar ? 'رقم الوردية' : 'Shift no.', shiftNo),
                  MapEntry(ar ? 'وقت الفتح' : 'Opened at', date(session.openedAt)),
                  MapEntry(ar ? 'وقت الإغلاق' : 'Closed at', date(session.closedAt)),
                ],
              )
            : ProfessionalPdfTheme.compactHeader(profile: profile, title: title),
        footer: (context) => ProfessionalPdfTheme.footer(context: context, profile: profile, isArabic: ar),
        build: (_) => [
          ProfessionalPdfTheme.infoStrip(
            isArabic: ar,
            entries: [
              MapEntry(ar ? 'الصندوق' : 'Cash drawer', session.cashLocationName),
              MapEntry(ar ? 'فتح بواسطة' : 'Opened by', session.openedBy),
              MapEntry(ar ? 'أغلق بواسطة' : 'Closed by', session.closedBy),
            ],
          ),
          pw.SizedBox(height: 14),
          ProfessionalPdfTheme.table(
            headers: ar
                ? ['رصيد الافتتاح', 'إجمالي الداخل', 'إجمالي الخارج', 'المتوقع', 'المعدود', 'الفرق']
                : ['Opening', 'Cash in', 'Cash out', 'Expected', 'Counted', 'Difference'],
            data: [[
              money(session.openingBalance),
              money(cashIn),
              money(cashOut),
              money(session.expectedCash),
              money(session.countedCash),
              money(session.difference),
            ]],
          ),
          if (session.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            ProfessionalPdfTheme.note(ar ? 'الملاحظات' : 'Notes', session.notes.trim(), isArabic: ar),
          ],
          if (detailed) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              ar ? 'حركات الوردية' : 'Shift movements',
              textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              style: pw.TextStyle(color: ProfessionalPdfTheme.navy, fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (movements.isEmpty)
              pw.Text(ar ? 'لا توجد حركات مرتبطة بهذه الوردية.' : 'No movements are linked to this shift.')
            else
              ProfessionalPdfTheme.table(
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
                cellStyle: const pw.TextStyle(fontSize: 7.5),
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
      ),
    );
    return pdf.save();
  }
}
