@echo off
call build.bat
if errorlevel 1 exit /b 1

REM -hdosvirt/-hdosdir: the program's HYPPO file calls (d81attach, loadfile) see target\
C:\Emulation\Mega65\xmega65.exe -8 "%~dp0target\archon65.d81" -autoload -hdosvirt -hdosdir "%~dp0target"
