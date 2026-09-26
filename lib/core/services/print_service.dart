import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../localization/app_localizations.dart';
import '../../models/print_settings.dart';
import '../../models/store_profile.dart';

class PrintSelection {
  const PrintSelection({
    required this.format,
    required this.printerId,
    required this.directPrint,
    required this.copies,
  });

  final String format;
  final String printerId;
  final bool directPrint;
  final int copies;
}

/// Centralizes the print preference behavior used by every non-barcode print
/// action. Barcode labels intentionally keep their own specialized workflow.
class PrintService {
  static Future<PrintSelection> resolveSelection({
    required BuildContext? context,
    required StoreProfile profile,
    required String documentKey,
    required List<String> allowedFormats,
  }) async {
    final defaults = profile.printSettings.forDocument(documentKey);
    final safeFormat = allowedFormats.contains(defaults.format)
        ? defaults.format
        : allowedFormats.first;
    final initial = PrintSelection(
      format: safeFormat,
      printerId: defaults.printerId,
      directPrint: defaults.directPrint,
      copies: defaults.copies,
    );

    if (!profile.printSettings.showOptionsBeforePrint || context == null) {
      return initial;
    }

    final selected = await showDialog<PrintSelection>(
      context: context,
      builder: (dialogContext) => _PrintSelectionDialog(
        profile: profile,
        documentKey: documentKey,
        initial: initial,
        allowedFormats: allowedFormats,
      ),
    );
    return selected ?? initial;
  }

  static Future<void> printPdf({
    required BuildContext? context,
    required StoreProfile profile,
    required String documentKey,
    Uint8List? bytes,
    Future<Uint8List> Function(PrintSelection selection)? bytesBuilder,
    required String name,
    required PdfPageFormat defaultFormat,
    List<String>? allowedFormats,
  }) async {
    final formats =
        allowedFormats ?? PrintDocumentKeys.allowedFormatsFor(documentKey);
    final selection = await resolveSelection(
      context: context,
      profile: profile,
      documentKey: documentKey,
      allowedFormats: formats,
    );
    final configuredPrinter = profile.printSettings.printerById(
      selection.printerId,
    );
    final format = pageFormatFor(selection.format, fallback: defaultFormat);
    final outputBytes =
        bytesBuilder == null ? bytes : await bytesBuilder(selection);
    if (outputBytes == null) {
      throw ArgumentError('Print content is missing.');
    }

    Future<Uint8List> onLayout(PdfPageFormat _) async => outputBytes;

    if (selection.directPrint && configuredPrinter != null) {
      final printer = Printer(
        url: configuredPrinter.url,
        name: configuredPrinter.name,
      );
      final info = await Printing.info();
      if (info.directPrint) {
        for (var copy = 0; copy < selection.copies; copy++) {
          await Printing.directPrintPdf(
            printer: printer,
            onLayout: onLayout,
            name: name,
            format: format,
            usePrinterSettings: false,
            forceCustomPrintPaper: true,
          );
        }
        return;
      }
    }

    await Printing.layoutPdf(
      onLayout: onLayout,
      name: name,
      format: format,
      dynamicLayout: false,
    );
  }

  static PdfPageFormat pageFormatFor(
    String format, {
    required PdfPageFormat fallback,
  }) {
    switch (format) {
      case PrintPaperFormats.mm80:
        return const PdfPageFormat(
            80 * PdfPageFormat.mm, 180 * PdfPageFormat.mm);
      case PrintPaperFormats.mm58:
        return const PdfPageFormat(
            58 * PdfPageFormat.mm, 180 * PdfPageFormat.mm);
      case PrintPaperFormats.shippingLabel:
        return const PdfPageFormat(
            102 * PdfPageFormat.mm, 152 * PdfPageFormat.mm);
      case PrintPaperFormats.a4:
      default:
        return fallback;
    }
  }
}

class _PrintSelectionDialog extends StatefulWidget {
  const _PrintSelectionDialog({
    required this.profile,
    required this.documentKey,
    required this.initial,
    required this.allowedFormats,
  });

  final StoreProfile profile;
  final String documentKey;
  final PrintSelection initial;
  final List<String> allowedFormats;

  @override
  State<_PrintSelectionDialog> createState() => _PrintSelectionDialogState();
}

class _PrintSelectionDialogState extends State<_PrintSelectionDialog> {
  late String _format;
  late String _printerId;
  late bool _directPrint;
  late int _copies;

  @override
  void initState() {
    super.initState();
    _format = widget.initial.format;
    _printerId = widget.initial.printerId;
    _directPrint = widget.initial.directPrint;
    _copies = widget.initial.copies;
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final printers = widget.profile.printSettings.printers;
    final selectedPrinter =
        printers.any((item) => item.id == _printerId) ? _printerId : '';

    return AlertDialog(
      title: Text(tr.text('print_settings')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _format,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr.text('print_size')),
              items: widget.allowedFormats
                  .map((format) => DropdownMenuItem<String>(
                        value: format,
                        child: Text(_formatLabel(format)),
                      ))
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _format = value;
                  if (!printers.any((item) => item.id == _printerId)) {
                    _printerId = '';
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedPrinter,
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: tr.text('default_printer')),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(tr.text('system_default_printer')),
                ),
                ...printers.map((printer) => DropdownMenuItem<String>(
                      value: printer.id,
                      child:
                          Text(printer.name, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (value) => setState(() => _printerId = value ?? ''),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.text('automatic_printing')),
              value: _directPrint,
              onChanged: (value) => setState(() => _directPrint = value),
            ),
            DropdownButtonFormField<int>(
              initialValue: _copies,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr.text('copies')),
              items: List<int>.generate(99, (index) => index + 1)
                  .map((value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      ))
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _copies = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(PrintSelection(
            format: _format,
            printerId: _printerId,
            directPrint: _directPrint,
            copies: _copies,
          )),
          child: Text(tr.text('print')),
        ),
      ],
    );
  }

  String _formatLabel(String format) {
    switch (format) {
      case PrintPaperFormats.mm80:
        return '80 mm';
      case PrintPaperFormats.mm58:
        return '58 mm';
      case PrintPaperFormats.shippingLabel:
        return 'Shipping label 4 × 6 in';
      case PrintPaperFormats.a4:
      default:
        return 'PDF A4';
    }
  }
}
