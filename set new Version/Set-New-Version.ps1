Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $root 'pubspec.yaml'
$appBrandPath = Join-Path $root 'lib\core\app_brand.dart'
$installerPath = Join-Path $root 'installer\ventio.iss'
$buildScriptPath = Join-Path $root 'scripts\build_windows_installer.ps1'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-CurrentVersion {
  $content = Get-Content -Raw -LiteralPath $pubspecPath
  if ($content -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') {
    throw 'Could not read version from pubspec.yaml.'
  }

  [pscustomobject]@{
    Version = $Matches[1]
    Build = [int]$Matches[2]
    Full = "$($Matches[1])+$($Matches[2])"
  }
}

function Set-FileText {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Text
  )

  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Update-VersionFiles {
  param(
    [Parameter(Mandatory = $true)][string]$FullVersion
  )

  $versionParts = $FullVersion.Split('+')
  if ($versionParts.Count -ne 2) {
    throw 'Version must look like 1.2.3+45.'
  }

  $versionName = $versionParts[0].Trim()
  $buildNumber = $versionParts[1].Trim()
  if ($versionName -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$' -or $buildNumber -notmatch '^[0-9]+$') {
    throw 'Version must look like 1.2.3+45.'
  }

  $pubspec = Get-Content -Raw -LiteralPath $pubspecPath
  $pubspec = [regex]::Replace(
    $pubspec,
    '(?m)^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+\s*$',
    "version: $FullVersion"
  )
  Set-FileText -Path $pubspecPath -Text $pubspec

  $appBrand = Get-Content -Raw -LiteralPath $appBrandPath
  $appBrand = [regex]::Replace(
    $appBrand,
    "(?m)(defaultValue:\s*')[^']*(')",
    '${1}' + $FullVersion + '${2}'
  )
  Set-FileText -Path $appBrandPath -Text $appBrand

  $installer = Get-Content -Raw -LiteralPath $installerPath
  $installer = [regex]::Replace(
    $installer,
    '(?m)^  #define AppVersion ".*"$',
    "  #define AppVersion `"$versionName`""
  )
  $installer = [regex]::Replace(
    $installer,
    '(?m)^  #define AppBuild ".*"$',
    "  #define AppBuild `"$buildNumber`""
  )
  Set-FileText -Path $installerPath -Text $installer
}

function Invoke-InstallerBuild {
  $stdout = Join-Path $env:TEMP ("ventio-build-" + [guid]::NewGuid().ToString('N') + ".log")
  $stderr = Join-Path $env:TEMP ("ventio-build-" + [guid]::NewGuid().ToString('N') + ".err")

  try {
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
      '-NoProfile'
      '-ExecutionPolicy', 'Bypass'
      '-File', $buildScriptPath
    ) -WorkingDirectory $root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

    while (-not $process.HasExited) {
      [System.Windows.Forms.Application]::DoEvents()
      Start-Sleep -Milliseconds 200
    }

    $outText = if (Test-Path -LiteralPath $stdout) { Get-Content -Raw -LiteralPath $stdout } else { '' }
    $errText = if (Test-Path -LiteralPath $stderr) { Get-Content -Raw -LiteralPath $stderr } else { '' }

    return [pscustomobject]@{
      ExitCode = $process.ExitCode
      StdOut = $outText
      StdErr = $errText
    }
  }
  finally {
    Remove-Item -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue
  }
}

$current = Get-CurrentVersion

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Set New Version'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(860, 620)
$form.MinimumSize = New-Object System.Drawing.Size(820, 560)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.AutoSize = $true
$title.Text = 'Ventio version updater'
$title.Location = New-Object System.Drawing.Point(18, 18)
$title.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)

$currentLabel = New-Object System.Windows.Forms.Label
$currentLabel.AutoSize = $true
$currentLabel.Text = "Current version: $($current.Full)"
$currentLabel.Location = New-Object System.Drawing.Point(20, 64)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.AutoSize = $true
$versionLabel.Text = 'New version'
$versionLabel.Location = New-Object System.Drawing.Point(20, 108)

$versionBox = New-Object System.Windows.Forms.TextBox
$versionBox.Location = New-Object System.Drawing.Point(20, 136)
$versionBox.Size = New-Object System.Drawing.Size(240, 28)
$versionBox.Text = $current.Full

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = 'Refresh'
$refreshButton.Location = New-Object System.Drawing.Point(280, 132)
$refreshButton.Size = New-Object System.Drawing.Size(110, 36)

$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = 'Apply and build'
$applyButton.Location = New-Object System.Drawing.Point(404, 132)
$applyButton.Size = New-Object System.Drawing.Size(160, 36)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.AutoSize = $true
$statusLabel.Text = 'Ready'
$statusLabel.Location = New-Object System.Drawing.Point(20, 184)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(20, 218)
$logBox.Size = New-Object System.Drawing.Size(800, 320)
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font('Consolas', 10)

function Write-Log {
  param([string]$Text)
  $timestamp = (Get-Date).ToString('HH:mm:ss')
  $logBox.AppendText("[$timestamp] $Text`r`n")
  $logBox.SelectionStart = $logBox.TextLength
  $logBox.ScrollToCaret()
}

$refreshButton.Add_Click({
  try {
    $script:current = Get-CurrentVersion
    $currentLabel.Text = "Current version: $($script:current.Full)"
    $versionBox.Text = $script:current.Full
    $statusLabel.Text = 'Version loaded'
    Write-Log "Loaded current version $($script:current.Full)."
  }
  catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Set New Version', 'OK', 'Error') | Out-Null
  }
})

$applyButton.Add_Click({
  try {
    $newVersion = $versionBox.Text.Trim()
    if ($newVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$') {
      throw 'Please use the format 1.2.3+45.'
    }

    $applyButton.Enabled = $false
    $refreshButton.Enabled = $false
    $statusLabel.Text = 'Updating files...'
    Write-Log "Updating version to $newVersion."

    Update-VersionFiles -FullVersion $newVersion
    Write-Log 'Version files updated.'
    $currentLabel.Text = "Current version: $newVersion"
    $script:current = [pscustomobject]@{ Full = $newVersion }
    $statusLabel.Text = 'Building installer...'
    Write-Log 'Starting installer build.'

    $result = Invoke-InstallerBuild
    if ($result.StdOut) {
      Write-Log $result.StdOut.TrimEnd()
    }
    if ($result.StdErr) {
      Write-Log $result.StdErr.TrimEnd()
    }

    if ($result.ExitCode -ne 0) {
      throw "Installer build failed with exit code $($result.ExitCode)."
    }

    $statusLabel.Text = 'Done'
    Write-Log "Installer build completed for $newVersion."
    [System.Windows.Forms.MessageBox]::Show("Version updated and installer created for $newVersion.", 'Set New Version', 'OK', 'Information') | Out-Null
  }
  catch {
    $statusLabel.Text = 'Error'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Set New Version', 'OK', 'Error') | Out-Null
    Write-Log "Error: $($_.Exception.Message)"
  }
  finally {
    $applyButton.Enabled = $true
    $refreshButton.Enabled = $true
  }
})

$form.Controls.AddRange(@(
  $title,
  $currentLabel,
  $versionLabel,
  $versionBox,
  $refreshButton,
  $applyButton,
  $statusLabel,
  $logBox
))

Write-Log "Ready. Current version is $($current.Full)."
[void]$form.ShowDialog()
