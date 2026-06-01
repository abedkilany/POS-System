#!/usr/bin/env python3
"""Static guardrails for Ventio Host-authoritative sync stage 5.

This script intentionally performs source-level checks that are cheap to run in
CI or before shipping a build. It does not replace Flutter tests; it catches the
regressions that previously broke the sync contract while the full Dart toolchain
is not always available on every packaging machine.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    path = ROOT / rel
    if not path.exists():
        raise AssertionError(f"Missing required file: {rel}")
    return path.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_contains(rel: str, needle: str, message: str) -> None:
    require(needle in read(rel), message)


def main() -> int:
    app_store = read("lib/data/app_store.dart")
    queue = read("lib/models/sync_queue_item.dart")
    cloud = read("lib/core/services/cloud_sync_service.dart")
    lan = read("lib/core/services/lan_sync_service_io.dart")
    core = read("lib/core/services/unified_sync_core_service.dart")
    engine = read("lib/core/sync_unified/unified_sync_engine.dart")

    # Stage 1 guardrails.
    require("status == 'submitted'" in queue, "SyncQueueItem must support submitted state.")
    require("target == 'cloud_host'" in cloud and "markPushSubmitted" in cloud,
            "Cloud Client relay ACK must mark cloud_host drafts submitted, not synced.")
    require("Host confirmation rule" in core and "sourceCommandId" in core,
            "Authoritative Host events must resolve submitted drafts by original command/request ids.")

    # Stage 2 guardrails.
    for key in ("requestId", "eventId", "sourceCommandId", "kind': 'authoritativeEvent'", "sequence: _nextSyncSequence()"):
        require(key in app_store, f"Missing Host-authoritative identity/sequence marker: {key}")
    require("_isReplayOrDuplicateSyncEvent" in app_store, "Duplicate/replay protection guard is missing.")
    require("lastAppliedSequence" in app_store, "Replay guard must use Host sequence cursor.")

    # Stage 3 guardrails.
    require("/changes/ack" in lan, "LAN receiver ACK endpoint must exist.")
    require("recordPeerSyncResult" in lan, "Delivery tracking must record peer sync state.")
    require("validateClientDraftForHostAcceptance" in app_store, "Host must validate Client drafts before acceptance.")
    require("markSyncChangesRejectedByIds" in app_store, "Rejected requests must remain visible to the Client.")

    # Stage 4 guardrails.
    require("Legacy LAN Sync V1 endpoints are intentionally disabled" in lan,
            "Legacy LAN /pull and /sync endpoints must stay disabled.")
    require("UnifiedSyncEngine" in engine and "transport.pushPending" in engine and "transport.pullChanges" in engine,
            "Unified sync engine must remain the orchestration path.")

    # Regression scans.
    forbidden_imports = []
    for path in (ROOT / "lib").rglob("*.dart"):
        text = path.read_text(encoding="utf-8")
        if "AutoLanSyncController" in text and "UnifiedAutoLanSyncController" not in text:
            forbidden_imports.append(str(path.relative_to(ROOT)))
        if "AutoCloudSyncController" in text and "UnifiedAutoCloudSyncController" not in text:
            forbidden_imports.append(str(path.relative_to(ROOT)))
    require(not forbidden_imports, "Old auto sync controllers are referenced: " + ", ".join(forbidden_imports))

    # Make sure cloud_host is not acknowledged through the final synced path in
    # the same branch. This catches accidental reversal of the Stage 1 fix.
    cloud_host_branch = re.search(r"if \(target == 'cloud_host'\) \{(?P<body>.*?)\} else \{(?P<else>.*?)\}", cloud, re.S)
    require(cloud_host_branch is not None, "cloud_host branch not found in Cloud push flow.")
    require("markPushSubmitted" in cloud_host_branch.group("body"), "cloud_host branch must mark submitted.")
    require("markPushAcknowledged" not in cloud_host_branch.group("body"), "cloud_host branch must not mark acknowledged/synced.")

    print("Sync stage 5 audit passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"Sync stage 5 audit failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
