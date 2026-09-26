import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_font_loader.dart';
import '../../models/print_settings.dart';
import '../../models/store_profile.dart';
import 'print_service.dart';

class SimpleReportPdfService {
  static Future<void> printReport({
    required StoreProfile profile,
    String documentKey = PrintDocumentKeys.report,
    BuildContext? context,
    required String title,
    required List<String> lines,
    bool arabic = false,
  }) async {
    final pdfFonts = await PdfFontLoader.loadArabicFonts();
    final font = pdfFonts.regular;
    final bold = pdfFonts.bold;
    if (context != null && !context.mounted) return;
    await PrintService.printPdf(
      context: context,
      profile: profile,
      documentKey: documentKey,
      bytesBuilder: (selection) async {
        final pdf =
            pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
        pdf.addPage(pw.MultiPage(
          pageFormat: PrintService.pageFormatFor(
            selection.format,
            fallback: PdfPageFormat.a4,
          ),
          textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          build: (_) => [
            pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 20)),
            pw.SizedBox(height: 16),
            ...lines.map((line) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Text(line),
                )),
          ],
        ));
        return Uint8List.fromList(await pdf.save());
      },
      name: title,
      defaultFormat: PdfPageFormat.a4,
    );
  }
}
