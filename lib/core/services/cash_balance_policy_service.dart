import 'package:drift/drift.dart';

import '../../models/store_profile.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';

/// Authoritative store-wide policy for operational cash balances.
///
/// The per-location `allow_negative` column is legacy compatibility data only;
/// authorization comes exclusively from StoreProfile.allowNegativeCashBalance.
class CashBalancePolicyService {
  CashBalancePolicyService._();

  static StoreProfile _profile = StoreProfile.defaults;
  static const double _epsilon = 0.000001;

  static void configure(StoreProfile profile) {
    _profile = profile;
  }

  static bool get allowNegativeCashBalance =>
      _profile.allowNegativeCashBalance;

  static Future<void> ensureOutflowAllowed({
    required String cashLocationId,
    required double amount,
    VentioDriftDatabase? database,
  }) async {
    if (!amount.isFinite) {
      throw ArgumentError.value(amount, 'amount', 'Must be finite.');
    }
    if (allowNegativeCashBalance || amount <= 0) return;

    final id = cashLocationId.trim();
    if (id.isEmpty) {
      throw StateError('Cash location is unavailable.');
    }

    final db = database ?? SqliteMigrationManager.database;
    if (db == null) {
      throw StateError('SQLite database is not initialized.');
    }

    final row = await db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    if (row == null) {
      throw StateError('Cash location is unavailable.');
    }

    final balance = (row.data['current_balance'] as num?)?.toDouble() ?? 0.0;
    if (balance + _epsilon < amount) {
      throw StateError('Insufficient cash balance.');
    }
  }

  /// Applies the balance mutation and enforces DENY mode in the UPDATE itself.
  /// This is the final safety boundary: validation-only checks are useful for
  /// early errors, but no cash outflow should rely on a separate read alone.
  static Future<void> applyDelta({
    required String cashLocationId,
    required double delta,
    required String updatedAt,
    VentioDriftDatabase? database,
  }) async {
    if (!delta.isFinite) {
      throw ArgumentError.value(delta, 'delta', 'Must be finite.');
    }
    if (delta.abs() < _epsilon) return;
    final id = cashLocationId.trim();
    if (id.isEmpty) {
      throw StateError('Cash location is unavailable.');
    }
    final db = database ?? SqliteMigrationManager.database;
    if (db == null) {
      throw StateError('SQLite database is not initialized.');
    }

    final denyNegative = delta < 0 && !allowNegativeCashBalance;
    final updated = await db.customUpdate(
      denyNegative
          ? "UPDATE cash_locations SET current_balance = current_balance + ?, updated_at = ? WHERE id = ? AND deleted_at = '' AND is_active = 1 AND current_balance + ? >= ?"
          : "UPDATE cash_locations SET current_balance = current_balance + ?, updated_at = ? WHERE id = ? AND deleted_at = '' AND is_active = 1",
      variables: <Variable<Object>>[
        Variable<double>(delta),
        Variable<String>(updatedAt),
        Variable<String>(id),
        if (denyNegative) Variable<double>(delta),
        if (denyNegative) Variable<double>(-_epsilon),
      ],
    );
    if (updated == 1) return;

    final row = await db.customSelect(
      "SELECT current_balance FROM cash_locations WHERE id = ? AND deleted_at = '' AND is_active = 1 LIMIT 1",
      variables: <Variable<Object>>[Variable<String>(id)],
    ).getSingleOrNull();
    if (row == null) {
      throw StateError('Cash location is unavailable.');
    }
    if (denyNegative) {
      throw StateError('Insufficient cash balance.');
    }
    throw StateError('Cash balance update failed.');
  }
}
