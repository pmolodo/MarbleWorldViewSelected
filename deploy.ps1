#!/usr/bin/env -S powershell -NoProfile -ExecutionPolicy Bypass -File
<#
.SYNOPSIS
    Full-cycle deploy for testing: build the release, then (re)install the
    all-in-one build into the Marble World Steam install.

.DESCRIPTION
    1. Runs make-release.ps1 (build + package both zips).
    2. Locates the Marble World install via Steam discovery (cached in
       .build-cache\ by Find-MarbleWorldInstallDir).
    3. If a previous ViewSelected install is present (its uninstaller is found at
       the game root or in BepInEx\plugins), runs that uninstaller first.
    4. Extracts the freshly built AllInOne zip into the game folder.

    After it finishes, launch the game to test the new build.
#>
[CmdletBinding()]
param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

# Build helpers + Steam discovery. Dot-sourced (transitively pulls in
# provision-refs.ps1), giving $AssemblyName, $PluginFilePrefix,
# Find-MarbleWorldInstallDir, etc.
. (Join-Path $ProjectRoot "build.ps1")

# --- 1. Build + package -------------------------------------------------------
Write-Host "== Building release ==" -ForegroundColor Cyan
& (Join-Path $ProjectRoot "make-release.ps1") -Configuration $Configuration

# --- 2. Locate the game install ----------------------------------------------
Write-Host "== Locating Marble World install ==" -ForegroundColor Cyan
$gameDir = Find-MarbleWorldInstallDir
Write-Host "Game folder: $gameDir"

# --- 3. Uninstall any previous copy ------------------------------------------
# The AllInOne install drops the uninstaller at the game root; a plugin-only
# install puts it in BepInEx\plugins. Run whichever is present so we start clean.
$uninstallerName = "$PluginFilePrefix-uninstall.ps1"
$uninstallers = @(
    (Join-Path $gameDir $uninstallerName),
    (Join-Path $gameDir "BepInEx\plugins\$uninstallerName")
) | Where-Object { Test-Path -LiteralPath $_ }

if ($uninstallers.Count -eq 0) {
    Write-Host "No previous ViewSelected install found."
}
foreach ($uninstaller in $uninstallers) {
    Write-Host "== Uninstalling previous copy ==" -ForegroundColor Cyan
    Write-Host "Running $uninstaller"
    & $uninstaller
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Uninstaller reported problems (exit $LASTEXITCODE); continuing."
    }
}

# --- 4. Extract the fresh AllInOne build into the game folder -----------------
Write-Host "== Installing AllInOne build ==" -ForegroundColor Cyan
$distDir = Join-Path $BuildDir "dist"
$allInOne = Get-ChildItem -Path $distDir -Filter "$AssemblyName-AllInOne-*.zip" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $allInOne) {
    throw "No AllInOne zip found in $distDir (make-release.ps1 should have produced one)."
}

Write-Host "Extracting $($allInOne.Name) into $gameDir"
Expand-Archive -Path $allInOne.FullName -DestinationPath $gameDir -Force

Write-Host ""
Write-Host "Deployed. Launch Marble World to test." -ForegroundColor Green
