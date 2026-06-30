import 'package:flutter/material.dart';

class PageDataLoadIndicator extends StatelessWidget {
  const PageDataLoadIndicator({
    super.key,
    required this.loadedCount,
    required this.totalCount,
    this.label = '',
    this.iconSize = 16,
  });

  final int loadedCount;
  final int totalCount;
  final String label;
  final double iconSize;

  bool get _isComplete => totalCount <= 0 || loadedCount >= totalCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final complete = _isComplete;
    final color = complete ? const Color(0xFF16A34A) : colorScheme.primary;
    final icon = complete ? Icons.check_circle_outline : Icons.hourglass_top;
    final tooltip = label.isNotEmpty
        ? label
        : complete
            ? 'Data ready'
            : 'Preparing $loadedCount of $totalCount';

    return Tooltip(
      message: tooltip,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Icon(
          icon,
          key: ValueKey<bool>(complete),
          size: iconSize,
          color: color,
        ),
      ),
    );
  }
}
