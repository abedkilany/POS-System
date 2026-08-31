import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('posted snapshot backfill writes only typed snapshot columns', () {
    final source =
        File('lib/data/app_store_startup_migrations.dart').readAsStringSync();

    expect(
      source,
      contains(
        "UPDATE sales SET posted_snapshot_json = ? WHERE id = ? AND posted_snapshot_json = ''",
      ),
    );
    expect(
      source,
      contains(
        "UPDATE purchases SET posted_snapshot_json = ? WHERE id = ? AND posted_snapshot_json = ''",
      ),
    );
    expect(
      source,
      isNot(contains('posted_snapshot_json = ?, payload_json = ?')),
    );
  });
}
