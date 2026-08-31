import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final root = Directory.current.absolute;
  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final outputDir = Directory('quality_baseline/$timestamp');
  outputDir.createSync(recursive: true);

  final manifest = <String, dynamic>{
    'schemaVersion': 1,
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'projectRoot': root.path,
    'platform': Platform.operatingSystem,
    'appVersion': _pubspecVersion(),
    'testInventory': _testInventory(),
    'staticVersions': _staticVersionInventory(),
    'steps': <Map<String, dynamic>>[],
  };

  final steps = manifest['steps'] as List<Map<String, dynamic>>;
  var failed = false;

  Future<void> runStep(
    String name,
    String executable,
    List<String> arguments, {
    bool required = true,
  }) async {
    stdout.writeln('\n=== $name ===');
    final logFile = File('${outputDir.path}/${_safeName(name)}.log');
    final result = await _runAndTee(executable, arguments, logFile);
    final status = result.exitCode == 0 ? 'PASS' : 'FAIL';
    steps.add({
      'name': name,
      'command': [executable, ...arguments].join(' '),
      'status': status,
      'exitCode': result.exitCode,
      'required': required,
      'log': logFile.path,
    });
    if (required && result.exitCode != 0) failed = true;
  }

  await runStep('flutter_version', 'flutter', ['--version']);
  await runStep('flutter_pub_get', 'flutter', ['pub', 'get']);
  await runStep('flutter_analyze', 'flutter', ['analyze']);
  await runStep('flutter_test_full_coverage', 'flutter', [
    'test',
    '-r',
    'expanded',
    '--coverage',
    '--concurrency=1',
  ]);
  await runStep('coverage_policy', 'dart', [
    'run',
    'tool/check_coverage.dart',
    '--config',
    'tool/quality_gate_config.json',
  ]);

  if (Platform.isWindows) {
    await runStep('windows_integration_tests', 'flutter', [
      'test',
      'integration_test',
      '-d',
      'windows',
      '-r',
      'expanded',
    ]);
  } else {
    steps.add({
      'name': 'windows_integration_tests',
      'status': 'NOT_RUN',
      'required': true,
      'reason': 'Must be executed on the Windows release machine.',
    });
    // A required release-gate step that was not executed must never produce
    // an overall PASS. The Windows release machine is authoritative for Phase 0.
    failed = true;
  }

  manifest['result'] = failed ? 'FAIL' : 'PASS';
  manifest['note'] = Platform.isWindows
      ? 'All Phase 0 executable baseline checks were attempted.'
      : 'Windows desktop integration remains required before the baseline is accepted.';

  final manifestFile = File('${outputDir.path}/manifest.json');
  manifestFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  File('quality_baseline/LATEST.txt').writeAsStringSync('${outputDir.path}\n');

  _writeMarkdownSummary(outputDir, manifest);

  stdout.writeln('\nPhase 0 baseline result: ${manifest['result']}');
  stdout.writeln('Baseline artifacts: ${outputDir.path}');
  if (failed) exitCode = 1;
}

String _pubspecVersion() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) return 'unknown';
  final match = RegExp(r'^version:\s*(.+)$', multiLine: true)
      .firstMatch(file.readAsStringSync());
  return match?.group(1)?.trim() ?? 'unknown';
}

Map<String, dynamic> _testInventory() {
  int countTests(Directory directory, bool Function(File) include) {
    if (!directory.existsSync()) return 0;
    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .where(include)
        .length;
  }

  final disabled = <String>[];
  final integration = Directory('integration_test');
  if (integration.existsSync()) {
    for (final entity in integration.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.disabled')) {
        disabled.add(_relative(entity.path));
      }
    }
  }
  disabled.sort();

  return {
    'unitAndWidgetTestFiles': countTests(
      Directory('test'),
      (file) => file.path.endsWith('_test.dart'),
    ),
    'enabledIntegrationTestFiles': countTests(
      integration,
      (file) => file.path.endsWith('_test.dart'),
    ),
    'disabledIntegrationTests': disabled,
  };
}

Map<String, dynamic> _staticVersionInventory() {
  String? firstCapture(String path, RegExp expression) {
    final file = File(path);
    if (!file.existsSync()) return null;
    return expression.firstMatch(file.readAsStringSync())?.group(1);
  }

  return {
    'legacyAppStoreSchemaVersion': firstCapture(
      'lib/data/app_store_persistence_sync_core.dart',
      RegExp(r"_schemaVersionKey,\s*'([0-9]+)'"),
    ),
    'driftSchemaVersion': firstCapture(
      'lib/core/storage/sqlite/ventio_drift_database.dart',
      RegExp(r'schemaVersion\s*=>\s*([0-9]+)'),
    ),
    'directPeerHandshakeVersion': firstCapture(
      'lib/core/services/direct_peer_handshake.dart',
      RegExp(r'_version\s*=\s*([0-9]+)'),
    ),
    'authenticatedPeerSessionVersion': firstCapture(
      'lib/core/services/authenticated_peer_session.dart',
      RegExp(r'_version\s*=\s*([0-9]+)'),
    ),
    'unifiedSnapshotVersion': firstCapture(
      'lib/core/snapshot/unified_snapshot.dart',
      RegExp(r'static const version\s*=\s*([0-9]+)'),
    ),
    'syncProtocolVersion': null,
    'syncProtocolVersionNote':
        'No single authoritative sync protocol version constant was found; multiple protocol/schema versions exist and should be centralized before an incompatible sync change.',
  };
}

Future<_RunResult> _runAndTee(
  String executable,
  List<String> arguments,
  File logFile,
) async {
  final sink = logFile.openWrite();
  try {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: true,
      workingDirectory: Directory.current.path,
    );

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stdout.writeln(line);
      sink.writeln(line);
    }).asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderr.writeln(line);
      sink.writeln('[stderr] $line');
    }).asFuture<void>();

    final code = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    await sink.flush();
    return _RunResult(code);
  } on ProcessException catch (error) {
    final message = 'Unable to execute $executable: $error';
    stderr.writeln(message);
    sink.writeln('[stderr] $message');
    await sink.flush();
    return const _RunResult(127);
  } finally {
    await sink.close();
  }
}

void _writeMarkdownSummary(Directory outputDir, Map<String, dynamic> manifest) {
  final buffer = StringBuffer()
    ..writeln('# Ventio Phase 0 Baseline')
    ..writeln()
    ..writeln('- Created: ${manifest['createdAtUtc']}')
    ..writeln('- Platform: ${manifest['platform']}')
    ..writeln('- App version: ${manifest['appVersion']}')
    ..writeln('- Result: **${manifest['result']}**')
    ..writeln()
    ..writeln('## Test inventory')
    ..writeln();

  final inventory = manifest['testInventory'] as Map<String, dynamic>;
  buffer
    ..writeln('- Unit/widget test files: ${inventory['unitAndWidgetTestFiles']}')
    ..writeln('- Enabled integration test files: ${inventory['enabledIntegrationTestFiles']}')
    ..writeln('- Disabled integration tests: ${(inventory['disabledIntegrationTests'] as List).length}');
  for (final path in inventory['disabledIntegrationTests'] as List) {
    buffer.writeln('  - `$path`');
  }

  buffer
    ..writeln()
    ..writeln('## Static versions')
    ..writeln();
  final versions = manifest['staticVersions'] as Map<String, dynamic>;
  for (final entry in versions.entries) {
    buffer.writeln('- ${entry.key}: ${entry.value ?? 'not centralized'}');
  }

  buffer
    ..writeln()
    ..writeln('## Executed checks')
    ..writeln();
  for (final step in manifest['steps'] as List) {
    buffer.writeln('- ${step['name']}: **${step['status']}**');
  }

  File('${outputDir.path}/summary.md').writeAsStringSync(buffer.toString());
}

String _safeName(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_').toLowerCase();

String _relative(String path) {
  final normalized = path.replaceAll('\\', '/');
  final cwd = Directory.current.absolute.path.replaceAll('\\', '/');
  return normalized.startsWith('$cwd/') ? normalized.substring(cwd.length + 1) : normalized;
}

class _RunResult {
  const _RunResult(this.exitCode);
  final int exitCode;
}
