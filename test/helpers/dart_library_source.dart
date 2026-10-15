import 'dart:io';

/// Reads a Dart library and the source files that contain its implementation.
///
/// When [path] names a library root, all declared parts are included. When it
/// names a part, the root and the sibling parts for that source area are read.
String readDartLibrarySource(String path) {
  final requested = File(path).absolute;
  final requestedSource = requested.readAsStringSync().replaceAll('\r\n', '\n');
  final partOf = RegExp(r"^\s*part\s+of\s+'([^']+)'\s*;", multiLine: true)
      .firstMatch(requestedSource);
  if (partOf != null) {
    final root =
        File(requested.parent.uri.resolve(partOf.group(1)!).toFilePath());
    final rootSource = root.readAsStringSync().replaceAll('\r\n', '\n');
    final uriMatches = RegExp(r"^\s*part\s+'([^']+)'\s*;", multiLine: true)
        .allMatches(rootSource)
        .map((match) => match.group(1)!)
        .toList(growable: false);
    final partName = requested.uri.pathSegments.last;
    final area = partName.endsWith('.dart')
        ? partName.substring(0, partName.length - 5)
        : partName;
    final relatedUris = uriMatches.where((uri) {
      final name = uri.split('/').last;
      return name == partName || name.startsWith('${area}_');
    });
    return <String>[
      requestedSource,
      for (final uri in relatedUris)
        if (root.parent.uri.resolve(uri).toFilePath() != requested.path)
          File(root.parent.uri.resolve(uri).toFilePath())
              .readAsStringSync()
              .replaceAll('\r\n', '\n'),
    ].join('\n');
  }

  final partUris = RegExp(r"^\s*part\s+'([^']+)'\s*;", multiLine: true)
      .allMatches(requestedSource)
      .map((match) => match.group(1)!)
      .toList(growable: false);
  if (partUris.isEmpty) return requestedSource;

  return <String>[
    requestedSource,
    for (final uri in partUris)
      File(requested.parent.uri.resolve(uri).toFilePath())
          .readAsStringSync()
          .replaceAll('\r\n', '\n'),
  ].join('\n');
}
