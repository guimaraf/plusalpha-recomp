# Preparação e compilação local

O port aceita somente **Street Fighter EX Plus Alpha (USA), `SLUS-00548`**.
Nenhuma BIOS ou imagem do jogo acompanha o repositório.

Os exemplos abaixo partem da raiz de `plusalpha-recomp` no Windows.

## 1. Inicializar os submódulos

Se a clonagem não usou `--recurse-submodules`:

```powershell
git submodule update --init --recursive
```

## 2. Preparar os arquivos fornecidos pelo usuário

Coloque sua BIOS SCPH-1001 validada em:

```text
psxrecomp/bios/SCPH1001.BIN
```

Coloque sua imagem CUE/BIN validada em:

```text
PlusAlphaProject/disc-a/Street Fighter EX Plus Alpha (USA).cue
PlusAlphaProject/disc-a/Street Fighter EX Plus Alpha (USA).bin
```

Confira os hashes em `PlusAlphaProject/BIOS.md` e
`PlusAlphaProject/DISC.md` antes de continuar.

## 3. Compilar as ferramentas do framework

```powershell
cmake -S .\psxrecomp\recompiler -B .\psxrecomp\recompiler\build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build .\psxrecomp\recompiler\build --target psxrecomp-game
cmake --build .\psxrecomp\recompiler\build --target psxrecomp-bios
```

## 4. Gerar os fontes locais da BIOS

```powershell
.\psxrecomp\tools\regen_bios.ps1
```

As saídas ficam em `psxrecomp/generated/` e não são versionadas.

## 5. Extrair o executável do jogo

```powershell
python .\PlusAlphaProject\tools\extract_psx_exe.py `
  --disc ".\PlusAlphaProject\disc-a\Street Fighter EX Plus Alpha (USA).cue" `
  --name "SLUS_005.48" `
  --output ".\PlusAlphaProject\local\SLUS_005.48"
```

O SHA-1 esperado do executável é
`D8B81E036AA53C37EF983871C187CC9D00A27156`.

## 6. Gerar os fontes locais do jogo

```powershell
.\PlusAlphaProject\tools\generate_game.ps1
```

As saídas ficam em `PlusAlphaProject/generated/` e não são versionadas.

## 7. Configurar e compilar o runtime

O runtime usa a toolchain MSYS2 UCRT64 com SDL2:

```powershell
.\PlusAlphaProject\tools\configure_runtime.ps1
C:\msys64\ucrt64\bin\cmake.exe --build .\PlusAlphaProject\build-ucrt --target psx-runtime
```

## 8. Executar

```powershell
Push-Location .\PlusAlphaProject
.\build-ucrt\psx-runtime.exe --game .\game.toml --disc ".\disc-a\Street Fighter EX Plus Alpha (USA).cue"
Pop-Location
```

O launcher é exclusivo deste jogo e não oferece seleção de outros títulos.
