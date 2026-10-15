import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/sale_workflow_service.dart';
import 'package:ventio/models/product_costing.dart';
import 'package:ventio/models/sale_item.dart';

void main() {
  const service = SaleWorkflowService();

  test('validates sale lines and normalizes non-finite discount', () {
    final cleaned = service.validateCreate(
      items: const <SaleItem>[
        SaleItem(
          productId: 'product-1',
          productName: 'Product',
          unitPrice: 5,
          quantity: 2,
        ),
      ],
      discount: double.infinity,
      productExists: (id) => id == 'product-1',
    );
    expect(cleaned, 0);
    expect(
      () => service.validateCreate(
        items: const <SaleItem>[
          SaleItem(
            productId: 'missing',
            productName: 'Missing',
            unitPrice: 5,
            quantity: 1,
          ),
        ],
        discount: 0,
        productExists: (_) => false,
      ),
      throwsArgumentError,
    );
  });

  test('prepares lines without consuming stock cost layers', () {
    final prepared = service.prepareItems(
      const <SaleItem>[
        SaleItem(
          productId: 'product-1',
          productName: 'Product',
          unitPrice: 9,
          quantity: 2,
          unitCost: 3,
          costCurrency: 'LBP',
          baseQuantity: 6,
          conversionToBase: 3,
        ),
      ],
      costingMethod: InventoryCostingMethod.fifo,
    ).single;

    expect(prepared.effectiveBaseQuantity, 6);
    expect(prepared.costingMethodAtSale, InventoryCostingMethod.fifo);
    expect(prepared.costCurrency, 'LBP');
    expect(prepared.costExchangeRate, 1);
    expect(prepared.costLayerConsumptions, isEmpty);
  });

  test('normalizes customer payment and blocks walk-in credit', () {
    final partialCredit = service.prepareInitialPayment(
      customerId: 'customer-1',
      customerName: 'Customer',
      paymentMethod: 'Credit',
      paymentStatus: 'paid',
      saleTotalInInvoiceCurrency: 20,
      cashReceivedAmount: 6,
      walkInCustomerId: 'walk-in-id',
      walkInCustomerName: 'Walk-in',
    );
    expect(partialCredit.paymentStatus, 'partial');
    expect(partialCredit.paidAmount, 6);
    expect(partialCredit.initialPaymentMethod, 'Cash');

    expect(
      () => service.prepareInitialPayment(
        customerId: '',
        customerName: '',
        paymentMethod: 'Credit',
        paymentStatus: 'credit',
        saleTotalInInvoiceCurrency: 20,
        cashReceivedAmount: 0,
        walkInCustomerId: 'walk-in-id',
        walkInCustomerName: 'Walk-in',
      ),
      throwsArgumentError,
    );
  });
}
