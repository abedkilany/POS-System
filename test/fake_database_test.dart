import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_local_database.dart';

void main() {
  group('FakeLocalDatabase contract', () {
    test('starts empty and records writes', () async {
      final db = FakeLocalDatabase();

      expect(db.isEmpty, isTrue);
      await db.setString('products_v4', '[{"id":"p1"}]');

      expect(db.isEmpty, isFalse);
      expect(db.getString('products_v4'), '[{"id":"p1"}]');
      expect(db.writes, contains('products_v4'));
    });

    test('can be seeded for repository and store tests', () {
      final db = FakeLocalDatabase({'store_profile_v5': '{"name":"Test Store"}'});

      expect(db.containsKey('store_profile_v5'), isTrue);
      expect(db.snapshot, containsPair('store_profile_v5', '{"name":"Test Store"}'));
    });

    test('records deletes and removes values', () async {
      final db = FakeLocalDatabase({'cloud_last_pull_cursor': '2026-01-01T00:00:00Z'});

      await db.deleteString('cloud_last_pull_cursor');

      expect(db.containsKey('cloud_last_pull_cursor'), isFalse);
      expect(db.deletes, ['cloud_last_pull_cursor']);
    });

    test('simulates offline storage failures', () async {
      final db = FakeLocalDatabase()..online = false;

      expect(() => db.setString('k', 'v'), throwsA(isA<StateError>()));
      expect(() => db.deleteString('k'), throwsA(isA<StateError>()));
    });
  });
}
