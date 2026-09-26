import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/models/print_settings.dart';

void main() {
  test('document defaults use standard, narrow, and shipping formats', () {
    expect(
      PrintDocumentKeys.defaultFormatFor(PrintDocumentKeys.salesInvoice),
      PrintPaperFormats.a4,
    );
    expect(
        PrintDocumentKeys.allowedFormatsFor(PrintDocumentKeys.salesInvoice),
        containsAll(<String>[
          PrintPaperFormats.a4,
          PrintPaperFormats.mm58,
          PrintPaperFormats.mm80,
          PrintPaperFormats.shippingLabel,
        ]));
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
          url: 'printer://test',
        ),
      ],
      documents: {
        PrintDocumentKeys.report: PrintDocumentSettings(
          format: PrintPaperFormats.a4,
          printerId: 'system:test',
          directPrint: true,
          copies: 3,
        ),
      },
    );

    final restored = PrintSettings.fromJson(settings.toJson());

    expect(restored.showOptionsBeforePrint, isTrue);
    expect(restored.printers.single.name, 'Office Printer');
    expect(restored.forDocument(PrintDocumentKeys.report).printerId,
        'system:test');
    expect(restored.forDocument(PrintDocumentKeys.report).directPrint, isTrue);
    expect(restored.forDocument(PrintDocumentKeys.report).copies, 3);
  });

  test('invalid persisted formats fall back to the document default', () {
    final settings = PrintSettings.fromJson({
      'documents': {
        PrintDocumentKeys.cashReceipt: {'format': 'unknown-format'},
        PrintDocumentKeys.shippingLabel: {'format': PrintPaperFormats.a4},
      },
    });

    expect(settings.forDocument(PrintDocumentKeys.cashReceipt).format,
        PrintPaperFormats.mm80);
    expect(settings.forDocument(PrintDocumentKeys.shippingLabel).format,
        PrintPaperFormats.shippingLabel);
  });
}
