param(
  [double]$Minimum = 75.0,
  [string]$LcovPath = "coverage/lcov.info"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $LcovPath)) {
  throw "Coverage file not found: $LcovPath. Run: flutter test --coverage"
}

$excludedPatterns = @(
  'lib\app.dart',
  'lib\widgets\*',
  'lib\features\*\*_page.dart',
  'lib\features\*\*_page_*.dart',
  'lib\features\*\*_widgets.dart',
  'lib\features\dev_tools\stress_lab_page.dart',
  'lib\features\maintenance\diagnostics_page.dart',
  'lib\features\settings\settings_page_backup.dart',
  'lib\core\services\*_io.dart',
  'lib\core\services\*_stub.dart',
  'lib\core\storage\sqlite\sqlite_database_connection_io.dart',
  'lib\core\services\google_drive_browser_auth_io.dart'
)

$hit = 0
$found = 0
$currentHit = 0
$currentFound = 0
$includeCurrent = $true
$currentFile = ''
foreach ($line in Get-Content $LcovPath) {
  if ($line -like 'SF:*') {
    if ($currentFile -and $includeCurrent) {
      $hit += $currentHit
      $found += $currentFound
    }
    $currentFile = $line.Substring(3).Trim()
    $includeCurrent = $true
    foreach ($pattern in $excludedPatterns) {
      if ($currentFile -like $pattern) {
        $includeCurrent = $false
        break
      }
    }
    $currentHit = 0
    $currentFound = 0
    continue
  }
  if (-not $includeCurrent) { continue }
  if ($line -match '^LH:(\d+)') {
    $currentHit += [int]$matches[1]
    continue
  }
  if ($line -match '^LF:(\d+)') {
    $currentFound += [int]$matches[1]
    continue
  }
}

if ($currentFile -and $includeCurrent) {
  $hit += $currentHit
  $found += $currentFound
}

if ($found -eq 0) { throw "No coverable lines found in $LcovPath" }
$percent = [math]::Round(($hit / $found) * 100, 2)
Write-Host "Coverage: $percent% ($hit / $found lines). Minimum: $Minimum%"
if ($percent -lt $Minimum) {
  throw "Coverage gate failed: $percent% is below $Minimum%"
}
