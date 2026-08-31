# Phase 0 Implementation Report

## Scope

Implemented only **Phase 0 — Production Baseline Gate**. No Ventio business behavior, accounting logic, inventory logic, sync write path, database schema, or UI feature behavior was intentionally changed.

## Changes made

1. Added `tool/quality_gate_config.json` as the shared coverage-policy source.
   - Current enforced baseline: 35%.
   - Progressive target: 75%.
   - Shared coverage exclusions are declared once.
2. Added `tool/check_coverage.dart` as the cross-platform LCOV evaluator.
3. Replaced the separate Bash/PowerShell coverage implementations with thin wrappers around the same evaluator.
4. Updated both full quality-gate scripts to use the same coverage policy.
5. Added `tool/run_phase0_baseline.dart` plus Bash/PowerShell launchers.
   - Captures Flutter version.
   - Runs pub get, analyze, full tests with coverage, coverage policy, and Windows integration tests when on Windows.
   - Records test inventory and static app/schema/protocol version information.
   - Produces timestamped `manifest.json`, `summary.md`, and per-step logs.
6. Added `docs/production_baseline.md` with the static baseline and acceptance rule.
7. Updated README quality-gate instructions.
8. Added `quality_baseline/` to `.gitignore` because generated logs are local evidence rather than source files.

## Static baseline recorded from the supplied archive

- App version: `1.0.26+26`.
- 88 unit/widget test files.
- 2 enabled integration-test files.
- 2 disabled critical integration tests:
  - `integration_test/navigation_flow_test.dart.disabled`
  - `integration_test/performance_flow_test.dart.disabled`
- Legacy AppStore schema marker: 17.
- Drift schema version: 27.
- Direct peer handshake protocol version: 1.
- Authenticated peer session protocol version: 1.
- Unified snapshot version: 1.
- No single authoritative Sync Protocol Version constant was found.

## Important baseline finding fixed

Before Phase 0, the quality gates were not equivalent:

- Bash forced coverage >= 75% and counted the entire LCOV file.
- PowerShell forced coverage >= 35% and excluded selected UI/IO files.

Therefore the same source/tests could receive different release judgments on different platforms. The new shared evaluator eliminates the calculation divergence.

## Verification performed in this review environment

- JSON configuration parses successfully.
- Bash scripts pass `bash -n` syntax validation.
- Source-tree diff confirms only Phase 0 tooling/docs/README/.gitignore changed.

## Verification not executable in this environment

This environment does not contain Flutter or Dart SDK binaries, so the following results are intentionally **not claimed**:

- `flutter analyze` result.
- Full Flutter test result.
- Actual coverage percentage.
- Windows integration-test result.
- Dart compile/analyze result for the newly added tooling.

Run the following on the Windows development/release machine to produce the authoritative executable baseline:

```powershell
.\tool\run_phase0_baseline.ps1
```

Phase 1 must not begin until that runner completes and the baseline evidence is reviewed.
