$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

dart run tool/run_phase0_baseline.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
