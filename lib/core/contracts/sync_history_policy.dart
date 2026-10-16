/// Shared defaults for retaining acknowledged synchronization history.
abstract final class SyncHistoryPolicy {
  static const int keepRecentChanges = 200;
  static const int minChangesBeforeCompact = 1000;
}
