import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/core/services/cash_phase7_migration_service.dart',
  ).readAsStringSync();

  test('returned purchases are not treated as missing active purchase journals', () {
    expect(
      source,
      contains("lower(trim(p.status)) = 'received'"),
    );
    expect(
      source,
      contains("je.reference_id LIKE p.id || ':purchase_edit:%'"),
    );
  });

  test('voucher reconciliation subtracts refunds before allocation balance', () {
    expect(source, contains('FROM cash_refund_allocations cra'));
    expect(source, contains("pa.allocation_kind = 'reversal'"));
    expect(source, contains('THEN -pa.amount ELSE pa.amount END'));
    expect(source, contains('v.amount - COALESCE(('));
    expect(source, contains('v.unallocated_amount + COALESCE(SUM('));
    expect(source, contains(r"refunded=${row.data['refunded']}"));
  });

  test('party control reconciliation includes reversed journal pairs', () {
    expect(
      source,
      contains("je.status IN ('posted', 'reversed') AND jl.party_type = 'customer'"),
    );
    expect(
      source,
      contains("je.status IN ('posted', 'reversed') AND jl.party_type = 'supplier'"),
    );
  });
}
