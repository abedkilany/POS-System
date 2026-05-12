$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$localTemp = Join-Path $projectRoot ".dart_tool\flutter_test_temp"
New-Item -ItemType Directory -Force -Path $localTemp | Out-Null

$env:TEMP = $localTemp
$env:TMP = $localTemp

flutter pub get
flutter analyze
flutter test -r expanded --coverage --concurrency=1
& "$PSScriptRoot\check_coverage.ps1" -Minimum 35
flutter test integration_test -d windows -r expanded

Write-Host "Quality gate passed." -ForegroundColor Green
Write-Host "Optional golden baseline update:" -ForegroundColor Yellow
Write-Host "flutter test test/golden_smoke_test.dart --dart-define=RUN_GOLDENS=true --update-goldens" -ForegroundColor Yellow
