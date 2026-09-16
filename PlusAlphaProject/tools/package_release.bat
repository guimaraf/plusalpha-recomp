@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Package Decoupled Clean-Room Release Bundle
:: Street Fighter EX Plus Alpha Recomp (Zero Proprietary Assets)
:: ============================================================================

set "PROJECT_ROOT=%~dp0.."
pushd "%PROJECT_ROOT%"

if not "%~1"=="" (
    if exist "%~1" (
        set "OUT_DIR=%~f1"
    ) else (
        set "OUT_DIR=%PROJECT_ROOT%\%~1"
    )
) else (
    set "OUT_DIR=%PROJECT_ROOT%\buildNoCopyright-s1-268"
)
set "LAUNCHER_EXE=%PROJECT_ROOT%\buildLauncher\StreetFighterEXPlusAlpha_Launcher.exe"

if not exist "%LAUNCHER_EXE%" (
    echo [ERROR] Launcher executable not found: %LAUNCHER_EXE%
    echo Please build StreetFighterEXPlusAlpha_Launcher first.
    exit /b 1
)

echo [RELEASE] Cleaning previous release package...
if exist "%OUT_DIR%" rmdir /s /q "%OUT_DIR%"
mkdir "%OUT_DIR%"
mkdir "%OUT_DIR%\compileBuild"
mkdir "%OUT_DIR%\compileBuild\tools"
mkdir "%OUT_DIR%\compileBuild\overlay_toolchain"
mkdir "%OUT_DIR%\compileBuild\overlay_toolchain\tcc"
mkdir "%OUT_DIR%\compileBuild\psxrecomp\runtime\include"
mkdir "%OUT_DIR%\compileBuild\psxrecomp\tools"

echo [RELEASE] Copying StreetFighterEXPlusAlpha_Launcher.exe and runtime dependencies...
copy /Y "%LAUNCHER_EXE%" "%OUT_DIR%\StreetFighterEXPlusAlpha_Launcher.exe" >nul
copy /Y "%PROJECT_ROOT%\buildLauncher\SDL2.dll" "%OUT_DIR%\SDL2.dll" >nul
if exist "%PROJECT_ROOT%\buildLauncher\libgcc_s_seh-1.dll" copy /Y "%PROJECT_ROOT%\buildLauncher\libgcc_s_seh-1.dll" "%OUT_DIR%\" >nul
if exist "%PROJECT_ROOT%\buildLauncher\libwinpthread-1.dll" copy /Y "%PROJECT_ROOT%\buildLauncher\libwinpthread-1.dll" "%OUT_DIR%\" >nul
if exist "%PROJECT_ROOT%\buildLauncher\libstdc++-6.dll" copy /Y "%PROJECT_ROOT%\buildLauncher\libstdc++-6.dll" "%OUT_DIR%\" >nul

where strip >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [RELEASE] Stripping debug symbols from release executable...
    strip "%OUT_DIR%\StreetFighterEXPlusAlpha_Launcher.exe"
) else if exist "C:\msys64\ucrt64\bin\strip.exe" (
    echo [RELEASE] Stripping debug symbols from release executable...
    "C:\msys64\ucrt64\bin\strip.exe" "%OUT_DIR%\StreetFighterEXPlusAlpha_Launcher.exe"
)

echo [RELEASE] Copying config files and launcher UI assets...
copy /Y "%PROJECT_ROOT%\game.toml" "%OUT_DIR%\game.toml" >nul
if exist "%PROJECT_ROOT%\overlay_captures.json" copy /Y "%PROJECT_ROOT%\overlay_captures.json" "%OUT_DIR%\compileBuild\overlay_captures.json" >nul
if not exist "%OUT_DIR%\compileBuild\overlay_captures.json" if exist "%PROJECT_ROOT%\buildClean-ucrt-s1-268\overlay_captures.json" copy /Y "%PROJECT_ROOT%\buildClean-ucrt-s1-268\overlay_captures.json" "%OUT_DIR%\compileBuild\overlay_captures.json" >nul
if exist "%PROJECT_ROOT%\keybinds.ini" copy /Y "%PROJECT_ROOT%\keybinds.ini" "%OUT_DIR%\keybinds.ini" >nul
copy /Y "%PROJECT_ROOT%\buildLauncher\launcher.rml" "%OUT_DIR%\launcher.rml" >nul
if exist "%PROJECT_ROOT%\buildLauncher\launcher.rcss" copy /Y "%PROJECT_ROOT%\buildLauncher\launcher.rcss" "%OUT_DIR%\launcher.rcss" >nul
if exist "%PROJECT_ROOT%\buildLauncher\fonts" xcopy /E /I /Y "%PROJECT_ROOT%\buildLauncher\fonts" "%OUT_DIR%\fonts" >nul
if exist "%PROJECT_ROOT%\buildLauncher\img" xcopy /E /I /Y "%PROJECT_ROOT%\buildLauncher\img" "%OUT_DIR%\img" >nul
if exist "%PROJECT_ROOT%\input.ini" copy /Y "%PROJECT_ROOT%\input.ini" "%OUT_DIR%\input.ini" >nul
if exist "%PROJECT_ROOT%\settings.toml" copy /Y "%PROJECT_ROOT%\settings.toml" "%OUT_DIR%\settings.toml" >nul

echo [RELEASE] Copying local recompile toolchain into compileBuild\...
xcopy /E /I /Y "%PROJECT_ROOT%\overlay_toolchain\tcc" "%OUT_DIR%\compileBuild\overlay_toolchain\tcc" >nul
xcopy /E /I /Y "%PROJECT_ROOT%\overlay_toolchain\python" "%OUT_DIR%\compileBuild\overlay_toolchain\python" >nul
copy /Y "%PROJECT_ROOT%\overlay_toolchain\psxrecomp-game.exe" "%OUT_DIR%\compileBuild\overlay_toolchain\psxrecomp-game.exe" >nul

echo [RELEASE] Copying build tools and scripts into compileBuild\...
copy /Y "%PROJECT_ROOT%\tools\compile_game_core.bat" "%OUT_DIR%\compileBuild\tools\compile_game_core.bat" >nul
copy /Y "%PROJECT_ROOT%\tools\compile_tcc_overlays.bat" "%OUT_DIR%\compileBuild\tools\compile_tcc_overlays.bat" >nul
copy /Y "%PROJECT_ROOT%\tools\game_core_vars.c" "%OUT_DIR%\compileBuild\tools\game_core_vars.c" >nul
copy /Y "%PROJECT_ROOT%\tools\launcher.def" "%OUT_DIR%\compileBuild\tools\launcher.def" >nul

echo [RELEASE] Copying minimal headers and compile script into compileBuild\...
xcopy /E /I /Y "%PROJECT_ROOT%\..\psxrecomp\runtime\include" "%OUT_DIR%\compileBuild\psxrecomp\runtime\include" >nul
copy /Y "%PROJECT_ROOT%\..\psxrecomp\tools\compile_overlays.py" "%OUT_DIR%\compileBuild\psxrecomp\tools\compile_overlays.py" >nul
xcopy /E /I /Y "%PROJECT_ROOT%\seeds" "%OUT_DIR%\compileBuild\seeds" >nul
xcopy /E /I /Y "%PROJECT_ROOT%\seeds" "%OUT_DIR%\seeds" >nul

echo [RELEASE] Verifying clean-room integrity (0 proprietary Capcom/Sony bytes)...
set "DIRTY=0"
if exist "%OUT_DIR%\local" set "DIRTY=1"
if exist "%OUT_DIR%\cache" set "DIRTY=1"
if exist "%OUT_DIR%\generated" set "DIRTY=1"
if exist "%OUT_DIR%\game_core.dll" set "DIRTY=1"
if exist "%OUT_DIR%\buildClean-ucrt-s1-268" set "DIRTY=1"
for /r "%OUT_DIR%" %%F in (*.bin *.cue *.iso) do (
    if exist "%%F" (
        echo [ERROR] Forbidden disc asset found: %%F
        set "DIRTY=1"
    )
)
for /r "%OUT_DIR%" %%F in (SLUS_005.48_full.c SLUS_005.48_dispatch.c) do (
    if exist "%%F" (
        echo [ERROR] Forbidden precompiled C file found: %%F
        set "DIRTY=1"
    )
)

if "!DIRTY!"=="1" (
    echo [FATAL] Clean-room release verification FAILED! Removing package...
    rmdir /s /q "%OUT_DIR%"
    exit /b 1
)

echo ============================================================================
echo [SUCCESS] Clean-room release bundle assembled at:
echo %OUT_DIR%
echo Contains 0 bytes of proprietary assets. Ready for public distribution!
echo ============================================================================

popd
