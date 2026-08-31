# P11 Stress Lab sensitive-action authorization fix

## Symptom
A clean Windows build failed the Real User Scenario after Phase 5 sensitive-action guards were enabled. Sale and purchase return/cancel operations threw `SensitiveActionAuthRequiredException`, which cascaded into refund, stock reconciliation, persistence, and Unified Batch certification failures.

## Root cause
Stress Lab intentionally uses the same AppStore mutation paths as the UI, but it had not been updated to perform the fresh password proof now required for `sales.reverse` and `purchases.reverse`.

## Fix
- Ask the currently signed-in user for their password once before a Real User Scenario run.
- Authorize only `purchases.reverse` and `sales.reverse`.
- Use a 30-minute grant for Run All Scenarios and 10 minutes for shorter runs.
- Clear all Stress Lab sensitive-action authorization immediately when the run exits, including failures.
- Do not bypass or weaken the domain guard.

## Verification contract
`test/real_user_scenario_contract_test.dart` now asserts the Stress Lab authorization lifecycle and cleanup.
