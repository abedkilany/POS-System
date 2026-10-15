import 'dart:io';

/// Returns the implementation source for the AppStore library after the
/// domain split. Contract tests use this instead of assuming every AppStore
/// method body lives physically in app_store.dart.
String readAppStoreImplementationSource() {
  final mainSource = File('lib/data/app_store.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final partPattern = RegExp(r"^\s*part\s+'([^']+)';", multiLine: true);
  final implementationParts = <String>[];
  final forwardingParts = <String>[];

  for (final match in partPattern.allMatches(mainSource)) {
    final relativePath = match.group(1);
    if (relativePath == null || !relativePath.startsWith('app_store_')) {
      continue;
    }
    final partFile = File('lib/data/$relativePath');
    if (!partFile.existsSync()) continue;
    final section = '// ---- $relativePath ----\n'
        '${partFile.readAsStringSync().replaceAll('\r\n', '\n')}\n';
    if (relativePath.startsWith('app_store_forwarding_api')) {
      forwardingParts.add(section);
    } else {
      implementationParts.add(section);
    }
  }

  // Source-contract tests should find the real method implementation before
  // the compatibility forwarding mixins, whose method signatures are the same.
  return <String>[
    ...implementationParts,
    '// ---- app_store.dart ----\n$mainSource',
    ...forwardingParts,
  ].join('\n');
}
