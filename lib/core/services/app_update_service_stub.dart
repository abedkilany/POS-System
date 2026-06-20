class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.build,
    this.channel = 'stable',
    this.notes = const <String>[],
    this.windowsUrl = '',
    this.sha256 = '',
    this.sizeBytes = 0,
    this.required = false,
  });

  final String version;
  final int build;
  final String channel;
  final List<String> notes;
  final String windowsUrl;
  final String sha256;
  final int sizeBytes;
  final bool required;

  String get displayVersion => '$version+$build';

  bool isNewerThan(String currentVersion, int currentBuild) {
    final versionCompare =
        _compareSemanticVersion(version, currentVersion.trim());
    if (versionCompare != 0) return versionCompare > 0;
    return build > currentBuild;
  }
}

class AppUpdateService {
  const AppUpdateService();

  bool get isSupported => false;

  Future<AppUpdateInfo?> fetchLatest() async => null;

  Future<AppUpdateInfo?> checkForUpdate() async => null;

  Future<String> downloadUpdate(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
    void Function(void Function())? registerCancel,
  }) async {
    throw UnsupportedError('Ventio updates are only supported on Windows.');
  }

  Future<void> launchInstaller(String installerPath) async {
    throw UnsupportedError('Ventio updates are only supported on Windows.');
  }

  Future<String> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError('Ventio updates are only supported on Windows.');
  }
}

AppUpdateService getAppUpdateService() => const AppUpdateService();

int _compareSemanticVersion(String a, String b) {
  final left = _semanticParts(a);
  final right = _semanticParts(b);
  for (var i = 0; i < 3; i += 1) {
    final diff = left[i].compareTo(right[i]);
    if (diff != 0) return diff;
  }
  return 0;
}

List<int> _semanticParts(String value) {
  final clean = value.split('+').first.trim();
  final parts = clean.split('.');
  return List<int>.generate(
    3,
    (index) => index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0,
  );
}
