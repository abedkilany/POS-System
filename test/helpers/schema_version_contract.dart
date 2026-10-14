import 'package:flutter_test/flutter_test.dart';

void expectSchemaVersionAtLeast(String source, int minimumVersion) {
  final schemaVersion = int.tryParse(
    RegExp(r'int get schemaVersion\s*=>\s*(\d+)\s*;')
            .firstMatch(source)
            ?.group(1) ??
        '',
  );
  expect(schemaVersion, isNotNull);
  expect(schemaVersion ?? 0, greaterThanOrEqualTo(minimumVersion));
}
