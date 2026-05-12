import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/store_profile.dart';

void main() {
  group('Backup validation contract', () {
    Map<String, dynamic> validBackup({
      List<dynamic> products = const [],
      List<dynamic> customers = const [],
      List<dynamic> sales = const [],
      List<dynamic> suppliers = const [],
      List<dynamic> expenses = const [],
      String storeName = 'QA Store',
    }) {
      return <String, dynamic>{
        'version': 11,
        'generatedAt': DateTime(2026, 1, 2, 3, 4, 5).toIso8601String(),
        'storeProfile': StoreProfile.defaults.copyWith(name: storeName).toJson(),
        'products': products,
        'customers': customers,
        'sales': sales,
        'suppliers': suppliers,
        'expenses': expenses,
        'purchases': const [],
        'stockMovements': const [],
        'categories': const [],
        'brands': const [],
        'units': const [],
        'roles': const [],
        'users': const [],
        'syncChanges': const [],
        'syncQueue': const [],
      };
    }

    test('accepts a structurally complete backup and reports counts', () {
      final result = AppStore().validateBackupJson(jsonEncode(validBackup(
        products: const [<String, Object?>{'id': 'p1'}],
        customers: const [<String, Object?>{'id': 'c1'}, <String, Object?>{'id': 'c2'}],
        sales: const [<String, Object?>{'id': 's1'}],
        suppliers: const [<String, Object?>{'id': 'sup1'}],
        expenses: const [<String, Object?>{'id': 'e1'}],
      )));

      expect(result.isValid, isTrue);
      expect(result.errorMessage, isNull);
      expect(result.summary?.version, 11);
      expect(result.summary?.productsCount, 1);
      expect(result.summary?.customersCount, 2);
      expect(result.summary?.salesCount, 1);
      expect(result.summary?.suppliersCount, 1);
      expect(result.summary?.expensesCount, 1);
      expect(result.summary?.storeName, 'QA Store');
      expect(result.summary?.generatedAt, DateTime(2026, 1, 2, 3, 4, 5));
    });

    test('rejects non-object, malformed, and incomplete backups safely', () {
      final store = AppStore();

      expect(store.validateBackupJson('[]').isValid, isFalse);
      expect(store.validateBackupJson('{not-json').isValid, isFalse);

      final incomplete = store.validateBackupJson(jsonEncode(<String, dynamic>{'products': const []}));
      expect(incomplete.isValid, isFalse);
      expect(incomplete.errorMessage, contains('Missing required backup sections'));
    });

    test('uses a safe default store name when profile name is absent', () {
      final backup = validBackup(storeName: '')..['storeProfile'] = <String, Object?>{};
      final result = AppStore().validateBackupJson(jsonEncode(backup));

      expect(result.isValid, isTrue);
      expect(result.summary?.storeName, 'My Store');
    });
  });
}
