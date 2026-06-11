import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import 'unified_snapshot.dart';

/// Shared visual progress for all snapshot lifecycle operations.
///
/// Phase 3 keeps Connect, Restore publish, Repair, and Rebuild on the same
/// user-facing progress model. LAN and Cloud feed the same value/label stream;
/// the widget only presents the unified snapshot sections.
class UnifiedSnapshotProgressView extends StatelessWidget {
  const UnifiedSnapshotProgressView({
    super.key,
    required this.value,
    required this.label,
    this.titleKey = 'snapshot_progress_title',
    this.footerKey = 'snapshot_progress_keep_open',
  });

  final double? value;
  final String label;
  final String titleKey;
  final String footerKey;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final effectiveValue = value?.clamp(0.0, 1.0).toDouble();
    final activeIndex = _activeSectionIndex(effectiveValue);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_sync_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr.text(titleKey),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (effectiveValue != null) Text('${(effectiveValue * 100).round()}%'),
          ],
        ),
        const SizedBox(height: 12),
        Text(label.trim().isEmpty ? tr.text('snapshot_progress_preparing') : label),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: effectiveValue),
        const SizedBox(height: 14),
        ...List.generate(UnifiedSnapshotCatalog.sections.length, (index) {
          final section = UnifiedSnapshotCatalog.sections[index];
          final done = effectiveValue != null && effectiveValue >= _sectionEnd(index);
          final active = !done && index == activeIndex;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  done ? Icons.check_circle : active ? Icons.downloading_outlined : Icons.radio_button_unchecked,
                  size: 20,
                  color: done ? Colors.green : active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(tr.text(section.labelKey))),
                Text(
                  done
                      ? tr.text('snapshot_section_completed')
                      : active
                          ? tr.text('snapshot_section_in_progress')
                          : tr.text('snapshot_section_waiting'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 6),
        Text(tr.text(footerKey), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  int _activeSectionIndex(double? value) {
    if (value == null) return 0;
    final sections = UnifiedSnapshotCatalog.sections.length;
    if (value >= 0.86) return sections - 1;
    final normalized = ((value - 0.18) / 0.52).clamp(0.0, 0.999999);
    return (normalized * sections).floor().clamp(0, sections - 1);
  }

  double _sectionEnd(int index) {
    final sections = UnifiedSnapshotCatalog.sections.length;
    return 0.18 + ((index + 1) / sections) * 0.52;
  }
}
