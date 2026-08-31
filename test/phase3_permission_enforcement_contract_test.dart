import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/cash_operation_service.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/user_role.dart';
import 'support/test_business_session_context.dart';
import 'helpers/app_store_source.dart';

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('Phase 3 permission enforcement contracts', () {
    test('inventory mutations use inventory permissions, not product edit', () {
      final inventory = _source('lib/data/app_store_inventory.dart');
      final manufacturing = _source('lib/data/app_store_manufacturing.dart');

      expect(inventory, isNot(contains('requireProductsEdit')));
      expect(
        inventory,
        contains('requirePermission(AppPermission.inventoryCountsManage);'),
      );
      expect(
        inventory,
        contains('requirePermission(AppPermission.inventoryCorrectionsManage);'),
      );
      expect(
        manufacturing,
        contains(
          'requirePermission(AppPermission.inventoryManufacturingManage);',
        ),
      );
      expect(
        manufacturing,
        isNot(contains('requirePermission(AppPermission.productsEdit);')),
      );
    });

    test('purchase lifecycle separates manage and cancel permissions', () {
      final purchases = _source('lib/data/app_store_purchases.dart');

      expect(
        purchases,
        contains('requirePermission(AppPermission.purchasesManage);'),
      );
      expect(
        purchases,
        contains('requirePermission(AppPermission.purchasesCancel);'),
      );
      expect(
        purchases,
        isNot(contains('requirePermission(AppPermission.suppliersManage);')),
      );
    });

    test('supplier money operations require payment permission', () {
      final cash = _source('lib/data/app_store_warehouse_cash.dart');

      expect(
        cash,
        contains('requirePermission(AppPermission.suppliersPaymentManage);'),
      );
    });

    test('quotations and delivery notes use their dedicated permissions', () {
      final sales = _source('lib/data/app_store_sales_returns.dart');

      expect(
        sales,
        contains('requirePermission(AppPermission.quotationsManage);'),
      );
      expect(
        sales,
        contains('AppPermission.deliveryNotesManage'),
      );
    });

    test('high-risk sync and developer actions have internal guards', () {
      final identity = _source('lib/data/app_store_identity_users.dart');
      final access = _source('lib/data/app_store_access_auth.dart');

      expect(
        identity,
        contains(
          'Future<void> setActiveSyncTransport(String transport) async {\n'
          '    requirePermission(AppPermission.syncManage);',
        ),
      );
      expect(
        identity,
        contains(
          "Future<void> requestHostTransfer({String reason = ''}) async {\n"
          '    requirePermission(AppPermission.syncManage);',
        ),
      );
      expect(
        identity,
        contains(
          'Future<void> activateApprovedHostTransfer() async {\n'
          '    requirePermission(AppPermission.syncManage);',
        ),
      );
      expect(
        access,
        contains(
          'Future<void> setStressLabEnabled(bool enabled) async {\n'
          '    requirePermission(AppPermission.maintenanceManage);',
        ),
      );
      final settings = _source('lib/features/settings/settings_page.dart');
      expect(
        settings,
        contains('widget.store.requirePermission(AppPermission.syncManage);'),
      );
    });

    test('derived manage flags do not grant unrelated permissions', () {
      final store = readAppStoreImplementationSource();

      expect(
        store,
        contains(
          'bool get canManagePurchases =>\n'
          '      hasPermission(AppPermission.purchasesManage);',
        ),
      );
      final inventoryStart = store.indexOf('bool get canManageInventory =>');
      final inventoryEnd = store.indexOf('bool get canViewReports', inventoryStart);
      expect(inventoryStart, greaterThanOrEqualTo(0));
      expect(inventoryEnd, greaterThan(inventoryStart));
      final inventoryBlock = store.substring(inventoryStart, inventoryEnd);
      expect(inventoryBlock, isNot(contains('inventoryMovementsView')));
    });

    test('direct accounting and cash mutation UIs enforce permissions', () {
      final accounting = _source('lib/features/accounting/accounting_page.dart');
      final cash = _source('lib/features/cash/cash_page.dart');
      final sales = _source('lib/features/sales/sales_page.dart');

      expect(
        accounting,
        contains('requirePermission(AppPermission.accountingManage);'),
      );
      expect(
        cash,
        contains('requirePermission(AppPermission.cashBoxManage);'),
      );
      expect(
        sales,
        contains('requirePermission(AppPermission.cashBoxManage);'),
      );
    });



    test('cash mutation services reject direct calls without cash permission', () async {
      final denied = TestBusinessSessionContext(permissions: <String>{});
      final db = VentioDriftDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await expectLater(
        CashOperationService(db, authorization: denied).withdrawal(
          cashLocationId: 'blocked-location',
          counterpartAccountId: 'blocked-account',
          amount: 1,
        ),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        AccountingService.openCashDrawer(
          authorization: denied,
          drawerNo: 'Blocked drawer',
          openingBalance: 0,
        ),
        throwsA(isA<StateError>()),
      );

      expect(denied.hasPermission(AppPermission.cashBoxManage), isFalse);
    });

    test('sale warehouse preference is a protected setting', () {
      final core = _source('lib/data/app_store_core_loading.dart');
      expect(
        core,
        contains(
          'Future<void> setSaleWarehouseId(String warehouseId) async {\n'
          '    requirePermission(AppPermission.settingsManage);',
        ),
      );
    });
  });
}
