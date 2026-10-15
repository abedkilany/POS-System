part of 'ventio_drift_database.dart';

extension VentioDriftDatabaseMethods6 on VentioDriftDatabase {
  Future<void> _addColumnIfMissing(
      String table, String column, String definition) async {
    try {
      await customStatement(
          'ALTER TABLE $table ADD COLUMN $column $definition');
    } catch (_) {
      // Column already exists on upgraded local databases.
    }
  }
}
