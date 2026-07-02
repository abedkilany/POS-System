class AppBrand {
  const AppBrand._();

  static const name = 'Ventio';
  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.28+28',
  );
  static const cloudAppVersion = 'ventio';
  static const description =
      'Offline-first sales, inventory, sync, and backup management.';

  static String get versionName => version.split('+').first;

  static int get buildNumber {
    final parts = version.split('+');
    if (parts.length < 2) return 0;
    return int.tryParse(parts.last.trim()) ?? 0;
  }
}
