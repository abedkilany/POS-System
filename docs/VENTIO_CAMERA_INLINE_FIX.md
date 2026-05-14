# Ventio Camera Inline Fix

- Reviewed `lib/features/sales/sales_page.dart`.
- Sales no longer calls `BarcodeScannerPage` or opens a camera route from the sales camera button.
- The mobile camera scanner is now rendered as a dedicated inline `Card` inside the Sales page controls.
- The scanner preview is no longer injected inside the barcode input station on mobile; this avoids the UI feeling like a floating/pop-up block.
- The inline scanner remains active for continuous barcode reads, with duplicate suppression, sound, and haptic feedback.

Note: a native camera permission prompt may still appear the first time Android/iOS asks for camera access. That is an OS permission dialog, not the scanner page.
