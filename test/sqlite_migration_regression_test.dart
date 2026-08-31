import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';

Future<File> _createLegacyDatabaseFile() async {
  final directory = Directory(
      p.join(Directory.systemTemp.path, 'ventio_sqlite_migration_test'));
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, 'legacy.sqlite'));
  if (await file.exists()) {
    await file.delete();
  }

  final sqlite = sqlite3.open(file.path);
  sqlite.execute('''
    CREATE TABLE products (
      id TEXT PRIMARY KEY NOT NULL,
      entity_type TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT NOT NULL DEFAULT '',
      device_id TEXT NOT NULL DEFAULT '',
      sync_status TEXT NOT NULL DEFAULT '',
      store_id TEXT NOT NULL DEFAULT '',
      branch_id TEXT NOT NULL DEFAULT '',
      version INTEGER NOT NULL DEFAULT 1,
      last_modified_by_device_id TEXT NOT NULL DEFAULT '',
      sort_index INTEGER NOT NULL DEFAULT 0
    );
  ''');
  sqlite.close();

  return file;
}

void main() {
  test(
      'initializeFoundation repairs legacy products tables missing track_stock',
      () async {
    final file = await _createLegacyDatabaseFile();
    final db = VentioDriftDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
    });

    await expectLater(db.initializeFoundation(), completes);

    final columns = await db.customSelect('PRAGMA table_info(products);').get();
    expect(
      columns.any((row) => row.read<String>('name') == 'track_stock'),
      isTrue,
    );
  });

  test('schema 25 removes the retired products.stock column', () async {
    final db = VentioDriftDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initializeFoundation();
    await db.customStatement(
      'ALTER TABLE products ADD COLUMN stock REAL NOT NULL DEFAULT 0',
    );
    await db.customStatement(
      'CREATE INDEX idx_products_deleted_track_stock_stock_name '
      'ON products(deleted_at, track_stock, stock, lower(name))',
    );

    await db.dropLegacyProductStockColumn();

    final columns = await db.customSelect('PRAGMA table_info(products);').get();
    expect(
      columns.any((row) => row.read<String>('name') == 'stock'),
      isFalse,
    );
  });

}
