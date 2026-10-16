class AppStoreActionException implements Exception {
  const AppStoreActionException(this.message);

  final String message;

  @override
  String toString() => message;
}
