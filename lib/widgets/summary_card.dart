import 'package:flutter/material.dart';

import '../core/utils/responsive.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.title, required this.value, required this.icon});

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 240.0;
        final compact = width < 220;
        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: compact ? 0 : 180, maxWidth: VentioResponsive.adaptiveWidth(context, mobile: double.infinity, tablet: 320, desktop: 340)),
          child: Card(
            child: Padding(
              padding: VentioResponsive.cardInsets(context),
              child: Row(
                children: [
                  CircleAvatar(radius: compact ? 20 : 24, child: Icon(icon, size: compact ? 20 : 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            value,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
