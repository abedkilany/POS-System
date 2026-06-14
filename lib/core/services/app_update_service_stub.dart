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
}

class AppUpdateService {
  const AppUpdateService();

  bool get isSupported => false;

  Future<AppUpdateInfo?> checkForUpdate() async => null;

  Future<String> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError('Ventio updates are only supported on Windows.');
  }
}

AppUpdateService getAppUpdateService() => const AppUpdateService();
