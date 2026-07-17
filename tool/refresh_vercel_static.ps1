# Rebuild Flutter web and copy into vercel_static/ for Vercel (committed static deploy).
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "Building Flutter web (release)..."
flutter pub get
flutter build web --release --base-href /

$dest = Join-Path $root "vercel_static"
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Path $dest | Out-Null
Copy-Item -Path (Join-Path $root "build\web\*") -Destination $dest -Recurse -Force

if (-not (Test-Path (Join-Path $dest "flutter_bootstrap.js"))) {
  throw "flutter_bootstrap.js missing in vercel_static"
}
Write-Host "Done. Commit vercel_static/ and push, then redeploy Vercel."
