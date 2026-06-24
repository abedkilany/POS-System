import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SetNewVersionApp());
}

class SetNewVersionApp extends StatelessWidget {
  const SetNewVersionApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF117A65);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Set New Version',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.light,
      ),
      home: const ControlCenterPage(),
    );
  }
}

class VersionInfo {
  const VersionInfo({required this.version, required this.build});

  final String version;
  final int build;

  String get full => '$version+$build';
}

enum TerminalLineKind { command, output, info, warning, error, success, muted }

class TerminalLine {
  const TerminalLine({
    required this.kind,
    required this.text,
  });

  final TerminalLineKind kind;
  final String text;
}

class CommandPreset {
  const CommandPreset({
    required this.label,
    required this.command,
    required this.icon,
    this.displayCommand,
    this.requiresConfirmation = false,
    this.opensPowerShell = false,
    this.confirmTitle,
    this.confirmMessage,
  });

  final String label;
  final String command;
  final String? displayCommand;
  final IconData icon;
  final bool requiresConfirmation;
  final bool opensPowerShell;
  final String? confirmTitle;
  final String? confirmMessage;
}

class ControlCenterPage extends StatefulWidget {
  const ControlCenterPage({super.key});

  @override
  State<ControlCenterPage> createState() => _ControlCenterPageState();
}

class _ControlCenterPageState extends State<ControlCenterPage> {
  final TextEditingController _versionController = TextEditingController();
  final TextEditingController _manualCommandController = TextEditingController();
  final ScrollController _terminalScrollController = ScrollController();

  Directory? _ventioRoot;
  VersionInfo? _currentVersion;
  bool _loading = true;
  bool _busy = false;
  String _status = 'Loading project...';
  String? _activeCommand;
  final List<TerminalLine> _terminal = <TerminalLine>[];

  static const _flutterCommands = <CommandPreset>[
    CommandPreset(
      label: 'flutter create .',
      command: 'flutter create .',
      displayCommand: 'flutter create .',
      icon: Icons.create_new_folder_outlined,
      requiresConfirmation: true,
      confirmTitle: 'Run flutter create',
      confirmMessage:
          'This can update platform files inside Ventio. Run it now?',
    ),
    CommandPreset(
      label: 'flutter clean',
      command: 'flutter clean',
      icon: Icons.cleaning_services_outlined,
    ),
    CommandPreset(
      label: 'flutter pub get',
      command: 'flutter pub get',
      icon: Icons.download_outlined,
    ),
    CommandPreset(
      label: 'flutter analyze',
      command: 'flutter analyze',
      icon: Icons.fact_check_outlined,
    ),
    CommandPreset(
      label: 'flutter test -r expanded',
      command: 'flutter test -r expanded',
      icon: Icons.science_outlined,
    ),
    CommandPreset(
      label: 'flutter build windows --release',
      command: 'flutter build windows --release',
      icon: Icons.desktop_windows_outlined,
    ),
    CommandPreset(
      label: 'flutter build apk --release',
      command: 'flutter build apk --release',
      icon: Icons.android_outlined,
    ),
    CommandPreset(
      label: 'flutter build web --release',
      command: 'flutter build web --release',
      icon: Icons.language_outlined,
    ),
  ];

  static const _gitCommands = <CommandPreset>[
    CommandPreset(
      label: 'git status',
      command: 'git status',
      icon: Icons.history_outlined,
    ),
    CommandPreset(
      label: 'git add',
      command: 'git add -A',
      displayCommand: 'git add -A',
      icon: Icons.add_circle_outline,
      requiresConfirmation: true,
      confirmTitle: 'Stage changes',
      confirmMessage: 'This will stage all current changes in Ventio.',
    ),
    CommandPreset(
      label: 'git commit "update"',
      command: 'git commit -m "update"',
      icon: Icons.commit_outlined,
      requiresConfirmation: true,
      confirmTitle: 'Commit changes',
      confirmMessage: 'This will create a commit with message "update".',
    ),
    CommandPreset(
      label: 'git commit "restore"',
      command: 'git commit -m "restore"',
      icon: Icons.commit_outlined,
      requiresConfirmation: true,
      confirmTitle: 'Commit changes',
      confirmMessage: 'This will create a commit with message "restore".',
    ),
    CommandPreset(
      label: 'git push origin main',
      command: 'git push origin main',
      icon: Icons.cloud_upload_outlined,
      requiresConfirmation: true,
      confirmTitle: 'Push to origin',
      confirmMessage: 'This will push the current branch to origin main.',
    ),
    CommandPreset(
      label: 'git archive Ventio.zip',
      command: 'git archive --format=zip --output=Ventio.zip main',
      displayCommand: 'git archive --format=zip --output=Ventio.zip main',
      icon: Icons.archive_outlined,
      requiresConfirmation: true,
      confirmTitle: 'Create archive',
      confirmMessage: 'This will create Ventio.zip from the main branch.',
    ),
    CommandPreset(
      label: 'open server',
      command:
          r'Set-Location "$HOME\Desktop\Ventio\SSH"; ssh -i .\ssh-key-2026-06-13.key ubuntu@139.185.35.173',
      displayCommand:
          r'Set-Location "$HOME\Desktop\Ventio\SSH"; ssh -i .\ssh-key-2026-06-13.key ubuntu@139.185.35.173',
      icon: Icons.terminal_rounded,
      opensPowerShell: true,
      requiresConfirmation: true,
      confirmTitle: 'Open server session',
      confirmMessage:
          'This will open PowerShell and connect to the server using the SSH key.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadProject();
  }

  @override
  void dispose() {
    _versionController.dispose();
    _manualCommandController.dispose();
    _terminalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProject() async {
    setState(() {
      _loading = true;
      _status = 'Finding Ventio root...';
    });

    try {
      final root = await _findVentioRoot();
      final current = await _readCurrentVersion(root);
      setState(() {
        _ventioRoot = root;
        _currentVersion = current;
        _versionController.text = current.full;
        _status = 'Ready';
        _loading = false;
        _terminal
          ..clear()
          ..add(TerminalLine(
            kind: TerminalLineKind.success,
            text: 'Loaded ${current.full} from pubspec.yaml.',
          ));
      });
      _scrollTerminalToBottom();
    } catch (error) {
      setState(() {
        _loading = false;
        _status = 'Could not load project';
        _terminal
          ..clear()
          ..add(TerminalLine(
            kind: TerminalLineKind.error,
            text: 'Error: $error',
          ));
      });
      _scrollTerminalToBottom();
    }
  }

  Future<Directory> _findVentioRoot() async {
    final candidates = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];

    for (final start in candidates) {
      var current = start;
      while (true) {
        final pubspec = File(
          '${current.path}${Platform.pathSeparator}pubspec.yaml',
        );
        final buildScript = File(
          '${current.path}${Platform.pathSeparator}scripts${Platform.pathSeparator}build_windows_installer.ps1',
        );

        if (await pubspec.exists() && await buildScript.exists()) {
          final text = await pubspec.readAsString();
          if (text.contains(RegExp(r'^name:\s*ventio\s*$', multiLine: true))) {
            return current;
          }
        }

        final parent = current.parent;
        if (parent.path == current.path) {
          break;
        }
        current = parent;
      }
    }

    throw 'Could not locate the Ventio repository root.';
  }

  Future<VersionInfo> _readCurrentVersion(Directory root) async {
    final pubspec = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    final text = await pubspec.readAsString();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(text);
    if (match == null) {
      throw 'Could not read version from pubspec.yaml.';
    }

    return VersionInfo(
      version: match.group(1)!,
      build: int.parse(match.group(2)!),
    );
  }

  Future<void> _setVersionFiles(Directory root, String fullVersion) async {
    final match = RegExp(r'^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$')
        .firstMatch(fullVersion);
    if (match == null) {
      throw 'Use the format 1.2.3+45.';
    }

    final versionName = match.group(1)!;
    final buildNumber = match.group(2)!;
    final pubspecPath = '${root.path}${Platform.pathSeparator}pubspec.yaml';
    final appBrandPath =
        '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}core${Platform.pathSeparator}app_brand.dart';
    final installerPath =
        '${root.path}${Platform.pathSeparator}installer${Platform.pathSeparator}ventio.iss';

    var pubspec = await File(pubspecPath).readAsString();
    pubspec = pubspec.replaceFirstMapped(
      RegExp(
        r'^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+\s*$',
        multiLine: true,
      ),
      (_) => 'version: $fullVersion',
    );
    await File(pubspecPath).writeAsString(pubspec);

    var appBrand = await File(appBrandPath).readAsString();
    appBrand = appBrand.replaceFirstMapped(
      RegExp(r"(defaultValue:\s*')[^']*(')"),
      (_) => "defaultValue: '$fullVersion'",
    );
    await File(appBrandPath).writeAsString(appBrand);

    var installer = await File(installerPath).readAsString();
    installer = installer.replaceFirstMapped(
      RegExp(r'^  #define AppVersion ".*"$', multiLine: true),
      (_) => '  #define AppVersion "$versionName"',
    );
    installer = installer.replaceFirstMapped(
      RegExp(r'^  #define AppBuild ".*"$', multiLine: true),
      (_) => '  #define AppBuild "$buildNumber"',
    );
    await File(installerPath).writeAsString(installer);
  }

  Future<void> _appendLine(TerminalLine line) async {
    if (!mounted) return;
    setState(() {
      _terminal.add(line);
    });
    _scrollTerminalToBottom();
  }

  Future<void> _appendText(String text, TerminalLineKind kind) async {
    final normalized = _stripAnsi(text).trimRight();
    if (normalized.isEmpty) return;
    await _appendLine(TerminalLine(kind: kind, text: normalized));
  }

  String _phaseForCommand(String command) {
    final normalized = command.toLowerCase().trim();
    if (normalized.contains('flutter create')) {
      return 'Refreshing Flutter project files...';
    }
    if (normalized.contains('flutter clean')) {
      return 'Cleaning Flutter build artifacts...';
    }
    if (normalized.contains('flutter pub get')) {
      return 'Fetching packages...';
    }
    if (normalized.contains('flutter analyze')) {
      return 'Analyzing code...';
    }
    if (normalized.contains('flutter test')) {
      return 'Running tests...';
    }
    if (normalized.contains('flutter build windows')) {
      return 'Building Windows installer...';
    }
    if (normalized.contains('flutter build apk')) {
      return 'Building Android APK...';
    }
    if (normalized.contains('flutter build web')) {
      return 'Building web release...';
    }
    if (normalized.contains('git status')) {
      return 'Inspecting git status...';
    }
    if (normalized.contains('git add')) {
      return 'Staging changes...';
    }
    if (normalized.contains('git commit')) {
      return 'Creating commit...';
    }
    if (normalized.contains('git push')) {
      return 'Uploading to GitHub...';
    }
    if (normalized.contains('git archive')) {
      return 'Creating archive...';
    }
    if (normalized.contains('powershell.exe')) {
      return 'Opening PowerShell session...';
    }
    return 'Running command...';
  }

  void _scrollTerminalToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_terminalScrollController.hasClients) return;
      _terminalScrollController.jumpTo(
        _terminalScrollController.position.maxScrollExtent,
      );
    });
  }

  String _stripAnsi(String value) {
    return value.replaceAll(
      RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'),
      '',
    );
  }

  bool _shouldShowLine(String line) {
    final trimmed = _stripAnsi(line).trim();
    if (trimmed.isEmpty) return false;

    const mutedExact = {
      'Resolving dependencies...',
      'Downloading packages...',
      'Got dependencies!',
    };
    if (mutedExact.contains(trimmed)) return false;

    if (RegExp(r'^[A-Za-z0-9_.-]+\s+[0-9]').hasMatch(trimmed)) return false;
    if (trimmed.contains('available)')) return false;
    if (trimmed.startsWith('Packages are up to date.')) return false;
    if (trimmed.startsWith('Running "flutter pub get"')) return false;

    return true;
  }

  TerminalLineKind _classifyLine(String line, {required bool isError}) {
    final trimmed = _stripAnsi(line).trim();
    if (trimmed.isEmpty) return TerminalLineKind.muted;
    if (isError) return TerminalLineKind.error;
    if (trimmed.startsWith('> ')) return TerminalLineKind.command;

    final lower = trimmed.toLowerCase();
    if (lower.contains('warning') ||
        lower.contains('deprecated') ||
        lower.contains('available')) {
      return TerminalLineKind.warning;
    }
    if (lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('fatal') ||
        lower.contains('exception') ||
        lower.contains('could not') ||
        lower.contains('not found') ||
        lower.contains('permission denied') ||
        lower.contains('no such file')) {
      return TerminalLineKind.error;
    }
    if (lower.contains('success') ||
        lower.contains('completed successfully') ||
        lower.contains('all tests passed') ||
        lower.startsWith('done') ||
        lower.contains('built build\\windows') ||
        lower.contains('built build/windows') ||
        lower.contains('successfully')) {
      return TerminalLineKind.success;
    }
    if (lower.contains('building') ||
        lower.contains('running') ||
        lower.contains('copying') ||
        lower.contains('creating')) {
      return TerminalLineKind.info;
    }
    return TerminalLineKind.output;
  }

  Future<bool> _confirmAction(String title, String message) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Run'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _runPreset(CommandPreset preset) async {
    if (_busy) return;
    if (preset.requiresConfirmation) {
      final allowed = await _confirmAction(
        preset.confirmTitle ?? 'Run command',
        preset.confirmMessage ?? 'Run this command on Ventio now?',
      );
      if (!allowed) return;
    }

    if (preset.opensPowerShell) {
      await _launchPowerShellSession(
        preset.command,
        displayCommand: preset.displayCommand ?? preset.command,
      );
      return;
    }

    await _runCommand(
      preset.command,
      displayCommand: preset.displayCommand ?? preset.command,
    );
  }

  Future<void> _runManualCommand() async {
    final command = _manualCommandController.text.trim();
    if (command.isEmpty) return;
    await _runCommand(command);
  }

  Future<void> _runCommand(
    String command, {
    String? displayCommand,
    bool manageBusy = true,
  }) async {
    final root = _ventioRoot;
    if (root == null) return;
    if (manageBusy && _busy) return;

    final phase = _phaseForCommand(command);
    if (manageBusy) {
      setState(() {
        _busy = true;
        _status = phase;
        _activeCommand = displayCommand ?? command;
      });
    } else {
      setState(() {
        _status = phase;
        _activeCommand = displayCommand ?? command;
      });
    }

    final shown = displayCommand ?? command;
    final stopwatch = Stopwatch()..start();
    await _appendLine(
      TerminalLine(kind: TerminalLineKind.info, text: phase),
    );
    await _appendLine(
      TerminalLine(kind: TerminalLineKind.command, text: '> $shown'),
    );

    try {
      final process = await Process.start(
        'cmd.exe',
        ['/c', command],
        workingDirectory: root.path,
        runInShell: false,
      );

      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (_shouldShowLine(line)) {
              _appendText(
                line,
                _classifyLine(line, isError: false),
              );
            }
          });
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (_shouldShowLine(line)) {
              _appendText(
                line,
                _classifyLine(line, isError: true),
              );
            }
          });

      final stdoutDone = stdoutSub.asFuture<void>();
      final stderrDone = stderrSub.asFuture<void>();
      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);

      if (exitCode == 0) {
        await _appendLine(
          TerminalLine(
            kind: TerminalLineKind.success,
            text:
                'Done in ${stopwatch.elapsed.inSeconds}.${(stopwatch.elapsed.inMilliseconds % 1000).toString().padLeft(3, '0')}s',
          ),
        );
      } else {
        await _appendLine(
          TerminalLine(
            kind: TerminalLineKind.error,
            text: 'Command failed with exit code $exitCode.',
          ),
        );
      }
    } catch (error) {
      await _appendLine(
        TerminalLine(
          kind: TerminalLineKind.error,
          text: 'Error: $error',
        ),
      );
    } finally {
      if (mounted && manageBusy) {
        setState(() {
          _busy = false;
          _status = 'Ready';
          _activeCommand = null;
        });
      } else if (mounted) {
        setState(() {
          _status = 'Ready';
          _activeCommand = null;
        });
      }
    }
  }

  Future<void> _launchPowerShellSession(
    String command, {
    String? displayCommand,
  }) async {
    final root = _ventioRoot;
    if (root == null || _busy) return;

    setState(() {
      _busy = true;
      _status = 'Opening PowerShell...';
      _activeCommand = displayCommand ?? command;
    });

    final shown = displayCommand ?? command;
    try {
      await _appendLine(
        TerminalLine(kind: TerminalLineKind.command, text: '> $shown'),
      );
      await Process.start(
        'cmd.exe',
        [
          '/c',
          'start',
          '',
          'powershell.exe',
          '-NoExit',
          '-Command',
          command,
        ],
        workingDirectory: root.path,
        runInShell: false,
      );
      await _appendLine(
        const TerminalLine(
          kind: TerminalLineKind.success,
          text: 'PowerShell window opened.',
        ),
      );
    } catch (error) {
      await _appendLine(
        TerminalLine(
          kind: TerminalLineKind.error,
          text: 'Error: $error',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Ready';
          _activeCommand = null;
        });
      }
    }
  }

  Future<void> _updateVersionAndBuild() async {
    final root = _ventioRoot;
    if (root == null || _busy) return;

    final newVersion = _versionController.text.trim();
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$').hasMatch(newVersion)) {
      await _appendLine(
        const TerminalLine(
          kind: TerminalLineKind.error,
          text: 'Use the format 1.2.3+45.',
        ),
      );
      return;
    }

      setState(() {
        _busy = true;
        _status = 'Updating version files...';
        _activeCommand = 'update version + build installer';
      });

    try {
      await _appendLine(
        TerminalLine(
          kind: TerminalLineKind.command,
          text: '> update version -> $newVersion',
        ),
      );
      await _setVersionFiles(root, newVersion);
      await _appendLine(
        const TerminalLine(
          kind: TerminalLineKind.success,
          text: 'Version files updated.',
        ),
      );

      final updated = await _readCurrentVersion(root);
      setState(() {
        _currentVersion = updated;
        _versionController.text = updated.full;
        _status = 'Building installer...';
      });

      await _appendLine(
        const TerminalLine(
          kind: TerminalLineKind.info,
          text: 'Building Windows installer...',
        ),
      );

      await _runCommand(
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\\build_windows_installer.ps1',
        displayCommand: 'scripts\\build_windows_installer.ps1',
        manageBusy: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Ready';
          _activeCommand = null;
        });
      }
    }
  }

  Future<void> _refreshProjectInfo() async {
    if (_busy) return;
    await _loadProject();
  }

  Future<void> _openVentioFolder() async {
    final root = _ventioRoot;
    if (root == null) return;
    await Process.start('explorer.exe', [root.path]);
  }

  Color _colorFor(TerminalLineKind kind, ColorScheme scheme) {
    switch (kind) {
      case TerminalLineKind.command:
        return const Color(0xFF4FC3F7);
      case TerminalLineKind.output:
        return const Color(0xFFE6E6E6);
      case TerminalLineKind.info:
        return const Color(0xFF9CDCFE);
      case TerminalLineKind.warning:
        return const Color(0xFFD7BA7D);
      case TerminalLineKind.error:
        return const Color(0xFFF44747);
      case TerminalLineKind.success:
        return const Color(0xFF4EC9B0);
      case TerminalLineKind.muted:
        return scheme.outlineVariant;
    }
  }

  Widget _buildCommandButton(CommandPreset preset) {
    final isBusy = _busy;
    return SizedBox(
      width: 240,
      child: FilledButton.tonalIcon(
        onPressed: isBusy ? null : () => _runPreset(preset),
        icon: Icon(preset.icon, size: 18),
        label: Text(
          preset.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildLeftPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = _currentVersion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ventio control center',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Run commands and update versions directly against the Ventio root.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoChip(label: 'Current', value: current?.full ?? 'Unknown'),
                  _InfoChip(label: 'Status', value: _status),
                  _InfoChip(
                    label: 'Root',
                    value: _ventioRoot == null
                        ? 'Not found'
                        : _ventioRoot!.path.split(Platform.pathSeparator).last,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Version',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _versionController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'New version',
                  hintText: '1.0.49+59',
                  helperText: 'Use MAJOR.MINOR.PATCH+BUILD',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit_rounded),
                ),
                onSubmitted: (_) => _updateVersionAndBuild(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _updateVersionAndBuild,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Update + build installer'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _refreshProjectInfo,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reload'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Flutter',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _flutterCommands.map(_buildCommandButton).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Git',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _gitCommands.map(_buildCommandButton).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Custom command',
          child: Column(
            children: [
              TextField(
                controller: _manualCommandController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Enter a command',
                  hintText: 'flutter pub outdated',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.terminal_rounded),
                ),
                onSubmitted: (_) => _runManualCommand(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _runManualCommand,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Run command'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _manualCommandController.clear(),
                    icon: const Icon(Icons.clear_rounded),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Text(
                  'Results',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 12),
                if (_activeCommand != null)
                  Flexible(
                    child: Text(
                      _activeCommand!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _terminal.isEmpty
                      ? null
                      : () {
                          final buffer = _terminal
                              .map((line) => line.text)
                              .join('\n');
                          Clipboard.setData(ClipboardData(text: buffer));
                        },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy output'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Open Ventio root',
                  onPressed: _ventioRoot == null ? null : _openVentioFolder,
                  icon: const Icon(Icons.folder_open_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
              ),
              child: _terminal.isEmpty
                  ? Center(
                      child: Text(
                        'No commands yet.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF808080),
                            ),
                      ),
                    )
                  : ListView.builder(
                      controller: _terminalScrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _terminal.length,
                      itemBuilder: (context, index) {
                        final entry = _terminal[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            entry.text,
                            softWrap: true,
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 13.5,
                              height: 1.3,
                              color: _colorFor(entry.kind, scheme),
                              fontWeight: entry.kind == TerminalLineKind.command
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        title: const Text('Set New Version'),
        actions: [
          IconButton(
            tooltip: 'Reload project',
            onPressed: _busy ? null : _refreshProjectInfo,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Open Ventio root',
            onPressed: _ventioRoot == null ? null : _openVentioFolder,
            icon: const Icon(Icons.folder_open_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(18),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            child: _buildLeftPanel(context),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 6,
                          child: _buildTerminalPanel(context),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: _buildLeftPanel(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 460,
                          child: _buildTerminalPanel(context),
                        ),
                      ],
                    ),
            ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
