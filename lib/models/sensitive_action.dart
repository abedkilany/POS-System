class SensitiveAction {
  SensitiveAction._();

  static const String backupRestore = 'backup.restore';
  static const String usersManage = 'security.users.manage';
  static const String rolesManage = 'security.roles.manage';
  static const String saleReverse = 'sales.reverse';
  static const String purchaseReverse = 'purchases.reverse';
  static const String databaseDestructive = 'database.destructive';
  static const String storeOwnerCredentials =
      'security.store_owner.credentials';
}

class SensitiveActionAuthRequiredException implements Exception {
  const SensitiveActionAuthRequiredException(this.action);

  final String action;

  @override
  String toString() =>
      'Re-authentication is required before sensitive action: $action';
}
