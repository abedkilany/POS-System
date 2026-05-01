import 'dart:async';

import '../../data/app_store.dart';
import '../../models/app_identity.dart';

class CloudSyncSettings {
  const CloudSyncSettings({
    required this.enabled,
    required this.apiBaseUrl,
    required this.apiToken,
  });

  final bool enabled;
  final String apiBaseUrl;
  final String apiToken;

  bool get isConfigured => enabled && apiBaseUrl.trim().isNotEmpty && apiToken.trim().isNotEmpty;
}

class CloudSyncResult {
  const CloudSyncResult({required this.ok, required this.message});
  final bool ok;
  final String message;
}

/// Cloud sync foundation.
///
/// The marketplace must talk to the Host only. This service intentionally keeps
/// the contract in one place so the future Vercel/Neon API can reuse the same
/// local changelog used by LAN sync:
///
/// Client devices -> Windows Host -> Cloud API -> Neon/PostgreSQL.
class CloudSyncService {
  CloudSyncService(this.store);

  final AppStore store;

  Future<CloudSyncResult> syncNow(CloudSyncSettings settings) async {
    final identity = store.appIdentity;
    if (!identity.isHost) {
      return const CloudSyncResult(
        ok: false,
        message: 'Cloud sync is allowed from the Host device only.',
      );
    }
    if (identity.syncMode == SyncMode.localOnly || identity.syncMode == SyncMode.lanOnly) {
      return const CloudSyncResult(
        ok: false,
        message: 'Enable cloudConnected or marketplaceEnabled sync mode first.',
      );
    }
    if (!settings.isConfigured) {
      return const CloudSyncResult(
        ok: false,
        message: 'Cloud API settings are not configured yet.',
      );
    }

    // Placeholder for the next milestone: POST pending SyncChange rows to the
    // backend, receive acknowledgements, then pull marketplace orders/updates.
    return CloudSyncResult(
      ok: true,
      message: 'Cloud sync foundation is ready. Pending changes: ${store.pendingSyncCount}.',
    );
  }
}
