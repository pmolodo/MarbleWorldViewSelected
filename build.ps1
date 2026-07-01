#!/usr/bin/env -S powershell -NoProfile -ExecutionPolicy Bypass -File
<#
.SYNOPSIS
    Provisions the reference assemblies and builds ViewSelected.dll.

.DESCRIPTION
    Ensures the repo-local lib\ folder holds the reference assemblies the .csproj
    needs (via provision-refs.ps1 - downloads BepInEx, auto-discovers the game's
    Unity/Assembly-CSharp DLLs from Steam), then runs `dotnet build`.

    Dot-source this file to reuse Invoke-PluginBuild and, transitively,
    provision-refs.ps1's constants/functions (Get-BepInExArchive, the BepInEx
    download constants, ...); run it directly to just build.
#>
[CmdletBinding()]
param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

# Reference provisioning + shared build config. Dot-sourced so its variables and
# functions (Initialize-BuildReferences, Get-BepInExArchive, $BepInExVersion, ...)
# are available here and to anything that dot-sources this script.
. (Join-Path $PSScriptRoot "provision-refs.ps1")

$AssemblyName = "ViewSelected"
$TargetFramework = "netstandard2.0"
# Prefix for this plugin's shipped auxiliary files (README, manifest, uninstaller,
# third-party notices). Shared by make-release.ps1 and deploy.ps1.
$PluginFilePrefix = "ViewSelectedPlugin"


function Invoke-PluginBuild {
    # Populate lib\ if needed, then `dotnet build`. Returns the path to the built
    # plugin DLL; throws if the build fails or the output is missing. `dotnet`
    # output is sent to the host so it does not pollute the returned path.
    param([string]$Configuration = "Release")

    Initialize-BuildReferences

    Write-Host "Building $AssemblyName ($Configuration)..."
    dotnet build -c $Configuration | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE"
    }

    $dllPath = Join-Path $PSScriptRoot "bin\$Configuration\$TargetFramework\$AssemblyName.dll"
    if (-not (Test-Path $dllPath)) {
        throw "Expected build output not found: $dllPath"
    }
    return $dllPath
}


# Build when invoked directly (not when dot-sourced for reuse).
if ($MyInvocation.InvocationName -ne '.') {
    $dll = Invoke-PluginBuild -Configuration $Configuration
    Write-Host "Built: $dll"
}
