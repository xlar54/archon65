@echo off
setlocal
REM MEGA65 build: compile the assets, assemble with 64tass, write the D81 with c1541.
REM Rename PROJECT for a new project. The game must be the first file on the disk
REM (Xemu -autoload RUNs the first file) and is also written as AUTOBOOT.C65, which a real
REM MEGA65 starts from the mounted disk.
set PROJECT=archon65
if not exist target mkdir target
REM c1541 writes its settings under the user profile: keep them inside target\
if not exist target\userprofile\AppData\Roaming mkdir target\userprofile\AppData\Roaming
set "USERPROFILE=%CD%\target\userprofile"
set "APPDATA=%USERPROFILE%\AppData\Roaming"

del target\*.d81 2>nul
del target\*.lst 2>nul
del target\*.lbl 2>nul
del target\%PROJECT% 2>nul

REM Assets: src\assets (PNG sprite sheets, asm tables) -> src\gen\*, target\assets\*.
python tools\build_assets.py
if errorlevel 1 exit /b 1

.\64tass.exe --cbm-prg -C -I src src\main.asm -l target\%PROJECT%.lbl -o target\%PROJECT%
if errorlevel 1 exit /b 1

cd target
..\c1541.exe -format "%PROJECT%,01" d81 %PROJECT%.d81 >nul
if errorlevel 1 (cd .. & exit /b 1)
..\c1541.exe -attach %PROJECT%.d81 -write %PROJECT% %PROJECT% >nul
if errorlevel 1 (cd .. & exit /b 1)
..\c1541.exe -attach %PROJECT%.d81 -write %PROJECT% autoboot.c65 >nul
if errorlevel 1 (cd .. & exit /b 1)
REM asset files listed by tools\build_assets.py (written lower case = PETSCII upper case)
for /f %%f in (assets\files.txt) do (
    ..\c1541.exe -attach %PROJECT%.d81 -write assets\%%f %%f >nul
    if errorlevel 1 (echo failed writing %%f & cd .. & exit /b 1)
)
cd ..

REM keep only the D81 and the labels (the Xemu test harness reads them)
del target\%PROJECT% 2>nul
rmdir /s /q target\assets 2>nul
rmdir /s /q target\userprofile 2>nul

echo Built target\%PROJECT%.d81
