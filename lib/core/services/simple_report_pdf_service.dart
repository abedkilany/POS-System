import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_font_loader.dart';

class SimpleReportPdfService {
  static Future<void> printReport({
    required String title,
    required List<String> lines,
    bool arabic = false,
  }) async {
    final pdfFonts = await PdfFontLoader.loadArabicFonts();
    final font = pdfFonts.regular;
    final bold = pdfFonts.bold;
    final pdf =
        pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
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
    await Printing.layoutPdf(
        onLayout: (_) async => Uint8List.fromList(await pdf.save()));
  }
}
