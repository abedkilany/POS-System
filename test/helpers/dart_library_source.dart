import 'dart:io';

/// Reads one implementation file when responsibility has moved out of its
/// original `part` library into an independently testable service/model.
String readDartFileSource(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

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

/// Extracts one block-bodied Dart method by its declaration prefix.
///
/// The method may be followed by another declaration in a different `part`
/// file, so tests should not use that next declaration as the method boundary.
String extractDartMethodSource(String source, String declarationPrefix) {
  final start = source.indexOf(declarationPrefix);
  if (start < 0) {
    throw StateError('Dart method was not found: $declarationPrefix');
  }

  final parametersStart = source.indexOf('(', start);
  if (parametersStart < 0) {
    throw StateError('Dart method has no parameter list: $declarationPrefix');
  }

  var parameterDepth = 0;
  var parametersEnd = -1;
  for (var index = parametersStart; index < source.length; index += 1) {
    final skipped = _skipDartNonCode(source, index);
    if (skipped != index) {
      index = skipped - 1;
      continue;
    }

    switch (source[index]) {
      case '(':
        parameterDepth += 1;
        break;
      case ')':
        parameterDepth -= 1;
        if (parameterDepth == 0) {
          parametersEnd = index;
          index = source.length;
        }
        break;
    }
  }
  if (parametersEnd < 0) {
    throw StateError(
        'Dart method parameters are not closed: $declarationPrefix');
  }

  final bodyStart = _findNextMethodBody(source, parametersEnd + 1);
  final bodyEnd = _findMatchingDartBrace(source, bodyStart);
  return source.substring(start, bodyEnd + 1);
}

/// Returns the brace-delimited block that follows [marker].
String extractDartBlockAfter(String source, String marker) {
  final markerStart = source.indexOf(marker);
  if (markerStart < 0) {
    throw StateError('Dart block marker was not found: $marker');
  }
  final bodyStart = source.indexOf('{', markerStart);
  if (bodyStart < 0) {
    throw StateError('Dart block has no opening brace: $marker');
  }
  final bodyEnd = _findMatchingDartBrace(source, bodyStart);
  return source.substring(bodyStart, bodyEnd + 1);
}

int _findNextMethodBody(String source, int start) {
  for (var index = start; index < source.length; index += 1) {
    final skipped = _skipDartNonCode(source, index);
    if (skipped != index) {
      index = skipped - 1;
      continue;
    }
    if (source[index] == '{') return index;
    if (source[index] == ';' || source.startsWith('=>', index)) break;
  }
  throw StateError('Dart method body was not found.');
}

int _findMatchingDartBrace(String source, int bodyStart) {
  var depth = 0;
  for (var index = bodyStart; index < source.length; index += 1) {
    final skipped = _skipDartNonCode(source, index);
    if (skipped != index) {
      index = skipped - 1;
      continue;
    }
    if (source[index] == '{') depth += 1;
    if (source[index] == '}') {
      depth -= 1;
      if (depth == 0) return index;
    }
  }
  throw StateError('Dart method body braces are not balanced.');
}

/// Skips a comment or string literal, returning [index] when it points to
/// ordinary Dart code. Braces and parentheses inside these regions are not
/// structural delimiters for source-contract tests.
int _skipDartNonCode(String source, int index) {
  if (source.startsWith('//', index)) {
    final newline = source.indexOf('\n', index + 2);
    return newline < 0 ? source.length : newline + 1;
  }
  if (source.startsWith('/*', index)) {
    var depth = 1;
    var cursor = index + 2;
    while (cursor < source.length && depth > 0) {
      if (source.startsWith('/*', cursor)) {
        depth += 1;
        cursor += 2;
      } else if (source.startsWith('*/', cursor)) {
        depth -= 1;
        cursor += 2;
      } else {
        cursor += 1;
      }
    }
    return cursor;
  }

  final quote = source[index];
  if (quote != "'" && quote != '"') return index;
  final isRaw = index > 0 &&
      (source[index - 1] == 'r' || source[index - 1] == 'R') &&
      (index < 2 || !_isDartIdentifierCharacter(source[index - 2]));
  final isTriple = source.startsWith('$quote$quote$quote', index);
  final delimiterLength = isTriple ? 3 : 1;
  var cursor = index + delimiterLength;
  while (cursor < source.length) {
    if (isTriple && source.startsWith('$quote$quote$quote', cursor)) {
      return cursor + 3;
    }
    if (!isTriple && source[cursor] == quote) return cursor + 1;
    if (!isRaw && source[cursor] == r'\' && cursor + 1 < source.length) {
      cursor += 2;
    } else {
      cursor += 1;
    }
  }
  return source.length;
}

bool _isDartIdentifierCharacter(String character) =>
    RegExp(r'[A-Za-z0-9_$]').hasMatch(character);
