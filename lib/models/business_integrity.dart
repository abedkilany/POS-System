class DataConflict {
  const DataConflict({
    required this.entityType,
    required this.keyName,
    required this.keyValue,
    required this.recordIds,
    this.blocking = false,
    this.message = '',
  });

  final String entityType;
  final String keyName;
  final String keyValue;
  final List<String> recordIds;
  final bool blocking;
  final String message;

  String get title => '$entityType duplicate $keyName: $keyValue';
}

class BusinessDataIntegrityResult {
  const BusinessDataIntegrityResult({
    required this.ok,
    required this.message,
    this.problemCount = 0,
  });
  final bool ok;
  final String message;
  final int problemCount;
}

class BusinessDataIntegrityRepairResult {
  const BusinessDataIntegrityRepairResult({
    required this.reactivatedProducts,
    required this.archivedProductsCreated,
    required this.unresolvedProductIds,
  });

  final int reactivatedProducts;
  final int archivedProductsCreated;
  final List<String> unresolvedProductIds;

  bool get changed => reactivatedProducts > 0 || archivedProductsCreated > 0;
}
