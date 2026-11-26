# Toolchain portátil (`tools\`)

Este documento explica como obter, a partir de um clone limpo, as mesmas ferramentas usadas para gerar o jogo: MSYS2 (gcc, cmake, ninja), Python e o pacote `cmake-clang-v1` do RetroPorting-Toolchains. Tudo é instalado dentro de `tools\`, na raiz do repositório, sem tocar em `C:\msys64`, no Python do sistema nem no PATH global.

> **Estado de validação:** o instalador foi exercitado somente com `-DryRun` e em execução idempotente sobre um `tools\` já preenchido. **A instalação do zero (pasta `tools\` vazia, com download) ainda está a validar.** Trate o primeiro uso em outra máquina como a validação dela.

## 1. Visão geral

- `tools\` fica na **raiz do repositório** (`plusalpha-recomp\tools\`) e **não é versionado**. O `.gitignore` do repositório já ignora `/tools/`, então nada do toolchain entra em commits.
- Os scripts versionados ficam em `PlusAlphaProject/tools/`:
  - `toolchain.lock.json`: fonte de verdade (versões, URLs e sha256);
  - `setup_portable_toolchain.ps1` e `.bat`: instalador;
  - `toolchain_paths.ps1`: resolução de caminhos usada pelos scripts de build;
  - `toolchain/env.ps1.in` e `env.sh.in`: modelos dos ativadores `tools\env.ps1` e `tools\env.sh`.
- O instalador é idempotente: o que já estiver instalado e correto é apenas conferido.
- Os pacotes MSYS2 são os **mesmos usados para gerar o jogo** (versões idênticas às de `C:\msys64` da máquina de origem). O SDL3 não vem do MSYS2: o build o obtém por FetchContent (`PSX_SDL3_FETCH=ON`); o pacote SDL2 do MSYS2 serve só ao backend SDL2 (A/B).

## 2. Componentes

Versões lidas de `PlusAlphaProject/tools/toolchain.lock.json`.

| Componente | Versão | Uso | Download |
|---|---|---|---|
| MSYS2 base | `msys2-base-x86_64-20261120` | Raiz do ambiente em `tools\msys64` | https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-20261120.tar.zst |
| Pacotes `mingw-w64-*` | 92 (71 em `ucrt64`, 21 em `mingw64`), instalados com `pacman -U` | Compilador e ferramentas do build do jogo e dos overlays | https://repo.msys2.org/mingw/ (URL exata de cada pacote no lock) |
| gcc / gcc-libs | 16.1.0-5 | Compilação do runtime e dos overlays | idem |
| binutils | 2.46.1-2 | Ligador e utilitários | idem |
| cmake | 4.4.0-1 | Configuração do build do jogo | idem |
| ninja | 1.13.2-1 | Gerador Ninja | idem |
| pkgconf | 1~2.5.1-2 | Localização de bibliotecas | idem |
| ccache | 4.13.6-2 | Cache de compilação (opcional) | idem |
| SDL2 | 2.32.10-1 | Backend SDL2 (A/B) | idem |
| Python | 3.13.11 (pacote NuGet) | Geração, overlays/AOT, `auto_session.py`, testes | https://www.nuget.org/api/v2/package/python/3.13.11 |
| Pillow / numpy / PyYAML / pytest | 12.1.1 / 2.4.2 / 6.0.3 / 9.2.0 | Ferramentas e testes do `psxrecomp` | PyPI, via `pip download` (instalação posterior sem rede, com versões fixas) |
| retcomm `cmake-clang-v1` | 1.0.14 (llvm 22.1.8, cmake 3.31.12, ninja 1.13.2) | Build do **recompilador** (`psxrecomp/recompiler`) | https://github.com/RetroPortingToolKit/RetroPorting-Toolchains/releases/download/v1.0.14/cmake-clang-v1-windows-x64.zip |

Dependências transitivas do pip também ficam fixadas no lock (`pip_resolved`: colorama, iniconfig, packaging, pluggy, Pygments, além dos quatro acima).

### Origem do retcomm

O `cmake-clang-v1` é o pacote que o framework `psxrecomp` já usa como toolchain recomendada (`psxrecomp/README.md`, seção de pré-requisitos, e `psxrecomp/docs/LOCAL_CODEGEN_SDK.md`, que descreve o cache compartilhado `%LOCALAPPDATA%\retcomm\toolchains\cmake-clang-v1\<tag>\`). Aqui ele é instalado em `tools\retcomm\cmake-clang-v1\1.0.14\`, com cópia local para que o build não dependa do cache do usuário.

### Espaço em disco (aproximado)

| Pasta | Tamanho |
|---|---|
| `tools\msys64` | 1,6 GB |
| `tools\python` | cerca de 134 MB |
| `tools\retcomm` | 0,8 GB |
| `tools\_dl` (cache de downloads) | cerca de 280 MB, mais o zip do retcomm (cerca de 200 MB) quando baixado |

## 3. Instalação rápida

Na raiz do repositório:

```powershell
.\PlusAlphaProject\tools\setup_portable_toolchain.bat
```

O `.bat` apenas chama o `.ps1` com `-NoProfile -ExecutionPolicy Bypass` e repassa os argumentos. Equivalente direto:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\PlusAlphaProject\tools\setup_portable_toolchain.ps1
```

Etapas executadas (`-Component all`): MSYS2 base, pacotes pinados, Python e pip, retcomm, geração de `tools\env.ps1`/`tools\env.sh` e testes de fumaça (gcc `-shared` em ucrt64 e mingw64, cmake/ninja, imports Python, binários do retcomm).

Parâmetros:

| Parâmetro | Efeito |
|---|---|
| `-RepoRoot <dir>` | Raiz do repositório (padrão: duas pastas acima do script). |
| `-CacheDir <dir>` | Cache offline adicional; quando informado, **nada é baixado**. |
| `-Component msys2\|python\|retcomm\|all` | Instala só um componente (padrão `all`). |
| `-DryRun` | Confere lock, cache (sha256), instalação atual e URLs (HEAD); não baixa nem instala. |
| `-Force` | Refaz as etapas mesmo já instaladas (reextrai e reinstala; não apaga pastas). |
| `-LockFile <arq>` | Usa outro lock em vez de `toolchain.lock.json`. |

Recomendação: rodar `-DryRun` antes da primeira instalação para ver quais arquivos faltam e quais URLs ainda respondem.

## 4. Modo offline e cache

Os downloads vão para `tools\_dl` (base MSYS2, `python.nupkg`, `.pkg.tar.zst` com `.sig`, wheels em `_dl\pip` e o zip do retcomm em `_dl\retcomm`). Cada arquivo é conferido pelo sha256 do lock.

Para instalar sem rede (ou quando um pacote MSYS2 saiu do repositório), copie um `tools\_dl` preservado para qualquer pasta e aponte:

```powershell
.\PlusAlphaProject\tools\setup_portable_toolchain.bat -CacheDir D:\cache\_dl
```

O cache é procurado recursivamente por nome de arquivo. No modo offline, wheels são lidas de `<CacheDir>\pip` (ou de `tools\_dl\pip`). Arquivo ausente ou com sha256 divergente aborta a etapa com erro explícito.

Observação sobre o `tools\_dl` atual da máquina de origem: ele contém a base MSYS2, os pacotes, o `python.nupkg` e `port.lst`/`py/`, mas **não** tem `_dl\retcomm` (zip do retcomm) nem `_dl\pip` (wheels). Um cache offline completo precisa dessas duas pastas, que o instalador cria ao baixar.

## 5. Ativar o ambiente

Os ativadores são gerados em `tools\` pelo instalador e alteram **somente a sessão atual**:

```powershell
. .\tools\env.ps1          # PowerShell (dot-source)
```

```bash
source tools/env.sh         # Git Bash
```

Efeitos (conforme `toolchain/env.ps1.in` e `env.sh.in`):

- `PLUSALPHA_TOOLS_ROOT`, `PLUSALPHA_MSYS2_ROOT` (`tools\msys64`) e `PLUSALPHA_PYTHON` (`tools\python\python.exe`);
- `PSX_MINGW_BIN` (`mingw64\bin`, usado pelos testes do `psxrecomp` e por `compile_overlays.py`), `PLUSALPHA_UCRT_BIN`, `PLUSALPHA_MINGW_BIN`;
- se o retcomm estiver presente: `PLUSALPHA_RETCOMM_ROOT`, `PLUSALPHA_CLANG`, `PLUSALPHA_CMAKE`, `PLUSALPHA_NINJA`. O retcomm **não** entra no PATH, para não misturar o cmake dele com o do MSYS2;
- o PATH recebe `tools\python`, `tools\python\Scripts` e `tools\msys64\ucrt64\bin`; `TEMP`/`TMP` e `PYTHONUTF8=1` também são ajustados.

## 6. Como os scripts escolhem as ferramentas

Os scripts de `PlusAlphaProject/tools/*.ps1` carregam `toolchain_paths.ps1`. Parâmetro explícito do usuário sempre vence; sem ele, a ordem é:

| Ferramenta | Ordem de resolução |
|---|---|
| MSYS2 | `PLUSALPHA_MSYS2_ROOT` → `<repo>\tools\msys64` (se existir `ucrt64\bin`) → `C:\msys64` |
| Python | `PLUSALPHA_PYTHON` → `<repo>\tools\python\python.exe` → `python` do PATH |
| retcomm | `PLUSALPHA_RETCOMM_ROOT` → versão mais nova em `<repo>\tools\retcomm\cmake-clang-v1\<versão>` (com `bin\clang.exe`) |

Os scripts colocam `ucrt64\bin` no PATH do processo (apenas ucrt64: acrescentar mingw64 na frente trocaria o gcc dos builds). Portanto, **não é obrigatório** rodar `env.ps1` antes de `build_online.ps1`; o ativador é útil para sessões interativas, para `auto_session.py` com o Python correto (`auto_session.py` usa `sys.executable`; rode-o com `tools\python\python.exe`) e para os testes do `psxrecomp`.

## 7. Configure do recompilador

O build do recompilador usa o clang/cmake/ninja do retcomm e o Python portátil (o `find_package(Python3 ...)` em `psxrecomp/recompiler/CMakeLists.txt` precisa de um Python com `tomllib`). Configuração equivalente à do `CMakeCache.txt` de `psxrecomp/recompiler/build`, a partir da raiz do repositório (comando documentado, **não executado** nesta tarefa):

```powershell
$rc = "$PWD\tools\retcomm\cmake-clang-v1\1.0.14\bin"
$env:PATH = "$rc;$env:PATH"
& "$rc\cmake.exe" -S .\psxrecomp\recompiler -B .\psxrecomp\recompiler\build -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_C_COMPILER="$rc\clang.exe" `
  -DCMAKE_CXX_COMPILER="$rc\clang++.exe" `
  -DCMAKE_MAKE_PROGRAM="$rc\ninja.exe" `
  -DCMAKE_AR="$rc\llvm-ar.exe" `
  -DPSXRECOMP_STATIC_CLI=ON `
  -DPython3_EXECUTABLE="$PWD\tools\python\python.exe"
```

No cache de referência, `CMAKE_RC_COMPILER` aponta para `tools\msys64\ucrt64\bin\windres.exe` (resolvido automaticamente pelo CMake quando o `ucrt64\bin` está no PATH; se necessário, acrescente `-DCMAKE_RC_COMPILER=...`). Trocar de compilador invalida o cache existente: o primeiro build após reconfigurar é completo.

O passo 3 de [BUILD_LOCAL.md](../BUILD_LOCAL.md) (`cmake -S ... -G Ninja`) continua válido; este comando só fixa explicitamente as ferramentas do toolchain portátil.

## 8. Solução de problemas

- **`gcc` retorna código 1 sem nenhuma mensagem.** O gcc do MSYS2 só funciona com o `bin` dele no PATH (o `cc1` precisa das DLLs). Chamá-lo por caminho absoluto sem isso falha em silêncio. Rode `. .\tools\env.ps1` (ou `source tools/env.sh`), ou acrescente `tools\msys64\ucrt64\bin` (ou `mingw64\bin`) ao PATH do processo. Os testes do `psxrecomp` leem `PSX_MINGW_BIN`.
- **Pacote MSYS2 sumiu do repositório (HEAD/download com 404).** O MSYS2 mantém só as versões recentes; as URLs do lock (`may_be_removed_upstream`) podem deixar de existir. Use um `tools\_dl` preservado com `-CacheDir`. Por isso o cache deve ser guardado de forma durável e, se possível, copiado para fora do repositório.
- **`sha256 divergente`.** O arquivo do cache não bate com o lock; o instalador o substitui por download (ou aborta no modo offline). Não edite o lock para "fazer passar": ele é a fonte de verdade.
- **`pacman -U` falha ou pacotes ausentes ao final.** Confira a mensagem `Pacotes ainda ausentes apos pacman`. O instalador usa um `pacman.setup.conf` temporário com `SigLevel = Never` apenas durante o `pacman -U`; a integridade vem do sha256 do lock. Não use `pacman -Syu` neste ambiente (puxaria versões diferentes das pinadas).
- **`ModuleNotFoundError: tomllib` no CMake/testes.** Algum passo está usando outro Python (por exemplo 3.10). Passe `-DPython3_EXECUTABLE=<repo>\tools\python\python.exe` ao reconfigurar o recompilador.
- **Download do retcomm lento ou falha na extração.** O zip tem cerca de 200 MB (`size` no lock: 209.497.009 bytes) e é extraído com `tar.exe`; confira espaço em disco e antivírus.
- **`pacman` online reclama do chaveiro (keyring).** O instalador não inicializa o chaveiro do pacman do MSYS2 portátil; a integridade dos pacotes vem do sha256 do lock. Para usar o pacman online, rode `pacman-key --init` e `pacman-key --populate msys2` dentro de `tools\msys64` (pode demorar ou travar esperando o gpg-agent).

## 9. Limites

- A instalação do zero (com download) **não foi testada**; só `-DryRun` e execução idempotente.
- O instalador não altera o PATH global nem o `C:\msys64`; `/tools/` é ignorado pelo `.gitignore`.
- Somente Windows x64 (MSYS2 UCRT64/MinGW64 e retcomm `windows-x64`).
- As versões são as da máquina que gerou o jogo; a reprodução depende de o MSYS2 ainda hospedar (ou de você ter em cache) os pacotes pinados.
- Não substitui BIOS, imagem do disco nem o restante do fluxo de [BUILD_LOCAL.md](../BUILD_LOCAL.md).
