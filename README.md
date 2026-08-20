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
- geração local do executável recompilado a partir de uma cópia legítima do jogo;
- framework fixado como submódulo para manter o port reproduzível.

## Estrutura

- `PlusAlphaProject/`: configuração, seeds e ferramentas específicas do jogo;
- `psxrecomp/`: framework e runtime importados como submódulo;
- `PlusAlphaProject/disc-a/`: local reservado para a imagem do usuário;
- `PlusAlphaProject/local/`: executável extraído localmente;
- `PlusAlphaProject/generated/`: código regenerável e não versionado.

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
