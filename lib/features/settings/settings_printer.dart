part of 'settings_page.dart';

extension _SettingsPrinterSection on SettingsPage {
  List<Widget> _printerCards(BuildContext context) => <Widget>[
        _printSettingsCard(context),
      ];

  Widget _printSettingsCard(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final settings = store.storeProfile.printSettings;
    final configuredDefaults = settings.documents.values
        .where((item) => item.printerId.trim().isNotEmpty)
        .length;
    return _SectionCard(
      icon: Icons.print_outlined,
      title: tr.text('print_settings'),
      subtitle: tr.text('print_settings_desc'),
      trailing: FilledButton.icon(
        onPressed: store.hasPermission(AppPermission.settingsManage)
            ? () => _editPrintSettings(context)
            : null,
        icon: const Icon(Icons.settings_outlined),
        label: Text(tr.text('edit')),
      ),
      child: _InfoGrid(
        items: [
          _InfoGridItem(
            Icons.tune_outlined,
            tr.text('print_options_before_print'),
            settings.showOptionsBeforePrint
                ? tr.text('enabled')
                : tr.text('disabled'),
          ),
          _InfoGridItem(
            Icons.devices_outlined,
            tr.text('detected_printers'),
            '${settings.printers.length}',
          ),
          _InfoGridItem(
            Icons.link_outlined,
            tr.text('configured_print_defaults'),
            '$configuredDefaults',
          ),
          _InfoGridItem(
            Icons.local_shipping_outlined,
            tr.text('shipping_label_size'),
            '4 × 6 in',
          ),
        ],
      ),
    );
  }

  Future<List<PrintPrinterProfile>> _detectPrintPrinters() async {
    final byId = <String, PrintPrinterProfile>{};

    try {
      for (final printer in await Printing.listPrinters()) {
        final id = 'system:${printer.url}';
        byId[id] = PrintPrinterProfile(
          id: id,
          name: printer.name,
          kind: 'system',
          url: printer.url,
        );
      }
    } catch (_) {
      // A platform may not expose the system printer list.
    }

    final thermalService = ThermalPrinterService();
    try {
      for (final type in thermal.PrinterType.values) {
        try {
          for (final printer in await thermalService.listPrinters(type)) {
            final id = _thermalPrinterId(printer);
            if (id.isEmpty) continue;
            byId[id] = PrintPrinterProfile(
              id: id,
              name: printer.name.trim().isEmpty ? id : printer.name,
              kind: 'thermal',
              thermalType: printer.type.name,
              ip: printer.ip,
              port: int.tryParse(printer.port) ?? 9100,
              bluetoothAddress: printer.bleAddress,
              usbAddress: printer.usbAddress,
            );
          }
        } catch (_) {
          // USB/Bluetooth/network discovery is platform-dependent.
        }
      }
    } finally {
      await thermalService.dispose();
    }

    return byId.values.toList(growable: false);
  }

  String _thermalPrinterId(thermal.Printer printer) {
    final type = printer.type.name;
    final address = switch (printer.type) {
      thermal.PrinterType.network => '${printer.ip}:${printer.port}',
      thermal.PrinterType.bluetooth => printer.bleAddress,
      thermal.PrinterType.usb => printer.usbAddress,
    };
    final value = address.trim();
    return value.isEmpty ? '' : 'thermal:$type:$value';
  }

  Future<void> _editPrintSettings(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final current = store.storeProfile.printSettings;
    var detected = List<PrintPrinterProfile>.of(current.printers);
    var settings = current;

    // Refresh the device list as the settings editor opens so the printer
    // choices are based on the printers currently attached to this computer.
    try {
      final found = await _detectPrintPrinters();
      detected = <PrintPrinterProfile>[
        ...{for (final item in detected) item.id: item}.values,
        ...{for (final item in found) item.id: item}.values,
      ];
      settings = settings.copyWith(printers: detected);
    } catch (_) {
      // Keep previously saved printers if discovery is unavailable.
    }

    final result = await showDialog<PrintSettings>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          Future<void> refreshPrinters() async {
            final found = await _detectPrintPrinters();
            if (!dialogContext.mounted) return;
            setState(() {
              detected = <PrintPrinterProfile>[
                ...{for (final item in detected) item.id: item}.values,
                ...{for (final item in found) item.id: item}.values,
              ];
              settings = settings.copyWith(printers: detected);
            });
          }

          return AlertDialog(
            title: Text(tr.text('print_settings')),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr.text('print_options_before_print')),
                      subtitle:
                          Text(tr.text('print_options_before_print_desc')),
                      value: settings.showOptionsBeforePrint,
                      onChanged: (value) => setState(() {
                        settings =
                            settings.copyWith(showOptionsBeforePrint: value);
                      }),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${tr.text('detected_printers')}: ${detected.length}',
                            style: Theme.of(dialogContext).textTheme.titleSmall,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: refreshPrinters,
                          icon: const Icon(Icons.refresh_outlined),
                          label: Text(tr.text('detect_printers')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...PrintDocumentKeys.all.map(
                      (key) => _buildDocumentPrintSetting(
                        dialogContext,
                        key,
                        settings,
                        detected,
                        (next) => setState(() => settings = next),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(tr.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(settings),
                child: Text(tr.text('save')),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      await store.updateStoreProfile(
        store.storeProfile.copyWith(printSettings: result),
      );
    }
  }

  Widget _buildDocumentPrintSetting(
    BuildContext context,
    String key,
    PrintSettings settings,
    List<PrintPrinterProfile> printers,
    ValueChanged<PrintSettings> onChanged,
  ) {
    final tr = AppLocalizations.of(context);
    final document = settings.forDocument(key);
    final compatible = printers
        .where((printer) => _printerSupportsFormat(printer, document.format))
        .toList(growable: false);
    final selectedPrinter =
        compatible.any((item) => item.id == document.printerId)
            ? document.printerId
            : '';

    void update(PrintDocumentSettings next) {
      final documents = <String, PrintDocumentSettings>{
        ...settings.documents,
        key: next,
      };
      onChanged(settings.copyWith(documents: documents));
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_printDocumentLabel(tr, key),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: document.format,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr.text('print_size'),
                      isDense: true,
                    ),
                    items: _formatsForDocument(key)
                        .map((format) => DropdownMenuItem<String>(
                              value: format,
                              child: Text(_printFormatLabel(tr, format)),
                            ))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      final nextPrinter = printers.any((item) =>
                              item.id == document.printerId &&
                              _printerSupportsFormat(item, value))
                          ? document.printerId
                          : '';
                      update(document.copyWith(
                        format: value,
                        printerId: nextPrinter,
                      ));
                    },
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedPrinter,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr.text('default_printer'),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: '',
                        child: Text(tr.text('system_default_printer')),
                      ),
                      ...compatible.map((printer) => DropdownMenuItem<String>(
                            value: printer.id,
                            child: Text(printer.name,
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (value) =>
                        update(document.copyWith(printerId: value ?? '')),
                  ),
                ),
                FilterChip(
                  label: Text(tr.text('automatic_printing')),
                  selected: document.directPrint,
                  onSelected: (value) =>
                      update(document.copyWith(directPrint: value)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _formatsForDocument(String key) {
    return PrintDocumentKeys.allowedFormatsFor(key);
  }

  bool _printerSupportsFormat(PrintPrinterProfile printer, String format) {
    if (PrintPaperFormats.isThermal(format)) return printer.isThermal;
    return printer.isSystem;
  }

  String _printDocumentLabel(AppLocalizations tr, String key) {
    const labels = <String, String>{
      PrintDocumentKeys.salesInvoice: 'sales_invoice',
      PrintDocumentKeys.salesReturn: 'sales_return',
      PrintDocumentKeys.thermalSalesInvoice: 'thermal_sales_invoice',
      PrintDocumentKeys.purchaseInvoice: 'purchase_invoice',
      PrintDocumentKeys.cashReceipt: 'cash_receipt',
      PrintDocumentKeys.cashShiftReport: 'cash_shift_report',
      PrintDocumentKeys.expense: 'expense',
      PrintDocumentKeys.accountStatement: 'account_statement',
      PrintDocumentKeys.expenseStatement: 'expense_statement',
      PrintDocumentKeys.report: 'reports',
      PrintDocumentKeys.quotation: 'quotations',
      PrintDocumentKeys.deliveryNote: 'delivery_notes',
      PrintDocumentKeys.priceList: 'price_list',
      PrintDocumentKeys.manufacturingBom: 'manufacturing_bom',
      PrintDocumentKeys.manufacturingOrder: 'manufacturing_order',
      PrintDocumentKeys.manufacturingOrders: 'manufacturing_orders',
      PrintDocumentKeys.warehouseInventory: 'warehouse_inventory',
      PrintDocumentKeys.warehouseTransfer: 'warehouse_transfer',
      PrintDocumentKeys.accountingPage: 'accounting',
      PrintDocumentKeys.shippingLabel: 'shipping_label',
    };
    final translationKey = labels[key];
    return translationKey == null ? key : tr.text(translationKey);
  }

  String _printFormatLabel(AppLocalizations tr, String format) {
    switch (format) {
      case PrintPaperFormats.thermal80:
        return '80 mm';
      case PrintPaperFormats.thermal58:
        return '58 mm';
      case PrintPaperFormats.shippingLabel:
        return '4 × 6 in';
      case PrintPaperFormats.a4:
      default:
        return 'PDF A4';
    }
  }
}
