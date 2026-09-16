@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Compile Combat Overlays with Embedded Tiny C Compiler (TCC)
:: PSXRecomp / Street Fighter EX Plus Alpha - Standalone Zero-Install Toolchain
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
pushd "%PROJECT_ROOT%"

set "CAPTURES=%PROJECT_ROOT%\overlay_captures.json"
if not exist "%CAPTURES%" set "CAPTURES=%GAME_ROOT%\overlay_captures.json"
if not exist "%CAPTURES%" set "CAPTURES=%ROOT%\overlay_captures.json"
if not exist "%CAPTURES%" set "CAPTURES=%ROOT%\PlusAlphaProject\overlay_captures.json"

set "GAME_TOML=%GAME_ROOT%\game.toml"
if not exist "%GAME_TOML%" set "GAME_TOML=%PROJECT_ROOT%\game.toml"
if not exist "%GAME_TOML%" set "GAME_TOML=%ROOT%\game.toml"

set "RECOMPILER=%PROJECT_ROOT%\overlay_toolchain\psxrecomp-game.exe"
if not exist "%RECOMPILER%" set "RECOMPILER=%GAME_ROOT%\overlay_toolchain\psxrecomp-game.exe"
if not exist "%RECOMPILER%" set "RECOMPILER=%ROOT%\overlay_toolchain\psxrecomp-game.exe"
if not exist "%RECOMPILER%" set "RECOMPILER=%ROOT%\psxrecomp\recompiler\build\psxrecomp-game.exe"
if not exist "%RECOMPILER%" set "RECOMPILER=%PROJECT_ROOT%\..\psxrecomp\recompiler\build\psxrecomp-game.exe"

set "RUNTIME_INC=%PROJECT_ROOT%\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%GAME_ROOT%\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%ROOT%\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%PROJECT_ROOT%\..\psxrecomp\runtime\include"
if not exist "%RUNTIME_INC%" set "RUNTIME_INC=%PROJECT_ROOT%\compileBuild\psxrecomp\runtime\include"

set "TCC_EXE=%PROJECT_ROOT%\overlay_toolchain\tcc\tcc.exe"
if not exist "%TCC_EXE%" set "TCC_EXE=%GAME_ROOT%\overlay_toolchain\tcc\tcc.exe"
if not exist "%TCC_EXE%" set "TCC_EXE=%ROOT%\overlay_toolchain\tcc\tcc.exe"

set "SCRIPT=%PROJECT_ROOT%\psxrecomp\tools\compile_overlays.py"
if not exist "%SCRIPT%" set "SCRIPT=%GAME_ROOT%\psxrecomp\tools\compile_overlays.py"
if not exist "%SCRIPT%" set "SCRIPT=%ROOT%\psxrecomp\tools\compile_overlays.py"
if not exist "%SCRIPT%" set "SCRIPT=%PROJECT_ROOT%\..\psxrecomp\tools\compile_overlays.py"
if not exist "%SCRIPT%" set "SCRIPT=%PROJECT_ROOT%\compileBuild\psxrecomp\tools\compile_overlays.py"

set "CACHE_OUT=%GAME_ROOT%\cache"
if not exist "%CACHE_OUT%" mkdir "%CACHE_OUT%" >nul 2>&1

set "PYTHON_EXE=%PROJECT_ROOT%\overlay_toolchain\python\python.exe"
if not exist "%PYTHON_EXE%" set "PYTHON_EXE=%GAME_ROOT%\overlay_toolchain\python\python.exe"
if not exist "%PYTHON_EXE%" set "PYTHON_EXE=%ROOT%\overlay_toolchain\python\python.exe"
if not exist "%PYTHON_EXE%" (
    where python >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        set "PYTHON_EXE=python"
    ) else (
        echo [ERROR] Python not found in overlay_toolchain\python\python.exe or PATH.
        exit /b 1
    )
)

if not exist "%CAPTURES%" (
    echo [ERROR] Overlay captures not found: %CAPTURES%
    exit /b 1
)
if not exist "%RECOMPILER%" (
    echo [ERROR] Recompiler not found: %RECOMPILER%
    exit /b 1
)
if not exist "%TCC_EXE%" (
    echo [ERROR] TCC binary not found: %TCC_EXE%
    exit /b 1
)
if not exist "%SCRIPT%" (
    echo [ERROR] Compile overlays script not found: %SCRIPT%
    exit /b 1
)

echo [TCC] Compiling combat overlay DLLs with embedded TCC...
"%PYTHON_EXE%" "%SCRIPT%" ^
    --captures "%CAPTURES%" ^
    --game-toml "%GAME_TOML%" ^
    --recompiler "%RECOMPILER%" ^
    --runtime-include "%RUNTIME_INC%" ^
    --out-dir "%CACHE_OUT%" ^
    --compiler tcc ^
    --tcc "%TCC_EXE%" ^
    --cps

if %ERRORLEVEL% EQU 0 (
    echo [TCC] Overlays compiled successfully into %CACHE_OUT%!
    if exist "%ROOT%\buildClean-ucrt-s1-268" if not "%CACHE_OUT%"=="%ROOT%\buildClean-ucrt-s1-268\cache" (
        if not exist "%ROOT%\buildClean-ucrt-s1-268\cache" mkdir "%ROOT%\buildClean-ucrt-s1-268\cache" >nul 2>&1
        xcopy /E /I /Y "%CACHE_OUT%" "%ROOT%\buildClean-ucrt-s1-268\cache\" >nul 2>&1
    )
    if exist "%ROOT%\PlusAlphaProject" if not "%CACHE_OUT%"=="%ROOT%\PlusAlphaProject\cache" (
        if not exist "%ROOT%\PlusAlphaProject\cache" mkdir "%ROOT%\PlusAlphaProject\cache" >nul 2>&1
        xcopy /E /I /Y "%CACHE_OUT%" "%ROOT%\PlusAlphaProject\cache\" >nul 2>&1
    )
) else (
    echo [ERROR] Overlay compilation failed with exit code %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

popd
