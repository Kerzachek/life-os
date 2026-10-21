<#
.SYNOPSIS
    Builds the Flutter Windows release with embedded OAuth keys and packages it into an Inno Setup installer.

.DESCRIPTION
    Steps:
      1. Verifies key.json presence
      2. flutter build windows --release --dart-define-from-file=key.json
      3. ISCC.exe installer.iss

.PARAMETER IsccPath
    Optional. Full path to ISCC.exe if it is not found automatically.

.EXAMPLE
    .\build_installer.ps1
#>
[CmdletBinding()]
param(
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

# --- Pre-checks (fail fast) ---
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter not found in PATH."
}
if (-not (Test-Path (Join-Path $PSScriptRoot 'key.json'))) {
    throw "key.json not found in project root. Create it with your OAuth credentials before building."
}
if (-not (Test-Path (Join-Path $PSScriptRoot 'installer.iss'))) {
    throw "installer.iss not found next to build_installer.ps1."
}
$iscc = Find-Iscc -Explicit $IsccPath
Write-Host "Using ISCC: $iscc" -ForegroundColor DarkGray

# --- Step 1: Flutter release build with key.json ---
Write-Host "`n==> flutter build windows --release --dart-define-from-file=key.json" -ForegroundColor Cyan
& flutter build windows --release --dart-define-from-file=key.json
if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows --release failed (exit code $LASTEXITCODE)."
}

$sourceDir = Join-Path $PSScriptRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path $sourceDir)) {
    throw "Release folder not found: $sourceDir"
}

# --- Step 2: Compile installer ---
Write-Host "`n==> ISCC.exe installer.iss" -ForegroundColor Cyan
& $iscc 'installer.iss'
if ($LASTEXITCODE -ne 0) {
    throw "ISCC.exe failed (exit code $LASTEXITCODE)."
}

$output = Join-Path $PSScriptRoot 'build\installer\LifeOS-Setup.exe'
Write-Host "`nDone. Installer: $output" -ForegroundColor Green