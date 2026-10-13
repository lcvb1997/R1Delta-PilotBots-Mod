@echo off
rem Builds everything for a release:
rem   native\  -> build\pilotbots.dll, build\pbinject.exe  (x64, static CRT, own MinHook copy)
rem   copies them into installer\payload and installer\ferramentas
rem   installer\PilotBots.iss -> release\PilotBots_R1Delta_Setup_<version>.exe (+ release\pilotbots.dll)
rem Needs Visual Studio (C++ desktop workload) and Inno Setup 6.
setlocal
cd /d "%~dp0"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq delims=" %%i in (`call "%VSWHERE%" -latest -products * -property installationPath`) do set "VS=%%i"
if not defined VS (echo Visual Studio not found & exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

if not exist build\obj mkdir build\obj
set MH=native\thirdparty\minhook
set CFLAGS=/nologo /O2 /MT /W3 /EHsc /std:c++17 /DNDEBUG /DWIN32_LEAN_AND_MEAN

cl %CFLAGS% /LD /I%MH%\include /Fobuild\obj\ native\src\pilotbots.cpp %MH%\src\hook.c %MH%\src\buffer.c %MH%\src\trampoline.c %MH%\src\hde\hde64.c /Febuild\pilotbots.dll /link /NOLOGO || exit /b 1
cl %CFLAGS% /Fobuild\obj\ native\tools\pbinject.cpp /Febuild\pbinject.exe /link /NOLOGO || exit /b 1

if not exist installer\payload\POMotorNativoBots mkdir installer\payload\POMotorNativoBots
if not exist installer\ferramentas mkdir installer\ferramentas
copy /y build\pilotbots.dll installer\payload\POMotorNativoBots\ >nul || exit /b 1
copy /y build\pbinject.exe installer\ferramentas\ >nul || exit /b 1

set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (echo Inno Setup 6 not found & exit /b 1)
"%ISCC%" /Q installer\PilotBots.iss || exit /b 1
copy /y build\pilotbots.dll release\ >nul

echo.
echo BUILD OK - release\
dir /b release
