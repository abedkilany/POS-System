import 'package:flutter/material.dart';

import 'startup_timing_service.dart';

class PageTimingScope extends StatefulWidget {
  const PageTimingScope({
    super.key,
    required this.pageKey,
    required this.child,
    this.pageLabel = '',
    this.autoReady = true,
  });

  final String pageKey;
  final String pageLabel;
  final bool autoReady;
  final Widget child;

  @override
  State<PageTimingScope> createState() => _PageTimingScopeState();
}

class _PageTimingScopeState extends State<PageTimingScope> {
  bool _markedBuilt = false;
  bool _markedReady = false;

  @override
  void initState() {
    super.initState();
    StartupTimingService.markPageEntered(
      widget.pageKey,
      pageLabel: widget.pageLabel,
    );
  }

  @override
  void didUpdateWidget(covariant PageTimingScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageLabel != widget.pageLabel) {
      StartupTimingService.registerPage(
        pageKey: widget.pageKey,
        pageLabel: widget.pageLabel,
      );
    }
  }

  @override
  void dispose() {
    StartupTimingService.markPageExited(
      widget.pageKey,
      pageLabel: widget.pageLabel,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_markedBuilt) {
      _markedBuilt = true;
      StartupTimingService.markPageBuilt(
        widget.pageKey,
        pageLabel: widget.pageLabel,
      );
      if (widget.autoReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _markedReady) return;
          _markedReady = true;
          StartupTimingService.markPageReady(
            widget.pageKey,
            pageLabel: widget.pageLabel,
          );
        });
      }
    }
    return widget.child;
  }

  void markReadyNow({String details = ''}) {
    if (!mounted || _markedReady) return;
    _markedReady = true;
    StartupTimingService.markPageReady(
      widget.pageKey,
      pageLabel: widget.pageLabel,
      details: details,
    );
  }
}
