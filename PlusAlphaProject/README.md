# Street Fighter EX Plus Alpha Recomp

Configuração específica do port de **Street Fighter EX Plus Alpha**, edição USA
`SLUS-00548`, para o framework PSXRecomp.

## Conteúdo versionado

- `game.toml`: identidade e configuração do jogo;
- `seeds/entry_funcs.txt`: entradas estáticas aprovadas da baseline;
- `tools/extract_psx_exe.py`: extração local do executável principal;
- `tools/generate_game.ps1`: geração validada dos fontes do jogo;
- `tools/configure_runtime.ps1`: configuração do runtime com MSYS2 UCRT64;
- `DISC.md` e `BIOS.md`: hashes das únicas entradas aceitas.

## Conteúdo exclusivamente local

- `disc-a/`: imagem CUE/BIN fornecida pelo usuário;
- `local/`: executável `SLUS_005.48` extraído pelo usuário;
- `generated/`: fontes produzidos pelo recompiler;
- `build*/`: artefatos de compilação;
- `saves/`: cartões de memória e saves.

Esses diretórios são ignorados pelo Git e não fazem parte da distribuição.

O framework usado pelo port fica em `../psxrecomp/` como submódulo fixado. Veja
`BUILD_LOCAL.md` para preparar uma cópia local.
