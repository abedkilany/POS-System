import 'dart:math' as math;

import 'package:flutter/material.dart';

enum VentioScreenSize { compact, mobile, tablet, desktop }

class VentioResponsive {
  const VentioResponsive._();

  static const double compactBreakpoint = 380;
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1100;
  static const double maxContentWidth = 1280;

  static VentioScreenSize sizeForWidth(double width) {
    if (width < compactBreakpoint) return VentioScreenSize.compact;
    if (width < mobileBreakpoint) return VentioScreenSize.mobile;
    if (width < tabletBreakpoint) return VentioScreenSize.tablet;
    return VentioScreenSize.desktop;
  }

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactBreakpoint;
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletBreakpoint;

  static VentioScreenSize sizeOf(BuildContext context) =>
      sizeForWidth(MediaQuery.sizeOf(context).width);

  static T adaptive<T>(BuildContext context,
      {required T compact,
      required T mobile,
      required T tablet,
      required T desktop}) {
    switch (sizeOf(context)) {
      case VentioScreenSize.compact:
        return compact;
      case VentioScreenSize.mobile:
        return mobile;
      case VentioScreenSize.tablet:
        return tablet;
      case VentioScreenSize.desktop:
        return desktop;
    }
  }

  static double adaptiveWidth(BuildContext context,
      {required double mobile,
      required double tablet,
      required double desktop,
      double? compact}) {
    return adaptive<double>(context,
        compact: compact ?? mobile,
        mobile: mobile,
        tablet: tablet,
        desktop: desktop);
  }

  static double clampToScreen(BuildContext context, double preferred,
      {double min = 120, double horizontalPadding = 32}) {
    final available = MediaQuery.sizeOf(context).width - horizontalPadding;
    return preferred.clamp(min, available < min ? min : available).toDouble();
  }

  static double pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 340) return 8;
    if (width < compactBreakpoint) return 10;
    if (width < mobileBreakpoint) return 12;
    if (width < tabletBreakpoint) return 16;
    return 24;
  }

  static double cardPadding(BuildContext context) {
    return adaptiveWidth(context,
        compact: 10, mobile: 12, tablet: 16, desktop: 18);
  }

  static double gap(BuildContext context) {
    return adaptiveWidth(context,
        compact: 8, mobile: 10, tablet: 12, desktop: 16);
  }

  static EdgeInsets pageInsets(BuildContext context) =>
      EdgeInsets.all(pagePadding(context));

  static EdgeInsets cardInsets(BuildContext context) =>
      EdgeInsets.all(cardPadding(context));

  static double modalMaxWidth(BuildContext context, [double preferred = 560]) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final margin = pagePadding(context) * 2;
    return math.max(260, math.min(preferred, screenWidth - margin));
  }

  static double dialogSmallWidth(BuildContext context) {
    return clampToScreen(
      context,
      adaptiveWidth(context, mobile: 460, tablet: 520, desktop: 520),
    );
  }

  static double dialogMediumWidth(BuildContext context) {
    return clampToScreen(
      context,
      adaptiveWidth(context, mobile: 560, tablet: 720, desktop: 820),
    );
  }

  static double dialogLargeWidth(BuildContext context) {
    return clampToScreen(
      context,
      adaptiveWidth(context, mobile: 560, tablet: 860, desktop: 1040),
      horizontalPadding: pagePadding(context) * 2,
    );
  }

  static EdgeInsets dialogInsets(BuildContext context) {
    final horizontal = adaptiveWidth(
      context,
      compact: 12,
      mobile: 16,
      tablet: 24,
      desktop: 32,
    );
    final vertical = adaptiveWidth(
      context,
      compact: 12,
      mobile: 16,
      tablet: 24,
      desktop: 24,
    );
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }

  static BoxConstraints dialogConstraints(
    BuildContext context, {
    double? maxWidth,
  }) {
    return BoxConstraints(maxWidth: maxWidth ?? dialogLargeWidth(context));
  }

  static bool isWideDialogLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 900;
  }

  static int columnsForWidth(double width,
      {int mobile = 1, int tablet = 2, int desktop = 3}) {
    if (width < mobileBreakpoint) return mobile;
    if (width < tabletBreakpoint) return tablet;
    return desktop;
  }
}

class ResponsivePage extends StatelessWidget {
  const ResponsivePage(
      {super.key,
      required this.child,
      this.padding,
      this.maxWidth = VentioResponsive.maxContentWidth});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? VentioResponsive.pageInsets(context),
          child: child,
        ),
      ),
    );
  }
}

class ResponsiveDialogBox extends StatelessWidget {
  const ResponsiveDialogBox(
      {super.key, required this.child, this.maxWidth = 560, this.padding});

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final safeWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final inset = VentioResponsive.pagePadding(context);
        final targetWidth = math
            .max(260.0, math.min(maxWidth, safeWidth - (inset * 2)))
            .toDouble();
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: targetWidth),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Padding(
                padding: padding ?? EdgeInsets.all(inset), child: child),
          ),
        );
      },
    );
  }
}

class ResponsiveActionRow extends StatelessWidget {
  const ResponsiveActionRow({super.key, required this.children, this.spacing});

  final List<Widget> children;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final gap = spacing ?? VentioResponsive.gap(context);
    if (VentioResponsive.isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    }
    return Wrap(
        spacing: gap,
        runSpacing: gap,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children);
  }
}

class ResponsiveTwoPane extends StatelessWidget {
  const ResponsiveTwoPane(
      {super.key,
      required this.first,
      required this.second,
      this.breakpoint = 900,
      this.gap});

  final Widget first;
  final Widget second;
  final double breakpoint;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final spacing = gap ?? VentioResponsive.gap(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, SizedBox(height: spacing), second]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: first),
          SizedBox(width: spacing),
          Expanded(child: second)
        ]);
      },
    );
  }
}

class ResponsiveFormGrid extends StatelessWidget {
  const ResponsiveFormGrid(
      {super.key,
      required this.children,
      this.breakpoint = 760,
      this.spacing = 12});

  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= breakpoint;
        if (!isWide) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
