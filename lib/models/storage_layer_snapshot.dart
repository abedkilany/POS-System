class StorageLayerSnapshot {
  const StorageLayerSnapshot({
    required this.sqliteAuthoritative,
    required this.productCacheCount,
    required this.salesCacheCount,
    required this.supplierCacheCount,
    required this.derivedCacheCount,
    required this.syncChangeCount,
    required this.syncQueueCount,
  });

  final bool sqliteAuthoritative;
  final int productCacheCount;
  final int salesCacheCount;
  final int supplierCacheCount;
  final int derivedCacheCount;
  final int syncChangeCount;
  final int syncQueueCount;

  String toLogLine() =>
      'sqliteAuthoritative=$sqliteAuthoritative products=$productCacheCount sales=$salesCacheCount '
      'suppliers=$supplierCacheCount derivedCaches=$derivedCacheCount syncChanges=$syncChangeCount '
      'syncQueue=$syncQueueCount';
}
