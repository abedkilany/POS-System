import '../../models/store_profile.dart';

double roundLbpAmount(double value, int step) {
  if (step <= 0) return value;
  return (value / step).round() * step.toDouble();
}

double convertUsdToLbp(double usdAmount, StoreProfile profile) {
  final converted = usdAmount * profile.usdToLbpRate;
  return roundLbpAmount(converted, profile.lbpRounding);
}

String formatCurrency(double value, {String currency = 'USD'}) {
  final normalized = currency.toUpperCase();
  if (normalized == 'LBP') {
    final isWholeNumber = value == value.roundToDouble();
    return 'LBP ${isWholeNumber ? value.round().toString() : value.toStringAsFixed(2)}';
  }
  final symbol = switch (normalized) {
    'USD' => r'$',
    _ => '$normalized ',
  };
  return '$symbol${value.toStringAsFixed(2)}';
}

String formatUsdReferenceAmount(double usdAmount, StoreProfile profile) {
  switch (profile.priceDisplayMode) {
    case 'lbp':
      return formatCurrency(convertUsdToLbp(usdAmount, profile), currency: 'LBP');
    case 'both':
      return "${formatCurrency(usdAmount, currency: 'USD')} (${formatCurrency(convertUsdToLbp(usdAmount, profile), currency: 'LBP')})";
    case 'usd':
    default:
      return formatCurrency(usdAmount, currency: 'USD');
  }
}

double toUsdReferencePrice(double amount, String currency, StoreProfile profile) {
  final normalized = currency.toUpperCase();
  if (normalized == 'LBP') {
    final rate = profile.usdToLbpRate <= 0 ? StoreProfile.defaults.usdToLbpRate : profile.usdToLbpRate;
    return amount / rate;
  }
  return amount;
}
