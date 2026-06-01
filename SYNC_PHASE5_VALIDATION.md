# Sync Phase 5 Validation

Phase 5 is the hardening/verification pass for the Host-authoritative sync refactor.
It does not introduce a second sync path. It adds guardrails and test coverage around
the scenarios that must remain true after phases 1-4.

## Contract validated

1. Host may run LAN, Cloud, or both.
2. Client may keep LAN and Cloud configuration, but only one active transport may run.
3. Client draft changes become `submitted` after Cloud relay delivery, not `synced`.
4. Client draft changes become confirmed only after receiving a Host authoritative event.
5. Host authoritative events use Host sequence and a new event identity.
6. LAN receiver ACK is separate from applying/publishing a data change.
7. Delivery tracking records peer applied/ACK cursor and sequence.
8. Legacy LAN `/pull` and `/sync` endpoints remain disabled.
9. Old auto sync controllers remain unreferenced.

## Added files

- `test/sync_stage5_contract_test.dart`
  - Documents and tests the expected state machine and identity model.
- `tool/sync_stage5_audit.py`
  - Static regression audit for environments where Flutter/Dart tooling is not available.

## How to run

When the Flutter SDK is available:

```bash
flutter test test/sync_stage5_contract_test.dart
flutter test test/sync_and_permissions_test.dart test/mock_sync_server_test.dart
```

On packaging machines without Flutter/Dart, run the static guardrail audit:

```bash
python3 tool/sync_stage5_audit.py
```

## Manual scenario checklist

- Host LAN only + LAN Client: Client creates product, Host accepts, Client confirms after pull.
- Host Cloud only + Cloud Client: Client request stays submitted until Host publishes event.
- Host LAN + Cloud: Host-created sale reaches LAN and Cloud clients once.
- Transport switch on Client: disable current active transport before enabling the other.
- Offline Client draft: draft remains visible as pending/submitted until Host confirmation.
- Duplicate barcode/product code: Host rejects request and Client sees rejected state.
- Duplicate invoice number: Host rejects request and Client sees rejected state.
- Stock movement replay: repeated event does not apply stock quantity twice.
- Legacy LAN endpoint call: `/pull` and `/sync` return gone/disabled response.
