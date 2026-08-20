import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/store_profile.dart';

class ProfessionalPdfTheme {
  static const PdfColor navy = PdfColor(0.035, 0.13, 0.25);
  static const PdfColor gold = PdfColor(0.84, 0.61, 0.10);
  static const PdfColor ink = PdfColor(0.08, 0.11, 0.17);
  static const PdfColor muted = PdfColor(0.39, 0.43, 0.50);
  static const PdfColor line = PdfColor(0.86, 0.88, 0.91);
  static const PdfColor soft = PdfColor(0.972, 0.976, 0.982);

  static final RegExp _arabicScript = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
  );
  static final RegExp _numericLike = RegExp(r'^[\s0-9٠-٩.,:/+\-()%$€£¥]+$');

  /// The document locale controls labels and layout order, while dynamic
  /// business data can be Arabic, Latin, numeric, or mixed independently.
  /// Always resolve the bidi direction from the actual text being rendered.
  static bool containsArabic(String value) => _arabicScript.hasMatch(value);

  static pw.TextDirection directionFor(String value) =>
      containsArabic(value) ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  static pw.TextAlign textAlignFor(String value, {pw.TextAlign fallback = pw.TextAlign.left}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return fallback;
    if (_numericLike.hasMatch(trimmed)) return pw.TextAlign.center;
    return containsArabic(trimmed) ? pw.TextAlign.right : fallback;
  }

  static pw.Alignment alignmentFor(String value, {pw.Alignment fallback = pw.Alignment.centerLeft}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return fallback;
    if (_numericLike.hasMatch(trimmed)) return pw.Alignment.center;
    return containsArabic(trimmed) ? pw.Alignment.centerRight : fallback;
  }

  static Future<pw.ThemeData> loadTheme() async {
    final baseFont = pw.Font.ttf(await rootBundle.load('assets/fonts/Tahoma.ttf'));
    final boldFont = pw.Font.ttf(await rootBundle.load('assets/fonts/Tahoma-Bold.ttf'));
    return pw.ThemeData.withFont(base: baseFont, bold: boldFont);
  }

  static Uint8List? logoBytes(StoreProfile profile) {
    final raw = profile.logoDataBase64.trim();
    if (raw.isEmpty) return null;
    try {
      final comma = raw.indexOf(',');
      final payload = raw.startsWith('data:') && comma >= 0 ? raw.substring(comma + 1) : raw;
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  static pw.Widget brandRule() => pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Row(
          children: [
            pw.Container(width: 4, height: 4, decoration: const pw.BoxDecoration(color: gold, shape: pw.BoxShape.circle)),
            pw.SizedBox(width: 5),
            pw.Expanded(flex: 42, child: pw.Container(height: 2.2, color: navy)),
            pw.Expanded(flex: 18, child: pw.Container(height: 2.2, color: gold)),
            pw.Expanded(flex: 42, child: pw.Container(height: 2.2, color: navy)),
            pw.SizedBox(width: 5),
            pw.Container(width: 4, height: 4, decoration: const pw.BoxDecoration(color: gold, shape: pw.BoxShape.circle)),
          ],
        ),
      );

  static pw.Widget header({
    required StoreProfile profile,
    required String title,
    required String englishTitle,
    required bool isArabic,
    List<MapEntry<String, String>> meta = const [],
  }) {
    final logo = logoBytes(profile);
    return pw.Column(
      children: [
        brandRule(),
        pw.SizedBox(height: 14),
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 31,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      title,
                      textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                      maxLines: 1,
                      style: pw.TextStyle(
                        color: navy,
                        fontSize: title.length > 16 ? 13.2 : 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (englishTitle.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(englishTitle.toUpperCase(), textDirection: pw.TextDirection.ltr, style: const pw.TextStyle(color: gold, fontSize: 7, letterSpacing: 1.5)),
                    ],
                    if (meta.isNotEmpty) pw.SizedBox(height: 11),
                    ...meta.map((entry) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 5),
                          child: metaItem(entry.key, entry.value, isArabic: isArabic),
                        )),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 38,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logo != null)
                      pw.Container(
                        height: 96,
                        alignment: pw.Alignment.center,
                        child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
                      )
                    else
                      pw.Container(
                        height: 70,
                        alignment: pw.Alignment.center,
                        child: pw.Text(profile.name, textAlign: pw.TextAlign.center, textDirection: directionFor(profile.name), style: pw.TextStyle(color: navy, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 31,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(profile.name, textAlign: textAlignFor(profile.name, fallback: pw.TextAlign.right), textDirection: directionFor(profile.name), style: pw.TextStyle(color: navy, fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
                    if (profile.phone.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 7),
                      pw.Text(profile.phone.trim(), textAlign: pw.TextAlign.right, textDirection: pw.TextDirection.ltr, style: const pw.TextStyle(color: ink, fontSize: 8.5)),
                    ],
                    if (profile.address.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 5),
                      pw.Text(profile.address.trim(), textAlign: textAlignFor(profile.address.trim(), fallback: pw.TextAlign.right), textDirection: directionFor(profile.address.trim()), style: const pw.TextStyle(color: muted, fontSize: 7.8, lineSpacing: 2)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 13),
      ],
    );
  }

  static pw.Widget compactHeader({required StoreProfile profile, required String title}) => pw.Column(
        children: [
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(title, textDirection: directionFor(title), style: pw.TextStyle(color: navy, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text(profile.name, textDirection: directionFor(profile.name), style: pw.TextStyle(color: navy, fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Container(height: 1.2, color: line),
          pw.SizedBox(height: 9),
        ],
      );

  static String _localizedFooterNote(StoreProfile profile, String? languageCode) {
    final raw = profile.footerNote.trim();
    if (raw.isEmpty) return profile.name;
    if (languageCode == null || languageCode.isEmpty) return raw;

    String normalized(String value) => value
        .trim()
        .replaceAll(RegExp(r'[.\u06D4]+\s*$'), '')
        .replaceAll('’', "'")
        .toLowerCase();

    final current = normalized(raw);
    final defaults = <String>{
      normalized('Thank you for shopping with us.'),
      normalized('شكراً لتسوقكم معنا.'),
      normalized("Merci d'avoir magasiné avec nous."),
    };
    if (!defaults.contains(current)) return raw;

    if (languageCode == 'ar') return 'شكراً لتسوقكم معنا.';
    if (languageCode == 'fr') return "Merci d'avoir magasiné avec nous.";
    return 'Thank you for shopping with us.';
  }

  static pw.Widget footer({
    required pw.Context context,
    required StoreProfile profile,
    required bool isArabic,
    String? languageCode,
  }) {
    final page = isArabic
        ? 'صفحة ${context.pageNumber} من ${context.pagesCount}'
        : 'Page ${context.pageNumber} of ${context.pagesCount}';
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(height: 1, color: line),
        pw.SizedBox(height: 7),
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _localizedFooterNote(profile, languageCode),
                textDirection: directionFor(_localizedFooterNote(profile, languageCode)),
                textAlign: textAlignFor(_localizedFooterNote(profile, languageCode)),
                style: const pw.TextStyle(color: muted, fontSize: 7.2),
              ),
              pw.Text(page, textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr, style: const pw.TextStyle(color: muted, fontSize: 7.2)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget metaItem(String label, String value, {required bool isArabic}) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr, style: const pw.TextStyle(color: muted, fontSize: 6.8)),
          pw.SizedBox(height: 1.5),
          pw.Text(value, textDirection: directionFor(value), textAlign: textAlignFor(value), style: pw.TextStyle(color: ink, fontSize: 8.3, fontWeight: pw.FontWeight.bold)),
        ],
      );

  static pw.Widget infoStrip({
    required List<MapEntry<String, String>> entries,
    required bool isArabic,
    List<int>? flexes,
    double verticalPadding = 9,
  }) {
    if (entries.isEmpty) return pw.SizedBox();
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.symmetric(horizontal: 13, vertical: verticalPadding),
      decoration: pw.BoxDecoration(color: soft, border: pw.Border.all(color: line, width: .7)),
      child: pw.Directionality(
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        child: pw.Row(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) pw.SizedBox(width: 12),
              if (i > 0) pw.Container(width: .7, height: 24, color: line),
              if (i > 0) pw.SizedBox(width: 12),
              pw.Expanded(
                flex: flexes != null && i < flexes.length ? flexes[i] : 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      entries[i].key,
                      textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(color: muted, fontSize: 6.8),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      entries[i].value,
                      textDirection: directionFor(entries[i].value),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(color: ink, fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static pw.Table table({
    required List<String> headers,
    required List<List<String>> data,
    Map<int, pw.TableColumnWidth>? columnWidths,
    pw.TextStyle? cellStyle,
  }) {
    final resolvedCellStyle = cellStyle ?? const pw.TextStyle(color: ink, fontSize: 8);

    pw.Widget buildCell(
      String value, {
      required bool isHeader,
      required int rowIndex,
    }) {
      final direction = directionFor(value);
      const alignment = pw.Alignment.center;
      const textAlign = pw.TextAlign.center;

      return pw.Container(
        alignment: alignment,
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        decoration: pw.BoxDecoration(
          color: isHeader
              ? navy
              : rowIndex.isOdd
                  ? soft
                  : PdfColors.white,
          border: isHeader
              ? null
              : const pw.Border(
                  bottom: pw.BorderSide(color: line, width: .45),
                ),
        ),
        child: pw.Text(
          value,
          textDirection: direction,
          textAlign: textAlign,
          style: isHeader
              ? pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                )
              : resolvedCellStyle,
        ),
      );
    }

    return pw.Table(
      columnWidths: columnWidths,
      border: null,
      children: [
        pw.TableRow(
          children: [
            for (final header in headers)
              buildCell(header, isHeader: true, rowIndex: -1),
          ],
        ),
        for (var rowIndex = 0; rowIndex < data.length; rowIndex++)
          pw.TableRow(
            children: [
              for (final value in data[rowIndex])
                buildCell(value, isHeader: false, rowIndex: rowIndex),
            ],
          ),
      ],
    );
  }

  static pw.Widget summaryBox({required List<MapEntry<String, String>> rows, required bool isArabic, int highlightIndex = -1}) {
    return pw.Align(
      alignment: isArabic ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
      child: pw.Container(
        width: 260,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: .8)),
        child: pw.Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: i == highlightIndex ? navy : (i.isEven ? PdfColors.white : soft),
                child: pw.Directionality(
                  textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(rows[i].key, style: pw.TextStyle(color: i == highlightIndex ? PdfColors.white : muted, fontSize: i == highlightIndex ? 9 : 8, fontWeight: i == highlightIndex ? pw.FontWeight.bold : pw.FontWeight.normal)),
                      pw.Text(rows[i].value, textDirection: directionFor(rows[i].value), textAlign: textAlignFor(rows[i].value), style: pw.TextStyle(color: i == highlightIndex ? PdfColors.white : ink, fontSize: i == highlightIndex ? 10.5 : 8.5, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static pw.Widget note(String title, String value, {required bool isArabic}) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: .7)),
        child: pw.Column(
          crossAxisAlignment: isArabic ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr, style: pw.TextStyle(color: navy, fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(value, textDirection: directionFor(value), textAlign: textAlignFor(value), style: const pw.TextStyle(color: ink, fontSize: 8)),
          ],
        ),
      );
}
