@echo off
rem Removes the Forever Planner updater (the scheduled task and its files). The addon itself stays installed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Unregister-ScheduledTask -TaskName 'Forever Planner updater' -Confirm:$false -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA 'ForeverPlanner') -ErrorAction SilentlyContinue; Write-Host 'Updater removed. The addon is still installed.'"
echo.
pause
