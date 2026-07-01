#!/usr/bin/env -S powershell -NoProfile -ExecutionPolicy Bypass -File
<#
.SYNOPSIS
    Builds ViewSelected.dll (Release) and packages it into two versioned .zips.

.DESCRIPTION
    Runs `dotnet build -c Release`, reads the plugin version out of
    ViewSelectedPlugin.cs, and produces two archives under dist\:

      * ViewSelected-BepInExPluginOnly-v<version>.zip
          Just the plugin DLL (drop into an existing BepInEx\plugins folder).

      * ViewSelected-AllInOne-v<version>.zip
          BepInEx (win x64, Mono) with the plugin already placed in
          BepInEx\plugins - extract into the game folder and you are done.
          The BepInEx archive is downloaded once to a cached location and its
          SHA256 is verified against a pinned hash before use.
#>
[CmdletBinding()]
param(
    [string]$Configuration = "Release",
    [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"

# Run from the project root (this script's own directory) regardless of cwd.
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

# Build + reference provisioning. Dot-sourced so its variables/functions
# (Invoke-PluginBuild, $AssemblyName, and - transitively via provision-refs.ps1 -
# the BepInEx download constants + Get-BepInExArchive) are available here.
. (Join-Path $ProjectRoot "build.ps1")

$SourceFile = Join-Path $ProjectRoot "ViewSelectedPlugin.cs"

# Auxiliary files at a zip's root are named "<component>-<type>" so they group
# and sort by the component they belong to. Our plugin's files use this prefix;
# BepInEx's own renamable files use the "BepInEx-" prefix. (Functional files
# doorstop/BepInEx require by exact name - winhttp.dll, doorstop_config.ini,
# .doorstop_version - are left untouched, as is the plugin DLL itself.)
$PluginFilePrefix = "ViewSelectedPlugin"

# README is shipped in both zips. The all-in-one archive extracts to the game
# install root, so it is renamed to make clear which mod it documents.
$ReadmeSource = Join-Path $ProjectRoot "README.md"
$ReadmeReleaseName = "$PluginFilePrefix-README.md"

# BepInEx bundle constants ($BepInExVersion, $Arch, $PlatformTag, $BepInExUrl,
# $BepInExZipName, ...) and the cached-download helper (Get-BepInExArchive) come
# from provision-refs.ps1, dot-sourced above.

# BepInEx's release zip ships no license file, so we bundle its license text
# (MIT for the 5.x line) into the AllInOne archive to satisfy MIT's "include the
# copyright and permission notice" requirement. Refresh this file if
# $BepInExVersion moves to a differently-licensed release (BepInEx 6.x is LGPL).
$BepInExLicenseFile = Join-Path $ProjectRoot "packaging\BepInEx-LICENSE.txt"


function New-Zip {
    param([string]$Path, [string[]]$Source)
    if (Test-Path $Path) {
        Remove-Item $Path
    }
    Compress-Archive -Path $Source -DestinationPath $Path
    Write-Host "Created release: $Path"
}

function Write-Manifest {
    # Write "<prefix>-manifest.txt" into $Dir listing every root-level entry that
    # the zip will contain (folders get a trailing "/"), including the manifest
    # itself. Used by the uninstall instructions. Call this last, after all other
    # files are staged.
    param([string]$Dir)
    $manifestName = "$PluginFilePrefix-manifest.txt"
    $entries = Get-ChildItem -Force -LiteralPath $Dir | ForEach-Object {
        if ($_.PSIsContainer) { "$($_.Name)/" } else { $_.Name }
    }
    $entries = @($entries) + $manifestName | Sort-Object
    Set-Content -Path (Join-Path $Dir $manifestName) -Value $entries -Encoding ascii
}


# --- Version -----------------------------------------------------------------
# Pull the version straight from the source of truth (PluginVersion constant).
$versionMatch = Select-String -Path $SourceFile -Pattern 'PluginVersion\s*=\s*"([^"]+)"'
if (-not $versionMatch) {
    throw "Could not find PluginVersion in $SourceFile"
}
$Version = $versionMatch.Matches[0].Groups[1].Value

# --- Build -------------------------------------------------------------------
# Provisions lib\ (downloads BepInEx; auto-discovers the game's Unity/Assembly-CSharp
# DLLs on first run) and runs dotnet build; returns the built plugin DLL path.
Write-Host "Building $AssemblyName v$Version ($Configuration)..."
$DllPath = Invoke-PluginBuild -Configuration $Configuration

$OutputPath = Join-Path $ProjectRoot $OutputDir
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

# Renamed README copy included in every release zip, with the <version>
# placeholder(s) substituted for the actual version. Written as UTF-8 without a
# BOM, preserving the source's line endings.
if (-not (Test-Path $ReadmeSource)) {
    throw "Missing README: $ReadmeSource"
}
$ReadmeReleaseCopy = Join-Path $OutputPath $ReadmeReleaseName
$readmeText = [System.IO.File]::ReadAllText($ReadmeSource) -replace '<version>', $Version
[System.IO.File]::WriteAllText($ReadmeReleaseCopy, $readmeText, (New-Object System.Text.UTF8Encoding($false)))

# --- Plugin-only zip ---------------------------------------------------------
# The plugin is an arch-independent netstandard2.0 managed DLL, so it is tagged
# win-dotnet rather than a specific architecture. Staged into a folder so the
# archive can carry its manifest.
$pluginStageDir = Join-Path $OutputPath "_pluginonly_stage"
if (Test-Path $pluginStageDir) {
    Remove-Item -Recurse -Force $pluginStageDir
}
New-Item -ItemType Directory -Force -Path $pluginStageDir | Out-Null
Copy-Item $DllPath -Destination $pluginStageDir
Copy-Item $ReadmeReleaseCopy -Destination $pluginStageDir
Write-Manifest -Dir $pluginStageDir

$pluginOnlyZip = Join-Path $OutputPath "$AssemblyName-BepInExPluginOnly-v${Version}_win-dotnet.zip"
New-Zip -Path $pluginOnlyZip -Source (Get-ChildItem -Force -LiteralPath $pluginStageDir | ForEach-Object { $_.FullName })
Remove-Item -Recurse -Force $pluginStageDir

# --- All-in-one zip (BepInEx + plugin) ---------------------------------------
$bepInExZip = Get-BepInExArchive

# Stage the BepInEx tree, drop the plugin into BepInEx\plugins, then zip the
# whole thing so it extracts straight into the game folder.
$stageDir = Join-Path $OutputPath "_allinone_stage"
if (Test-Path $stageDir) {
    Remove-Item -Recurse -Force $stageDir
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
Expand-Archive -Path $bepInExZip -DestinationPath $stageDir

# Prefix BepInEx's own root-level, renamable files so they group by component.
$stagedChangelog = Join-Path $stageDir "changelog.txt"
if (Test-Path $stagedChangelog) {
    Rename-Item -Path $stagedChangelog -NewName "BepInEx-changelog.txt"
}

$pluginsDir = Join-Path $stageDir "BepInEx\plugins"
New-Item -ItemType Directory -Force -Path $pluginsDir | Out-Null
Copy-Item $DllPath -Destination $pluginsDir

# License bits for the bundled BepInEx: its release zip has no license file, so
# ship its license text plus an attribution notice at the archive root.
if (-not (Test-Path $BepInExLicenseFile)) {
    throw "Missing bundled BepInEx license text: $BepInExLicenseFile"
}
Copy-Item $BepInExLicenseFile -Destination (Join-Path $stageDir "BepInEx-LICENSE.txt")

$noticeText = @"
THIRD-PARTY NOTICES
===================

This archive bundles BepInEx, included unmodified, under the MIT License.

  Component: BepInEx $BepInExVersion ($PlatformTag, Mono)
  License:   MIT - see BepInEx-LICENSE.txt in this archive
  Source:    https://github.com/BepInEx/BepInEx
  Download:  $BepInExUrl

The ViewSelected plugin (BepInEx\plugins\$AssemblyName.dll) is a separate work
under its own license; see the project's LICENSE file.
"@
Set-Content -Path (Join-Path $stageDir "$PluginFilePrefix-THIRD-PARTY-NOTICES.txt") -Value $noticeText -Encoding ascii

# README at the archive root, so it lands next to Marble World.exe on extract.
Copy-Item $ReadmeReleaseCopy -Destination (Join-Path $stageDir $ReadmeReleaseName)

# Manifest last, so it enumerates every other root-level entry (plus itself).
Write-Manifest -Dir $stageDir

$allInOneZip = Join-Path $OutputPath "$AssemblyName-AllInOne-v${Version}_$PlatformTag.zip"
New-Zip -Path $allInOneZip -Source (Get-ChildItem -Force -LiteralPath $stageDir | ForEach-Object { $_.FullName })

Remove-Item -Recurse -Force $stageDir
Remove-Item -Force $ReadmeReleaseCopy
