import '../../models/sync_change.dart';
import '../../models/sync_queue_item.dart';

/// Session-local cache state. SQLite remains authoritative.
class SyncState {
  final List<SyncChange> syncChanges = [];
  final List<SyncQueueItem> syncQueue = [];
  final List<SyncChange> sqliteDirtySyncChanges = [];
  final List<SyncQueueItem> sqliteDirtySyncQueue = [];
  final Map<String, Map<String, Map<String, dynamic>>> sqliteDirtyBusinessRows =
      <String, Map<String, Map<String, dynamic>>>{};
  int syncSequence = 0;
}
