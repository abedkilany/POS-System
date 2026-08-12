import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/core/services/thermal_printer_service.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/store_profile.dart';

void main() {
  testWidgets('thermal receipt renders Arabic and USD/LBP totals',
      (tester) async {
    final sale = Sale(
      id: 'sale-1',
      invoiceNo: 'INV-1',
      customerName: 'Walk-in',
      date: DateTime(2026, 8, 11, 12, 30),
      status: 'Paid',
      discount: 0,
      items: const [
        SaleItem(
          productId: 'p-1',
          productName: 'قهوة',
          unitPrice: 10,
          quantity: 2,
        ),
      ],
    );
    final profile = StoreProfile.defaults.copyWith(
      priceDisplayMode: 'multiple',
      priceDisplayCurrencies: const ['USD', 'LBP'],
      usdToLbpRate: 89500,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ThermalReceiptWidget(
          sale: sale,
          profile: profile,
          locale: const Locale('ar'),
          width: 384,
        ),
      ),
    );

    expect(find.text('فاتورة: INV-1'), findsOneWidget);
    expect(find.text('قهوة'), findsOneWidget);
    expect(find.textContaining('المجموع'), findsWidgets);
    expect(find.textContaining('LBP'), findsWidgets);
  });
}
