@echo off
rem Black | White self-test. Exit 0 = green.
rem Set GODOT to your Godot 4.7 console binary if it is not at the default path.
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
"%GODOT%" --headless --path "%~dp0." --import
"%GODOT%" --headless --path "%~dp0." -- --self-test
exit /b %ERRORLEVEL%
