@echo off
rem D492: the browser build for Vercel -> web\ (index.html + wasm + pck). Commit web\ and push.
rem Needs the Godot 4.7 web export templates (web_nothreads_release.zip) in %APPDATA%\Godot\export_templates\4.7.stable\.
setlocal
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%
"%GODOT%" --headless --path "%ROOT%\game" --import
"%GODOT%" --headless --path "%ROOT%\game" --export-release "Web" "%ROOT%\web\index.html"
if not exist "%ROOT%\web\index.pck" (echo Export produced no pck. & exit /b 1)
echo Built %ROOT%\web
exit /b 0
