# Migração do online — integração estática, validação offline pendente

Esta integração usa o rollback e o lobby oficiais do PSXRecomp. O suporte está
conectado no código e o build Windows com SDL3 foi concluído em 18/10/2026,
após autorização explícita do usuário para compilar. A qualificação de gameplay
offline e entre dois pares continua pendente. Não tratar esta branch como
release validada.

## Revisões

- Baseline anterior do jogo: `abcac1c070652bd115d50a34659ffbe43b24c5c0`.
- Baseline anterior do framework: `1cfa7fe449dd94e911fcb9c5491e6806c11935b7`.
- Base original integrada: `RetroPortingToolKit/psxrecomp`,
  `53a057f548cd1f93f1b4d8300caaeded72f4160d` (17/10/2026).
- `recomp-net`: `e53059306824edf4f0aec4aae5ae65151b18535f`.
- `rbengine`: `2a03e73693acee0fb78076ea058642c931bef12e`.
- `recomp-ui`: `0546fbcb0126bb14bf88d2128b4fe8a4229570a3`.

Os gitlinks dos submódulos fixam as versões. O framework mantém o histórico do
fork e incorpora o histórico original; nenhuma atualização remota é automática.
O cache de toolchain que veio rastreado no original foi excluído do índice do
fork; dependências regeneráveis não fazem parte desta alteração.

## Build feito pelo usuário

### Release Windows enxuta

Na raiz de `plusalpha-recomp`, execute localmente:

```powershell
.\PlusAlphaProject\tools\build_release.ps1 -Jobs 4
```

O comando usa os fontes já gerados, compila `Release` com SDL3, online e launcher,
sem debug tools nem wizard de geração, em `PlusAlphaProject/build-release-online`.
A build de diagnóstico e a referência estável são preservadas. Se precisar
regenerar fontes, acrescente `-Generate` (essa opção também compila os emitters).

O pacote é criado em uma pasta nova
`PlusAlphaProject/dist/exPlusAlpha-AAAAmmdd-HHmmss`. Para escolher outra pasta,
use `-OutputDir 'F:\meus-pacotes\exPlusAlpha-1'`; ela não pode existir.
Para empacotar novamente uma build release pronta, sem compilar:

```powershell
.\PlusAlphaProject\tools\build_release.ps1 -PackageOnly
```

O empacotador não compila nem baixa dependências. Copia o executável, DLLs não
pertencentes ao Windows detectadas recursivamente nos imports PE, assets,
configuração padrão, catálogo de mods bundled e licenças. Remove informações de
debug apenas da cópia do EXE e valida seu contrato `execution.json` pelo helper
oficial do framework. `release-manifest.json` registra hashes do pacote.

BIOS, disco, saves, mods instalados, escolhas pessoais de mods, caminhos locais,
settings pessoais, logs, dumps, fontes, bibliotecas de desenvolvimento e arquivos
do CMake não são copiados. O jogador seleciona sua própria SCPH1001 e seu CUE/BIN
no launcher; suas configurações e saves serão criados ao jogar. O catálogo usa
os padrões dos mods, sem copiar o estado pessoal da build de desenvolvimento.
MSYS2/Python são necessários para preparar o pacote, não para executá-lo.

Uma falha deixa `PACKAGE_INCOMPLETE.txt` na pasta criada: ela não é uma release
completa. Corrija a causa e use outra pasta nova. Nenhum pacote existente é
apagado ou sobrescrito. Antes de distribuir, teste a pasta em outro local,
com o PATH do MSYS2 removido: launcher, seleção de BIOS/disco, partida offline,
áudio, controle e depois sessão online entre duas máquinas. O empacotamento
valida arquivos e identidade; não certifica gameplay ou corrige o engasgo residual.

Na raiz do repositório, com Python 3.11+, MSYS2 UCRT64 e suas ferramentas:

```powershell
git submodule update --init --recursive
.\PlusAlphaProject\tools\build_online.ps1 -Generate
```

Antes, coloque sua própria SCPH-1001 em `bios/SCPH1001.BIN`, na raiz do
repositório. `-Generate` confere o hash dessa imagem, chama a CLI oficial,
recompila os emitters, gera o backend SCPH1001 e o jogo e depois compila o
runtime. Pode baixar o toolchain e as dependências fixadas pelo framework.
Para usar outro caminho local, acrescente `-BiosPath 'caminho\SCPH1001.BIN'`.

O CMake força `PSXRECOMP_BIOS_STEMS=SCPH1001`, inclusive ao reutilizar o cache
do build anterior. `[runtime] openbios = false` exige a BIOS retail em todos os
lançamentos. O launcher pede que cada jogador selecione sua imagem; não há
fallback para OpenBIOS e a ROM retail não acompanha o executável.

Saída atual: `PlusAlphaProject/build-online-static/exPlusAlpha.exe`. O diretório
`build-online/` anterior permanece preservado. As fontes do jogo vão
para `generated-online/`; o disco preparado, para `prepared-online/`. Ambos são
locais e ignorados. As pastas `generated/`, `buildTele-*`, `build_s1_309_*`, saves
e caches existentes não são movidos nem apagados. Não copie seus caches de
overlays ou save states antigos para a versão nova. Memory cards são separados
dos snapshots; faça os primeiros testes com os saves novos da pasta de build.

Para builds seguintes, sem mudar o emitter ou a configuração de geração:

```powershell
.\PlusAlphaProject\tools\build_online.ps1
```

SDL3 é o padrão atual. `-SdlBackend SDL2` permite comparar o backend legado.
`-SetupHost` gera o setup host oficial com o wizard; ele substitui o fluxo TinyCC
antigo e não usa `game_core.dll`/`compileBuild`. Os scripts S1-309 e os antigos
`package_release.*` pertencem à baseline; não os use nesta branch.

## Cobertura estática recuperada

O build agora exige o conjunto promovido S1-309: 2.219 DLLs do inventário,
2.086 unidades C e 4.748 entradas/variantes antes da deduplicação. A origem
padrão é `buildTele-s1-309-bezeus/static_overlays/`. O preparador apenas lê essa
pasta; os fontes e o EXE estáveis não são modificados.

`tools/prepare_retained_overlays.py` valida o inventário e as definições usadas
pelo dispatcher e copia os corpos nativos, byte a byte, para
`generated-online/retained-overlays/overlays_static_NNNN.c`. Os nomes dos
arquivos seguem o padrão do framework atual; os símbolos e corpos permanecem
os originais. As unidades são recompiladas com os headers atuais e com
`PSX_NO_DEBUG_TOOLS=1`, como na montagem estável.

Somente o dispatcher é reemitido pelo gerador atual. A extração preserva as
mesmas 3.884 verificações de variantes residentes por endereço/CRC/regiões e
as funções promovidas que elas chamam; adiciona as interfaces atuais de
consulta sem execução e estatísticas por entrada. Não são reemitidas as
instruções MIPS dos corpos nativos.

O recibo `retained_coverage.json` registra hashes de todas as cópias. O CMake
recusa fontes ausentes, alterados ou quantidade diferente de 2.086 unidades,
em vez de gerar silenciosamente um EXE sem as promoções. O comportamento em
execução ainda depende da validação offline; igualdade de inventário não prova
equivalência de gameplay após atualizar o runtime.

Se sua cópia preservada estiver em outro local, use
`-RetainedOverlayDir 'caminho\static_overlays'`. `-StaticOverlayDir` seleciona
apenas a pasta de destino preparada, separada da origem. Um clone novo sem os
fontes locais preservados falha com uma mensagem: a CLI de geração do main EXE
não reconstrói automaticamente esse conjunto de promoções.

`overlay_cache = false` segue a montagem estável: não depende das DLLs antigas.
Trechos ainda não cobertos continuam sujeitos ao caminho suportado pelo
runtime. Não há garantia de que o desempenho ou comportamento seja idêntico
antes dos testes do usuário.

## Launcher e recursos existentes

- Dois jogadores digitais, nome do jogo, ícone e configuração de baixa latência
  permanecem declarados no projeto.
- O launcher é agora o `recomp-ui`; o menu de configurações também é o oficial.
- `sfexp.png` continua sendo copiado. Para bezel, use Mods → Bezel Artwork e
  selecione essa imagem. O bezel oficial usa OpenGL; o botão `show_bezel` do
  RmlUi antigo e os seus caminhos Software/Vulkan não foram portados.
- A leitura de FPS é a do framework (`PSX_FPS_TELEMETRY=1` e hotkey do runtime).
  O botão persistente `Show FPS` do launcher antigo não integra a nova UI.
- O armazenamento criptografado de tempo de jogo foi preservado no fork. O
  total aparece em Credits e a gravação para antes de voltar ao lobby.
- UWP/Xbox não está qualificado nesta migração; o CMake recusa esse alvo.

## Roteiro de qualificação

1. Abrir **build-online-static/exPlusAlpha.exe**, selecionar a própria
   SCPH-1001 e usar **Software**, padrão do `game.toml` novo. Começar com
   bezel/mods desligados para comparar com a baseline Software.
   Executar offline com o disco USA original e conferir boot, seleção de
   personagens, Arcade, Versus, áudio, controles P1/P2 e estabilidade dos frames.
2. Em dois PCs, usar exatamente esta versão do port, o mesmo perfil de execução,
   disco e BIOS negociada. Ambos usam a mesma edição USA `SLUS-00548`.
3. Abrir Netplay e testar LAN/Direct IP. Confirmar P1 e P2, comandos simultâneos,
   início/fim de round, troca de cenário e retorno ao lobby com revanche.
4. Testar o lobby online. O servidor padrão é
   `ws://netplay.retcomm.net:8765`; a disponibilidade não foi confirmada aqui.
   O runtime permite outro servidor por `PSX_NET_LOBBY_URL`.
5. Manter rollback habilitado (padrão), depois comparar com Disable Rollback.
   Conferir correções sob atraso/jitter, ausência de desync e perda de conexão.
6. Consultar `netplay_status` no debug server (porta 4531) em ambos os pares:
   verificar avanço dos ticks e da confirmação de estados. Guardar logs em
   caso de mismatch, timeout, travamento ou queda de desempenho.

Os gates verificam CRC/SHA-1 do disco e TOC exatos: um track MODE2/2352,
224.511 setores. Content negotiation está desabilitada para partidas vanilla.
Os pares também precisam concordar na BIOS e na identidade de execução; o
lobby comum não torna partidas PSX compatíveis com jogos SNES.

## Verificações iniciais sem build

- 24 testes Python da CLI, incluindo o layout com framework irmão e os fluxos
  de geração/rebuild com processos substituídos por mocks.
- Sintaxe do script PowerShell, AST dos arquivos Python alterados, TOML e pins
  das três dependências.
- Contrato dos argumentos do CMake com o helper real, em modo script com
  criação de targets substituída; sem configurar compiladores ou compilar.
- SHA-256 e CRC32 do BIN local conferidos com a identidade USA; fingerprint
  calculado da TOC do CUE de um track.
- A CLI oficial `verify-disc` aceitou o track principal com os digests
  configurados. O status de subchannel foi `unknown`.

Essas verificações isoladas não validam compilação C/C++, desempenho ou sincronização
durante partidas. A comparação de whitespace com a base original é restrita às
adaptações locais; arquivos importados preservam a formatação do upstream.

## Primeiro build e auditoria em 18/10/2026 — OpenBIOS substituída

- Corrigido o registro de `test_cli_framework_layout.py` no CMake dos emitters;
  a proteção contra testes órfãos continua habilitada.
- Definido `[recompiler] bios_config = "../psxrecomp/bios/SCPH1001.toml"`
  para a geração localizar o perfil de endereços na estrutura de pastas do port.
  Esse perfil de geração não seleciona a BIOS usada em runtime.
- Emitters recompilados, OpenBIOS regenerada e jogo emitido em 45 shards,
  com 1.330 funções na tabela de dispatch.
- Build `RelWithDebInfo` concluído com GCC 16.1.0/UCRT64, SDL3, Netplay,
  ICE, recomp-net e rbengine habilitados; dois jobs no runtime.
- Executável: `build-online/exPlusAlpha.exe`, versão `0.2.0-online-dev`.
  Esse primeiro build ligou OpenBIOS e o usuário relatou tela preta. Foi
  substituído pela configuração exclusivamente SCPH1001; Vulkan não foi
  compilado por falta do SDK.
- Inspeção de imports: apenas DLLs do Windows/UCRT, sem DLLs externas do
  compilador, SDL ou bibliotecas de rede para copiar.
- CTest: `cli_framework_layout`, `cli_generate_aot_static` e `cli_rebuild_host`
  passaram (três suítes, 24 testes Python).
- O executável rodou `--audit-mod-plugins` sem iniciar o jogo: PASS,
  seis manifests e seis plugins declarados/registrados; código de saída zero.
- Logs locais: `../psxrecomp/.local/build-online.log`,
  `../psxrecomp/.local/generate-online-retry.log`,
  `../psxrecomp/.local/build-runtime-online-network.log` e
  `../psxrecomp/.local/online-plugin-audit.stdout.log`.

O download do WebP precisou de execução fora do ambiente de rede restrito.
Avisos de compilação do upstream permanecem; não impediram o build.
Não foram executadas partidas nem testada a sincronização pela rede.

Antes de distribuir, adaptar o empacotamento ao helper oficial
`psxrecomp/tools/package_game_release.sh`, incluindo assets, catálogo de mods,
toolchain de overlays e sidecar de execução. Não incluir a BIOS retail nem os
arquivos da OpenBIOS do build anterior. Os pacotes antigos
baseados em `compileBuild` não contêm a estrutura atual.

## Build SCPH-1001 concluído em 18/10/2026

Após o relato de tela preta com OpenBIOS, o port passou a exigir exclusivamente
a imagem SCPH-1001 já usada na baseline. Não foi feito trabalho para adaptar o
jogo à OpenBIOS.

- Origem local: `../bios/SCPH1001.BIN`, SHA-256 conferido com `BIOS.md`.
- Backend SCPH1001 regenerado a partir dessa imagem. A regeneração dos 45
  shards do jogo não alterou nenhum deles.
- CMake/cache e registro de backends contêm apenas SCPH1001. Inspeção do
  executável confirmou `SCPH1001_psx_bios_backend` e ausência do backend OpenBIOS.
- `build-online/exPlusAlpha.exe` recompilado com sucesso, quatro jobs;
  `build-online/game.toml` contém `openbios = false`.
- As duas cópias antigas de OpenBIOS da pasta de saída foram removidas após
  comparar seus hashes com os assets que o build anterior havia copiado.
  Nenhuma ROM retail foi copiada para a saída.
- Passaram os guards de seleção de BIOS e os dois testes da CLI para o perfil
  retail. Gameplay e partidas online continuam aguardando validação.
- Logs: `../psxrecomp/.local/generate-online-retail.log` e
  `../psxrecomp/.local/build-online-retail.log`.

Abra o executável e selecione sua própria `SCPH1001.BIN` no launcher. Na máquina
do desenvolvedor, use `F:\GitRevised\alphaplus\plusalpha-recomp\bios\SCPH1001.BIN`.
O jogador deve fornecer sua própria cópia dessa mesma revisão da BIOS.

## Conferência da integração estática em 18/10/2026

- As 2.086 unidades C preparadas foram comparadas byte a byte com a origem:
  nenhuma diferença nos corpos nativos.
- O executável já gerado em `build-online-static/exPlusAlpha.exe` contém
  todos os 4.424 símbolos exigidos pelo dispatcher original, sem ausências.
  Também contém as interfaces atuais de consulta e estatísticas do dispatcher.
- Backend SCPH1001 presente e backend OpenBIOS ausente na tabela de símbolos.
- Executável conferido: 480.919.084 bytes; SHA-256
  `c36293c84569af2b88f5797873d79078a09240e4fc6c8be12637020b17b5d677`.
- Os sete testes Python do preparador passaram, incluindo preservação dos
  fontes, idempotência e rejeição de inventário incompleto ou inválido.
- O log da compilação já concluída está em
  `../psxrecomp/.local/build-online-static.log`.

Os últimos ajustes de validação do recibo no CMake e de diretório em
`codegen_setup.c` foram feitos depois do início dessa compilação. Por isso,
esse EXE não representa integralmente o estado final dos fontes. Conforme a
instrução de deixar as builds com o usuário, não foi iniciada outra compilação.
Antes do teste offline, execute na raiz do repositório:

```powershell
.\PlusAlphaProject\tools\build_online.ps1 -Jobs 4
```

Não é necessário regenerar o jogo com `-Generate` para incorporar esses
ajustes. Nenhum teste de gameplay ou sessão online foi realizado nesta etapa;
a correção da tela preta ainda precisa ser confirmada pelo teste offline.

## Correção do contexto de threads — aguardando build e teste offline

A comparação com o framework estável `1cfa7fe` identificou a perda do
salvamento do contexto de saída de SYS(03) quando CloseTh já havia marcado
a thread emulada como livre (`0x1000`). OpenTh preserva o SR salvo ao reutilizar
esse slot. Os dois dumps da tela preta mostram o slot `0xA000E35C` encerrado
com interrupções habilitadas e depois reutilizado em `0x8018C880` com
`SR=0x40000400`, interrupções desabilitadas.

`runtime/src/traps.c` volta a salvar o contexto antes de selecionar a próxima
thread, tanto no caminho de fibers quanto no scheduler determinístico. A
retirada da fiber encerrada e as proteções de shadow permanecem. Não se força
o bit de interrupção: preserva-se o estado de saída efetivo do jogo, como na
versão estável. Nenhum corpo C promovido ou fonte gerado da BIOS foi alterado.

Esta correção não restaura as ferramentas de análise removidas na migração;
trata especificamente o contexto das threads emuladas. Não foi executada build
nem teste de gameplay após a alteração. Execute `tools/build_online.ps1 -Jobs 4`
a partir de `PlusAlphaProject`, ou o comando completo documentado acima a
partir da raiz do repositório, e valide offline antes de testar online.
Não é necessário usar `-Generate` para esta alteração de runtime.

## Entrada repetida no chat por IP direto — aguardando validação

O cliente LAN envia MOTK3 JOIN a cada 400 ms para atualizar o estado da sala.
O anfitrião já reconhecia o mesmo player_id e reutilizava seu assento, mas
anunciava cada pacote como uma entrada nova e redefinia `started=false`.
Isso produzia o spam de "Player has joined." mesmo com apenas dois jogadores.

Os handlers MOTK3 e MOTK1 em `runtime/src/main.cpp` agora distinguem uma
identidade já sentada de uma entrada nova: somente uma entrada nova anuncia
o jogador e limpa o estado de partida iniciada. Os pacotes periódicos continuam
atualizando o endpoint e respondendo com o estado da sala. Uma saída processada
seguida de uma nova entrada continua gerando anúncio.

Não foi executada build nem teste com duas instâncias após esta alteração.
Após compilar, recrie a sala, conecte P2 por IP direto e aguarde pelo menos
dez segundos: deve haver apenas um anúncio de entrada e dois assentos.
Confira também sair/reentrar, chat e início da partida nas duas instâncias.

## Recuperação de cobertura e diagnóstico do boot — 19/10/2026

A comparação dos EXEs confirmou 1.358 funções do main na build com bezel e
1.330 na build online: 29 antigas ausentes e uma nova. As 2.086 unidades C e
os 4.424 símbolos de overlays continuam preservados. As 29 entradas ausentes
agora são seeds explícitas; `tools/check_main_coverage.py` exige suas linhas
reais na tabela de dispatch antes de permitir a compilação pelo script.

Nesta atualização é obrigatório regenerar, pelo usuário:

```powershell
.\PlusAlphaProject\tools\build_online.ps1 -Generate -Jobs 4
```

O comando acima gera e compila. Não foi executado pelo agente. As entradas
somente estarão no novo EXE depois dessa geração/build; se o emitter recusar
uma seed, preserve o erro para análise em vez de remover o gate.

O launcher ImGui passa a consultar a verificação do disco de forma assíncrona:
o worker calcula identidade/CRC completo, a interface permanece responsiva e
Play/online ficam indisponíveis até existir resultado. O resultado é reutilizado
na sessão enquanto caminho, tamanho e data de modificação do mount/data track
permanecerem iguais. A política de TOC é reaplicada na thread principal.
Nenhum estado de UI/lobby é publicado pelo worker.

O detector fica pausado durante reboot e retorno ao lobby e é rearmado antes
do scheduler do jogo. O heartbeat continua disponível. Heartbeats e dumps
incluem o PID no nome para duas instâncias não sobrescreverem os arquivos
uma da outra. Dumps são escritos como `.json.partial` e publicados como
`.json` somente após a conclusão; uma saída abrupta pode deixar um `.partial`.
O limite de dumps e as capturas para falhas reais não foram desabilitados.

O dispatcher de overlays permanece com a regra de segmento exato do framework
atual. Não se normalizam aliases KUSEG/KSEG1 para KSEG0: os corpos foram
compilados para um segmento específico. Os dumps analisados não demonstram
que aliases sejam a causa do trecho `0x800E7CFC`; recuperar aliases exige uma
captura que identifique o segmento e geração compatível, não remover o gate.

Validar primeiro boot/luta offline; depois duas instâncias, saída ao lobby e
revanche. Comparar também abertura da interface e tempo até a verificação do
disco terminar. O custo de hash continua existindo, mas não deve impedir o
primeiro desenho. Nenhuma medição após build é afirmada nesta etapa.

## Limite do launcher e cadência inicial — 19/10/2026

O backend ImGui agora limita explicitamente o loop a 60 FPS com relógio
monotônico, independentemente da taxa do monitor ou do volume de eventos.
O VSync continua habilitado. A espera por eventos de até 16 ms foi substituída
por consulta sem espera: o limitador já controla o intervalo, evitando somar
uma segunda espera fixa. Um frame lento não gera uma sequência de compensação.
Esse limite se aplica somente ao launcher, inclusive ao retornar ao lobby.

A oscilação da tela CAPCOM ainda requer medição após esta build. O runtime
atual alterna carregamento acelerado e execução cadenciada; seu caminho de
turbo usa apresentação a cada 30 frames simulados, enquanto a versão estável
usava um prazo de apresentação em tempo real e reiniciava o pacer ao carregar.
Isso é uma hipótese de cadência, não uma confirmação por imagem de perda de
cobertura nativa. Não foram alterados o pacer do jogo, o turbo ou o rollback
nesta correção. Comparar tempos de apresentação e transições de turbo desde o
primeiro frame para determinar se essa hipótese explica o trecho inicial.

Não foi executada build nem medição de FPS após o ajuste do launcher.

## Recuperação da baseline

As branches `main` anteriores permanecem nos dois repositórios. Para comparar
com a versão validada, prefira outro checkout; não troque de branch com mudanças
pendentes e não use comandos de limpeza em builds, discos ou saves pessoais.
