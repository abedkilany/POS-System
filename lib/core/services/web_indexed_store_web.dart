import 'package:idb_shim/idb.dart' as idb;
import 'package:idb_shim/idb_browser.dart' as idb_browser;

class WebIndexedStore {
  static const _databaseName = 'ventio_local_v1';
  static const _storeName = 'key_value';

  late idb.Database _database;

  Future<void> open() async {
    final factory = idb_browser.getIdbFactory();
    if (factory == null) {
      throw StateError('IndexedDB is not available in this browser.');
    }
    _database = await factory.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        final database = event.database;
        if (!database.objectStoreNames.contains(_storeName)) {
          database.createObjectStore(_storeName, keyPath: 'key');
        }
      },
    );
  }

  Future<Map<String, String>> readAll() async {
    final transaction = _database.transaction(
      _storeName,
      idb.idbModeReadOnly,
    );
    final records = await transaction.objectStore(_storeName).getAll();
    await transaction.completed;
    final result = <String, String>{};
    for (final record in records) {
      if (record is Map) {
        final key = record['key'];
        final value = record['value'];
        if (key != null && value is String) {
          result[key.toString()] = value;
        }
      }
    }
    return result;
  }

  Future<void> put(String key, String value) async {
    final transaction = _database.transaction(
      _storeName,
      idb.idbModeReadWrite,
    );
    await transaction.objectStore(_storeName).put(<String, String>{
      'key': key,
      'value': value,
    });
    await transaction.completed;
  }

  Future<void> delete(String key) async {
    final transaction = _database.transaction(
      _storeName,
      idb.idbModeReadWrite,
    );
    await transaction.objectStore(_storeName).delete(key);
    await transaction.completed;
  }
}
