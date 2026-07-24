@echo off
if /i not "%~1"=="patch" if /i not "%~1"=="minor" if /i not "%~1"=="major" (
    echo Usage: build.cmd patch^|minor^|major
    echo Bumps the mod version in manifest.json + mmapi_mod_declare and zips a release into dist\.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %1
exit /b %ERRORLEVEL%
