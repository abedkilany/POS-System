import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../models/store_profile.dart';

double _roundToDecimals(double value, int decimals) {
  if (!value.isFinite) return 0;
  final factor = math.pow(10, decimals.clamp(0, 6)).toDouble();
  return (value * factor).roundToDouble() / factor;
}

double roundCashAmount(
  double value,
  double step, {
  String method = 'nearest',
}) {
  if (step <= 0 || !value.isFinite) return value;
  final ratio = value / step;
  final normalizedMethod = method.trim().toLowerCase();
  final roundedRatio = switch (normalizedMethod) {
    'up' => ratio.ceilToDouble(),
    'down' => ratio.floorToDouble(),
    _ => ratio.roundToDouble(),
  };
  return roundedRatio * step;
}

double roundLbpAmount(double value, int step) {
  return roundCashAmount(value, step.toDouble());
}

FinancialCurrency currencyDefinition(String currency, StoreProfile profile) {
  return profile.currencyByCode(currency);
}

int accountingDecimalsForCurrency(String currency, StoreProfile profile) {
  return currencyDefinition(currency, profile).decimalPlaces;
}

int cashDecimalsForCurrency(String currency, StoreProfile profile) {
  return currencyDefinition(currency, profile).cashDecimalPlaces;
}

double normalizePriceAmount(double value, StoreProfile profile) {
  return _roundToDecimals(value, profile.priceStorageDecimals);
}

double normalizeAccountingAmount(
  double value,
  String currency,
  StoreProfile profile,
) {
  return _roundToDecimals(value, accountingDecimalsForCurrency(currency, profile));
}

double normalizeCashAmount(
  double value,
  String currency,
  StoreProfile profile,
) {
  final definition = currencyDefinition(currency, profile);
  final rounded = _roundToDecimals(value, definition.cashDecimalPlaces);
  if (definition.roundingStep > 0) {
    return roundCashAmount(
      rounded,
      definition.roundingStep,
      method: definition.roundingMethod,
    );
  }
  return rounded;
}

double exchangeRate(
  String fromCurrency,
  String toCurrency,
  StoreProfile profile, {
  DateTime? effectiveAt,
}) {
  final from = fromCurrency.toUpperCase();
  final to = toCurrency.toUpperCase();
  if (from == to) return 1;
  final configured = profile.exchangeRateForDate(from, to, effectiveAt: effectiveAt);
  if (configured != null && configured.rate > 0) return configured.rate;

  // Legacy fallback kept to avoid breaking older installations.
  if (from == 'USD' && to == 'LBP') return profile.usdToLbpRate;
  if (from == 'LBP' && to == 'USD') {
    final rate = profile.usdToLbpRate <= 0
        ? StoreProfile.defaults.usdToLbpRate
        : profile.usdToLbpRate;
    return 1 / rate;
  }

  throw ArgumentError('No exchange rate configured for $from → $to.');
}

double convertCurrency(
  double amount,
  String fromCurrency,
  String toCurrency,
  StoreProfile profile, {
  bool normalizeResult = true,
  DateTime? effectiveAt,
}) {
  final from = fromCurrency.toUpperCase();
  final to = toCurrency.toUpperCase();
  final converted = amount * exchangeRate(from, to, profile, effectiveAt: effectiveAt);
  return normalizeResult ? normalizeAccountingAmount(converted, to, profile) : converted;
}

/// Converts a transaction amount to the company base/functional currency using
/// the historical rate valid on [effectiveAt]. This is the core professional
/// accounting pattern used by ERP systems: documents keep their transaction
/// currency while ledgers and reports keep a stable base-currency value.
double toBaseCurrencyAmount(
  double amount,
  String transactionCurrency,
  StoreProfile profile, {
  DateTime? effectiveAt,
  bool normalizeResult = true,
}) {
  return convertCurrency(
    amount,
    transactionCurrency,
    profile.baseCurrency,
    profile,
    effectiveAt: effectiveAt,
    normalizeResult: normalizeResult,
  );
}

/// Difference between the document's historical base amount and the base value
/// of a later settlement. Positive = exchange gain, negative = exchange loss.
double exchangeDifferenceAmount({
  required double originalBaseAmount,
  required double settlementAmount,
  required String settlementCurrency,
  required StoreProfile profile,
  DateTime? settlementDate,
}) {
  final settlementBase = toBaseCurrencyAmount(
    settlementAmount,
    settlementCurrency,
    profile,
    effectiveAt: settlementDate,
  );
  return normalizeAccountingAmount(
    settlementBase - originalBaseAmount,
    profile.baseCurrency,
    profile,
  );
}

double convertUsdToLbp(double usdAmount, StoreProfile profile) {
  final converted = convertCurrency(
    usdAmount,
    'USD',
    'LBP',
    profile,
    normalizeResult: false,
  );
  final lbpCurrency = profile.currencyByCode('LBP');
  if (lbpCurrency.roundingStep > 0) {
    return roundCashAmount(
      converted,
      lbpCurrency.roundingStep,
      method: lbpCurrency.roundingMethod,
    );
  }
  return normalizeAccountingAmount(converted, 'LBP', profile);
}

String _formatNumberWithThousands(double value, {required int decimalDigits}) {
  final formatter = NumberFormat.decimalPattern('en_US')
    ..minimumFractionDigits = decimalDigits
    ..maximumFractionDigits = decimalDigits;
  return formatter.format(value);
}

String formatCurrency(
  double value, {
  String currency = 'USD',
  StoreProfile? profile,
}) {
  final normalized = currency.toUpperCase();
  final definition = profile?.currencyByCode(normalized);
  final digits = definition?.decimalPlaces ?? 2;
  final symbol = definition?.symbol ??
      switch (normalized) {
        'USD' => r'$',
        'LBP' => 'LBP',
        _ => normalized,
      };
  final separator = symbol.endsWith(' ') || symbol.length <= 2 && symbol != 'LBP'
      ? ''
      : ' ';
  return '$symbol$separator${_formatNumberWithThousands(value, decimalDigits: digits)}';
}

String formatUsdReferenceAmount(double usdAmount, StoreProfile profile) {
  String formatAs(String currency) {
    final code = currency.toUpperCase();
    final amount = code == 'USD'
        ? usdAmount
        : convertCurrency(usdAmount, 'USD', code, profile);
    return formatCurrency(amount, currency: code, profile: profile);
  }

  switch (profile.priceDisplayMode) {
    case 'multiple':
      final codes = profile.priceDisplayCurrencies.isEmpty
          ? <String>[profile.defaultSaleInvoiceCurrency]
          : profile.priceDisplayCurrencies;
      return codes.map(formatAs).join(' / ');
    case 'selectable':
    case 'default':
    default:
      return formatAs(profile.defaultSaleInvoiceCurrency);
  }
}

double toUsdReferencePrice(double amount, String currency, StoreProfile profile) {
  return convertCurrency(amount, currency, 'USD', profile, normalizeResult: false);
}

double fromUsdReferencePrice(double usdAmount, String currency, StoreProfile profile) {
  return convertCurrency(usdAmount, 'USD', currency, profile);
}
