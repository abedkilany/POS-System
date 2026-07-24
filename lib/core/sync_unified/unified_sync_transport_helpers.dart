import 'sync_contracts.dart';
import 'sync_transport_adapter.dart';

/// Shared transport-facing helpers for the unified sync layer.
///
/// This file is intentionally narrow. It holds logic that should behave the
/// same for LAN and Cloud, while leaving the actual network transport details
/// inside their adapters.
class UnifiedSyncTransportHelpers {
  const UnifiedSyncTransportHelpers._();

  static Future<UnifiedSyncResult?> hostSyncBypassResult({
    required bool isHost,
    required String label,
    required Future<void> Function()? ensureHostReady,
    void Function(double value, String label)? onProgress,
  }) async {
    if (!isHost) return null;
    try {
      await ensureHostReady?.call();
    } catch (_) {
      // Host readiness is best-effort here. Any actual host startup failure is
      // still reported by the dedicated setup/status actions.
    }
    onProgress?.call(1.0, '$label Host is ready.');
    return UnifiedSyncResult(
      ok: true,
      message: '$label Host ready.',
    );
  }

  static UnifiedSyncError classifyError(bool ok, String message) {
    if (ok) return UnifiedSyncError.none;
    final lower = message.toLowerCase();
    final code = lower.contains('socketexception') ||
            lower.contains('timeoutexception') ||
            lower.contains('connection refused') ||
            lower.contains('failed host lookup') ||
            lower.contains('network is unreachable') ||
            lower.contains('no route to host') ||
            lower.contains('connection reset by peer') ||
            lower.contains('broken pipe') ||
            lower.contains('econnrefused') ||
            lower.contains('connection closed') ||
            lower.contains('host offline')
        ? UnifiedSyncErrorCode.networkUnavailable
        : lower.contains('expired') || lower.contains('already used')
            ? UnifiedSyncErrorCode.expiredPairingCode
            : lower.contains('snapshot')
                ? UnifiedSyncErrorCode.snapshotUnavailable
                : lower.contains('unauthorized') || lower.contains('401')
                    ? UnifiedSyncErrorCode.unauthorized
                    : lower.contains('forbidden') || lower.contains('cannot')
                        ? UnifiedSyncErrorCode.forbiddenRole
                        : lower.contains('conflict') || lower.contains('409')
                            ? UnifiedSyncErrorCode.conflict
                            : lower.contains('server error') ||
                                    lower.contains('500') ||
                                    lower.contains('502') ||
                                    lower.contains('503') ||
                                    lower.contains('504')
                                ? UnifiedSyncErrorCode.serverError
                                : lower.contains('required') ||
                                        lower.contains('invalid')
                                    ? UnifiedSyncErrorCode.validationFailed
                                    : lower.contains('not supported') ||
                                            lower.contains('unsupported') ||
                                            lower.contains(
                                                'handled by the existing')
                                        ? UnifiedSyncErrorCode.unsupported
                                        : UnifiedSyncErrorCode.unknown;
    return UnifiedSyncError(
      code: code,
      userMessage: message,
      debugMessage: message,
    );
  }
}
