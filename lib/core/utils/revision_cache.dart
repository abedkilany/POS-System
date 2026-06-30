class RevisionValueCache<T> {
  int? _revision;
  T? _value;
  bool _hasValue = false;

  T getOrCompute(int revision, T Function() compute) {
    if (_hasValue && _revision == revision) {
      return _value as T;
    }
    final value = compute();
    _revision = revision;
    _value = value;
    _hasValue = true;
    return value;
  }

  void invalidate() {
    _revision = null;
    _value = null;
    _hasValue = false;
  }
}

class RevisionKeyCache<T> {
  int? _revision;
  Object? _key;
  T? _value;
  bool _hasValue = false;

  T getOrCompute(int revision, Object key, T Function() compute) {
    if (_hasValue && _revision == revision && _key == key) {
      return _value as T;
    }
    final value = compute();
    _revision = revision;
    _key = key;
    _value = value;
    _hasValue = true;
    return value;
  }

  void invalidate() {
    _revision = null;
    _key = null;
    _value = null;
    _hasValue = false;
  }
}
