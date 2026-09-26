/// Supported paper formats for the central printing configuration.
class PrintPaperFormats {
  PrintPaperFormats._();

  static const mm80 = 'mm_80';
  static const mm58 = 'mm_58';
  static const a4 = 'a4';
  static const shippingLabel = 'shipping_label_4x6';

  static const all = <String>[
    a4,
    mm58,
    mm80,
    shippingLabel,
  ];

  /// Formats available to ordinary documents. Barcode labels deliberately
  /// keep their own size and layout workflow.
  static const documentFormats = <String>[
    a4,
    mm58,
    mm80,
    shippingLabel,
  ];

  static String normalize(String value, {String fallback = a4}) {
    final normalized = value.trim().toLowerCase();
    return all.contains(normalized) ? normalized : fallback;
  }
}

/// Stable identifiers for every non-barcode print action.
class PrintDocumentKeys {
  PrintDocumentKeys._();

  static const salesInvoice = 'sales_invoice';
  static const salesReturn = 'sales_return';
  static const purchaseInvoice = 'purchase_invoice';
  static const cashReceipt = 'cash_receipt';
  static const cashShiftReport = 'cash_shift_report';
  static const expense = 'expense';
  static const accountStatement = 'account_statement';
  static const expenseStatement = 'expense_statement';
  static const report = 'report';
  static const quotation = 'quotation';
  static const deliveryNote = 'delivery_note';
  static const priceList = 'price_list';
  static const manufacturingBom = 'manufacturing_bom';
  static const manufacturingOrder = 'manufacturing_order';
  static const manufacturingOrders = 'manufacturing_orders';
  static const warehouseInventory = 'warehouse_inventory';
  static const warehouseTransfer = 'warehouse_transfer';
  static const accountingPage = 'accounting_page';
  static const shippingLabel = 'shipping_label';

  static const all = <String>[
    salesInvoice,
    salesReturn,
    purchaseInvoice,
    cashReceipt,
    cashShiftReport,
    expense,
    accountStatement,
    expenseStatement,
    report,
    quotation,
    deliveryNote,
    priceList,
    manufacturingBom,
    manufacturingOrder,
    manufacturingOrders,
    warehouseInventory,
    warehouseTransfer,
    accountingPage,
    shippingLabel,
  ];

  static String defaultFormatFor(String key) {
    if (key == shippingLabel) return PrintPaperFormats.shippingLabel;
    if (key == cashReceipt) return PrintPaperFormats.mm80;
    return PrintPaperFormats.a4;
  }

  static List<String> allowedFormatsFor(String key) {
    if (key == shippingLabel) return const [PrintPaperFormats.shippingLabel];
    return PrintPaperFormats.documentFormats;
  }
}

class PrintPrinterProfile {
  const PrintPrinterProfile({
    required this.id,
    required this.name,
    this.url = '',
  });

  final String id;
  final String name;
  final String url;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
      };

  factory PrintPrinterProfile.fromJson(Map<String, dynamic> json) {
    return PrintPrinterProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }
}

class PrintDocumentSettings {
  const PrintDocumentSettings({
    required this.format,
    this.printerId = '',
    this.directPrint = false,
    this.copies = 1,
  });

  final String format;
  final String printerId;
  final bool directPrint;
  final int copies;

  PrintDocumentSettings copyWith({
    String? format,
    String? printerId,
    bool? directPrint,
    int? copies,
  }) {
    return PrintDocumentSettings(
      format: PrintPaperFormats.normalize(format ?? this.format),
      printerId: printerId ?? this.printerId,
      directPrint: directPrint ?? this.directPrint,
      copies: (copies ?? this.copies).clamp(1, 99),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'format': format,
        'printerId': printerId,
        'directPrint': directPrint,
        'copies': copies,
      };

  factory PrintDocumentSettings.fromJson(
      String key, Map<String, dynamic> json) {
    final requestedFormat = PrintPaperFormats.normalize(
      json['format']?.toString() ?? '',
      fallback: PrintDocumentKeys.defaultFormatFor(key),
    );
    final format = PrintDocumentKeys.allowedFormatsFor(key).contains(
      requestedFormat,
    )
        ? requestedFormat
        : PrintDocumentKeys.defaultFormatFor(key);
    return PrintDocumentSettings(
      format: format,
      printerId: json['printerId']?.toString() ?? '',
      directPrint: json['directPrint'] == true,
      copies: (json['copies'] as num? ?? 1).toInt().clamp(1, 99),
    );
  }
}

class PrintSettings {
  const PrintSettings({
    this.showOptionsBeforePrint = false,
    this.printers = const <PrintPrinterProfile>[],
    this.documents = const <String, PrintDocumentSettings>{},
  });

  final bool showOptionsBeforePrint;
  final List<PrintPrinterProfile> printers;
  final Map<String, PrintDocumentSettings> documents;

  PrintDocumentSettings forDocument(String key) {
    final saved = documents[key];
    if (saved == null) {
      return PrintDocumentSettings(
        format: PrintDocumentKeys.defaultFormatFor(key),
      );
    }
    final allowed = PrintDocumentKeys.allowedFormatsFor(key);
    return allowed.contains(saved.format)
        ? saved
        : saved.copyWith(format: PrintDocumentKeys.defaultFormatFor(key));
  }

  PrintPrinterProfile? printerById(String id) {
    if (id.trim().isEmpty) return null;
    for (final printer in printers) {
      if (printer.id == id) return printer;
    }
    return null;
  }

  PrintSettings copyWith({
    bool? showOptionsBeforePrint,
    List<PrintPrinterProfile>? printers,
    Map<String, PrintDocumentSettings>? documents,
  }) {
    return PrintSettings(
      showOptionsBeforePrint:
          showOptionsBeforePrint ?? this.showOptionsBeforePrint,
      printers:
          List<PrintPrinterProfile>.unmodifiable(printers ?? this.printers),
      documents: Map<String, PrintDocumentSettings>.unmodifiable(
          documents ?? this.documents),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'showOptionsBeforePrint': showOptionsBeforePrint,
        'printers': printers.map((printer) => printer.toJson()).toList(),
        'documents': <String, dynamic>{
          for (final entry in documents.entries)
            entry.key: entry.value.toJson(),
        },
      };

  factory PrintSettings.fromJson(Map<String, dynamic> json) {
    final rawPrinters = json['printers'];
    final printers = rawPrinters is List
        ? rawPrinters
            .whereType<Map>()
            .map((item) =>
                PrintPrinterProfile.fromJson(Map<String, dynamic>.from(item)))
            .where((printer) =>
                printer.id.trim().isNotEmpty && printer.url.trim().isNotEmpty)
            .toList(growable: false)
        : const <PrintPrinterProfile>[];
    final rawDocuments = json['documents'];
    final documents = <String, PrintDocumentSettings>{};
    if (rawDocuments is Map) {
      for (final entry in rawDocuments.entries) {
        final key = entry.key.toString();
        if (PrintDocumentKeys.all.contains(key) && entry.value is Map) {
          documents[key] = PrintDocumentSettings.fromJson(
            key,
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    return PrintSettings(
      showOptionsBeforePrint: json['showOptionsBeforePrint'] == true,
      printers: printers,
      documents: documents,
    );
  }
}
