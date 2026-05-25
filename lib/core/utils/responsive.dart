import 'package:flutter/material.dart';

enum VentioScreenSize { mobile, tablet, desktop }

class VentioResponsive {
  const VentioResponsive._();

  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1100;

  static VentioScreenSize sizeForWidth(double width) {
    if (width < mobileBreakpoint) return VentioScreenSize.mobile;
    if (width < tabletBreakpoint) return VentioScreenSize.tablet;
    return VentioScreenSize.desktop;
  }

  static bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < mobileBreakpoint;
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= tabletBreakpoint;

  static VentioScreenSize sizeOf(BuildContext context) => sizeForWidth(MediaQuery.sizeOf(context).width);

  static double adaptiveWidth(BuildContext context, {required double mobile, required double tablet, required double desktop}) {
    switch (sizeOf(context)) {
      case VentioScreenSize.mobile:
        return mobile;
      case VentioScreenSize.tablet:
        return tablet;
      case VentioScreenSize.desktop:
        return desktop;
    }
  }

  static double clampToScreen(BuildContext context, double preferred, {double min = 120, double horizontalPadding = 32}) {
    final available = MediaQuery.sizeOf(context).width - horizontalPadding;
    return preferred.clamp(min, available < min ? min : available).toDouble();
  }

  static double pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 380) return 8;
    if (width < mobileBreakpoint) return 12;
    if (width < tabletBreakpoint) return 16;
    return 24;
  }
}

class ResponsiveDialogBox extends StatelessWidget {
  const ResponsiveDialogBox({super.key, required this.child, this.maxWidth = 560, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final safeWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
        final targetWidth = safeWidth < maxWidth + 32 ? safeWidth - 32 : maxWidth;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: targetWidth.clamp(260, maxWidth).toDouble()),
          child: SingleChildScrollView(child: Padding(padding: padding, child: child)),
        );
      },
    );
  }
}
