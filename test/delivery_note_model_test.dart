import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/models/delivery_note.dart';
import 'package:ventio/models/sale_item.dart';

void main() {
  test('DeliveryNote serializes and restores status/items', () {
    final now = DateTime(2026, 1, 2, 3, 4, 5);
    final note = DeliveryNote(
      id: 'dn-1',
      deliveryNo: 'DLV-HOST-000001',
      saleId: 'sale-1',
      invoiceNo: 'INV-HOST-000001',
      customerName: 'Customer',
      customerId: 'customer-1',
      date: now,
      status: 'Delivered',
      deliveredAt: now,
      items: const [SaleItem(productId: 'p1', productName: 'Product', unitPrice: 10, quantity: 2)],
    );

    final restored = DeliveryNote.fromJson(note.toJson());

    expect(restored.id, 'dn-1');
    expect(restored.deliveryNo, 'DLV-HOST-000001');
    expect(restored.saleId, 'sale-1');
    expect(restored.isDelivered, isTrue);
    expect(restored.items.single.productName, 'Product');
    expect(restored.totalQuantity, 2);
  });
}
