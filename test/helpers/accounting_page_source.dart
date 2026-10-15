import 'dart:io';

/// Returns the complete AccountingPage library source, including its parts.
/// Source contract tests use this helper so they remain focused on behavior
/// while the page implementation is split across files.
String readAccountingPageImplementationSource() {
  const directory = 'lib/features/accounting';
  final mainFile = File('$directory/accounting_page.dart');
  final mainSource = mainFile.readAsStringSync().replaceAll('\r\n', '\n');
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
