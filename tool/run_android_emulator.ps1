# Run rapid_aid on Android Studio emulator (e.g. Medium Phone, adb id emulator-5554).
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $ProjectRoot

$sdkCandidates = @(
    $env:ANDROID_HOME,
    $env:ANDROID_SDK_ROOT,
    "$env:LOCALAPPDATA\Android\Sdk",
    "$env:USERPROFILE\AppData\Local\Android\Sdk"
) | Where-Object { $_ -and (Test-Path $_) }

$localProps = Join-Path $ProjectRoot "android\local.properties"
if (Test-Path $localProps) {
    $content = Get-Content $localProps -Raw
    if ($content -match 'sdk\.dir=(.+)') {
        $fromFile = $matches[1].Trim() -replace '\\\\', '\'
        if (Test-Path $fromFile) { $sdkCandidates = @($fromFile) + $sdkCandidates }
    }
}

foreach ($sdk in $sdkCandidates) {
    Write-Host "Configuring Flutter Android SDK: $sdk"
    flutter config --android-sdk $sdk | Out-Null
    break
}

if (-not $sdkCandidates) {
    Write-Warning @"
Android SDK not found. Install Android Studio, open SDK Manager, then set sdk.dir in:
  android\local.properties
Or run: flutter config --android-sdk <path-to-Sdk>
"@
}

$adb = $null
foreach ($sdk in $sdkCandidates) {
    $candidate = Join-Path $sdk "platform-tools\adb.exe"
    if (Test-Path $candidate) { $adb = $candidate; break }
}

if ($adb) {
    Write-Host "Connected devices:"
    & $adb devices
}

flutter pub get
$deviceId = "emulator-5554"
$devices = flutter devices 2>&1 | Out-String
if ($devices -match $deviceId) {
    flutter run -d $deviceId
} else {
    Write-Host "Device $deviceId not listed; starting on first available Android device..."
    flutter run
}
