import 'dart:io';

/// Reads the complete SettingsPage library, including its part files.
String readSettingsPageImplementationSource() {
  const directory = 'lib/features/settings';
  final mainFile = File('$directory/settings_page.dart');
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
