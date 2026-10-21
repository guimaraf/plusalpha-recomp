# Migração do online — integração estática, validação offline pendente

Esta integração usa o rollback e o lobby oficiais do PSXRecomp. O suporte está
conectado no código e o build Windows com SDL3 foi concluído em 18/10/2026,
após autorização explícita do usuário para compilar. A qualificação de gameplay
offline e entre dois pares continua pendente. Não tratar esta branch como
release validada.

## Revisões

### Captura da origem da defasagem — 21/10/2026

O roteiro de repetição, combate e arrasto está em
[NET_SYNC_TESTS.md](NET_SYNC_TESTS.md), com marcadores durante a captura.
Essa atualização dos scripts usa a build de diagnóstico já existente e não
exige recompilação. O coletor agora separa sessões recriadas nos mesmos EXEs;
reiniciar os processos exige uma captura nova.

Instrumentação preparada, aguardando build e teste locais. Não altera as
decisões de admissão, delay, rollback ou o prazo do limitador de FPS.
O defeito XA/FMV corrigido anteriormente continua corrigido; a origem da
defasagem restante ainda precisa ser comprovada.

Compile manualmente a nova versão:

```powershell
Set-Location F:\GitRevised\alphaplus\plusalpha-recomp
.\PlusAlphaProject\tools\build_online_diagnostics.ps1 -Generate -Jobs 2 -RunRegressionTests
```

O script cria `PlusAlphaProject/build-online-diagnostics-sync-trace-DATA-HORA`.
Copie a mesma build completa para `G:\sfPlus\onlineDiag1` e
`G:\sfPlus\onlineDiag2`, como nos testes anteriores. Feche as instâncias antigas.
Abra as duas cópias e o coletor com:

```powershell
.\PlusAlphaProject\tools\capture_net_sync.ps1 -Launch -Seconds 300
```

`-FirstDir` e `-SecondDir` permitem indicar outras pastas. Com `-Launch`, o
script verifica se os EXEs têm o mesmo SHA-256 e se as portas estão livres,
define `PSX_NET_SYNC_TRACE=1` e `PSX_DEBUG_TOGGLES=0` apenas para iniciar os
processos, e abre cada EXE usando sua própria pasta de trabalho. Não copia
builds, encerra jogos, muda configurações, injeta input ou compila.

Aguarde a confirmação **nas duas portas** antes de criar/entrar na sala.
Para o teste simples, crie a sala na primeira instância, entre pela segunda,
use o ajuste automático habitual e chegue à luta. O teste T04 do roteiro
permite recriar salas na mesma captura, mantendo os EXEs abertos. Deixe o versus
com tempo infinito por pelo menos um minuto. O coletor termina após 300 s;
Ctrl+C preserva os dados coletados. Mantenha os jogos abertos para inspeção.

Repita em uma captura nova, reiniciando ambos os processos e invertendo quem
cria a sala. Depois repita invertendo a ordem de abertura. Anote em cada teste
quem criou a sala, qual janela tinha foco e quando percebeu a diferença.
Os nomes `peer-4531`/`peer-4532` identificam portas; o papel real está em `host`.

Arquivos em `PlusAlphaProject/captures/net-sync-DATA-HORA`:

- `manifest.json`: horários, portas, etapas e hashes/caminhos dos EXEs com `-Launch`.
- `peer-4531.jsonl` e `peer-4532.jsonl`: eventos e consultas com início/fim da requisição.
- `summary.json`: perdas, erros e diferença temporal entre admissões do mesmo tick.

O histórico é ativado antes do processo iniciar e usa um ring de 32.768 eventos
em memória. Ele registra o retorno da criação da sessão, a entrada/saída da
barreira (inclusive tick 0), esperas prolongadas a cada 100 ms, apresentação e
limitador de FPS. Cada evento inclui QPC, prazo do limitador, tick, geração da
sessão, papel, delay, maior wire recebido, lead, pacotes recebidos, idade do
último pacote, FMV/XA, replay, dívida de timesync e fatias solicitadas, misses,
lateness e estado da decisão de auto-delay. `sample_ticks` mede o custo da
coleta do próprio evento, em unidades de QPC. Não há escrita em disco no
caminho de gravação do jogo; o coletor externo persiste os lotes.

`net_sync_trace` é um comando TCP de leitura com `after` (última sequência
recebida) e `count` (até 512). A coleta normal pede 128 eventos por lote e
consulta `netplay_status`/`video_info` a cada dois segundos quando não há atraso
de leitura. O VSync real vem de `video_info`; o ring não consulta GL em cada
evento, evitando uma sincronização adicional com a thread de renderização.
As consultas TCP ainda têm custo; observe `sample_ticks` e os intervalos de
requisição antes de atribuir qualquer pico exclusivamente ao jogo.

`lead` representa disponibilidade de entradas, **não** diferença de simulação.
O tick registrado é o cursor de admissão, não necessariamente o frame já
exibido. `slice_requested_ms` soma as esperas solicitadas pelo controlador;
as etapas de barreira e pacer mostram o tempo efetivamente transcorrido.
O resumo compara os relógios QPC somente no mesmo PC Windows, com frequência
igual; não serve para comparar relógios de computadores diferentes. Um valor
positivo em `b_minus_a_ms` significa que a porta B chegou ao mesmo tick depois
da A. Não é uma medida de latência física do controle. As sessões recriadas são analisadas separadamente; reiniciar os processos
exige uma captura nova.

Histórico desativado, comando inexistente, reinício detectado, perda de eventos
ou ausência de ticks comuns tornam a captura incompleta. Preserve os JSONL
mesmo assim. Nenhuma build foi executada pelo agente. Os testes Python do
coletor podem ser executados sem compilar:

```powershell
python -B -m unittest discover -s PlusAlphaProject/tools/tests -p test_capture_net_sync.py -v
```

### Referências da integração

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

Os scripts normal e release validam sempre `../bios/SCPH1001.BIN` (relativo
ao projeto), SHA-256 `71af94d1e47a68c11e8fdb9f8368040601514a42a5a399cda48c7d3bff1e99d3`.
Ambos fixam somente o backend SCPH1001 e recusam fontes de BIOS com fingerprint
desatualizado. A definição genérica `PSX_BUNDLED_BIOS_PATH` do framework não
seleciona o backend nem prova uso de OpenBIOS; o registro deste port é retail.

Para regenerar os fontes com essa BIOS e refazer as duas builds, execute na raiz:

```powershell
.\PlusAlphaProject\tools\build_online.ps1 -Generate -Jobs 2
.\PlusAlphaProject\tools\build_release.ps1 -Jobs 2
```

A geração é compartilhada entre as builds; não precisa repetir `-Generate` na
release após concluir o primeiro comando. Para gerar apenas a release novamente,
use `build_release.ps1 -Generate -Jobs 2`. Os dois scripts aceitam `-BiosPath`
para indicar outra localização da mesma imagem validada. Sem `-Generate`, a
imagem preparada no framework também precisa corresponder ao hash esperado.

O caminho Python de geração também grava `<stem>.emitter.sha` depois do emissor
concluir, usando o mesmo cálculo CMake da verificação. Em caso de erro ou mudança
dos insumos durante a geração, não publica um fingerprint válido. Se a configuração
parar com `stamp` vazio, execute novamente o primeiro comando com `-Generate`
após atualizar este código; não desative a verificação nem preencha o hash à mão.

### Placas de nomes (OpenGL)

No launcher, em Settings → Display, `Show player names` ativa/desativa as
placas para offline e netplay. A opção vem ligada e é salva em `settings.toml`,
`[video] player_nameplates = true/false`, inclusive ao sair do launcher e ao
voltar de uma partida. O jogo também lê essa preferência ao pular o launcher.
`nameplates-preview.ini` não é mais consultado: uma instalação release nova
não depende de copiar um arquivo de teste.

Com `Show player names` marcado, a seção `Offline Names` oferece os campos
`Player 1` (esquerda), `Player 2` (direita) e o botão `Save`. Cada nome aceita
até oito caracteres UTF-8, incluindo colagem; acentos combinantes acompanham
a letra. O botão grava imediatamente `[video] offline_player_1` e
`offline_player_2` em `settings.toml` e confirma `Offline names saved.`.
A edição fica separada dos nomes salvos: fechar o launcher ou iniciar sem
clicar em `Save` conserva os últimos nomes gravados. Desmarcar a opção apenas
oculta os campos e as barras, sem apagar os nomes. Campos vazios restauram
`Play 1` e `Play 2` no respectivo lado.

No início de cada sessão, após inicializar as barras, o runtime lê os nomes
offline salvos, inclusive quando o launcher é pulado. A gravação usa um arquivo
temporário na mesma pasta e só substitui o original após concluir a escrita.
Erros de leitura/gravação aparecem no launcher e não promovem a edição a nome
salvo. Os nomes permanecem fora da RAM emulada e dos snapshots.

Ao iniciar netplay, as placas recebem os nomes dos participantes da sala por
slot: 0 à esquerda, 1 à direita, iguais nas duas instâncias. LAN/IP direto
publica o nome editável antes de criar/entrar na sala, assim como o lobby online.
Os nomes são copiados no início da sessão; não há leitura de arquivo ou consulta
de rede por frame para atualizar as placas. Sem nome disponível, usa-se `Play 1`
ou `Play 2` no respectivo lado.

A apresentação online continua removendo um prefixo de bandeira Unicode e seu
separador, limitando cada nome a dez caracteres, preservando acentos e sem
modificar o nome da conta. O limite de oito dos campos offline é independente.
As molduras têm largura fixa, P1 alinhado à esquerda e P2 à direita. São
dimensionadas pela área de jogo apresentada, incluindo o ajuste de proporção.
As placas começam quando o HUD de luta é emitido, continuam no replay e
desaparecem ao sair da cena de luta. Não aparecem no Software.

Teste seleção → luta → KO → replay → seleção, redimensionamento e tela cheia.
As informações visuais ficam fora da RAM emulada e dos snapshots. Validar também
Fred/Felipe em ambas as janelas por IP direto, troca de slots, saída e nova sessão.
Validar também: pasta nova sem INI de prévia; opção ligada/desligada, fechar e
reabrir o launcher; retorno ao lobby e nova partida. O ajuste não altera input
delay, VSync, pacer ou rollback. A investigação de atraso fica para depois de
validar as placas. Os testes C++ de estado cobrem ativação sem arquivo, ocultação
ao desligar e limpeza do estado ao religar; precisam de compilação local.

Para validar nomes offline: salvar os dois campos, fechar e reabrir o launcher,
iniciar uma luta, editar sem salvar e iniciar novamente, salvar campos vazios,
tentar inserir/colar nove letras e testar nomes acentuados. Conferir também
offline → online → offline, mantendo os nomes da sala no online e recuperando
os nomes locais no offline. Os novos testes `offline_player_names_test` e
`recomp-ui-launcher-offline-names` cobrem persistência, falhas, validação UTF-8
e a separação entre edição e Save; sua execução exige compilação local.

Como o leitor de settings também participa do fingerprint do emissor da BIOS,
esta atualização requer uma geração local antes de compilar a release:

```powershell
.\PlusAlphaProject\tools\build_release.ps1 -Generate -Jobs 2
```

O runtime já forçava VSync off no netplay. Agora aplica essa política imediatamente
após criar a sessão, antes da admissão do primeiro tick, em host e cliente.
O intervalo efetivo é 0, inclusive se a preferência offline for adaptativa;
a preferência offline é preservada para quando a sessão terminar. O log registra
`netplay presentation: VSync OFF (swap interval 0)`. O limitador da simulação
continua ativo. Não se alteraram os sete frames de input delay observados no teste;
VSync off não elimina esse atraso configurado. Ainda é necessária validação local
após build, inclusive uma sessão longa para verificar eventual atraso cumulativo.

### Diagnostico online: musica XA e protecao de FMV

A captura de 21/10/2026 confirmou rollback ligado e VSync efetivo zero nas duas
instancias, mas oito frames de input delay e uma defasagem persistente entre
simulacoes. A musica XA durante a luta ativava `rb_fmv_media_active`, mesmo sem
video de 24 bits ou MDEC recente. Essa classificacao bloqueava a predicao normal
e suspendia timesync e a adaptacao automatica do delay durante a partida.

O detector agora usa evidencia de video: display de 24 bits ou MDEC recente.
Musica XA isolada nao ativa a protecao; videos silenciosos e a histerese entre
frames MDEC continuam protegidos. Nao houve alteracao do pacer, dos limites de
delay ou da politica de VSync nesta correcao. Ainda e necessario medir o efeito
na partida e verificar possiveis causas adicionais da defasagem.

Para gerar uma nova build completa (RelWithDebInfo, SDL3, launcher, rollback,
ICE e debug server ativos), execute na raiz do repositorio:

```powershell
.\PlusAlphaProject\tools\build_online_diagnostics.ps1 -Generate -Jobs 2 -RunRegressionTests
```

O script usa uma pasta nova `PlusAlphaProject/build-online-diagnostics-xa-fix-<data-hora>`,
com overlays proprios, e nao substitui builds existentes. `-RunRegressionTests`
compila e executa localmente um fixture com o corpo real do detector. Ele cobre
XA sem video, video de 24 bits, MDEC com e sem audio, fim de video com musica
persistente e retorno de um video silencioso. Tambem esta registrado no CTest
como `netplay_fmv_media_detection_test`. O agente nao executa essa compilacao.

Depois de copiar a mesma build para as duas pastas de teste, feche as instancias
anteriores e inicie pelo PowerShell:

```powershell
$env:PSX_DEBUG_TOGGLES = '0'
Start-Process 'G:\sfPlus\onlineDiag1\exPlusAlpha.exe' -WorkingDirectory 'G:\sfPlus\onlineDiag1' -ArgumentList '--debug-port', '4531'
Start-Process 'G:\sfPlus\onlineDiag2\exPlusAlpha.exe' -WorkingDirectory 'G:\sfPlus\onlineDiag2' -ArgumentList '--debug-port', '4532'
```

`PSX_DEBUG_TOGGLES=0` desativa as teclas experimentais de renderizacao e sua
preparacao de resolucao para A/B, mantendo os comandos TCP de diagnostico.
Cada instancia usa a propria pasta de trabalho para os relatorios locais.

Em `netplay_status`, os novos campos somente de leitura `input_delay`,
`fmv_media_active` e `xa_stream_active` permitem acompanhar o delay efetivo e
o detector, sem inspecionar memoria do processo. Na luta com musica, esperar
`xa_stream_active=1` e `fmv_media_active=0`; durante um FMV real, a protecao deve
ser 1. `video_info.gl_swap_interval` deve permanecer 0 no online.

Validar intro -> selecao -> luta com musica -> KO/replay -> nova luta, uma
sessao prolongada com tempo infinito e uma revanche. Comparar a diferenca de
ticks com consultas proximas no tempo, o delay efetivo, a confirmacao de estados
e `desync=0` nos dois pares. Rollback ligado nao implica delay fixo ou zero:
o automatico volta a poder ajustar o buffer durante a luta. Nao considerar a
correcao qualificada antes desses testes locais.

### Release Windows enxuta

Na raiz de `plusalpha-recomp`, execute localmente:

```powershell
.\PlusAlphaProject\tools\build_release.ps1 -Jobs 2
```

O comando usa os fontes já gerados, compila `Release` com SDL3, online e launcher,
sem debug tools nem wizard de geração, em uma pasta nova
`PlusAlphaProject/build-release-online-AAAAmmdd-HHmmss`, com os overlays
preparados dentro dela. As builds anteriores, incluindo a release antiga,
a build de diagnóstico e a referência estável, são preservadas. Se precisar
regenerar fontes, acrescente `-Generate` (essa opção também compila os emitters).

Os modos experimentais de input 1/2/3 nao sao habilitados nesta release, mesmo
se a variavel `PSX_OFFLINE_POST_IRQ_PACER` estiver definida no terminal. O modo
original permanece e o launcher, o IP direto, o lobby e o rollback continuam
habilitados. O script nao altera os fontes de comportamento do online.

Para escolher o nome da pasta de build, use por exemplo
`-BuildDirName build-release-online-input-baseline`. Se ela ja existir, o
script recusa recompilar por padrao. Para continuar intencionalmente uma build
interrompida, informe o mesmo nome e `-Incremental`:

```powershell
.\PlusAlphaProject\tools\build_release.ps1 -BuildDirName build-release-online-input-baseline -Incremental -Jobs 2
```

O pacote é criado em uma pasta nova
`PlusAlphaProject/dist/exPlusAlpha-AAAAmmdd-HHmmss`. Para escolher outra pasta,
use `-OutputDir 'F:\meus-pacotes\exPlusAlpha-1'`; ela não pode existir.
Para empacotar novamente uma build release pronta, sem compilar:

```powershell
.\PlusAlphaProject\tools\build_release.ps1 -PackageOnly -BuildDirName build-release-online-AAAAmmdd-HHmmss
```

Substitua o nome pelo diretorio real da compilacao desejada. Por compatibilidade,
`-PackageOnly` sem nome ainda empacota a antiga pasta `build-release-online`.
Nao usar essa forma abreviada para empacotar a release nova por engano.

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
