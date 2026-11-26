@echo off
rem Wrapper: instala o toolchain portatil (veja setup_portable_toolchain.ps1 -?). Repassa os argumentos.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_portable_toolchain.ps1" %*
exit /b %ERRORLEVEL%
