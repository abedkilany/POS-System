class UnifiedCloudSnapshotRetryResult<T> {
  const UnifiedCloudSnapshotRetryResult({
    this.value,
    this.lastFailure,
    required this.completed,
  });

  final T? value;
  final Object? lastFailure;
  final bool completed;
}

class UnifiedCloudSnapshotRetryFlow {
  const UnifiedCloudSnapshotRetryFlow._();

  static Future<UnifiedCloudSnapshotRetryResult<T>> pollUntilReady<T>({
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
        return UnifiedCloudSnapshotRetryResult<T>(
          value: value,
          completed: true,
        );
      } catch (error) {
        lastFailure = error;
      }
    }
    return UnifiedCloudSnapshotRetryResult<T>(
      lastFailure: lastFailure,
      completed: false,
    );
  }
}
