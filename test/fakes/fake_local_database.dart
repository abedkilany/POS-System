class FakeLocalDatabase {
  FakeLocalDatabase([Map<String, String>? seed]) : _data = Map<String, String>.from(seed ?? const {});

  final Map<String, String> _data;
  final List<String> writes = <String>[];
  final List<String> deletes = <String>[];
  bool online = true;

  bool get isEmpty => _data.isEmpty;
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_data);

  String? getString(String key) => _data[key];

  Future<void> setString(String key, String value) async {
    _ensureOnline();
    _data[key] = value;
    writes.add(key);
  }

  bool containsKey(String key) => _data.containsKey(key);

  Future<void> deleteString(String key) async {
    _ensureOnline();
    _data.remove(key);
    deletes.add(key);
  }

  void _ensureOnline() {
    if (!online) throw StateError('Fake database is offline.');
  }
}
