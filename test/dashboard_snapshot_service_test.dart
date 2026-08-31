import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/features/dashboard/dashboard_snapshot_service.dart';

void main() {
  group('DashboardSnapshotService', () {
    test(
        'computes sales totals from line items when computed fields are absent',
        () {
      final reference = DateTime(2026, 6, 30, 10);
      final summary = DashboardSnapshotService.computeSnapshotForTesting(
        <String, Object?>{
          'reference': reference.toIso8601String(),
          'productsJson': '[]',
          'salesJson': jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': 's1',
              'invoiceNo': 'INV-1',
              'customerName': 'Alice',
              'date': DateTime(2026, 6, 29, 12).toIso8601String(),
              'status': 'Paid',
              'discount': 5,
              'items': <Map<String, Object?>>[
                <String, Object?>{
                  'productId': 'p1',
                  'productName': 'Coffee',
                  'unitPrice': 10,
                  'quantity': 2,
                  'unitCost': 4,
                },
              ],
            },
          ]),
          'purchasesJson': '[]',
          'expensesJson': '[]',
          'stockMovementsJson': '[]',
          'accountTransactionsJson': '[]',
          'syncQueueJson': '[]',
        },
      );

      final salesLast7Days = summary['salesLast7Days'] as List<dynamic>;
      final june29 = salesLast7Days.cast<Map>().firstWhere(
            (item) => item['label'] == '06/29',
          );
      final topCustomers = summary['topCustomers'] as List<dynamic>;
      final recentOperations = summary['recentOperations'] as List<dynamic>;

      expect(summary['salesSince30Days'], 15);
      expect(summary['profitSince30Days'], 7);
      expect(june29['value'], 15);
      expect((topCustomers.first as Map)['value'], 15);
      expect((recentOperations.first as Map)['amount'], 15);
    });
  });
}
