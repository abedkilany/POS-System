$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$localTemp = Join-Path $projectRoot ".dart_tool\flutter_test_temp"
New-Item -ItemType Directory -Force -Path $localTemp | Out-Null

$env:TEMP = $localTemp
$env:TMP = $localTemp

flutter clean
flutter pub get
flutter analyze
flutter test -r expanded --concurrency=1
