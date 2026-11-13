@echo off
rem Sets up automatic updates for Forever Planner. Safe to run again.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Updater.ps1"
