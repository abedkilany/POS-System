import 'dart:io';

/// Reads the complete AccountingService facade and implementation source.
String readAccountingServiceSource() {
  final facade = File('lib/core/services/accounting_service.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final implementation = readAccountingServiceImplementationSource();
  final models = File('lib/core/services/accounting_service_models.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  // Keep implementation declarations first so source-contract tests that
  // extract a method body do not accidentally match the facade forwarder.
  return '$implementation\n$models\n$facade';
}

/// Reads the implementation library and all of its part files.
String readAccountingServiceImplementationSource() {
  const directory = 'lib/core/services';
  final mainSource = File('$directory/accounting_service_impl.dart')
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
