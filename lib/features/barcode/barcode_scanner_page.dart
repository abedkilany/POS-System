import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/barcode_feedback_service.dart';
import '../../core/utils/responsive.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({
    super.key,
    this.title = 'Scan barcode',
    this.helpText =
        'Point the camera at the product barcode. The code will be filled automatically.',
    this.formats,
  });

  final String title;
  final String helpText;
  final List<BarcodeFormat>? formats;

  static bool get isSupportedPlatform =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  MobileScannerController? _controller;

  bool _handled = false;

  @override
  void initState() {
    super.initState();
    if (!BarcodeScannerPage.isSupportedPlatform) return;
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: widget.formats ??
          const [
            BarcodeFormat.aztec,
            BarcodeFormat.codabar,
            BarcodeFormat.code128,
            BarcodeFormat.code39,
            BarcodeFormat.code93,
            BarcodeFormat.dataMatrix,
            BarcodeFormat.ean13,
            BarcodeFormat.ean8,
            BarcodeFormat.itf14,
            BarcodeFormat.pdf417,
            BarcodeFormat.qrCode,
            BarcodeFormat.upcA,
            BarcodeFormat.upcE,
          ],
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || code.isEmpty) continue;
      _handled = true;
      unawaited(BarcodeFeedbackService.play());
      Navigator.of(context).pop(code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final controller = _controller;
    if (!BarcodeScannerPage.isSupportedPlatform || controller == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title == 'Scan barcode'
              ? tr.text('scan_barcode_title')
              : widget.title),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  tr.text('camera_scanner_not_supported'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  tr.text('camera_scanner_not_supported_desc'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title == 'Scan barcode'
            ? AppLocalizations.of(context).text('scan_barcode_title')
            : widget.title),
        actions: [
          IconButton(
            tooltip: tr.text('flash'),
            onPressed: () => controller.toggleTorch(),
            icon: const Icon(Icons.flash_on_outlined),
          ),
          IconButton(
            tooltip: tr.text('switch_camera'),
            onPressed: () => controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: controller, onDetect: _handleDetect),
          IgnorePointer(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final frameWidth = VentioResponsive.clampToScreen(
                    context,
                    constraints.maxWidth * 0.70,
                    min: 180,
                    horizontalPadding: 48,
                  );
                  return Container(
                    width: frameWidth,
                    height: (frameWidth * 0.62).clamp(110, 180).toDouble(),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.90),
              child: Padding(
                padding: VentioResponsive.cardInsets(context),
                child: Text(
                  widget.helpText ==
                          'Point the camera at the product barcode. The code will be filled automatically.'
                      ? AppLocalizations.of(context).text('scan_barcode_help')
                      : widget.helpText,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
