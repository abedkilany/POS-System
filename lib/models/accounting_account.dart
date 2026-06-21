class AccountingAccount {
  const AccountingAccount({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.normalBalance,
    this.subtype = '',
    this.parentId = '',
    this.currency = 'USD',
    this.isSystem = false,
    this.isActive = true,
    this.description = '',
  });

  final String id;
  final String code;
  final String name;
  final String type;
  final String subtype;
  final String parentId;
  final String normalBalance;
  final String currency;
  final bool isSystem;
  final bool isActive;
  final String description;

  factory AccountingAccount.fromRow(Map<String, Object?> row) {
    return AccountingAccount(
      id: row['id']?.toString() ?? '',
      code: row['code']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      type: row['type']?.toString() ?? '',
      subtype: row['subtype']?.toString() ?? '',
      parentId: row['parent_id']?.toString() ?? '',
      normalBalance: row['normal_balance']?.toString() ?? '',
      currency: row['currency']?.toString() ?? 'USD',
      isSystem: row['is_system'] == 1,
      isActive: row['is_active'] != 0,
      description: row['description']?.toString() ?? '',
    );
  }
}
