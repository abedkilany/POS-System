$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

python tool/check_architecture_boundaries.py
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
python tool/test_architecture_boundary_checker.py
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$localTemp = Join-Path $projectRoot ".dart_tool\flutter_test_temp"
New-Item -ItemType Directory -Force -Path $localTemp | Out-Null

$env:TEMP = $localTemp
$env:TMP = $localTemp

flutter pub get
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
flutter analyze --no-pub
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
flutter test --no-pub -r expanded --coverage --concurrency=1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
& "$PSScriptRoot\check_coverage.ps1"
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
flutter test integration_test -d windows --no-pub -r expanded
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "Quality gate passed." -ForegroundColor Green
Write-Host "Optional golden baseline update:" -ForegroundColor Yellow
Write-Host "flutter test test/golden_smoke_test.dart --dart-define=RUN_GOLDENS=true --update-goldens" -ForegroundColor Yellow
