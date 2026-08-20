import 'package:flutter/material.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: (compact
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.headlineSmall)
                ?.copyWith(fontWeight: FontWeight.bold)),
        SizedBox(height: compact ? 1 : 4),
        Text(subtitle,
            style: compact ? Theme.of(context).textTheme.bodySmall : null),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              textBlock,
              if (action != null) ...[
                SizedBox(height: compact ? 4 : 12),
                Align(alignment: AlignmentDirectional.centerStart, child: action!),
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: textBlock),
            if (action != null) action!,
          ],
        );
      },
    );
  }
}
