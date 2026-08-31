param(
  [Nullable[double]]$Minimum = $null,
  [string]$LcovPath = "coverage/lcov.info"
)

$ErrorActionPreference = "Stop"
$argsList = @(
  "run",
  "tool/check_coverage.dart",
  "--lcov", $LcovPath,
  "--config", "tool/quality_gate_config.json"
)
if ($null -ne $Minimum) {
  $argsList += @("--minimum", $Minimum.ToString([System.Globalization.CultureInfo]::InvariantCulture))
}

& dart @argsList
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
