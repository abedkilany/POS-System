import '../../data/app_store.dart';

class DisasterRecoveryVerificationResult {
  const DisasterRecoveryVerificationResult({
    required this.ok,
    required this.message,
    this.path = '',
    this.generatedAt,
    this.backupVersion = 0,
  });

  final bool ok;
  final String message;
  final String path;
  final DateTime? generatedAt;
  final int backupVersion;
}

class DisasterRecoveryReadiness {
  const DisasterRecoveryReadiness({
    required this.ready,
    required this.checks,
  });

  final bool ready;
  final Map<String, bool> checks;
}

class DisasterRecoveryService {
  const DisasterRecoveryService(this.store);

  final AppStore store;

  Future<DisasterRecoveryReadiness> assessReadiness() async =>
      const DisasterRecoveryReadiness(
        ready: false,
        checks: <String, bool>{'platformSupported': false},
      );

  Future<DisasterRecoveryVerificationResult> createVerifiedCheckpoint() async {
    throw UnsupportedError('Disaster recovery checkpoints are not supported on Web.');
  }

  Future<DisasterRecoveryVerificationResult> verifyLatestBackup() async {
    throw UnsupportedError('Local backup verification is not supported on Web.');
  }
}
