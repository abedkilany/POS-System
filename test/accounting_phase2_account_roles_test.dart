import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/accounting/accounting_account_role.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/storage/sqlite/sqlite_migration_manager.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

Future<VentioDriftDatabase> _db() async {
  final db = VentioDriftDatabase(NativeDatabase.memory());
  await db.initializeFoundation();
  SqliteMigrationManager.useDatabaseForTesting(db);
  return db;
}

void main() {
  late VentioDriftDatabase db;

  setUp(() async {
    db = await _db();
  });

  tearDown(() async {
    await SqliteMigrationManager.resetForTesting();
  });

  test('Phase 2 seeds every semantic account role idempotently', () async {
    await db.initializeFoundation();
    final roles = await AccountingService.readAccountRoleMap();

    expect(roles.length, AccountingAccountRole.all.length);
    for (final role in AccountingAccountRole.all) {
      expect(roles[role.settingKey], isNotNull,
          reason: 'Missing ${role.settingKey}');
      expect(await AccountingService.resolveAccountRole(role.key), isNotEmpty);
    }
    expect(await AccountingService.validateAccountRoleConfiguration(), isEmpty);
  });

  test('one-to-one role update stays synchronized with legacy default',
      () async {
    final custom = await AccountingService.createAccount(
      code: '4190',
      name: 'مبيعات فرع الاختبار',
      type: 'revenue',
      normalBalance: 'credit',
      parentId: 'acc_revenue',
    );

    await AccountingService.updateAccountRole(
      roleKey: 'sales_revenue',
      accountId: custom.id,
    );

    final roles = await AccountingService.readAccountRoleMap();
    final defaults = await AccountingService.readDefaultAccountMap();
    expect(roles['role_sales_revenue_account_id'], custom.id);
    expect(defaults['default_sales_account_id'], custom.id);
  });

  test('legacy default update also keeps its Phase 2 role synchronized',
      () async {
    final custom = await AccountingService.createAccount(
      code: '5190',
      name: 'تكلفة مبيعات اختبار',
      type: 'cost_of_sales',
      normalBalance: 'debit',
      parentId: 'acc_cost_of_sales',
    );

    await AccountingService.updateDefaultAccount(
      key: 'default_cogs_account_id',
      accountId: custom.id,
    );

    final roles = await AccountingService.readAccountRoleMap();
    expect(roles['role_cogs_account_id'], custom.id);
  });

  test('specialized roles do not silently rewrite legacy shared settings',
      () async {
    final before = await AccountingService.readDefaultAccountMap();
    final legacyWasteBefore = before['default_waste_account_id'] ?? '';

    await AccountingService.updateAccountRole(
      roleKey: 'inventory_count_loss',
      accountId: 'acc_inventory_count_loss',
    );

    final after = await AccountingService.readDefaultAccountMap();
    expect(after['default_waste_account_id'] ?? '', legacyWasteBefore);
    expect(
      await AccountingService.resolveAccountRole('inventory_count_loss'),
      'acc_inventory_count_loss',
    );
  });

  test('role mapping rejects non-postable grouping accounts', () async {
    await expectLater(
      AccountingService.updateAccountRole(
        roleKey: 'inventory_count_loss',
        accountId: 'acc_inventory_variances',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
