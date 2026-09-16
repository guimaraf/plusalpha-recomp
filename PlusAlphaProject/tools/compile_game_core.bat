@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Compile Recompiled Game Core into game_core.dll with Tiny C Compiler (TCC)
:: PSXRecomp / Street Fighter Street Fighter EX Plus Alpha - Clean-Room Local Pipeline
:: ============================================================================

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."

if exist "%PROJECT_ROOT%\..\game.toml" (
    set "GAME_ROOT=%PROJECT_ROOT%\.."
) else if exist "%PROJECT_ROOT%\game.toml" (
    set "GAME_ROOT=%PROJECT_ROOT%"
) else (
    set "GAME_ROOT=%PROJECT_ROOT%"
)

if exist "%GAME_ROOT%\generated\SLUS_005.48_full.c" (
    set "ROOT=%GAME_ROOT%"
) else if exist "%PROJECT_ROOT%\generated\SLUS_005.48_full.c" (
    set "ROOT=%PROJECT_ROOT%"
) else (
    set "ROOT=%GAME_ROOT%"
)
pushd "%ROOT%"

set "TCC_EXE=%PROJECT_ROOT%\overlay_toolchain\tcc\tcc.exe"
if not exist "%TCC_EXE%" set "TCC_EXE=%GAME_ROOT%\overlay_toolchain\tcc\tcc.exe"
if not exist "%TCC_EXE%" set "TCC_EXE=%ROOT%\overlay_toolchain\tcc\tcc.exe"

set "RUNTIME_INC=%PROJECT_ROOT%\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%GAME_ROOT%\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%ROOT%\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%PROJECT_ROOT%\..\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%GAME_ROOT%\..\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%PROJECT_ROOT%\compileBuild\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%GAME_ROOT%\compileBuild\psxrecomp\runtime\include"

set "VARS_FILE=%SCRIPT_DIR%game_core_vars.c"
if not exist "%VARS_FILE%" set "VARS_FILE=%PROJECT_ROOT%\tools\game_core_vars.c"
if not exist "%VARS_FILE%" set "VARS_FILE=%ROOT%\tools\game_core_vars.c"

set "FULL_C=%ROOT%\generated\SLUS_005.48_full.c"
if not exist "%FULL_C%" set "FULL_C=%GAME_ROOT%\generated\SLUS_005.48_full.c"
if not exist "%FULL_C%" set "FULL_C=%PROJECT_ROOT%\generated\SLUS_005.48_full.c"
if not exist "%FULL_C%" set "FULL_C=%GAME_ROOT%\..\generated\SLUS_005.48_full.c"
if not exist "%FULL_C%" set "FULL_C=%PROJECT_ROOT%\..\..\generated\SLUS_005.48_full.c"

set "DISPATCH_C=%ROOT%\generated\SLUS_005.48_dispatch.c"
if not exist "%DISPATCH_C%" set "DISPATCH_C=%GAME_ROOT%\generated\SLUS_005.48_dispatch.c"
if not exist "%DISPATCH_C%" set "DISPATCH_C=%PROJECT_ROOT%\generated\SLUS_005.48_dispatch.c"
if not exist "%DISPATCH_C%" set "DISPATCH_C=%GAME_ROOT%\..\generated\SLUS_005.48_dispatch.c"
if not exist "%DISPATCH_C%" set "DISPATCH_C=%PROJECT_ROOT%\..\..\generated\SLUS_005.48_dispatch.c"

set "DEF_FILE=%SCRIPT_DIR%launcher.def"
if not exist "%DEF_FILE%" set "DEF_FILE=%PROJECT_ROOT%\tools\launcher.def"
if not exist "%DEF_FILE%" set "DEF_FILE=%GAME_ROOT%\tools\launcher.def"
if not exist "%DEF_FILE%" set "DEF_FILE=%GAME_ROOT%\compileBuild\tools\launcher.def"
if not exist "%DEF_FILE%" set "DEF_FILE=%ROOT%\tools\launcher.def"

set "OUT_DLL=%GAME_ROOT%\game_core.dll"

if not exist "%TCC_EXE%" (
    echo [ERROR] Embedded TCC not found at: %TCC_EXE%
    exit /b 1
)
if not exist "%FULL_C%" (
    echo [ERROR] Recompiled source not found: %FULL_C%
    echo Please run the recompiler psxrecomp-game first.
    exit /b 1
)
if not exist "%DISPATCH_C%" (
    echo [ERROR] Recompiled dispatch not found: %DISPATCH_C%
    exit /b 1
)
if not exist "%DEF_FILE%" (
    echo [ERROR] Launcher definition file not found: %DEF_FILE%
    exit /b 1
)

echo [TCC] Compiling game_core.dll with embedded TinyCC (~8 seconds)...
"%TCC_EXE%" -shared -rdynamic ^
    -DPSX_NO_DEBUG_TOOLS ^
    -DPSX_ENABLE_BLOCK_CYCLES=1 ^
    -I"%RUNTIME_INC%" ^
    "%FULL_C%" "%DISPATCH_C%" "%VARS_FILE%" "%DEF_FILE%" ^
    -o "%OUT_DLL%"

if %ERRORLEVEL% EQU 0 (
    echo [TCC] Successfully compiled game_core.dll to: %OUT_DLL%
    if exist "%PROJECT_ROOT%" if not "%OUT_DLL%"=="%PROJECT_ROOT%\game_core.dll" (
        copy /Y "%OUT_DLL%" "%PROJECT_ROOT%\game_core.dll" >nul 2>&1
    )
    if exist "%ROOT%" if not "%OUT_DLL%"=="%ROOT%\game_core.dll" (
        copy /Y "%OUT_DLL%" "%ROOT%\game_core.dll" >nul 2>&1
        echo [TCC] Mirrored to %ROOT%\game_core.dll
    )
    if exist "%ROOT%\buildClean-ucrt-s1-268" if not "%OUT_DLL%"=="%ROOT%\buildClean-ucrt-s1-268\game_core.dll" (
        copy /Y "%OUT_DLL%" "%ROOT%\buildClean-ucrt-s1-268\game_core.dll" >nul 2>&1
        echo [TCC] Mirrored to %ROOT%\buildClean-ucrt-s1-268\game_core.dll
    )
    if exist "%ROOT%\PlusAlphaProject" if not "%OUT_DLL%"=="%ROOT%\PlusAlphaProject\game_core.dll" (
        copy /Y "%OUT_DLL%" "%ROOT%\PlusAlphaProject\game_core.dll" >nul 2>&1
        echo [TCC] Mirrored to %ROOT%\PlusAlphaProject\game_core.dll
    )
) else (
    echo [ERROR] Failed to compile game_core.dll (exit code %ERRORLEVEL%)
    exit /b %ERRORLEVEL%
)

popd
