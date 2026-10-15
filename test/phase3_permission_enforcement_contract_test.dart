import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/accounting_service.dart';
import 'package:ventio/core/services/cash_operation_service.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/user_role.dart';
import 'support/test_business_session_context.dart';
import 'helpers/accounting_page_source.dart';
import 'helpers/settings_page_source.dart';
import 'helpers/sales_page_source.dart';
import 'helpers/dart_library_source.dart';

String _source(String path) => readDartLibrarySource(path);

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
        contains(
            'requirePermission(AppPermission.inventoryCorrectionsManage);'),
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

    test('high-risk sync actions have internal guards', () {
      final identity = _source('lib/data/app_store_identity_users.dart');

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
      final settings = readSettingsPageImplementationSource();
      expect(
        settings,
        contains(
          'widget.store.security.requirePermission(AppPermission.syncManage);',
        ),
      );
    });

    test('derived manage flags do not grant unrelated permissions', () {
      final security = _source('lib/data/app_store_domains.dart');
      final normalizedSecurity = security.replaceAll(RegExp(r'\s+'), ' ');

      expect(
        normalizedSecurity,
        contains(
          'bool get canManagePurchases => hasPermission(AppPermission.purchasesManage);',
        ),
      );
      final inventoryStart =
          security.lastIndexOf('bool get canManageInventory =>');
      final inventoryEnd =
          security.indexOf('bool get canViewReports', inventoryStart);
      expect(inventoryStart, greaterThanOrEqualTo(0));
      expect(inventoryEnd, greaterThan(inventoryStart));
      final inventoryBlock = security.substring(inventoryStart, inventoryEnd);
      expect(inventoryBlock, isNot(contains('inventoryMovementsView')));
    });

    test('direct accounting and cash mutation UIs enforce permissions', () {
      final accounting = readAccountingPageImplementationSource();
      final cash = _source('lib/features/cash/cash_page.dart');
      final sales = readSalesPageImplementationSource();

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

    test('cash mutation services reject direct calls without cash permission',
        () async {
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
