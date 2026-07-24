import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/core/sync_unified/sync_contracts.dart';
import 'package:ventio/core/sync_unified/unified_sync_transport_helpers.dart';

void main() {
  group('UnifiedSyncTransportHelpers', () {
    test('classifies unsupported messages the same way for every transport',
        () {
      final error = UnifiedSyncTransportHelpers.classifyError(
        false,
        'Cloud relay is not supported on this platform.',
      );

      expect(error.code, UnifiedSyncErrorCode.unsupported);
      expect(
          error.userMessage, 'Cloud relay is not supported on this platform.');
      expect(
          error.debugMessage, 'Cloud relay is not supported on this platform.');
    });

    test('classifies authorization and conflict errors consistently', () {
      final unauthorized = UnifiedSyncTransportHelpers.classifyError(
        false,
        '401 Unauthorized',
      );
      final conflict = UnifiedSyncTransportHelpers.classifyError(
        false,
        '409 Conflict detected',
      );

      expect(unauthorized.code, UnifiedSyncErrorCode.unauthorized);
      expect(conflict.code, UnifiedSyncErrorCode.conflict);
    });
  });
}
