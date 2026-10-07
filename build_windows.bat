@echo off
rem D395: build the Windows release of Black | White.
rem   build_windows.bat            -> dist\BlackWhite-<date>\ and dist\BlackWhite-<date>.zip
rem   build_windows.bat tests      -> dist\selftest\ (debug export of "Windows Desktop (tests)": run
rem                                    dist\selftest\BlackWhite.console.exe -- --self-test)
rem Needs Godot 4.7 stable export templates in %APPDATA%\Godot\export_templates\4.7.stable\.
rem Set GODOT to your Godot 4.7 console binary if it is not at the default path.
setlocal
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set STAMP=%%d

set MODE=--export-release
if /i "%~1"=="tests" (
  set PRESET=Windows Desktop ^(tests^)
  set OUT=%ROOT%\dist\selftest
  set MODE=--export-debug
) else (
  set PRESET=Windows Desktop
  set OUT=%ROOT%\dist\BlackWhite-%STAMP%
)

if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%" || exit /b 1

"%GODOT%" --headless --path "%ROOT%\game" --import
"%GODOT%" --headless --path "%ROOT%\game" %MODE% "%PRESET%" "%OUT%\BlackWhite.exe"
if errorlevel 1 (echo Export failed. & exit /b 1)
if not exist "%OUT%\BlackWhite.exe" (echo Export produced no exe. & exit /b 1)
if not exist "%OUT%\BlackWhite.pck" (echo Export produced no pck. & exit /b 1)

if /i "%~1"=="tests" (echo Built %OUT% & exit /b 0)

copy /y "%ROOT%\packaging\README.txt" "%OUT%\README.txt" >nul
if exist "%ROOT%\dist\BlackWhite-%STAMP%.zip" del "%ROOT%\dist\BlackWhite-%STAMP%.zip"
powershell -NoProfile -Command "Compress-Archive -Path '%OUT%' -DestinationPath '%ROOT%\dist\BlackWhite-%STAMP%.zip'"
if errorlevel 1 (echo Zip failed. & exit /b 1)
echo Built %OUT%
echo Zipped %ROOT%\dist\BlackWhite-%STAMP%.zip
exit /b 0
