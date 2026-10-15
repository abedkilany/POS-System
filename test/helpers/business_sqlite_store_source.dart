import 'dart:io';

/// Reads the public facade and implementation source for BusinessSqliteStore.
String readBusinessSqliteStoreSource() {
  final facade = File('lib/core/storage/sqlite/business_sqlite_store.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final implementation = readBusinessSqliteStoreImplementationSource();
  final models =
      File('lib/core/storage/sqlite/business_sqlite_store_models.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
  return '$facade\n$implementation\n$models';
}

/// Reads the implementation library and all of its part files.
String readBusinessSqliteStoreImplementationSource() {
  const directory = 'lib/core/storage/sqlite';
  final mainSource = File('$directory/business_sqlite_store_impl.dart')
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
