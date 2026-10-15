part of 'dashboard_page.dart';

class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: AppLocalizations.of(context).text('quick_actions'),
            icon: Icons.flash_on_rounded,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 6
                  : constraints.maxWidth >= 620
                      ? 3
                      : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: actions.map((action) {
                  return _QuickActionTile(
                    width: width,
                    action: action,
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatefulWidget {
  const _QuickActionTile({
    required this.width,
    required this.action,
    required this.textStyle,
  });

  final double width;
  final _QuickAction action;
  final TextStyle? textStyle;

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final baseFill = action.color.withValues(alpha: 0.075);
    final hoverFill = action.color.withValues(alpha: 0.14);
    final baseBorder = action.color.withValues(alpha: 0.10);
    final hoverBorder = action.color.withValues(alpha: 0.28);
    final shadowColor = action.color.withValues(alpha: _hovered ? 0.22 : 0.08);

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (_hovered) return;
          setState(() => _hovered = true);
        },
        onExit: (_) {
          if (!_hovered) return;
          setState(() => _hovered = false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: _hovered ? hoverFill : baseFill,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _hovered ? hoverBorder : baseBorder,
              width: _hovered ? 1.4 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: _hovered ? 18 : 8,
                offset: Offset(0, _hovered ? 8 : 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: action.onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      scale: _hovered ? 1.05 : 1,
                      child: _IconBubble(
                        icon: action.icon,
                        color: action.color,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      style: widget.textStyle?.copyWith(
                            color: _hovered
                                ? Theme.of(context).colorScheme.onSurface
                                : widget.textStyle?.color,
                          ) ??
                          DefaultTextStyle.of(context).style,
                      child: Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MainChartPanel extends StatelessWidget {
  const _MainChartPanel({
    required this.series,
    required this.title,
    required this.formatValue,
    required this.emptyLabel,
  });

  final DashboardChartSeries? series;
  final String title;
  final String Function(DashboardChartItem item) formatValue;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    final items = series?.items ?? const <DashboardChartItem>[];
    return _PremiumSurface(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, icon: Icons.show_chart_rounded),
          const SizedBox(height: 18),
          if (items.isEmpty)
            SizedBox(height: 260, child: Center(child: Text(emptyLabel)))
          else ...[
            SizedBox(
              height: 260,
              child: _LineChart(items: items),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items.take(7).map((item) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${localizeRuntimeMessage(item.label, tr)}  ${formatValue(item)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({
    required this.title,
    required this.clearText,
    required this.alerts,
    required this.statusColor,
  });

  final String title;
  final String clearText;
  final List<DashboardAlertItem> alerts;
  final Color Function(DashboardStatusLevel level) statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: title, icon: Icons.notifications_active_outlined),
          const SizedBox(height: 14),
          if (alerts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                clearText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF16A34A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ...alerts.take(5).map((alert) {
              final color = statusColor(alert.level);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.075),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color.withValues(alpha: 0.10)),
                  ),
                  child: Row(
                    children: [
                      _IconBubble(icon: alert.icon, color: color, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizeRuntimeMessage(alert.title, tr),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              localizeRuntimeMessage(alert.message, tr),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _FinancialSummaryPanel extends StatelessWidget {
  const _FinancialSummaryPanel({
    required this.title,
    required this.items,
    required this.labelBuilder,
    required this.moneyBuilder,
    required this.statusColor,
  });

  final String title;
  final List<DashboardFinancialItem> items;
  final String Function(DashboardFinancialItem item) labelBuilder;
  final String Function(double value) moneyBuilder;
  final Color Function(DashboardStatusLevel level) statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: title, icon: Icons.account_balance_wallet_outlined),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 5
                  : constraints.maxWidth >= 680
                      ? 3
                      : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items.map((item) {
                  final color = statusColor(item.level);
                  return SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.055),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: color.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          _IconBubble(icon: item.icon, color: color, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  labelBuilder(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  moneyBuilder(item.amount),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OperationsPanel extends StatelessWidget {
  const _OperationsPanel({
    required this.title,
    required this.emptyText,
    required this.operations,
    required this.operationIcon,
    required this.moneyBuilder,
    required this.dateBuilder,
  });

  final String title;
  final String emptyText;
  final List<DashboardOperationItem> operations;
  final IconData Function(DashboardOperationType type) operationIcon;
  final String Function(double value) moneyBuilder;
  final String Function(DateTime value) dateBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, icon: Icons.history_rounded),
          const SizedBox(height: 14),
          if (operations.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(emptyText),
            )
          else
            ...operations.take(6).map((operation) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconBubble(
                      icon: operationIcon(operation.type),
                      color: scheme.primary,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  operation.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                moneyBuilder(operation.amount),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${operation.subtitle} · ${dateBuilder(operation.at)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _SystemStatusData {
  const _SystemStatusData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
}

class _SystemStatusPanel extends StatelessWidget {
  const _SystemStatusPanel({required this.title, required this.items});

  final String title;
  final List<_SystemStatusData> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PremiumSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, icon: Icons.verified_outlined),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 5
                  : constraints.maxWidth >= 720
                      ? 3
                      : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items.map((item) {
                  return SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: item.color.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        children: [
                          _IconBubble(
                              icon: item.icon, color: item.color, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PremiumSurface extends StatelessWidget {
  const _PremiumSurface({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(30),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: _softShadow(context),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({
    required this.icon,
    required this.color,
    this.size = 48,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.105),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.items});

  final List<DashboardChartItem> items;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(
        items: items,
        color: Theme.of(context).colorScheme.primary,
        gridColor: Theme.of(context).colorScheme.outlineVariant,
      ),
      child: const SizedBox.expand(),
    );
  }
}
