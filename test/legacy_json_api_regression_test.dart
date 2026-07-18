import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy JSON data APIs stay out of runtime lib sources', () {
    final bannedPatterns = <String>[
      'LocalDatabaseService.getBusinessEntityListJson(',
      'LocalDatabaseService.getBusinessEntityListJsonBatches(',
      '_migrateBootstrapSharedPreferencesIfNeeded',
      '_loadRawData',
    ];

    final matches = <String, List<String>>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      final fileMatches = bannedPatterns
          .where(content.contains)
          .toList(growable: false);
      if (fileMatches.isNotEmpty) {
        matches[entity.path] = fileMatches;
      }
    }

    expect(
      matches,
      isEmpty,
      reason: 'Legacy JSON APIs should not appear in runtime lib sources.',
    );
  });
}
