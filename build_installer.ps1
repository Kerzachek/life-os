<#
.SYNOPSIS
    Builds the Flutter Windows release and packages it into a password-protected Inno Setup installer.

.DESCRIPTION
    Steps:
      1. flutter build windows --release
      2. ISCC.exe installer.iss

.PARAMETER Password
    Optional. Overrides the installer password defined in installer.iss.

.PARAMETER IsccPath
    Optional. Full path to ISCC.exe if it is not found automatically.

.EXAMPLE
    .\build_installer.ps1
    .\build_installer.ps1 -Password "MySecret"
#>
[CmdletBinding()]
param(
    [string]$Password,
    [string]$IsccPath
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

function Find-Iscc {
    param([string]$Explicit)

    if ($Explicit) {
        if (Test-Path $Explicit) { return (Resolve-Path $Explicit).Path }
        throw "ISCC.exe not found at the specified path: $Explicit"
    }

    $cmd = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Any Inno Setup version (7, 6, ...), newest first; per-machine and per-user installs.
    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        (Join-Path $env:LOCALAPPDATA 'Programs')
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $found = Get-ChildItem -Path $root -Directory -Filter 'Inno Setup*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'ISCC.exe' } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($found) { return $found }
    }

    throw ("ISCC.exe (Inno Setup) not found. Install it from https://jrsoftware.org/isdl.php " +
           "(or: winget install JRSoftware.InnoSetup) or pass -IsccPath.")
}

# --- Pre-checks (fail fast, before the long Flutter build) ---
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter not found in PATH."
}
if (-not (Test-Path (Join-Path $PSScriptRoot 'installer.iss'))) {
    throw "installer.iss not found next to build_installer.ps1."
}
$iscc = Find-Iscc -Explicit $IsccPath
Write-Host "Using ISCC: $iscc" -ForegroundColor DarkGray

# --- Step 1: Flutter release build ---
Write-Host "`n==> flutter build windows --release" -ForegroundColor Cyan
& flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows --release failed (exit code $LASTEXITCODE)."
}

$sourceDir = Join-Path $PSScriptRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path $sourceDir)) {
    throw "Release folder not found: $sourceDir"
}

# --- Step 2: Compile installer ---
Write-Host "`n==> ISCC.exe installer.iss" -ForegroundColor Cyan
$isccArgs = @()
if ($Password) { $isccArgs += "/DInstallPassword=$Password" }
$isccArgs += 'installer.iss'

& $iscc @isccArgs
if ($LASTEXITCODE -ne 0) {
    throw "ISCC.exe failed (exit code $LASTEXITCODE)."
}

$output = Join-Path $PSScriptRoot 'build\installer\LifeOS_Setup.exe'
Write-Host "`nDone. Installer: $output" -ForegroundColor Green
