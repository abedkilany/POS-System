import 'dart:io';

/// Reads the SalesPage library, including every part declared by its entry file.
String readSalesPageImplementationSource() {
  const directory = 'lib/features/sales';
  final mainSource = File('$directory/sales_page.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final partPattern = RegExp(r"^\s*part\s+'([^']+)';", multiLine: true);
  final buffer = StringBuffer(mainSource);

  for (final match in partPattern.allMatches(mainSource)) {
    final relativePath = match.group(1);
    if (relativePath == null) continue;
    final partSource = File('$directory/$relativePath')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    buffer
      ..writeln('\n// ---- $relativePath ----')
      ..writeln(partSource);
  }

  return buffer.toString();
}
