import 'package:flutter/material.dart';

import '../core/shortcuts/app_shortcuts.dart';

Future<String?> showShortcutKeyPicker({
  required BuildContext context,
  required String title,
  required String currentKey,
  required String noneLabel,
  required String cancelLabel,
  required String saveLabel,
}) {
  var selectedKey = SaleShortcutSettings.availableKeys.contains(currentKey)
      ? currentKey
      : SaleShortcutSettings.noneKey;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: DropdownButtonFormField<String>(
          initialValue: selectedKey,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.keyboard_outlined),
          ),
          items: [
            for (final keyName in SaleShortcutSettings.availableKeys)
              DropdownMenuItem(
                value: keyName,
                child: Text(keyName == SaleShortcutSettings.noneKey
                    ? noneLabel
                    : keyName),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => selectedKey = value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(selectedKey),
            child: Text(saveLabel),
          ),
        ],
      ),
    ),
  );
}

class ShortcutGuideChip extends StatelessWidget {
  const ShortcutGuideChip({
    super.key,
    required this.keyName,
    required this.label,
    required this.onPressed,
  });

  final String keyName;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.keyboard_outlined, size: 16),
      label: Text('$keyName $label'),
      onPressed: onPressed,
    );
  }
}
