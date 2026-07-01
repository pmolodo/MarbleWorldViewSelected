#!/usr/bin/env -S powershell -NoProfile -ExecutionPolicy Bypass -File
<#
.SYNOPSIS
    Uninstalls ViewSelected by deleting every file listed in
    ViewSelectedPlugin-manifest.txt, then removing directories left empty.

.DESCRIPTION
    Reads the manifest sitting next to this script and deletes each file it lists
    (paths are relative to this script's own folder). It records every directory a
    file was removed from, then - after all files are gone - deletes any of those
    directories that are now empty, walking upward and removing each newly empty
    parent too. The walk stops at this script's own folder, which (like anything
    above it) is never removed.

    This script and the manifest are themselves listed in the manifest, so a
    successful run leaves nothing behind.

    Best-effort: a file or directory that cannot be removed (e.g. locked) is
    reported and the run continues; the script exits non-zero if anything failed.
#>
[CmdletBinding()]
param(
    # Prompt before exiting. Set by the .bat wrapper so the console window stays
    # open long enough to read the output when launched by double-click.
    [switch]$Pause
)

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$ManifestName = "ViewSelectedPlugin-manifest.txt"
$ManifestPath = Join-Path $Root $ManifestName


function Remove-EmptyDirsUpward {
    # For each seed directory, delete it if empty, then repeat on its parent,
    # walking up until a non-empty directory, a missing directory, or the script
    # root (exclusive) is reached. Ancestors not in the seed set are still cleaned
    # if they become empty as their children are removed.
    param(
        [System.Collections.Generic.IEnumerable[string]]$Dirs,
        [string]$RootFull,
        [System.Collections.Generic.List[string]]$Failures
    )
    $rootPrefix = $RootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    foreach ($seed in $Dirs) {
        $dir = [System.IO.Path]::GetFullPath($seed)
        while ($true) {
            # Never touch the script root or anything at/above it.
            if ($dir.Equals($RootFull, [System.StringComparison]::OrdinalIgnoreCase)) { break }
            if (-not $dir.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { break }
            if (-not (Test-Path -LiteralPath $dir)) { break }
            # Stop as soon as a directory still holds any file or subdirectory.
            if (@(Get-ChildItem -Force -LiteralPath $dir).Count -ne 0) { break }
            try {
                Remove-Item -LiteralPath $dir -Force -ErrorAction Stop
                Write-Host "Removed empty dir: $dir"
            }
            catch {
                $Failures.Add("[dir] $dir  ($($_.Exception.Message))")
                Write-Warning "Could not remove dir: $dir - $($_.Exception.Message)"
                break
            }
            $dir = [System.IO.Path]::GetDirectoryName($dir)
            if ([string]::IsNullOrEmpty($dir)) { break }
        }
    }
}


function Invoke-Uninstall {
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest not found next to this script: $ManifestPath"
    }

    # Read the whole manifest up front, so deleting the manifest itself mid-run is
    # safe. Blank lines are ignored.
    $relPaths = @(Get-Content -LiteralPath $ManifestPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" })

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $touchedDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $failures = [System.Collections.Generic.List[string]]::new()

    foreach ($rel in $relPaths) {
        $target = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $target)) {
            Write-Host "Skipped (already gone): $rel"
            continue
        }
        $dir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($target))
        try {
            Remove-Item -LiteralPath $target -Force -ErrorAction Stop
            Write-Host "Removed: $rel"
            [void]$touchedDirs.Add($dir)
        }
        catch {
            $failures.Add("$rel  ($($_.Exception.Message))")
            Write-Warning "Could not remove: $rel - $($_.Exception.Message)"
        }
    }

    Remove-EmptyDirsUpward -Dirs $touchedDirs -RootFull $rootFull -Failures $failures

    Write-Host ""
    if ($failures.Count -gt 0) {
        Write-Warning "ViewSelected uninstall finished with $($failures.Count) problem(s):"
        foreach ($f in $failures) { Write-Warning "  $f" }
        return 1
    }
    Write-Host "ViewSelected uninstalled cleanly."
    return 0
}


$exitCode = Invoke-Uninstall
if ($Pause) {
    Read-Host "Press Enter to close"
}
exit $exitCode
