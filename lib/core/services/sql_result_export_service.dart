import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'sql_result_download_service.dart';

class SqlResultExportService {
  SqlResultExportService._();

  static Future<void> exportRows({
    required List<Map<String, Object?>> rows,
    required String format,
    required String baseFileName,
  }) async {
    if (rows.isEmpty) {
      throw StateError('No rows available to export.');
    }

    final normalizedFormat = format.toLowerCase().trim();
    final columns = orderedColumns(rows);
    switch (normalizedFormat) {
      case 'json':
        await downloadSqlResultFile(
          filename: '$baseFileName.json',
          bytes: Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(rows))),
          dialogTitle: 'Export SQL result as JSON',
          allowedExtensions: const ['json'],
        );
        return;
      case 'csv':
        await downloadSqlResultFile(
          filename: '$baseFileName.csv',
          bytes: Uint8List.fromList(utf8.encode(_toCsv(rows, columns))),
          dialogTitle: 'Export SQL result as CSV',
          allowedExtensions: const ['csv'],
        );
        return;
      case 'xlsx':
        await downloadSqlResultFile(
          filename: '$baseFileName.xlsx',
          bytes: _toXlsx(rows, columns),
          dialogTitle: 'Export SQL result as XLSX',
          allowedExtensions: const ['xlsx'],
        );
        return;
      default:
        throw ArgumentError('Unsupported export format: $format');
    }
  }

  static List<String> orderedColumns(List<Map<String, Object?>> rows) {
    final keys = <String>{};
    for (final row in rows) {
      keys.addAll(row.keys);
    }
    return keys.toList()..sort();
  }

  static String _toCsv(List<Map<String, Object?>> rows, List<String> columns) {
    final buffer = StringBuffer();
    buffer.writeln(columns.map(_csvCell).join(','));
    for (final row in rows) {
      buffer.writeln(columns.map((column) => _csvCell(_cellText(row[column]))).join(','));
    }
    return buffer.toString();
  }

  static String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    final escaped = text.replaceAll('"', '""');
    return '"$escaped"';
  }

  static Uint8List _toXlsx(List<Map<String, Object?>> rows, List<String> columns) {
    final archive = Archive();
    void addText(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addText('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''');
    addText('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
    addText('xl/_rels/workbook.xml.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');
    addText('xl/workbook.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="SQL Result" sheetId="1" r:id="rId1"/></sheets>
</workbook>''');
    addText('xl/styles.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>''');
    addText('xl/worksheets/sheet1.xml', _worksheetXml(rows, columns));

    final bytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(bytes);
  }

  static String _worksheetXml(List<Map<String, Object?>> rows, List<String> columns) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
    buffer.write(_xlsxRow(1, columns));
    for (var i = 0; i < rows.length; i++) {
      buffer.write(_xlsxRow(i + 2, [for (final column in columns) _cellText(rows[i][column])]));
    }
    buffer.write('</sheetData></worksheet>');
    return buffer.toString();
  }

  static String _xlsxRow(int index, List<Object?> values) {
    final cells = <String>[];
    for (var i = 0; i < values.length; i++) {
      final ref = '${_columnLetters(i + 1)}$index';
      cells.add('<c r="$ref" t="inlineStr"><is><t>${_xmlEscape(_cellText(values[i]))}</t></is></c>');
    }
    return '<row r="$index">${cells.join()}</row>';
  }

  static String _columnLetters(int columnNumber) {
    var number = columnNumber;
    final chars = <String>[];
    while (number > 0) {
      number--;
      chars.insert(0, String.fromCharCode(65 + (number % 26)));
      number ~/= 26;
    }
    return chars.join();
  }

  static String _cellText(Object? value) {
    if (value == null) return '';
    if (value is Map || value is List) return jsonEncode(value);
    return value.toString();
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
