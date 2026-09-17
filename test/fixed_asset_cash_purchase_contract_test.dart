import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = File('lib/core/services/accounting_service.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final page = File('lib/features/accounting/accounting_page.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('cash fixed-asset purchase is atomic with the asset transaction', () {
    final start = service.indexOf('static Future<void> createFixedAsset({');
    final end = service.indexOf(
      'static Future<int> runDepreciationForAsset(',
      start,
    );
    final body = service.substring(start, end);

    expect(body, contains('bool paidFromCashDrawer = false'));
    expect(body, contains('await _db.transaction(() async {'));
    expect(body, contains('_openCashDrawerLocationForDevice('));
    expect(body, contains('ensureCashOutflowAllowed('));
    expect(body, contains("INSERT INTO fixed_assets"));
    expect(body, contains("'cash_withdrawal'"));
    expect(body, contains('INSERT INTO cash_operations'));
    expect(body, contains('ledger.appendInExistingTransaction'));
    expect(body, contains("referenceType: 'fixed_asset'"));
    expect(body, contains('applyCashLocationDelta('));
    expect(body, contains('delta: -_roundMoney(amount)'));
    expect(body, contains('calculateCashDrawerExpectedCash('));
    expect(body, contains('UPDATE cash_drawer_sessions'));
  });

  test('fixed-asset dialog defaults to real cash drawer payment', () {
    final start = page.indexOf('Future<void> _createFixedAssetDialog() async {');
    final end = page.indexOf(
      'Future<void> _createPaymentAccountDialog() async {',
      start,
    );
    final body = page.substring(start, end);

    expect(body, contains("var paymentMode = 'cash_drawer'"));
    expect(body, contains("a.subtype.startsWith('fixed_')"));
    expect(body, contains('AppPermission.cashBoxManage'));
    expect(body, contains('paidFromCashDrawer: paidFromCashDrawer'));
    expect(body, contains('deviceId: widget.store.appIdentity.deviceId'));
    expect(body, contains('storeId: widget.store.appIdentity.storeId'));
    expect(body, contains('branchId: widget.store.appIdentity.branchId'));
  });
}
