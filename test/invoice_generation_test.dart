import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/invoice_pdf_service.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/store_profile.dart';

void main() {
  group('Invoice PDF generation', () {
    test('builds a non-empty PDF document with a valid header', () async {
      final bytes = await InvoicePdfService.buildInvoicePdf(
        profile: StoreProfile.defaults.copyWith(name: 'Ventio Test Store', currency: 'USD'),
        sale: Sale(
          id: 's1',
          invoiceNo: 'INV-TEST-001',
          customerName: 'Walk-in Customer',
          date: DateTime(2026, 1, 1, 10),
          status: 'Paid',
          discount: 2,
          items: const [
            SaleItem(productId: 'p1', productName: 'Coffee', unitPrice: 10, quantity: 2, unitCost: 4),
            SaleItem(productId: 'p2', productName: 'Tea', unitPrice: 5, quantity: 1, unitCost: 2),
          ],
        ),
      );

      expect(bytes.length, greaterThan(1000));
      expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    });

    test('supports custom currency prefixes without throwing', () async {
      final bytes = await InvoicePdfService.buildInvoicePdf(
        profile: StoreProfile.defaults.copyWith(currency: 'LBP'),
        sale: Sale(
          id: 's2',
          invoiceNo: 'INV-LBP-001',
          customerName: 'Customer',
          date: DateTime(2026, 1, 1),
          status: 'Paid',
          discount: 0,
          items: const [SaleItem(productId: 'p1', productName: 'Item', unitPrice: 150000, quantity: 1)],
        ),
      );

      expect(bytes, isNotEmpty);
    });
  });
}
