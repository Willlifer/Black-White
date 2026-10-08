@echo off
rem D395/D466: build the Windows release of Black | White.
rem   build_windows.bat            -> dist\BlackWhite-<date>.exe  (ONE file: the game data is embedded)
rem   build_windows.bat tests      -> dist\selftest\ (debug export of "Windows Desktop (tests)": run
rem                                    dist\selftest\BlackWhite.console.exe -- --self-test)
rem Needs Godot 4.7 stable export templates in %APPDATA%\Godot\export_templates\4.7.stable\.
rem Set GODOT to your Godot 4.7 console binary if it is not at the default path.
setlocal
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set STAMP=%%d

"%GODOT%" --headless --path "%ROOT%\game" --import

if /i "%~1"=="tests" (
  if exist "%ROOT%\dist\selftest" rmdir /s /q "%ROOT%\dist\selftest"
  mkdir "%ROOT%\dist\selftest" || exit /b 1
  "%GODOT%" --headless --path "%ROOT%\game" --export-debug "Windows Desktop (tests)" "%ROOT%\dist\selftest\BlackWhite.exe"
  if not exist "%ROOT%\dist\selftest\BlackWhite.pck" (echo Export produced no pck. & exit /b 1)
  echo Built %ROOT%\dist\selftest
  exit /b 0
)

set TMP=%ROOT%\dist\.build
if exist "%TMP%" rmdir /s /q "%TMP%"
mkdir "%TMP%" || exit /b 1
"%GODOT%" --headless --path "%ROOT%\game" --export-release "Windows Desktop" "%TMP%\BlackWhite.exe"
if errorlevel 1 (echo Export failed. & exit /b 1)
if not exist "%TMP%\BlackWhite.exe" (echo Export produced no exe. & exit /b 1)
move /y "%TMP%\BlackWhite.exe" "%ROOT%\dist\BlackWhite-%STAMP%.exe" >nul
rmdir /s /q "%TMP%"
echo Built %ROOT%\dist\BlackWhite-%STAMP%.exe
exit /b 0
