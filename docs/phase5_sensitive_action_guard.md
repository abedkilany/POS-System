# Phase 5 — Authentication & Sensitive Action Guard

## Status
Implemented on the P0–P3 baseline.

## Domain guard
Ventio now has an action-scoped, in-memory re-authentication grant. A successful password challenge grants only the requested sensitive action for three minutes and is bound to the active user. Login/logout/session changes clear the grant.

Protected operations include:
- Backup restore.
- User and role mutations.
- Sale reversal/return/cancellation paths.
- Purchase reversal/return/cancellation paths.
- Destructive database/reset actions.
- Store-owner credential changes.

The guard lives in the AppStore/domain layer so a different UI path cannot bypass it merely by skipping a dialog.

## Authentication hardening
- Local login failures are throttled: repeated failures inside a five-minute window trigger a short local lockout.
- New/changed local passwords use a six-character minimum floor where this workflow already enforced a minimum.
- Re-authentication success/failure and important account mutations are written to the audit log without recording passwords or password hashes.
- The database editor requires recent re-authentication for writes and records destructive/manual write activity.

## Test accommodation
Explicit in-memory/attached SQLite test stores bypass the interactive sensitive-action challenge so existing domain tests can exercise business behavior without UI credentials. Production stores do not use this bypass.
