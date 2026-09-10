Ventio analyze fix 2026-09-09

Fixes:
- use_build_context_synchronously in manufacturing_page.dart (_printBom)
- Locale is captured before the async gap.

This patch does NOT contain assets or database files.
The remaining flutter analyze asset warnings are resolved by restoring the user's own assets/ directory next to pubspec.yaml.
