import 'dart:convert';

import 'package:drift/drift.dart';

import '../../accounting/accounting_account_role.dart';
import '../../security/audit_integrity.dart';
import '../../security/audit_insert_guard.dart';
import 'sqlite_database_connection.dart';

part 'ventio_drift_database_methods_01.dart';
part 'ventio_drift_database_methods_02.dart';
part 'ventio_drift_database_methods_03.dart';
part 'ventio_drift_database_methods_04.dart';
part 'ventio_drift_database_methods_05.dart';
part 'ventio_drift_database_methods_06.dart';
part 'ventio_drift_database_methods_07.dart';
part 'ventio_drift_database_methods_08.dart';

/// Drift-backed SQLite foundation for Ventio.
///
/// Phase 3 keeps SQLite as the authoritative local store. legacy JSON storage is retained only
/// as a one-time safety backup source for devices upgrading from older builds.
/// The tables below track migration progress, sync state, and the app key/value
/// data that previously lived in legacy JSON storage.
class VentioDriftDatabase extends GeneratedDatabase {
  VentioDriftDatabase([QueryExecutor? executor])
      : super(executor ?? openVentioSqliteConnection());

  @override
  int get schemaVersion => 35;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => _applyFoundationSchema(),
        onUpgrade: (migrator, from, to) => _applyFoundationSchema(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA journal_mode = WAL;');
          // Phase 7 production durability: financial/stock commits must be
          // durable across abrupt process or power loss, not merely atomic
          // while the process remains alive. WAL + FULL is intentionally
          // stricter than the previous NORMAL setting.
          await customStatement('PRAGMA synchronous = FULL;');
          await customStatement('PRAGMA busy_timeout = 5000;');
        },
      );

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      const <DatabaseSchemaEntity>[];

  Future<void> initializeFoundation() async {
    await _applyFoundationSchema();
  }
}
