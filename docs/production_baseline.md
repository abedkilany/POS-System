# Ventio Production Baseline — Phase 0

This document defines the pre-production baseline that must be captured before Phase 1 modifies posted-document behavior.

## Static baseline from the reviewed source archive

- App version: `1.0.26+26`.
- Unit/widget test files: 88.
- Enabled desktop integration test files: 2.
- Disabled critical integration tests:
  - `integration_test/navigation_flow_test.dart.disabled`
  - `integration_test/performance_flow_test.dart.disabled`
- Legacy AppStore schema marker: 17.
- Drift schema version: 27.
- Direct peer handshake protocol version: 1.
- Authenticated peer session protocol version: 1.
- Unified snapshot version: 1.
- No single authoritative Sync Protocol Version constant was found. This is recorded as a baseline gap; incompatible sync changes must not be introduced until protocol-version ownership is centralized.

## Quality gate policy

The executable policy is stored in `tool/quality_gate_config.json` and is shared by Windows and Bash tooling.

- Current enforced coverage baseline: 35%.
- Progressive target: 75%.
- The baseline starts at 35% because the Windows release gate already enforced 35% before Phase 0. The target must be raised only after measuring actual coverage and adding tests; Phase 0 must not silently convert an existing baseline into a new release blocker.
- Coverage exclusions are now evaluated by one cross-platform Dart implementation (`tool/check_coverage.dart`) so PowerShell and Bash cannot calculate different percentages from the same `lcov.info`.

## Required executable baseline

Run on the Windows release machine with Flutter installed:

```powershell
.\tool\run_phase0_baseline.ps1
```

Or, for the common non-Windows checks:

```bash
./tool/run_phase0_baseline.sh
```

The runner records:

- Flutter version.
- `flutter pub get`.
- `flutter analyze`.
- Full test suite with coverage.
- Shared coverage-policy result.
- Windows integration tests when running on Windows.
- App/schema/protocol version inventory.
- Enabled/disabled integration-test inventory.

Generated evidence is written under `quality_baseline/<UTC timestamp>/` with `manifest.json`, `summary.md`, and per-step logs.

## Acceptance rule

Phase 0 is accepted only when the baseline runner reports PASS on the Windows release machine and the generated evidence is retained with the release work. The two currently disabled critical integration tests remain explicit baseline debt and must be re-enabled by the final Production Release Gate phase.
