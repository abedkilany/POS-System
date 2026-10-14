import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/services/pdf_font_loader.dart';
import '../../core/services/sql_result_download_service.dart';
import '../../core/services/sql_result_export_service.dart';
import 'assistant_provider.dart';

class AssistantReportExportService {
  AssistantReportExportService._();

  static Future<void> exportExcel({
    required AssistantChatTurn turn,
    required String fileName,
    required String dialogTitle,
    required String summaryLabel,
    required Map<String, String> columnLabels,
    required Map<String, String> reportNames,
  }) async {
    final rows = _flattenReports(turn.reports, summaryLabel, reportNames)
        .map((row) => <String, Object?>{
              for (final entry in row.entries)
                columnLabels[entry.key] ?? entry.key: entry.value,
            })
        .toList(growable: false);
    await SqlResultExportService.exportRows(
      rows: rows,
      format: 'xlsx',
      baseFileName: fileName,
      dialogTitle: dialogTitle,
    );
  }

  static Future<void> exportPdf({
    required AssistantChatTurn turn,
    required String fileName,
    required String dialogTitle,
    required String answerTitle,
    required String reportTitle,
    required List<String> tableHeaders,
    required String summaryLabel,
    required String reportLabel,
    required String periodLabel,
    required String currencyLabel,
    required Map<String, String> reportNames,
    required bool rightToLeft,
  }) async {
    final fonts = await PdfFontLoader.loadArabicFonts();
    final rows = _flattenReports(turn.reports, summaryLabel, reportNames);
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection:
            rightToLeft ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            answerTitle,
            style: pw.TextStyle(font: fonts.bold, fontSize: 19),
          ),
          pw.SizedBox(height: 12),
          ..._paragraphs(turn.content, fonts.regular),
          pw.SizedBox(height: 24),
          pw.Text(
            reportTitle,
            style: pw.TextStyle(font: fonts.bold, fontSize: 16),
          ),
          for (final report in turn.reports)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                '$reportLabel: ${reportNames[report['tool']?.toString()] ?? report['tool'] ?? ''}  ·  '
                '$periodLabel: ${_periodText(report['period'] ?? report['asOf'])}  ·  '
                '$currencyLabel: ${report['baseCurrency'] ?? ''}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 9),
              ),
            ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: tableHeaders,
            data: [
              for (final row in rows)
                [
                  row['section']?.toString() ?? '',
                  row['field']?.toString() ?? '',
                  row['value']?.toString() ?? '',
                ],
            ],
            headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
            cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: rightToLeft
                ? pw.Alignment.centerRight
                : pw.Alignment.centerLeft,
            headerAlignment: rightToLeft
                ? pw.Alignment.centerRight
                : pw.Alignment.centerLeft,
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(1.5),
              2: pw.FlexColumnWidth(2.2),
            },
          ),
        ],
      ),
    );
    await downloadSqlResultFile(
      filename: '$fileName.pdf',
      bytes: Uint8List.fromList(await document.save()),
      dialogTitle: dialogTitle,
      allowedExtensions: const <String>['pdf'],
    );
  }

  static List<pw.Widget> _paragraphs(String text, pw.Font font) {
    final blocks = text
        .replaceAll(RegExp(r'```[^\n]*\n?'), '')
        .split(RegExp(r'\n\s*\n'))
        .map((line) => line.replaceAll(RegExp(r'[`*_#]'), '').trim())
        .where((line) => line.isNotEmpty);
    return [
      for (final block in blocks)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(block, style: pw.TextStyle(font: font, fontSize: 10)),
        ),
    ];
  }

  static List<Map<String, Object?>> _flattenReports(
    List<AssistantJsonMap> reports,
    String summaryLabel,
    Map<String, String> reportNames,
  ) {
    final rows = <Map<String, Object?>>[];
    for (final report in reports) {
      final metadata = <String, Object?>{
        'report': reportNames[report['tool']?.toString()] ??
            report['report'] ??
            report['tool'] ??
            'Ventio report',
        'period': _periodText(report['period'] ?? report['asOf']),
        'generatedAtUtc': report['generatedAtUtc'] ?? '',
        'currency': report['baseCurrency'] ?? '',
        'source': report['source'] ?? '',
      };
      final rawData = report['data'];
      if (rawData is Map) {
        for (final entry in rawData.entries) {
          final section = entry.key.toString();
          final value = entry.value;
          if (value is List) {
            for (var index = 0; index < value.length; index += 1) {
              final item = value[index];
              if (item is Map) {
                for (final field in item.entries) {
                  rows.add(_row(
                    metadata,
                    '$section ${index + 1}',
                    field.key.toString(),
                    field.value,
                  ));
                }
              } else {
                rows.add(_row(metadata, section, '${index + 1}', item));
              }
            }
          } else if (value is Map) {
            for (final field in value.entries) {
              rows.add(_row(
                metadata,
                section,
                field.key.toString(),
                field.value,
              ));
            }
          } else {
            rows.add(_row(metadata, summaryLabel, section, value));
          }
        }
      } else {
        rows.add(_row(metadata, summaryLabel, 'data', rawData));
      }
    }
    if (rows.isEmpty) {
      throw StateError('No report data is available to export.');
    }
    return rows;
  }

  static Map<String, Object?> _row(
    Map<String, Object?> metadata,
    String section,
    String field,
    Object? value,
  ) =>
      <String, Object?>{
        ...metadata,
        'section': section,
        'field': field,
        'value': value is Map || value is List ? jsonEncode(value) : value,
      };

  static String _periodText(Object? value) {
    if (value is Map) {
      final from = value['from']?.toString() ?? '';
      final to = value['to']?.toString() ?? '';
      if (from.isEmpty) return to;
      if (to.isEmpty) return from;
      return '$from — $to';
    }
    return value?.toString() ?? '';
  }
}
