import 'package:flutter/foundation.dart' show Listenable;

import '../repositories/business_session_context.dart';
import 'domain_ports.dart';
export 'domain_ports.dart';

/// Runtime services depend on capabilities, never the concrete AppStore.
abstract interface class SyncSession implements Listenable {
  SecurityDomainPort get security;
  AppRuntimeDomainPort get runtime;
  SyncDomainPort get sync;
  RecoveryDomainPort get recovery;
}

abstract interface class AuthenticationSession {
  AppRuntimeDomainPort get runtime;
  SecurityDomainPort get security;
  SyncDomainPort get sync;
}

abstract interface class BackupSession {
  AppRuntimeDomainPort get runtime;
  RecoveryDomainPort get recovery;
}

/// Application composition contract. Prefer a single domain port in a leaf
/// component; use this session only when coordinating multiple domains.
abstract interface class ApplicationSession
    implements
        SyncSession,
        AuthenticationSession,
        BackupSession,
        BusinessSessionContext {
  CatalogDomainPort get catalog;
  CommerceDomainPort get commerce;
  AccountingDomainPort get accounting;
  InventoryDomainPort get inventory;
}
