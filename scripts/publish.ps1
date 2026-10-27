# Publish dsh-desktop-guard to npm (works on Windows PowerShell 5.1; ASCII-only on purpose).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish.ps1 -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish.ps1 -Otp 123456
#
# Why the explicit registry: the default registry on this machine is
# https://registry.npmmirror.com, a read-only mirror that cannot accept publishes.
param(
    [switch]$DryRun,
    [string]$Otp = '',
    [string]$Registry = 'https://registry.npmjs.org'
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "== $msg" -ForegroundColor Cyan }

# Native commands (npm) write notices to stderr; with 2>&1 + EAP=Stop PowerShell turns those into
# terminating errors, so capture them explicitly and use $LASTEXITCODE.
function Invoke-Npm {
    param([string[]]$NpmArgs)
    $out = & npm.cmd @NpmArgs 2>&1 | Out-String
    return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}

Step "1/6 package manifest"
$manifest = Get-Content 'package.json' -Raw | ConvertFrom-Json
$name = $manifest.name; $version = $manifest.version
if ($manifest.private -eq $true) { Fail 'package.json has "private": true' }
if (-not $manifest.dsh.bundle.patch) { Fail 'package.json is missing dsh.bundle.patch' }
Write-Host "  $name@$version (bundle patch: $($manifest.dsh.bundle.patch))"

Step "2/6 gui.ps1 BOM + required files"
foreach ($f in @('assets/gui.ps1', 'dsh/index.js', 'dsh/policy.js', 'cordis.patch.yml', 'README.md')) {
    if (-not (Test-Path $f)) { Fail "missing $f" }
}
$b = [IO.File]::ReadAllBytes((Resolve-Path 'assets/gui.ps1'))
if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) {
    Fail 'assets/gui.ps1 lost its UTF-8 BOM (PowerShell 5.1 will fail on the Chinese strings)'
}
Write-Host "  gui.ps1 BOM ok ($($b.Length) bytes)"

Step "3/6 tarball preview"
$pack = Invoke-Npm @('pack', '--dry-run', "--registry=$Registry")
($pack.Out -split "`n") | Where-Object { $_ -match 'package size|unpacked size|total files' } |
    ForEach-Object { Write-Host "  $($_.Trim())" }
if ($pack.Code -ne 0) { Fail "npm pack failed (exit $($pack.Code)):`n$($pack.Out)" }

if ($DryRun) { Step 'DryRun: stopping before login/publish'; exit 0 }

Step "4/6 login state"
$who = Invoke-Npm @('whoami', "--registry=$Registry")
$whoName = $who.Out.Trim()
if ($who.Code -ne 0 -or $whoName -match 'ENEEDAUTH|need auth|not logged in|error') {
    Write-Host '  not logged in. Run this once in your own terminal, then re-run this script:' -ForegroundColor Yellow
    Write-Host "    npm login --registry=$Registry" -ForegroundColor Yellow
    exit 2
}
Write-Host "  logged in as $whoName"

Step "5/6 name availability for this exact version"
$view = Invoke-Npm @('view', "$name@$version", 'version', "--registry=$Registry")
$viewOut = $view.Out.Trim()
if ($view.Code -eq 0 -and $viewOut -match '^[0-9]+\.[0-9]+\.[0-9]+') {
    Fail "$name@$version already exists on the registry; bump package.json version first"
}
Write-Host "  $name@$version does not exist yet (ok)"

Step "6/6 publish"
$npmArgs = @('publish', "--registry=$Registry", '--access', 'public')
if ($Otp) { $npmArgs += @('--otp', $Otp) }
Write-Host "  npm $($npmArgs -join ' ')"
& npm.cmd @npmArgs
$publishCode = $LASTEXITCODE
if ($publishCode -ne 0) { Fail "npm publish exited $publishCode" }

Write-Host ''
Step 'verify'
$verify = Invoke-Npm @('view', $name, 'version', 'dist.tarball', "--registry=$Registry")
Write-Host $verify.Out.Trim()
Write-Host ''
Write-Host 'Next: install the published package into a scratch DSH profile:' -ForegroundColor Green
Write-Host '  plugin_manager({ action: "install_bundle", target: "dsh-desktop-guard" })'
Write-Host '  -> expect application: "applied"; then run desktop { action: "windows" } once.'
