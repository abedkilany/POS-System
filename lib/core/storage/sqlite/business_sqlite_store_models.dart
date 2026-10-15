class BusinessSqliteValidationResult {
  const BusinessSqliteValidationResult(
      {required this.ok, required this.message});
  final bool ok;
  final String message;
}

class BusinessQueryPage<T> {
  const BusinessQueryPage(
      {required this.items,
      required this.totalCount,
      required this.limit,
      required this.offset});
  final List<T> items;
  final int totalCount;
  final int limit;
  final int offset;
  bool get hasMore => offset + items.length < totalCount;
}
