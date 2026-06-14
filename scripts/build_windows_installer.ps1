param(
  [string]$UpdateBaseUrl = "https://ventio.duckdns.org/releases/windows",
  [switch]$SkipFlutterBuild,
  [switch]$PublishToWebReleases
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$pubspec = Get-Content -Raw -LiteralPath "pubspec.yaml"
if ($pubspec -notmatch "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$") {
  throw "Could not read version from pubspec.yaml. Expected: version: MAJOR.MINOR.PATCH+BUILD"
}

$versionName = $Matches[1]
$buildNumber = $Matches[2]
$fullVersion = "$versionName+$buildNumber"

$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$installerOutDir = Join-Path $repoRoot "build\installer"
$manifestOutDir = Join-Path $repoRoot "build\releases"
$webReleaseDir = Join-Path $repoRoot "web\releases"
$webWindowsReleaseDir = Join-Path $webReleaseDir "windows"
$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

if (-not (Test-Path -LiteralPath $iscc)) {
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    throw "Inno Setup compiler was not found. Install Inno Setup 6 or add ISCC.exe to PATH."
  }
  $iscc = $command.Source
}

New-Item -ItemType Directory -Force -Path $installerOutDir | Out-Null
New-Item -ItemType Directory -Force -Path $manifestOutDir | Out-Null

if (-not $SkipFlutterBuild) {
  flutter build windows --release --dart-define "APP_VERSION=$fullVersion"
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter Windows build failed. Close any running Ventio windows and try again."
  }
}

if (-not (Test-Path -LiteralPath (Join-Path $releaseDir "Ventio.exe"))) {
  throw "Windows release build was not found at $releaseDir. Run without -SkipFlutterBuild first."
}

& $iscc `
  "/DAppVersion=$versionName" `
  "/DAppBuild=$buildNumber" `
  "/DSourceDir=$releaseDir" `
  "/DOutputDir=$installerOutDir" `
  "installer\ventio.iss"
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup compiler failed."
}

$installerName = "VentioSetup-$versionName-build$buildNumber.exe"
$installerPath = Join-Path $installerOutDir $installerName
if (-not (Test-Path -LiteralPath $installerPath)) {
  throw "Installer was not created at $installerPath."
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installerPath).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $installerPath).Length
$urlBase = $UpdateBaseUrl.TrimEnd("/")
$manifest = [ordered]@{
  version = $versionName
  build = [int]$buildNumber
  channel = "stable"
  windows = [ordered]@{
    url = "$urlBase/$installerName"
    sha256 = $hash
    size = $size
  }
  android = [ordered]@{
    source = "play_store"
  }
  notes = @()
  required = $false
}

$manifestJson = $manifest | ConvertTo-Json -Depth 6
$manifestPath = Join-Path $manifestOutDir "latest.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8NoBom)

if ($PublishToWebReleases) {
  New-Item -ItemType Directory -Force -Path $webWindowsReleaseDir | Out-Null
  Copy-Item -LiteralPath $installerPath -Destination (Join-Path $webWindowsReleaseDir $installerName) -Force
  [System.IO.File]::WriteAllText((Join-Path $webReleaseDir "latest.json"), $manifestJson, $utf8NoBom)
}

Write-Host "Ventio Windows installer created:"
Write-Host "  Installer: $installerPath"
Write-Host "  Version:   $fullVersion"
Write-Host "  SHA256:    $hash"
Write-Host "  Manifest:  $manifestPath"
if ($PublishToWebReleases) {
  Write-Host "  Web copy:  $(Join-Path $webWindowsReleaseDir $installerName)"
  Write-Host "  Web manifest: $(Join-Path $webReleaseDir "latest.json")"
}
