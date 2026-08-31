import 'dart:io';

/// Returns the implementation source for the AppStore library after the
/// domain split. Contract tests use this instead of assuming every AppStore
/// method body lives physically in app_store.dart.
String readAppStoreImplementationSource() {
  final mainSource = File('lib/data/app_store.dart').readAsStringSync();
  final partPattern = RegExp(r"^\s*part\s+'([^']+)';", multiLine: true);
  final buffer = StringBuffer();

  for (final match in partPattern.allMatches(mainSource)) {
    final relativePath = match.group(1);
    if (relativePath == null || !relativePath.startsWith('app_store_')) {
      continue;
    }
    final partFile = File('lib/data/$relativePath');
    if (!partFile.existsSync()) continue;
    buffer
      ..writeln('// ---- $relativePath ----')
      ..writeln(partFile.readAsStringSync())
      ..writeln();
  }

  return buffer.toString();
}
