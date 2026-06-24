import '../../models/store_profile.dart';

/// Immutable money value stored as minor units to avoid binary floating-point
/// drift in accounting code. Existing UI code can still pass doubles at the
/// boundary, but new ledger/storage code should prefer this type.
class MoneyValue {
  const MoneyValue({
    required this.currency,
    required this.minorUnits,
    required this.decimalPlaces,
  });

  final String currency;
  final int minorUnits;
  final int decimalPlaces;

  static int _scale(int decimalPlaces) {
    var scale = 1;
    for (var i = 0; i < decimalPlaces.clamp(0, 6); i += 1) {
      scale *= 10;
    }
    return scale;
  }

  factory MoneyValue.fromDouble(
    double amount, {
    required String currency,
    required StoreProfile profile,
  }) {
    final definition = profile.currencyByCode(currency);
    final scale = _scale(definition.decimalPlaces);
    return MoneyValue(
      currency: definition.code,
      minorUnits: (amount * scale).round(),
      decimalPlaces: definition.decimalPlaces,
    );
  }

  factory MoneyValue.fromMinorUnits(
    int minorUnits, {
    required String currency,
    required StoreProfile profile,
  }) {
    final definition = profile.currencyByCode(currency);
    return MoneyValue(
      currency: definition.code,
      minorUnits: minorUnits,
      decimalPlaces: definition.decimalPlaces,
    );
  }

  double toDouble() => minorUnits / _scale(decimalPlaces);

  MoneyValue operator +(MoneyValue other) {
    _assertSameCurrency(other);
    return MoneyValue(
      currency: currency,
      minorUnits: minorUnits + other.minorUnits,
      decimalPlaces: decimalPlaces,
    );
  }

  MoneyValue operator -(MoneyValue other) {
    _assertSameCurrency(other);
    return MoneyValue(
      currency: currency,
      minorUnits: minorUnits - other.minorUnits,
      decimalPlaces: decimalPlaces,
    );
  }

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'minorUnits': minorUnits,
        'decimalPlaces': decimalPlaces,
      };

  void _assertSameCurrency(MoneyValue other) {
    if (currency != other.currency || decimalPlaces != other.decimalPlaces) {
      throw ArgumentError('Cannot combine $currency and ${other.currency}.');
    }
  }
}
