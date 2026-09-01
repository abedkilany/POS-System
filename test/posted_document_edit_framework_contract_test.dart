import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('posted document edit framework executes the safety contract in order', () {
    final source = File(
      'lib/core/services/posted_document_edit_framework.dart',
    ).readAsStringSync();
    final executeStart = source.indexOf('Future<T> execute() async {');
    expect(executeStart, isNonNegative);
    final execute = source.substring(executeStart);

    final steps = <String>[
      'loadAuthoritative()',
      'validatePermission(current)',
      'validateVersion(current)',
      'validateDependencies(current)',
      'reverseOperationalEffects(current)',
      'reverseAccountingEffects(current)',
      'applyChanges(current)',
      'rebuildOperationalEffects(updated)',
      'buildPostedSnapshot(updated)',
      'repostAccounting(updated)',
      'rebuildDerivedState(updated)',
      'verifyIntegrity(updated)',
    ];

    var previous = -1;
    for (final step in steps) {
      final index = execute.indexOf(step);
      expect(index, greaterThan(previous), reason: '$step must keep contract order');
      previous = index;
    }
  });
}
