import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/models/print_settings.dart';

void main() {
  test('document defaults use thermal, A4, and shipping formats', () {
    expect(
      PrintDocumentKeys.defaultFormatFor(PrintDocumentKeys.thermalSalesInvoice),
      PrintPaperFormats.thermal80,
    );
    expect(
      PrintDocumentKeys.defaultFormatFor(PrintDocumentKeys.report),
      PrintPaperFormats.a4,
    );
    expect(
      PrintDocumentKeys.defaultFormatFor(PrintDocumentKeys.shippingLabel),
      PrintPaperFormats.shippingLabel,
    );
    expect(PrintDocumentKeys.all, isNot(contains('barcode')));
  });

  test('print settings round-trip preserves printers and document defaults',
      () {
    const settings = PrintSettings(
      showOptionsBeforePrint: true,
      printers: [
        PrintPrinterProfile(
          id: 'system:test',
          name: 'Office Printer',
          kind: 'system',
          url: 'printer://test',
        ),
      ],
      documents: {
        PrintDocumentKeys.report: PrintDocumentSettings(
          format: PrintPaperFormats.a4,
          printerId: 'system:test',
          directPrint: true,
        ),
      },
    );

    final restored = PrintSettings.fromJson(settings.toJson());

    expect(restored.showOptionsBeforePrint, isTrue);
    expect(restored.printers.single.name, 'Office Printer');
    expect(restored.forDocument(PrintDocumentKeys.report).printerId,
        'system:test');
    expect(restored.forDocument(PrintDocumentKeys.report).directPrint, isTrue);
  });

  test('invalid persisted formats fall back to the document default', () {
    final settings = PrintSettings.fromJson({
      'documents': {
        PrintDocumentKeys.cashReceipt: {'format': 'unknown-format'},
        PrintDocumentKeys.shippingLabel: {'format': PrintPaperFormats.a4},
      },
    });

    expect(settings.forDocument(PrintDocumentKeys.cashReceipt).format,
        PrintPaperFormats.thermal80);
    expect(settings.forDocument(PrintDocumentKeys.shippingLabel).format,
        PrintPaperFormats.shippingLabel);
  });
}
