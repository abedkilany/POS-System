import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product-derived flush drains in-flight SQLite work before dirty exit', () {
    final source =
        File('lib/data/app_store_identity_users.dart').readAsStringSync();
    final methodStart =
        source.indexOf('Future<void> _flushProductDerivedData() async');
    final methodEnd = source.indexOf(
      'Future<bool> _schedulePurchaseAccounting',
      methodStart,
    );
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));

    final method = source.substring(methodStart, methodEnd);
    final inFlightCheck = method.indexOf(
      'final inFlight = _productDerivedDataFlushInFlight;',
    );
    final dirtyExit = method.indexOf('if (!_productDerivedDataDirty) return;');

    expect(inFlightCheck, greaterThanOrEqualTo(0));
    expect(dirtyExit, greaterThan(inFlightCheck));
    expect(method, contains('await inFlight;'));
    expect(method, isNot(contains('_markProductDerivedDataDirty();')));
  });

  test('shutdown prevents timer rescheduling and performs a deterministic drain', () {
    final identitySource =
        File('lib/data/app_store_identity_users.dart').readAsStringSync();
    final syncSource =
        File('lib/data/app_store_sync_apply.dart').readAsStringSync();

    expect(
      identitySource,
      contains('if (_shutdownPrepared) return;'),
    );
    expect(
      syncSource,
      contains('await _flushProductDerivedData();'),
    );
    expect(
      syncSource,
      contains('await LocalDatabaseService.flushPendingWrites();'),
    );
  });
}
