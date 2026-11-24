@echo off
rem Exports the Android debug APK to builds\HighwayBlitzGodot.apk (git-ignored).
rem The web build is made and deployed by GitHub Actions on every push to main.
setlocal
cd /d "%~dp0"

set "GODOT=C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo Godot not found at %GODOT%
    exit /b 1
)

if not exist builds mkdir builds
rem Keep Godot from importing the exported files back into the project.
if not exist builds\.gdignore type nul > builds\.gdignore

echo === Exporting Android APK to builds\HighwayBlitzGodot.apk ===
if exist builds\HighwayBlitzGodot.apk del /q builds\HighwayBlitzGodot.apk
"%GODOT%" --headless --path . --export-debug "Android" builds/HighwayBlitzGodot.apk
if errorlevel 1 (
    echo Export failed.
    exit /b 1
)
if not exist builds\HighwayBlitzGodot.apk (
    echo Export failed: the APK was not created.
    exit /b 1
)
echo === Done: builds\HighwayBlitzGodot.apk ===
endlocal
