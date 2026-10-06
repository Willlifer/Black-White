@echo off
rem Launch Black | White.
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe
start "" "%GODOT%" --path "%~dp0."
