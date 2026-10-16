import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/features/sales/domain/sale_cart.dart';
import 'package:ventio/features/sales/domain/sale_payment_preview.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/store_profile.dart';

Product _product({bool measurable = false}) => Product(
      id: 'coffee',
      name: 'Coffee',
      code: 'C',
      price: 10,
      cost: 3,
      stock: 12,
      category: '',
      quantityType: measurable
          ? ProductQuantityType.measurable
          : ProductQuantityType.countable,
    );

const _piece =
    ProductSaleUnit(id: 'base', name: 'pcs', conversionToBase: 1, price: 10);
const _box =
    ProductSaleUnit(id: 'box', name: 'Box', conversionToBase: 6, price: 50);

void main() {
  test('merges matching product units and preserves separate sale units', () {
    final cart = SaleCart();
    cart.add(_product(), _piece);
    cart.add(_product(), _piece);
    cart.add(_product(), _box);
    expect(cart.items.length, 2);
    expect(cart.items.first.baseQuantity, 6);
    expect(cart.items.last.quantity, 2);
    expect(cart.subtotal, 70);
    expect(cart.itemCount, 3);
    expect(() => cart.items.clear(), throwsUnsupportedError);
  });

  test(
      'normalizes countable and measurable quantities and signals stock excess',
      () {
    final cart = SaleCart()..add(_product(), _piece);
    cart.changeQuantity(0, 1.6);
    expect(cart.items.single.quantity, 2);
    cart.changeQuantity(0, -1);
    expect(cart.items.single.quantity, 1);
    expect(cart.changeQuantity(0, 13), isTrue);
    cart.changeQuantity(0, double.nan);
    expect(cart.items.single.quantity, 13);
    cart.clear();
    cart.add(_product(measurable: true), _piece);
    cart.changeQuantity(0, 0.125);
    expect(cart.items.single.quantity, 0.125);
    cart.changeQuantity(0, -5);
    expect(cart.items.single.quantity, 0.001);
  });

  test(
      'repricing and restore preserve quantities without exposing mutable lines',
      () {
    final cart = SaleCart()..add(_product(), _box);
    cart.changeQuantity(0, 2);
    cart.reprice((product, unit) => 40);
    expect(cart.subtotal, 80);
    expect(cart.items.single.baseQuantity, 12);
    cart.replaceAll(cart.items);
    expect(cart.subtotal, 80);
    cart.removeAt(0);
    expect(cart.items, isEmpty);
  });

  test('profit uses base-unit costs and honors the authoritative batch preview',
      () {
    final cart = SaleCart()..add(_product(), _box);
    final fallback = cart.totals(discount: 5);
    expect(fallback.revenue, 45);
    expect(fallback.cost, 18);
    expect(fallback.profit, 27);
    expect(fallback.profitPercent, 60);
    expect(cart.totals(discount: 5, batchCost: 20).profit, 25);
    expect(cart.totals(discount: 100).revenue, 0);
    expect(cart.totals(discount: 100).profitPercent, 0);
  });

  SalePaymentPreview preview(String method, double received) {
    final defaults = StoreProfile.defaults;
    final profile = defaults.copyWith(
        currencies: defaults.currencies
            .map((currency) => currency.code == 'USD'
                ? currency.copyWith(roundingStep: 0.05)
                : currency)
            .toList());
    return SalePaymentPreview(
        profile: profile,
        baseTotal: 10.03,
        invoiceCurrency: 'USD',
        paymentCurrency: 'USD',
        paymentMethod: method,
        receivedInPaymentCurrency: received,
        effectiveAt: DateTime.utc(2026, 1, 1));
  }

  test('cash preview applies configured rounding and reports its difference',
      () {
    final value = preview('Cash', 0);
    expect(value.rawInvoiceTotal, closeTo(10.03, 0.000001));
    expect(value.invoiceTotal, closeTo(10.05, 0.000001));
    expect(value.roundingDifference, closeTo(0.02, 0.000001));
    expect(value.paidAmount, value.invoiceTotal);
    expect(value.paymentStatus, 'paid');
  });

  test('credit preview keeps exact totals and caps received cash', () {
    final unpaid = preview('Credit', 0);
    final partial = preview('Credit', 4);
    final excess = preview('Credit', 20);
    expect(unpaid.invoiceTotal, closeTo(10.03, 0.000001));
    expect(unpaid.paymentStatus, 'credit');
    expect(partial.paymentStatus, 'partial');
    expect(partial.paidAmount, 4);
    expect(excess.cashReceived, excess.invoiceTotal);
    expect(preview('Card', 0).roundingDifference, 0);
  });
}
