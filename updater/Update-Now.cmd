@echo off
rem Checks for a Forever Planner update right now.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-ForeverPlanner.ps1"
echo.
pause
