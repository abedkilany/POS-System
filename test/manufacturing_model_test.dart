import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/models/manufacturing.dart';

void main() {
  test('BillOfMaterials serializes and calculates unit cost', () {
    final bom = BillOfMaterials(
      id: 'bom-1',
      name: 'Coffee pack',
      outputProductId: 'finished-1',
      outputProductName: 'Finished coffee pack',
      outputQuantity: 2,
      components: const [
        BillOfMaterialsLine(productId: 'beans', productName: 'Beans', quantity: 4, unitCost: 3),
        BillOfMaterialsLine(productId: 'bag', productName: 'Bag', quantity: 2, unitCost: 0.5),
      ],
      notes: 'Test recipe',
    );

    expect(bom.unitCost, 6.5);
    final decoded = BillOfMaterials.fromJson(bom.toJson());
    expect(decoded.id, bom.id);
    expect(decoded.components.length, 2);
    expect(decoded.unitCost, 6.5);
  });

  test('ManufacturingOrder serializes', () {
    final order = ManufacturingOrder(
      id: 'mfg-1',
      orderNo: 'MFG-001',
      bomId: 'bom-1',
      bomName: 'Coffee pack',
      outputProductId: 'finished-1',
      outputProductName: 'Finished coffee pack',
      quantity: 10,
      notes: 'Batch one',
    );

    final decoded = ManufacturingOrder.fromJson(order.toJson());
    expect(decoded.orderNo, 'MFG-001');
    expect(decoded.quantity, 10);
    expect(decoded.status, 'completed');
  });
}
