class UnifiedDirectSnapshotRetryResult<T> {
  const UnifiedDirectSnapshotRetryResult({
    this.value,
    this.lastFailure,
    required this.completed,
  });

  final T? value;
  final Object? lastFailure;
  final bool completed;
}

class UnifiedDirectSnapshotRetryFlow {
  const UnifiedDirectSnapshotRetryFlow._();

  static Future<UnifiedDirectSnapshotRetryResult<T>> pollUntilReady<T>({
    required int maxAttempts,
    required Duration retryDelay,
    Future<void> Function(int attempt)? beforeAttempt,
    required Future<T> Function(int attempt) attempt,
  }) async {
    Object? lastFailure;
    for (var index = 0; index < maxAttempts; index += 1) {
      if (index > 0) {
        await Future<void>.delayed(retryDelay);
      }
      await beforeAttempt?.call(index);
      try {
        final value = await attempt(index);
        return UnifiedDirectSnapshotRetryResult<T>(
          value: value,
          completed: true,
        );
      } catch (error) {
        lastFailure = error;
      }
    }
    return UnifiedDirectSnapshotRetryResult<T>(
      lastFailure: lastFailure,
      completed: false,
    );
  }
}
