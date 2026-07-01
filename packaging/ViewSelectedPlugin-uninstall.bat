@echo off
rem Double-click launcher for ViewSelectedPlugin-uninstall.ps1 (.ps1 files are not
rem run on double-click by default). Runs the PowerShell uninstaller next to this
rem file, bypassing the execution policy for this one process only, and passes
rem -Pause so the window stays open until you press Enter. The uninstaller deletes
rem this .bat too (as a file listed in the manifest); it is the last command, so
rem cmd finishes cleanly afterward.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ViewSelectedPlugin-uninstall.ps1" -Pause
