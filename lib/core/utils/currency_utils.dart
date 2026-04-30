String formatCurrency(double value, {String currency = 'USD'}) {
  final symbol = switch (currency.toUpperCase()) {
    'USD' => r'$',
    'EUR' => '€',
    'GBP' => '£',
    'LBP' => 'LBP ',
    'SAR' => 'SAR ',
    'AED' => 'AED ',
    _ => '${currency.toUpperCase()} ',
  };
  return '$symbol${value.toStringAsFixed(2)}';
}
