# Pure DB-First Contract

This document defines the target storage model for Ventio.

## Runtime Rule

SQLite is the only source of truth for normal app runtime on native/mobile/desktop.

## Allowed Exceptions

- One-time migration from older app data.
- Backup import and restore flows.
- Test-only memory stores and mocks.
- Platform-specific web shims only if they are not treated as the production source of truth.

## Not Allowed In Runtime

- Using `SharedPreferences` as a business data store.
- Using legacy JSON blobs as the primary runtime store.
- Falling back to old storage paths when SQLite is available.

## Phase Plan

1. Stabilize the contract and acceptance rules.
2. Remove legacy bootstrap paths.
3. Consolidate runtime storage around SQLite only.
4. Remove legacy compatibility from normal runtime paths.
5. Lock the contract with regression checks.

## Acceptance Criteria

- App startup declares DB-first mode explicitly.
- Normal data reads and writes hit SQLite.
- Legacy paths remain only in migration, import, restore, or tests.
- Any source-level audit should find the old paths only in the allowed exceptions.
