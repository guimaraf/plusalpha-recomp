# Port UWP para Xbox One

O alvo UWP deste projeto é exclusivo para Xbox (x64, Dev Mode). Os ports desktop permanecem independentes: Windows usa MSYS2 UCRT64/MinGW e Linux usa SDL2 do sistema; ambos mantêm o launcher e seus caminhos atuais.

## Contrato de inicialização

O Xbox não compila nem exibe o launcher RmlUi. O runtime usa `SDL_GetPrefPath("PSXRecomp", "SLUS-00548")` e trabalha somente dentro da área gravável do pacote:

```text
LocalState/
└── PSXRecomp/
    └── SLUS-00548/
        ├── bios/
        │   └── SCPH1001.BIN
        ├── config/
        │   ├── game.toml
        │   ├── settings.toml
        │   ├── input.ini
        │   └── keybinds.ini
        ├── disc/
        │   └── game.cue
        ├── logs/
        │   └── debug_log.txt
        └── saves/
            ├── card1.mcd
            ├── card2.mcd
            ├── SLUS-00548.options
            └── states/
```

Na primeira execução, a ausência de `config/game.toml` funciona como sentinela. O jogo cria todos os diretórios, copia os quatro templates editáveis do pacote para `config/`, registra `CREATE_FOLDERS_SUCCESS` em `logs/debug_log.txt` e encerra com sucesso.

Depois disso, envie pelo Xbox Device Portal ou FTP:

- BIOS: `bios/SCPH1001.BIN` (524288 bytes, CRC32 `37157331`);
- disco: `disc/game.cue`, com os arquivos referenciados pelo CUE no mesmo diretório.

Na execução seguinte o runtime valida os nomes e o conteúdo, abre diretamente o jogo e não chama seletores de arquivo. Ausência ou invalidez é registrada no log e provoca encerramento limpo.

## Dados modificáveis

No UWP, `game.toml`, `settings.toml`, `input.ini`, `keybinds.ini`, memory cards, options, save states e logs ficam em LocalState. Atualizar o AppX não sobrescreve automaticamente arquivos que já foram copiados: para testar um novo template, edite a cópia via Portal/FTP ou remova somente o arquivo correspondente de `config/` antes da próxima inicialização.

No Windows e Linux nada disso muda: configurações e saves continuam sob controle do launcher e podem permanecer ao lado do executável.

## Controles

O `settings.toml` padrão configura P1 e P2 como `auto` e `digital`. O slot 2 permanece conectado no SIO mesmo quando não há segundo controle físico; quando um controle é conectado, o evento `SDL_CONTROLLERDEVICEADDED` atualiza a atribuição. No Xbox, o modo de desenvolvimento que mistura todos os controles no P1 fica desativado por padrão.

## Renderização e SDL2

O perfil Xbox usa SDL2 compilado para `WindowsStore`, linkado estaticamente. O renderer do jogo é forçado para software e o backend OpenGL desktop é substituído por um stub inerte somente nesse perfil. Não é empacotada nenhuma `SDL2.dll` de desktop.

A entrada `SDL_winrt_main_NonXAML.cpp` é compilada isoladamente com `/ZW` e chama `SDL_WinRTRunApp(SDL_main, ...)`. O runtime mantém uma única função `main`, renomeada pelo cabeçalho SDL para o alvo WinRT.

## Fibers

O backend UWP preserva a troca cooperativa no mesmo thread com `ConvertThreadToFiberEx`, `CreateFiberEx`, `SwitchToFiber` e `DeleteFiber`, usando `FIBER_FLAG_FLOAT_SWITCH`. Ele não simula fibers com threads, eventos ou TLS.

## Geração local com Visual Studio 2019

O script `UWP/Generate-UWP-VS2019.ps1` mantém toda a geração local dentro de `UWP-Build/`. Na primeira execução ele baixa o SDL2 2.30.2 oficial, compila e instala somente a dependência WindowsStore em `UWP-Build/_deps/` e gera a solução UWP x64 do jogo com o gerador `Visual Studio 16 2019`.

Pré-requisitos:

- Visual Studio 2019 com **Desenvolvimento para Plataforma Universal do Windows**, ferramentas C++ UWP x64 e Windows 10 SDK;
- CMake disponível no `PATH` e com o gerador do Visual Studio 2019;
- acesso à internet na primeira execução para obter o SDL2.

Execute no PowerShell, partindo da raiz do repositório:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\UWP\Generate-UWP-VS2019.ps1
```

O comando padrão não compila o jogo. Ele gera `UWP-Build/StreetFighterEXPlusAlphaRecomp.sln`, que pode ser aberta no Visual Studio 2019. Para gerar e abrir a solução automaticamente:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\UWP\Generate-UWP-VS2019.ps1 -Open
```

Para compilar ou solicitar o pacote local explicitamente:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\UWP\Generate-UWP-VS2019.ps1 -Build -Configuration Release
powershell -NoProfile -ExecutionPolicy Bypass -File .\UWP\Generate-UWP-VS2019.ps1 -Package -Configuration Release
```

`-Package` também compila o alvo `psx-runtime` e direciona a saída sem assinatura para `UWP-Build/AppPackages/`. A instalação no Xbox pode exigir que o Visual Studio ou o processo de distribuição configure certificado e assinatura compatíveis com o console.

Para selecionar explicitamente outro Windows 10 SDK instalado, use `-WindowsSdkVersion`, por exemplo `-WindowsSdkVersion 10.0.19041.0`. O script não apaga uma configuração existente: se `UWP-Build/` pertencer a outro gerador ou não for WindowsStore, ele para e solicita remoção manual do diretório.

## CI e artefato

O job desktop Windows continua exclusivamente em MSYS2 UCRT64/MinGW. O job UWP baixa o código-fonte SDL2, compila uma instalação WindowsStore separada no diretório temporário do runner e gera somente o artefato `EXPlusAlpha-Recomp-UWP-Xbox-x64.zip`.
