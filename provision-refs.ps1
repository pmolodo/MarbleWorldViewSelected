#!/usr/bin/env -S powershell -NoProfile -ExecutionPolicy Bypass -File
<#
.SYNOPSIS
    Populates the repo-local lib\ folder with the reference assemblies the build
    needs, without any hardcoded local paths.

.DESCRIPTION
    The committed .csproj references DLLs from $(MSBuildThisFileDirectory)lib\,
    so nothing machine-specific lives in git. This script fills that folder:

      * BepInEx.dll - extracted from the pinned BepInEx release zip, which is
        downloaded once and SHA256-verified (cached under .build-cache\). Never
        read from a game install.

      * UnityEngine*.dll + Assembly-CSharp.dll - copied out of the installed
        Marble World game, whose location is auto-discovered from Steam (registry
        + libraryfolders.vdf), so no path is hardcoded. Assembly-CSharp.dll is the
        game's proprietary code and cannot be downloaded, so an install must be
        present the first time lib\ is populated; afterwards lib\ is self-
        sufficient and the install is never touched again.

    Idempotent: only fetches/copies files that are not already vendored in lib\.

    Dot-source this file to reuse its constants and functions (Get-BepInExArchive,
    Find-MarbleWorldManagedDir, Initialize-BuildReferences) from other scripts;
    run it directly to just provision lib\.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# --- Shared build configuration ----------------------------------------------
# Steam AppID for Marble World (from its appmanifest_<id>.acf).
$MarbleWorldAppId = 1491340
# Folder Unity emits next to the game exe; holds the Managed reference assemblies.
$GameDataFolder = "Marble World_Data"

# Pinned BepInEx bundle (Windows Mono builds). We pick the archive matching this
# machine's architecture - no cross-compile for now. If the version is bumped,
# update the URL/SHA256 for both architectures below.
$BepInExVersion = "5.4.23.5"
$Arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
# Suffix baked into the release zip names, e.g. "win-x64".
$PlatformTag = "win-$Arch"
$BepInExSha256ByArch = @{
    "x64" = "82F9878551030F54657792C0740D9D51A09500EEAE1FBA21106B0C441E6732C4"
    "x86" = "37651C79E40D6F909572A4F461AC25350BB3EF8FE7FBD29F1AA8791A33B84C82"
}
$BepInExZipName = "BepInEx_win_${Arch}_$BepInExVersion.zip"
$BepInExUrl = "https://github.com/BepInEx/BepInEx/releases/download/v$BepInExVersion/$BepInExZipName"
$BepInExSha256 = $BepInExSha256ByArch[$Arch]

# Persistent cache so the ~4MB BepInEx download only happens once.
$CacheDir = Join-Path $PSScriptRoot ".build-cache"

# Repo-local vendored reference assemblies (gitignored). The .csproj HintPaths
# point here via $(MSBuildThisFileDirectory)lib.
$LibDir = Join-Path $PSScriptRoot "lib"
# Path of BepInEx.dll inside the BepInEx release zip.
$BepInExDllEntry = "BepInEx/core/BepInEx.dll"
# DLLs vendored from the game's Managed folder (Unity facades + game code).
$ManagedDllNames = @(
    "Assembly-CSharp.dll",
    "UnityEngine.CoreModule.dll",
    "UnityEngine.InputLegacyModule.dll",
    "UnityEngine.dll"
)
# Caches the discovered game install folder so repeat lookups skip Steam discovery.
$InstallCacheFile = Join-Path $CacheDir "marble-world-install.txt"


function Get-BepInExArchive {
    # Returns the path to a hash-verified local copy of the BepInEx zip,
    # downloading it to the cache only if a valid copy is not already present.
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    $cachedZip = Join-Path $CacheDir $BepInExZipName

    if (Test-Path $cachedZip) {
        $have = (Get-FileHash -Algorithm SHA256 -Path $cachedZip).Hash
        if ($have -eq $BepInExSha256) {
            Write-Host "Using cached $BepInExZipName"
            return $cachedZip
        }
        Write-Host "Cached $BepInExZipName failed hash check; re-downloading."
        Remove-Item $cachedZip
    }

    Write-Host "Downloading $BepInExUrl ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $BepInExUrl -OutFile $cachedZip

    $have = (Get-FileHash -Algorithm SHA256 -Path $cachedZip).Hash
    if ($have -ne $BepInExSha256) {
        Remove-Item $cachedZip
        throw "SHA256 mismatch for $BepInExZipName`n  expected $BepInExSha256`n  got      $have"
    }
    Write-Host "Downloaded and verified $BepInExZipName"
    return $cachedZip
}


function Get-SteamLibraryPath {
    # Steam records its own location in the registry; return it (or $null if
    # Steam is not installed / the key is absent). HKCU first (per-user, always
    # the active install), then the 32-bit HKLM fallback.
    foreach ($probe in @(
        @{ Path = "HKCU:\Software\Valve\Steam"; Name = "SteamPath" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"; Name = "InstallPath" }
    )) {
        try {
            $value = (Get-ItemProperty -Path $probe.Path -Name $probe.Name -ErrorAction Stop).($probe.Name)
            if ($value) { return $value }
        }
        catch {
            # Key/value absent - try the next probe.
        }
    }
    return $null
}


function Get-SteamLibraryFolders {
    # Enumerate every Steam library folder root. Games can live on other drives,
    # so we cannot assume the default library. Starts with Steam's own root, then
    # adds the "path" entries parsed out of libraryfolders.vdf (both the modern
    # config\ location and the legacy steamapps\ one).
    param([string]$SteamPath)

    $roots = [System.Collections.Generic.List[string]]::new()
    $roots.Add($SteamPath)

    foreach ($rel in @("config\libraryfolders.vdf", "steamapps\libraryfolders.vdf")) {
        $vdf = Join-Path $SteamPath $rel
        if (-not (Test-Path $vdf)) { continue }
        $text = [System.IO.File]::ReadAllText($vdf)
        foreach ($m in [regex]::Matches($text, '"path"\s*"([^"]+)"')) {
            # VDF escapes backslashes as "\\"; unescape to a real Windows path.
            $roots.Add(($m.Groups[1].Value -replace '\\\\', '\'))
        }
    }

    # De-duplicate case-insensitively, preserving discovery order.
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    return $roots | Where-Object { $_ -and $seen.Add($_) }
}


function Find-MarbleWorldInstallDirUncached {
    # Auto-discover the game install folder (the one containing Marble World.exe /
    # Marble World_Data) via Steam. Throws with actionable guidance if not found -
    # we never fall back to a hardcoded path.
    $steamPath = Get-SteamLibraryPath
    if (-not $steamPath) {
        throw "Could not locate a Steam install (registry key Valve\Steam not found). A Marble World install is required."
    }

    foreach ($lib in (Get-SteamLibraryFolders -SteamPath $steamPath)) {
        # Prefer the installdir recorded in the app manifest; fall back to the
        # conventional "Marble World" folder name.
        $installDirs = [System.Collections.Generic.List[string]]::new()
        $acf = Join-Path $lib "steamapps\appmanifest_$MarbleWorldAppId.acf"
        if (Test-Path $acf) {
            $acfText = [System.IO.File]::ReadAllText($acf)
            $im = [regex]::Match($acfText, '"installdir"\s*"([^"]+)"')
            if ($im.Success) { $installDirs.Add($im.Groups[1].Value) }
        }
        $installDirs.Add("Marble World")

        foreach ($installDir in $installDirs) {
            $gameDir = Join-Path $lib "steamapps\common\$installDir"
            if (Test-Path (Join-Path $gameDir "$GameDataFolder\Managed\Assembly-CSharp.dll")) {
                return $gameDir
            }
        }
    }

    throw "Could not find a Marble World (Steam AppID $MarbleWorldAppId) install in any Steam library. Install the game first."
}


function Find-MarbleWorldInstallDir {
    # Cached wrapper around the Steam discovery: reuse the previously found install
    # folder if it still looks valid, otherwise rediscover and re-cache it.
    if (Test-Path -LiteralPath $InstallCacheFile) {
        $cached = (Get-Content -LiteralPath $InstallCacheFile -Raw).Trim()
        if ($cached -and (Test-Path (Join-Path $cached "$GameDataFolder\Managed\Assembly-CSharp.dll"))) {
            return $cached
        }
    }
    $gameDir = Find-MarbleWorldInstallDirUncached
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    Set-Content -LiteralPath $InstallCacheFile -Value $gameDir -Encoding ascii
    return $gameDir
}


function Find-MarbleWorldManagedDir {
    # The game's Managed folder (source of the Unity + Assembly-CSharp reference
    # DLLs), under the auto-discovered install folder.
    return Join-Path (Find-MarbleWorldInstallDir) "$GameDataFolder\Managed"
}


function Initialize-BuildReferences {
    # Ensure lib\ holds every reference DLL the .csproj needs. Idempotent: only
    # fetches/copies what is missing. Touches a game install only if the game
    # DLLs are not already vendored.
    New-Item -ItemType Directory -Force -Path $LibDir | Out-Null

    # BepInEx.dll - from the downloaded, hash-verified release zip.
    $bepDest = Join-Path $LibDir "BepInEx.dll"
    if (Test-Path $bepDest) {
        Write-Host "Vendored: BepInEx.dll (already present)"
    }
    else {
        $zip = Get-BepInExArchive
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $entry = $archive.GetEntry($BepInExDllEntry)
            if (-not $entry) {
                throw "Entry '$BepInExDllEntry' not found in $zip"
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $bepDest, $true)
        }
        finally {
            $archive.Dispose()
        }
        Write-Host "Vendored: BepInEx.dll (extracted from $BepInExZipName)"
    }

    # Unity + Assembly-CSharp - copied from the auto-discovered game install, but
    # only if any are missing (so a present install is not required on rebuilds).
    $missing = $ManagedDllNames | Where-Object { -not (Test-Path (Join-Path $LibDir $_)) }
    if (-not $missing) {
        Write-Host "Vendored: game DLLs (all already present)"
        return
    }

    $managed = Find-MarbleWorldManagedDir
    Write-Host "Discovered game Managed dir: $managed"
    foreach ($dll in $missing) {
        $src = Join-Path $managed $dll
        if (-not (Test-Path $src)) {
            throw "Expected game DLL not found: $src"
        }
        Copy-Item -Path $src -Destination $LibDir
        Write-Host "Vendored: $dll (from game install)"
    }
}


# Run provisioning when invoked directly (not when dot-sourced for reuse).
if ($MyInvocation.InvocationName -ne '.') {
    Initialize-BuildReferences
    Write-Host "lib\ is ready: $LibDir"
}
