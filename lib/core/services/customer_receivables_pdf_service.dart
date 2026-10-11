import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/print_settings.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';
import 'print_service.dart';
import 'professional_pdf_theme.dart';

class CustomerReceivableRow {
  const CustomerReceivableRow({
    required this.name,
    required this.phone,
    required this.balance,
  });

  final String name;
  final String phone;
  final double balance;
}

class CustomerReceivablesPdfService {
  static Future<Uint8List> build({
    required List<CustomerReceivableRow> customers,
    required StoreProfile profile,
    required Locale locale,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final isArabic = locale.languageCode == 'ar';
    final theme = await ProfessionalPdfTheme.loadTheme();
    final pdf = pw.Document(theme: theme);
    final total = customers.fold<double>(0, (sum, item) => sum + item.balance);
    final title =
        isArabic ? 'حسابات الزبائن غير المسددة' : 'Unpaid Customer Accounts';
    final headers = isArabic
        ? ['الزبون', 'الهاتف', 'الرصيد المستحق']
        : ['Customer', 'Phone', 'Amount due'];
    final data = customers
        .map((item) => [
              item.name,
              item.phone,
              formatUsdReferenceAmount(item.balance, profile),
            ])
        .toList(growable: false);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: title,
                englishTitle: 'UNPAID CUSTOMER ACCOUNTS',
                isArabic: isArabic,
                meta: [
                  MapEntry(isArabic ? 'عدد الزبائن' : 'Customers',
                      '${customers.length}'),
                ],
              )
            : ProfessionalPdfTheme.compactHeader(
                profile: profile, title: title),
        footer: (context) => ProfessionalPdfTheme.footer(
          context: context,
          profile: profile,
          isArabic: isArabic,
        ),
        build: (_) => [
          if (customers.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 30),
              child: pw.Center(
                child: pw.Text(isArabic
                    ? 'لا توجد حسابات غير مسددة.'
                    : 'There are no unpaid customer accounts.'),
              ),
            )
          else ...[
            ProfessionalPdfTheme.table(headers: headers, data: data),
            pw.SizedBox(height: 14),
            ProfessionalPdfTheme.summaryBox(
              isArabic: isArabic,
              highlightIndex: 0,
              rows: [
                MapEntry(
                  isArabic ? 'إجمالي المبالغ المستحقة' : 'Total amount due',
                  formatUsdReferenceAmount(total, profile),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> print({
    required BuildContext context,
    required List<CustomerReceivableRow> customers,
    required StoreProfile profile,
    required Locale locale,
  }) async {
    await PrintService.printPdf(
      context: context,
      profile: profile,
      documentKey: PrintDocumentKeys.customerReceivables,
      bytesBuilder: (selection) => build(
        customers: customers,
        profile: profile,
        locale: locale,
        pageFormat: PrintService.pageFormatFor(
          selection.format,
          fallback: PdfPageFormat.a4,
        ),
      ),
      name: 'unpaid-customer-accounts',
      defaultFormat: PdfPageFormat.a4,
    );
  }
}
