# Street Fighter EX Plus Alpha Recomp

Independent static/hybrid port of **Street Fighter EX Plus Alpha** for PlayStation, dedicated exclusively to the North American edition `SLUS-00548`.

The repository contains only source code, configuration, and discovery data necessary to generate the port. It does not contain BIOS, game images, extracted executables, saves, or code generated from these files.

## Status

- gameplay validated in Software 1x at 60 FPS in baseline scenarios;
- launcher dedicated to `SLUS-00548`;
- execution with LLE BIOS SCPH-1001;
- CI-generated release built from statically recompiled sources;
- framework pinned as a submodule to keep the port reproducible.

## Structure

- `PlusAlphaProject/`: configuration, seeds, and game-specific tools;
- `psxrecomp/`: framework and runtime imported as a submodule;
- `PlusAlphaProject/disc-a/`: reserved folder for the user's image;
- `PlusAlphaProject/local/`: locally extracted executable;
- `PlusAlphaProject/generated/`: generated C code from the game's executable.

## Cloning

Clone including all submodules:

```bash
git clone --recurse-submodules https://github.com/guimaraf/plusalpha-recomp.git
cd plusalpha-recomp
```

If the repository was already cloned without recursion:

```bash
git submodule update --init --recursive
```

Complete instructions are in [`PlusAlphaProject/BUILD_LOCAL.md`](PlusAlphaProject/BUILD_LOCAL.md).

## Protected Files

You must provide your own SCPH-1001 BIOS and your own image of the USA edition `SLUS-00548`. Accepted hashes are documented in [`PlusAlphaProject/BIOS.md`](PlusAlphaProject/BIOS.md) and [`PlusAlphaProject/DISC.md`](PlusAlphaProject/DISC.md).

Do not open issues asking for BIOS, ROM, BIN/CUE, ISO, or extracted executables.

## Framework and Attributions

The framework is located at [`guimaraf/psxrecomp-plusalpha`](https://github.com/guimaraf/psxrecomp-plusalpha) and maintains its PolyForm Noncommercial 1.0.0 license and third-party attributions in the submodule itself.

---
## Português do Brasil

# Street Fighter EX Plus Alpha Recomp

Porte estático/híbrido independente de **Street Fighter EX Plus Alpha** para
PlayStation, dedicado exclusivamente à edição norte-americana `SLUS-00548`.

O repositório contém somente código-fonte, configuração e dados de descoberta
necessários para gerar o port. Ele não contém BIOS, imagem do jogo, executável
extraído, saves ou código gerado a partir desses arquivos.

## Estado

- gameplay validado em Software 1x a 60 FPS nos cenários cobertos pela baseline;
- launcher dedicado ao `SLUS-00548`;
- execução com BIOS LLE SCPH-1001;
- geração do executável automatizada via CI a partir dos fontes recompilados;
- framework fixado como submódulo para manter o port reproduzível.

## Estrutura

- `PlusAlphaProject/`: configuração, seeds e ferramentas específicas do jogo;
- `psxrecomp/`: framework e runtime importados como submódulo;
- `PlusAlphaProject/disc-a/`: local reservado para a imagem do usuário;
- `PlusAlphaProject/local/`: executável extraído localmente;
- `PlusAlphaProject/generated/`: código C gerado a partir do executável original.

## Clonagem

Clone incluindo todos os submódulos:

```bash
git clone --recurse-submodules https://github.com/guimaraf/plusalpha-recomp.git
cd plusalpha-recomp
```

Se o repositório já tiver sido clonado sem recursão:

```bash
git submodule update --init --recursive
```

As instruções completas estão em
[`PlusAlphaProject/BUILD_LOCAL.md`](PlusAlphaProject/BUILD_LOCAL.md).

## Arquivos protegidos

Você precisa fornecer sua própria BIOS SCPH-1001 e sua própria imagem da edição
USA `SLUS-00548`. Os hashes aceitos estão documentados em
[`PlusAlphaProject/BIOS.md`](PlusAlphaProject/BIOS.md) e
[`PlusAlphaProject/DISC.md`](PlusAlphaProject/DISC.md).

Não abra issues pedindo BIOS, ROM, BIN/CUE, ISO ou executáveis extraídos.

## Framework e atribuições

O framework está em
[`guimaraf/psxrecomp-plusalpha`](https://github.com/guimaraf/psxrecomp-plusalpha)
e mantém sua licença PolyForm Noncommercial 1.0.0 e as atribuições de terceiros
no próprio submódulo.
