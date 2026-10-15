part of 'invoice_pdf_service.dart';

extension _InvoicePdfServicePart3 on _InvoicePdfServiceImplementation {
  String _formatMoney(double usdAmount, StoreProfile profile) {
    String formatAs(String currency) {
      final code = currency.toUpperCase();
      final definition = profile.currencyByCode(code);
      final amount = code == 'USD'
          ? usdAmount
          : usdAmount *
              (profile.exchangeRateForDate('USD', code)?.rate ??
                  (code == 'LBP' ? profile.usdToLbpRate : 1));
      final rounded = definition.roundingStep > 0
          ? roundCashAmount(
              amount,
              definition.roundingStep,
              method: definition.roundingMethod,
            )
          : amount;
      final decimals = definition.decimalPlaces;
      final value = decimals == 0
          ? rounded.round().toString()
          : rounded.toStringAsFixed(decimals);
      return '${definition.symbol} $value';
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
}
