import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final options = _parseArgs(args);
  final configFile = File(options.configPath);
  if (!configFile.existsSync()) {
    stderr.writeln('Quality gate config not found: ${options.configPath}');
    exitCode = 2;
    return;
  }

  final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final minimum = options.minimum ??
      (config['coverageMinimumPercent'] as num?)?.toDouble() ??
      0.0;
  final excludes = (config['coverageExcludes'] as List<dynamic>? ?? const [])
      .map((value) => _normalizePath('$value'))
      .toList(growable: false);

  final lcov = File(options.lcovPath);
  if (!lcov.existsSync()) {
    stderr.writeln(
      'Coverage file not found: ${options.lcovPath}. Run: flutter test --coverage',
    );
    exitCode = 2;
    return;
  }

  var totalHit = 0;
  var totalFound = 0;
  var includedFiles = 0;
  var excludedFiles = 0;

  String? currentFile;
  var currentHit = 0;
  var currentFound = 0;

  void commitCurrent() {
    if (currentFile == null) return;
    final path = _normalizeSourcePath(currentFile);
    if (_matchesAny(path, excludes)) {
      excludedFiles += 1;
    } else {
      includedFiles += 1;
      totalHit += currentHit;
      totalFound += currentFound;
    }
  }

  for (final rawLine in lcov.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.startsWith('SF:')) {
      commitCurrent();
      currentFile = line.substring(3).trim();
      currentHit = 0;
      currentFound = 0;
    } else if (line.startsWith('LH:')) {
      currentHit += int.tryParse(line.substring(3).trim()) ?? 0;
    } else if (line.startsWith('LF:')) {
      currentFound += int.tryParse(line.substring(3).trim()) ?? 0;
    }
  }
  commitCurrent();

  if (totalFound == 0) {
    stderr.writeln('No coverable lines found after exclusions in ${options.lcovPath}');
    exitCode = 2;
    return;
  }

  final percent = (totalHit / totalFound) * 100.0;
  stdout.writeln(
    'Coverage: ${percent.toStringAsFixed(2)}% '
    '($totalHit / $totalFound lines). Minimum: ${minimum.toStringAsFixed(2)}%',
  );
  stdout.writeln(
    'Coverage files: $includedFiles included, $excludedFiles excluded '
    '(shared policy: ${options.configPath}).',
  );

  if (percent + 1e-9 < minimum) {
    stderr.writeln(
      'Coverage gate failed: ${percent.toStringAsFixed(2)}% is below '
      '${minimum.toStringAsFixed(2)}%',
    );
    exitCode = 1;
  }
}

class _Options {
  const _Options({
    required this.lcovPath,
    required this.configPath,
    this.minimum,
  });

  final String lcovPath;
  final String configPath;
  final double? minimum;
}

_Options _parseArgs(List<String> args) {
  var lcovPath = 'coverage/lcov.info';
  var configPath = 'tool/quality_gate_config.json';
  double? minimum;

  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (arg == '--lcov' && index + 1 < args.length) {
      lcovPath = args[++index];
    } else if (arg == '--config' && index + 1 < args.length) {
      configPath = args[++index];
    } else if (arg == '--minimum' && index + 1 < args.length) {
      minimum = double.tryParse(args[++index]);
      if (minimum == null) {
        stderr.writeln('Invalid --minimum value: ${args[index]}');
        exit(2);
      }
    } else {
      stderr.writeln('Unknown or incomplete argument: $arg');
      exit(2);
    }
  }

  return _Options(
    lcovPath: lcovPath,
    configPath: configPath,
    minimum: minimum,
  );
}

String _normalizePath(String value) => value.replaceAll('\\', '/');

String _normalizeSourcePath(String sourcePath) {
  var path = _normalizePath(sourcePath);
  final cwd = _normalizePath(Directory.current.absolute.path);
  if (path.startsWith('$cwd/')) {
    path = path.substring(cwd.length + 1);
  }
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  return path;
}

bool _matchesAny(String path, List<String> patterns) {
  for (final pattern in patterns) {
    if (_globMatches(path, pattern)) return true;
  }
  return false;
}

bool _globMatches(String path, String glob) {
  final buffer = StringBuffer('^');
  for (var index = 0; index < glob.length; index += 1) {
    final char = glob[index];
    if (char == '*') {
      final isDouble = index + 1 < glob.length && glob[index + 1] == '*';
      if (isDouble) {
        index += 1;
        if (index + 1 < glob.length && glob[index + 1] == '/') {
          index += 1;
          buffer.write('(?:.*/)?');
        } else {
          buffer.write('.*');
        }
      } else {
        buffer.write('[^/]*');
      }
    } else if (char == '?') {
      buffer.write('[^/]');
    } else {
      buffer.write(RegExp.escape(char));
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString()).hasMatch(path);
}
