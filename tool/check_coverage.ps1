param(
  [double]$Minimum = 35.0,
  [string]$LcovPath = "coverage/lcov.info"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $LcovPath)) {
  throw "Coverage file not found: $LcovPath. Run: flutter test --coverage"
}

$lines = Select-String $LcovPath -Pattern "^LH:|^LF:"
$hit = 0
$found = 0
foreach ($line in $lines) {
  if ($line.Line -match "^LH:(\d+)") { $hit += [int]$matches[1] }
  if ($line.Line -match "^LF:(\d+)") { $found += [int]$matches[1] }
}

if ($found -eq 0) { throw "No coverable lines found in $LcovPath" }
$percent = [math]::Round(($hit / $found) * 100, 2)
Write-Host "Coverage: $percent% ($hit / $found lines). Minimum: $Minimum%"
if ($percent -lt $Minimum) {
  throw "Coverage gate failed: $percent% is below $Minimum%"
}
