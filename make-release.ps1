#!/usr/bin/env -S powershell -NoProfile -ExecutionPolicy Bypass -File
<#
.SYNOPSIS
    Builds ViewSelected.dll (Release) and packages it into a versioned .zip.

.DESCRIPTION
    Runs `dotnet build -c Release`, reads the plugin version out of
    ViewSelectedPlugin.cs, and zips the built DLL into
    dist\ViewSelected-v<version>.zip.
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

$AssemblyName = "ViewSelected"
$TargetFramework = "netstandard2.0"
$SourceFile = Join-Path $ProjectRoot "ViewSelectedPlugin.cs"
$DllPath = Join-Path $ProjectRoot "bin\$Configuration\$TargetFramework\$AssemblyName.dll"

# Pull the version straight from the source of truth (PluginVersion constant).
$versionMatch = Select-String -Path $SourceFile -Pattern 'PluginVersion\s*=\s*"([^"]+)"'
if (-not $versionMatch) {
    throw "Could not find PluginVersion in $SourceFile"
}
$Version = $versionMatch.Matches[0].Groups[1].Value
Write-Host "Building $AssemblyName v$Version ($Configuration)..."

dotnet build -c $Configuration
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $DllPath)) {
    throw "Expected build output not found: $DllPath"
}

$OutputPath = Join-Path $ProjectRoot $OutputDir
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$ZipPath = Join-Path $OutputPath "$AssemblyName-v$Version.zip"
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath
}

Compress-Archive -Path $DllPath -DestinationPath $ZipPath
Write-Host "Created release: $ZipPath"
