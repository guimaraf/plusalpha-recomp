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

## Recording with OBS on Windows

For stable video capture, use **Window Capture** in OBS and select the game
window. The game may be displayed fullscreen; capturing its window is still the
recommended method. Avoid **Display Capture** when frame-perfect recording is
important: in local tests, it occasionally produced apparent skipped frames in
the recorded video even though the game itself continued reporting stable FPS
and frame time.

During my tests, I recorded two complete Arcade matches in each of the
following configurations:

- OpenGL renderer, without video encoding or resolution scaling;
- OpenGL renderer, with video encoding and scaling from 1080p to 1440p;
- Software renderer, with video encoding and scaling from 1080p to 1440p.

Window Capture showed no FPS drops in any of my runs. The Display Capture
behavior may involve the OBS capture path, the Windows compositor, SDL2, and the
selected rendering backend; my tests did not isolate it as an SDL2 defect.

### Interpreting CPU clock readings

The CPU clock normally shown directly by MSI Afterburner/RTSS is an
instantaneous clock and should not be treated as the processor's effective
workload. For more representative readings, use HWiNFO's **Effective Clock**,
exported to MSI Afterburner/RTSS through HWiNFO Shared Memory and `HwInfo.dll`.

On my test machine, the clean build `buildClean-ucrt-s1-261-clean-ddark-bomb`
typically measured about 200-400 MHz of effective CPU clock, staying near
300 MHz during Ryu versus Ken gameplay. Running OBS increased it by roughly
100 MHz, remaining near or below 500 MHz. These values are specific to my
machine and test environment and are not performance requirements.

Consequently, a displayed instantaneous clock near the processor's maximum is
not, by itself, evidence that interpreted game instructions are saturating the
CPU. Interpreted code can still have a performance cost, but it must be assessed
with frame-time data, effective clocks, and controlled comparisons.

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

## Captura com OBS no Windows

Para obter uma gravação estável, use **Captura de Janela** no OBS e selecione a
janela do jogo. O jogo pode permanecer em tela cheia; ainda assim, a captura da
janela é o método recomendado. Evite **Captura de Tela/Monitor** quando for
importante preservar todos os quadros: nos testes locais, esse método apresentou
saltos aparentes de quadros no vídeo gravado em alguns momentos, embora o jogo
continuasse indicando FPS e frametime estáveis.

Durante meus testes, gravei duas partidas completas do modo Arcade em cada uma
destas configurações:

- renderizador OpenGL, sem codec de vídeo e sem escala de resolução;
- renderizador OpenGL, com codec e escala de 1080p para 1440p;
- renderizador Software, com codec e escala de 1080p para 1440p.

A Captura de Janela não apresentou queda de FPS em nenhuma das minhas execuções. O
comportamento observado na Captura de Tela/Monitor pode envolver o caminho de
captura do OBS, o compositor do Windows, o SDL2 e o backend de renderização
selecionado; meus testes não isolaram esse comportamento como um defeito do SDL2.

### Como interpretar o clock da CPU

O clock de CPU normalmente exibido diretamente pelo MSI Afterburner/RTSS é um
clock instantâneo e não deve ser tratado como a carga efetiva do processador.
Para uma leitura mais representativa, use o **Effective Clock** do HWiNFO,
exportado para o MSI Afterburner/RTSS por meio de Shared Memory e `HwInfo.dll`.

Na minha máquina de teste, a build limpa `buildClean-ucrt-s1-261-clean-ddark-bomb`
apresentou normalmente cerca de 200-400 MHz de clock efetivo, permanecendo
próxima de 300 MHz durante o gameplay de Ryu contra Ken. Com o OBS em execução,
houve aumento aproximado de 100 MHz, mantendo-se próximo ou abaixo de 500 MHz.
Esses números pertencem à minha máquina e ao ambiente testados e não constituem
requisitos de desempenho.

Portanto, um clock instantâneo exibido próximo ao máximo do processador não é,
isoladamente, evidência de que as instruções interpretadas do jogo estejam
saturando a CPU. O código interpretado ainda pode ter custo de desempenho, mas
isso deve ser avaliado com dados de frametime, clocks efetivos e comparações
controladas.

## Framework e atribuições

O framework está em
[`guimaraf/psxrecomp-plusalpha`](https://github.com/guimaraf/psxrecomp-plusalpha)
e mantém sua licença PolyForm Noncommercial 1.0.0 e as atribuições de terceiros
no próprio submódulo.
