import 'dart:io';

/// Reads independent contracts together with the adapters implementing them.
String readDomainBoundarySource() => <String>[
      for (final file
          in Directory('lib/core/contracts').listSync().whereType<File>())
        if (file.path.endsWith('_domain_port.dart')) file.readAsStringSync(),
      for (final file in Directory('lib/data').listSync().whereType<File>())
        if (file.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('app_store_domains_'))
          file.readAsStringSync(),
    ].join('\n');

String readSessionStateSource() => <String>[
      File('lib/data/app_store_state.dart').readAsStringSync(),
      for (final file
          in Directory('lib/data/state').listSync().whereType<File>())
        if (file.path.endsWith('.dart')) file.readAsStringSync(),
    ].join('\n');

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
    if (relativePath == 'app_store_domains.dart' ||
        relativePath.startsWith('app_store_domains_')) {
      // Domain ports and adapters are routing surfaces, not workflow
      // implementations. Keep source-contract method extraction pointed at
      // the executable data/workflow parts instead of matching an adapter
      // method with the same name first.
      continue;
    }
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
