@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-yang-mi-skin.ps1" -ThemeId bridal-moonlight -RestartExisting
pause
