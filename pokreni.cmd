@echo off
rem Dvoklik pokrece Fotograf na ovom racunaru (http://localhost:8080).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pokreni.ps1" %*
pause
