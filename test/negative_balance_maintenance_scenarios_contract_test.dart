import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final stressLab = File('lib/features/dev_tools/stress_lab_page.dart');

  test('maintenance scenario lab covers negative stock and cash policies', () {
    final source = stressLab.readAsStringSync();
    final start = source.indexOf(
      'Future<void> _runNegativeBalancePolicyMaintenanceScenarios(',
    );
    final end = source.indexOf(
      'Future<String> _resolveNegativePolicyCounterpartAccount()',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);

    for (final token in const <String>[
      'صيانة التطبيق',
      'المخزون السالب OFF — منع البيع',
      'المخزون السالب ON — إنشاء Deficit',
      'تسوية Deficit وتصحيح COGS',
      'الرصيد النقدي السالب OFF — منع السحب',
      'الرصيد النقدي السالب ON — السماح والاستعادة',
      'Reversal نقدي OFF — منع التحول للسالب',
      'Reversal نقدي ON — السماح بالسالب',
      'allowNegativeStock: false',
      'allowNegativeStock: true',
      'allowNegativeCashBalance: false',
      'allowNegativeCashBalance: true',
      "reference_type = 'inventory_deficit_cost_reconciliation'",
      'negativeBatches=0',
      'saleTotalUnchanged',
    ]) {
      expect(body, contains(token), reason: token);
    }
  });

  test('comprehensive scenario run wires maintenance negative-balance suite', () {
    final source = stressLab.readAsStringSync();
    expect(
      source,
      contains(
        'await _runNegativeBalancePolicyMaintenanceScenarios(actor: actor);',
      ),
    );
    expect(source, contains("import '../../core/services/payment_voucher_service.dart';"));
  });
}
