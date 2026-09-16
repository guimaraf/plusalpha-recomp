@echo off
setlocal
cd /d "%~dp0\.."
if exist "buildTele-s1-268\StreetFighterEXPlusAlphaRecomp.exe" (
    echo Iniciando Street Fighter EX Plus Alpha [buildTele-s1-268] com telemetria na porta 4531...
    "buildTele-s1-268\StreetFighterEXPlusAlphaRecomp.exe" --game "game.toml" --disc "disc-a\Street Fighter EX Plus Alpha (USA).cue"
) else (
    echo ERRO: Executavel buildTele-s1-268\StreetFighterEXPlusAlphaRecomp.exe nao encontrado!
    pause
)
