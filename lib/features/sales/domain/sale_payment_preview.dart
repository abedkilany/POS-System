import '../../../core/utils/currency_utils.dart';
import '../../../models/store_profile.dart';

/// Display calculation shared by the invoice and payment panels. Persistence
/// still validates and freezes its own amounts at the time of posting.
class SalePaymentPreview {
  const SalePaymentPreview(
      {required this.profile,
      required this.baseTotal,
      required this.invoiceCurrency,
      required this.paymentCurrency,
      required this.paymentMethod,
      required this.receivedInPaymentCurrency,
      required this.effectiveAt});

  final StoreProfile profile;
  final double baseTotal;
  final String invoiceCurrency;
  final String paymentCurrency;
  final String paymentMethod;
  final double receivedInPaymentCurrency;
  final DateTime effectiveAt;

  double _convert(double amount, String from, String to) =>
      convertCurrency(amount, from, to, profile, effectiveAt: effectiveAt);

  double get rawInvoiceTotal =>
      _convert(baseTotal, profile.baseCurrency, invoiceCurrency);
  double get invoiceTotal {
    if (paymentMethod != 'Cash') return rawInvoiceTotal;
    final paymentAmount =
        _convert(rawInvoiceTotal, invoiceCurrency, paymentCurrency);
    return _convert(
        normalizeCashAmount(paymentAmount, paymentCurrency, profile),
        paymentCurrency,
        invoiceCurrency);
  }

  double get roundingDifference => invoiceTotal - rawInvoiceTotal;
  double get cashReceived =>
      _convert(receivedInPaymentCurrency, paymentCurrency, invoiceCurrency)
          .clamp(0, invoiceTotal)
          .toDouble();
  double get paidAmount =>
      paymentMethod == 'Credit' ? cashReceived : invoiceTotal;
  String get paymentStatus => paymentMethod == 'Credit'
      ? (cashReceived > 0 ? 'partial' : 'credit')
      : 'paid';
}
