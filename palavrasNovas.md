# Inventario de palavras novas

Este documento e a fonte de verdade para os candidatos ineditos encontrados
pelas coletas de descoberta. Antes de iniciar outra descoberta profunda, toda a
fila `pendente` abaixo deve ser triada.

## Regras de manutencao

- `PC observado` nao e automaticamente uma funcao: pode ser entrada interior,
  retorno de chamada, destino de jump table ou alias.
- Uma linha so passa para `processado` depois de boundary, callers, aliases,
  closure, fluxo indireto, telemetria e regressao aprovados.
- Um lote apenas preparado permanece `selecionado`; ele ainda nao conta como
  cobertura promovida.
- Nenhuma seed nova pode ser selecionada sem pre-auditoria completa da closure
  alcancavel em area isolada e um limite explicito de palavras definido antes
  da geracao dos artefatos principais.
- Se a closure medida exceder o limite, o candidato deve ser rejeitado; nunca
  aumentar o numero esperado de funcoes apenas para aceitar a expansao.
- `0x8019E6D0` permanece exclusivamente na watchlist e nunca deve entrar como
  seed sem nova evidencia reproduzivel.
- Nao executar nova descoberta profunda enquanto houver candidatos adequados
  nesta fila.

## Baseline atual

- Checkpoint promovido: **S1-255 Release limpo**.
- Cobertura: **110.494 / 195.584 palavras (56,4944%)**.
- Funcoes geradas: **1.049**.
- Entradas do dispatcher: **16.488**.
- Auditor codegen: **CLEAN**.
- Configuracao validada: **Release**, `PSX_DEBUG_TOOLS=OFF`, runtime estatico.
- Ranges SHA-256:
  `30BCD2340878A0C9057CA4B8A66F582A0695AF844B1E45E9409678951D76D404`.
- Executavel validado SHA-256:
  `97A75A613D412180CEF19F295454F80DB29E499C07F33CBC0C97C3824B50C930`.

O checkpoint cumulativo incorpora S1-251, S1-253, S1-254 e S1-255. A regressao
Release percorreu Expert Mode, Bonus Barril com Guile, Versus Doctrine Dark x
Skullomania e cinco partidas completas de Arcade. Nao houve regressao
percebida; o jogo permaneceu em 60 FPS e a linha de frametime ficou
extremamente estavel. A politica revisada do turbo loading, incluindo o teto de
apresentacao de 30 Hz, tambem integra este checkpoint.

A tentativa S1-252 contaminou temporariamente os fontes de trabalho com 1.054
funcoes e ranges SHA-256
`2F3A18F08ED029E7D5D7227E60DC6AA38367187D9D9DD9DE2DD91C4713BBA7E1`.
Os fontes foram restaurados para S1-251 e novamente auditados como `CLEAN`, com
1.042 funcoes e SHA-256 `BB5EA43C77096772D1997D52EBA01C84F9DE674D057053D0D61FD9561D6A6D25`.
O incidente foi encerrado sem incorporar a closure integral; somente os lotes
posteriormente pre-auditados foram promovidos no checkpoint S1-255.

## Material de origem

- `PlusAlphaProject/local/telemetry/modified-m01-bonus-barril-01/candidates.txt`
- `PlusAlphaProject/local/telemetry/discovery-m02-versus-doctrine-skullomania-01/candidates.txt`

As duas coletas contem 84 PCs unicos. Na baseline S1-250, 34 ja pertencem a
ranges nativos e 50 ainda estao fora deles. Os 50 PCs restantes nao equivalem a
50 funcoes.

## Lotes processados

| Lote | Funcoes/ranges promovidos | Palavras novas | Cobertura acumulada | Estado |
|---|---|---:|---:|---|
| S1-240 | `0x8013CB08..0x8013CB8B` | 33 | 106.352 | processado; checkpoint S1-242 |
| S1-241 | `0x801102A0..0x8011062F` | 228 | 106.580 | processado; checkpoint S1-242 |
| S1-242 | `0x80137FE8`, `0x80138084`, `0x8013827C` | 245 | 106.825 | processado; checkpoint S1-242 |
| S1-243 | `0x80162D68..0x8016313B` | 245 | 107.070 | processado; checkpoint S1-245 |
| S1-244 | `0x80107A74..0x80107D7F` | 195 | 107.265 | processado; checkpoint S1-245 |
| S1-245 | `0x8011D310..0x8011D9B3` | 425 | 107.690 | processado; checkpoint S1-245 |
| S1-246 | `0x8011D030` + `0x8011D078` | 184 | 107.874 | processado; checkpoint S1-248 |
| S1-247 | `0x801A92B8..0x801A939B` | 57 | 107.931 | processado; checkpoint S1-248 |
| S1-248 | `0x801A9DC0..0x801A9FD3` | 133 | 108.064 | processado; checkpoint S1-248 |
| S1-249 | `0x8019F6A8` + `0x8019FB64` | 125 | 108.189 | processado; checkpoint S1-250 |
| S1-250 | `0x8019F5CC`, `0x8019FB4C`, `0x8019FB84`, `0x8019FB94` | 76 | 108.265 | processado; checkpoint S1-250 |
| S1-251 | `0x8014C708..0x8014C72F` | 10 | 108.275 | processado; checkpoint S1-255 |
| S1-253 | `0x8017D860`, `0x8017DA08`, `0x80191000` | 184 | 108.459 | processado; checkpoint S1-255 |
| S1-254 | `0x8017DA9C`, `0x80190EB8`, `0x80190FAC` | 155 | 108.614 | processado; checkpoint S1-255 |
| S1-255 | `0x8018F10C..0x80190E6B` | 1.880 | 110.494 | processado; checkpoint S1-255 |

Total promovido desde S1-239: **4.175 palavras**.

## Lote em validacao

Nenhum. O proximo lote ainda depende de pre-auditoria e orcamento explicito.

O S1-251 e um wrapper formal de 40 bytes. A telemetria confirmou 8.736 entradas
na raiz, sem misses, e que o alvo da celula `0x80018800` foi `0x80018DE0` entre
BEFORE e AFTER. As 4.096 amostras do callback retornaram por `0x8014C720`; o
alvo permanece RAM dinamica, portanto nao entra como seed nem closure estatica.

O S1-251 isolado acrescentou 10 palavras ao checkpoint S1-250. A promocao
integral foi concluida pelo checkpoint Release S1-255.

## Candidato rejeitado: S1-252

O despachante `0x8016FC28` parecia conter somente 39 palavras, mas possui dois
`JAL` diretos para codigo ainda interpretado. A geracao expandiu recursivamente
a closure para **12 funcoes e 2.805 palavras**, excedendo completamente o
escopo de um micro-lote. O candidato foi rejeitado antes de build.

| Funcao | Range | Palavras | Decisao |
|---|---|---:|---|
| `0x8016FC28` | `0x8016FC28..0x8016FCC3` | 39 | raiz rejeitada |
| `0x8017D860` | `0x8017D860..0x8017DA07` | 106 | closure rejeitada |
| `0x8017DA08` | `0x8017DA08..0x8017DA9B` | 37 | closure rejeitada |
| `0x8017DA9C` | `0x8017DA9C..0x8017DBBF` | 73 | closure rejeitada |
| `0x8018F10C` | `0x8018F10C..0x80190E6B` | 1.880 | closure principal rejeitada |
| `0x80190EB8` | `0x80190EB8..0x80190FAB` | 61 | closure rejeitada |
| `0x80190FAC` | `0x80190FAC..0x80190FFF` | 21 | closure rejeitada |
| `0x80191000` | `0x80191000..0x801910A3` | 41 | closure rejeitada |
| `0x801910A4` | `0x801910A4..0x801912D7` | 141 | closure rejeitada |
| `0x801914C0` | `0x801914C0..0x80191587` | 50 | closure rejeitada |
| `0x80191C84` | `0x80191C84..0x80192127` | 297 | closure principal rejeitada |
| `0x80192D6C` | `0x80192D6C..0x80192E57` | 59 | closure rejeitada |
| **Total** |  | **2.805** | **rejeitado; nao compilar** |

As duas closures principais somam 2.177 palavras. A raiz e as nove auxiliares
somam outras 628 palavras. Toda essa evidencia permanece registrada para uma
eventual reavaliacao futura, que exigira novo orcamento explicito e
pre-auditoria isolada.

## Pre-auditoria S1-253

Primeiro micro-lote proposto a partir das folhas chamadas por `0x8018F10C`.
O orcamento foi fixado em **menos de 200 palavras** antes da geracao. A seed
principal ainda nao foi alterada; a previa deve ser gerada somente em
`local/preaudit/`.

| Funcao | Range | Palavras | SHA-256 do corpo | Caller conhecido |
|---|---|---:|---|---|
| `0x8017D860` | `0x8017D860..0x8017DA07` | 106 | `43F7DA960644EFE8DC1C199749FC08D8392A28591A3FC3577B7020FB3B9F0F67` | `JAL 0x8018FEEC` em `0x8018F10C` |
| `0x8017DA08` | `0x8017DA08..0x8017DA9B` | 37 | `3D7FF33BBC5B4A01DFFB86A1BD3C58DC7F2EE59B2B5182D2BEBE928E6B6F1639` | `JAL 0x80190E20` em `0x8018F10C` |
| `0x80191000` | `0x80191000..0x801910A3` | 41 | `86EA5B37A52FD2703CECF74FCF6672011A29D7E2726F166BFAA4181E8EF61368` | `JAL 0x8018FEF4` em `0x8018F10C` |
| **Total** |  | **184** |  | **dentro do orcamento** |

Fluxo estatico auditado:

- `0x8017D860` chama tres funcoes ja nativas: `0x8019497C`, `0x80194904` e
  `0x801948DC`; termina por `JR`.
- `0x8017DA08` chama `0x8017B154`, ja nativa. Os jumps `0x8017DA2C ->
  0x8017DA84` e `0x8017DA4C -> 0x8017DA74` sao internos ao proprio corpo.
- `0x80191000` chama `0x80190E6C`, ja nativa; termina por `JR`.
- Nenhuma das tres funcoes contem JALR, COP2/GTE, referencia estatica ao
  scratchpad, DIV/MULT ou BREAK.
- A closure estatica esperada e exatamente o proprio trio, com 184 palavras.
  Qualquer quarta funcao bloqueia o lote.

Previa isolada `s1-253-preview-01` aprovada: **1.045 funcoes**, delta exato de
**184 palavras**, auditoria `CLEAN`, artefatos principais preservados e ranges
SHA-256 `80DF7E6811A60B300CD5371818A2504FB571EB806B5FC755BD470A4582077068`.
As tres seeds foram ativadas para o lote S1-253 e os fontes principais foram
gerados com a mesma contagem, hash e auditoria `CLEAN`.

A primeira tentativa de coleta `s1-253-telemetry-01` foi descartada por erro do
coletor antes de concluir o BEFORE: `static_misses` referenciava uma variavel
local durante sua propria declaracao sob `set -u`. Nao houve janela valida nem
decisao tecnica. O mesmo padrao preventivo foi corrigido em `collect_after`
antes da repeticao integral de `prepare`, `before` e `after`.

A repeticao valida da coleta S1-253 usou Bonus Barril com Guile por 125 segundos.
O artefato, o manifesto e as tres armas do `fntrace` foram confirmados. Houve
514.411 novos despachos estaticos, zero miss, zero aborto, zero handoff nativo e
zero bloqueio de texto. O frametime permaneceu limpo: p50 16,683 ms, p95
16,793 ms e maximo 17,922 ms. A regressao manual posterior cobriu Versus
Doctrine Dark x Skullomania no cenario Skullomania, Trial e varias partidas de
Arcade sem problema percebido.

Entretanto, `0x8017D860`, `0x8017DA08` e `0x80191000` tiveram **zero hits** na
janela valida. O filtro auxiliar `fn_entry` tambem saturou sua pilha de
observacao, portanto nao serve como gate positivo desse run. O `fntrace` exato
permaneceu armado e vazio. Decisao: **regressao manual limpa; promocao tecnica
pendente; tres funcoes em `observacao_sem_hit`**. Elas nao devem ser usadas como
base para aprovar outro lote ate aparecerem em uma rota reproduzivel.

## Campanha multi-PC de alcance

Para evitar novas tentativas sem rota conhecida, foi preparada uma campanha
interativa que observa simultaneamente funcoes nativas e interpretadas durante
o gameplay. A primeira watchlist contem as 12 funcoes da closure rejeitada
S1-252, incluindo o trio S1-253. A inclusao na watchlist nao promove seed nem
altera o status de closure.

Arquivos da infraestrutura:

- `PlusAlphaProject/seeds/function_watchlist.txt`: enderecos observados;
- `PlusAlphaProject/tools/observe_function_watchlist.sh`: campanha por
  confronto, com notificacao de primeiro hit e matriz consolidada;
- comandos de runtime `pc_watch_arm`, `pc_watch_reset`, `pc_watch_stop`,
  `pc_watch_dump` e `pc_watch_clear`.

As campanhas `s1-253-function-watch-01` e `-02` validaram o observador e
localizaram rotas de frontend, modos e opcoes. A rota completa
`expert-mode-complete`, em `s1-253-function-watch-03`, durou 71 segundos e
encontrou 8 das 12 funcoes, com 9.586 hits. O trio S1-253 finalmente recebeu
evidencia positiva: `0x8017D860` teve 2 hits nativos, `0x8017DA08` teve 1.636
hits nativos e `0x80191000` teve 7 hits nativos. Na mesma rota,
`0x8018F10C`, ainda interpretada e com 1.880 palavras, teve 1.638 hits.

Ao retornar para a selecao de personagem nessa rota houve lag forte e
temporario. Os totais agregados nao mostram uma recursao descontrolada, mas nao
permitem localizar o instante do custo. Por isso foi criada uma segunda
infraestrutura, sem polling TCP durante a janela:

- `PlusAlphaProject/tools/observe_function_watchlist_timer.sh`;
- comandos `pc_watch_timer_state`, `pc_watch_timer_start`,
  `pc_watch_timer_stop`, `pc_watch_timer_dump` e `pc_watch_timer_clear`;
- amostragem em RAM a cada 100 ms por thread SDL de baixa prioridade;
- timeline de frames, ciclos e deltas cumulativos por funcao.

As timelines temporizadas foram coletadas com turbo desligado e com as politicas
experimentais de turbo. Elas nao mostraram congelamento da thread de emulacao:
na coleta `expert-mode-complete-timer` o maior periodo sem novo frame foi 0 ms.
O atraso visual na volta para a selecao foi isolado na politica de apresentacao
do turbo; o teto por tempo de host foi ajustado para 30 Hz. A tentativa de
cancelar turbo por input foi revertida porque o jogo consulta o controle tambem
durante loadings reais. Estado: **rota positiva do trio comprovada e S1-253
processado no checkpoint Release S1-255**.

## Pre-auditoria S1-254 aprovada

O S1-254 remove as tres folhas ainda interpretadas chamadas com alta frequencia
por `0x8018F10C` na rota Expert Mode. O orcamento foi fixado em
**exatamente 155 palavras** antes da previa.

| Funcao | Range | Palavras | SHA-256 do corpo | Hits interpretados de referencia |
|---|---|---:|---|---:|
| `0x8017DA9C` | `0x8017DA9C..0x8017DBBF` | 73 | `E524079B407C7D73BA9FAB0FFD47922EAA626A2E8B1D1C3FA811C7CE33889670` | 1.636 |
| `0x80190EB8` | `0x80190EB8..0x80190FAB` | 61 | `E9946F974DB4785696E82C73DC62128B8A422F5FB52241D2377ABC9E9BA08EF9` | 1.515 |
| `0x80190FAC` | `0x80190FAC..0x80190FFF` | 21 | `66C2068653C40574C0FF3A56627AB7DFBEB07448E6E83B4F4B5B5286AF8BE3F7` | 1.514 |
| **Total** |  | **155** |  | **4.665** |

Fluxo estatico auditado antes da previa:

- `0x8017DA9C` possui dois JAL para `0x8010C72C`, ja nativa;
- `0x80190EB8` possui oito JAL para tres alvos ja nativos:
  `0x80193A18`, `0x801252A8` e `0x80125024`;
- `0x80190FAC` possui dois JAL para `0x80193A18` e `0x80125024`, ja nativas;
- nenhuma das tres contem JALR, COP2/GTE, scratchpad estatico, DIV, MULT ou
  BREAK;
- a closure esperada e exatamente o proprio trio. Qualquer quarta funcao ou
  delta diferente de 155 palavras bloqueia o lote;
- `0x8018F10C` permanece fora do S1-254. Depois da promocao do trio, seus 35
  alvos JAL unicos estarao nativos, permitindo audita-la separadamente como um
  lote futuro de 1.880 palavras;
- `0x8016FC28` permanece rejeitada como seed direta: ela tambem chama a familia
  `0x80191C84` de Options/Memory Card e reabriria uma closure sem relacao com o
  teste Expert.

O script `PlusAlphaProject/tools/preaudit_s1_254_sources.ps1` confirmou a
baseline S1-253 de 1.045 funcoes e SHA-256
`80DF7E6811A60B300CD5371818A2504FB571EB806B5FC755BD470A4582077068`,
gerou somente em `local/preaudit/s1-254-preview-01`, validou os corpos e call
sites e executou a auditoria codegen apenas na area isolada. Resultado:

- funcoes adicionadas: `0x8017DA9C`, `0x80190EB8`, `0x80190FAC`;
- palavras adicionadas: 155;
- funcoes totais: 1.048;
- cobertura projetada: 108.614/195.584 palavras (55,5332%);
- ranges SHA-256:
  `2A1B157977603D23A886102BE01A2B7A4B12B7514F450FD893CC96E26B4C4991`;
- auditoria codegen: `CLEAN`;
- fontes principais, BIOS e build: preservados pela previa.

Depois da aprovacao da previa, as tres seeds foram ativadas em
`PlusAlphaProject/seeds/entry_funcs.txt`. Foram preparados os scripts separados:

- `PlusAlphaProject/tools/generate_s1_254_sources.ps1`;
- `PlusAlphaProject/tools/compile-run_s1_254_telemetry.sh`;
- `PlusAlphaProject/tools/telemetry_before_after_s1_254.sh`.

O coletor formal usa `pc_watch` exato para os tres alvos e `fntrace` para os
enderecos de retorno conhecidos. A janela inicia na selecao de personagem do
Expert Mode, percorre uma tarefa curta e termina ao voltar para a mesma selecao.
Ela deve ficar preferencialmente abaixo de 45 segundos para evitar saturacao do
ring `fntrace`.

A geracao principal produziu exatamente **1.048 funcoes**, cobertura de
**108.614/195.584 palavras (55,5332%)**, auditoria `CLEAN` e o SHA-256 aprovado.
A build isolada `buildClean-ucrt-s1-254-tele` foi compilada localmente pelo
usuario. Na janela valida de 37 segundos, o `pc_watch` exato registrou:

| Funcao | Hits nativos | Hits interpretados | Fallback |
|---|---:|---:|---|
| `0x8017DA9C` | 1.812 | 0 | nao |
| `0x80190EB8` | 1.753 | 0 | nao |
| `0x80190FAC` | 1.752 | 0 | nao |
| **Total** | **5.317** | **0** | **nao** |

O dispatcher acumulou mais 233.289 hits estaticos com zero miss. Aborts,
`native_handoffs` e `text_native_blocked` permaneceram em zero. O frametime foi
p50 16,682 ms, p95 16,734 ms e maximo 18,680 ms. O `fntrace` permaneceu vazio
porque essas chamadas nativas diretas nao atravessam `psx_dispatch`; o
`pc_watch`, alimentado no prologo universal das funcoes compiladas, e a evidencia
positiva apropriada. Assim, o texto `gate insuficiente` gerado pelo coletor foi
um falso negativo de observabilidade, nao uma falha da S1-254.

O usuario concluiu a regressao manual sem perceber regressao no jogo. Estado:
**S1-254 processado no checkpoint Release S1-255**. Naquele ponto, das cinco
funcoes interpretadas observadas na rota Expert Mode, tres eram nativas e ainda
restavam `0x8018F10C` e `0x8016FC28`.

## Pre-auditoria S1-255 aprovada

O proximo lote deve atacar somente `0x8018F10C`, a funcao principal da rota
Expert Mode. O orcamento foi fixado em **exatamente 1.880 palavras** antes da
previa isolada. `0x8016FC28` continua fora do lote porque sua segunda familia de
chamadas reabre a closure de Options/Memory Card iniciada por `0x80191C84`.

| Funcao | Range | Palavras | SHA-256 do corpo | Evidencia interpretada |
|---|---|---:|---|---:|
| `0x8018F10C` | `0x8018F10C..0x80190E6B` | 1.880 | `5AE8E7FD7CA4DA21B03CE4DF7813561B77FCEDFC16F920B82614ABCE8893E2C9` | 1.638 hits na rota `expert-mode-complete` |

Fluxo estatico medido antes da previa:

- 86 sites `JAL` alcancam 35 alvos formais unicos; os 35 aparecem na baseline
  S1-254 como funcoes nativas;
- os tres alvos promovidos no S1-254 (`0x8017DA9C`, `0x80190EB8` e
  `0x80190FAC`) eliminam a ultima closure direta pendente dessa funcao;
- nao ha `JALR`, COP2/GTE, referencia estatica ao scratchpad, DIV ou BREAK;
- ha quatro instrucoes `MULT`, em `0x8018FAE4`, `0x8018FB30`, `0x8018FB88` e
  `0x80190540`; elas elevam o risco e exigem regressao funcional direcionada;
- a entrada usa `JR $v0` em `0x8018F1B4` sobre uma tabela de cinco palavras em
  `0x801AE638`; os destinos `0x8018F1BC`, `0x8018FF24`, `0x801903AC`,
  `0x80190450` e `0x801909F8` sao todos internos ao proprio corpo;
- os 13 jumps absolutos `J` observados tambem permanecem dentro do corpo;
- a closure esperada da previa e exatamente `0x8018F10C`, com 1.880 palavras.
  Qualquer segunda funcao ou delta diferente bloqueia o lote.

A previa isolada `s1-255-preview-01` confirmou exatamente **1.049 funcoes**,
adicionando somente `0x8018F10C` e 1.880 palavras. A cobertura projetada e
**110.494/195.584 palavras (56,4944%)**, a auditoria codegen terminou `CLEAN` e
o ranges SHA-256 obtido foi
`30BCD2340878A0C9057CA4B8A66F582A0695AF844B1E45E9409678951D76D404`.
Fontes principais, BIOS e build foram preservados pela previa.

Depois da aprovacao, a seed `0x8018F10C` foi ativada em
`PlusAlphaProject/seeds/entry_funcs.txt`. Foram preparados os scripts separados:

- `PlusAlphaProject/tools/generate_s1_255_sources.ps1`;
- `PlusAlphaProject/tools/compile-run_s1_255_telemetry.sh`;
- `PlusAlphaProject/tools/telemetry_before_after_s1_255.sh`.

O coletor S1-255 usa `pc_watch` na entrada formal, nos cinco destinos da jump
table e nos quatro blocos que contem `MULT`. O gate nao depende de `fntrace`:
entrada nativa sem interpretacao, ao menos um estado interno observado, zero
fallback, zero miss e integridade do runtime sao obrigatorios. Estados e blocos
de multiplicacao nao alcancados ficam explicitamente registrados para orientar
rotas adicionais.

Os fontes principais foram gerados com exatamente **1.049 funcoes**, auditoria
`CLEAN` e o SHA-256 aprovado. A coleta `s1-255-telemetry-01`, com 48 segundos,
registrou 2.622 entradas nativas em `0x8018F10C`, zero entradas interpretadas e
zero fallback. Os cinco estados da jump table foram alcancados; a soma de seus
hits foi exatamente 2.622, cobrindo cada entrada da funcao. Um dos quatro blocos
`MULT` foi observado; os outros tres sao ramos condicionais, sem impacto no gate
estrutural completo. O dispatcher ganhou 270.885 hits estaticos com zero miss.
Aborts, `native_handoffs`, `text_native_blocked` e divergencias de texto
permaneceram em zero. Frametime: p50 16,683 ms, p95 16,737 ms e maximo
18,244 ms.

A regressao manual da build de telemetria passou pelo Expert Mode, Bonus Barril
com Guile, Versus Doctrine Dark x Skullomania e quatro partidas completas de
Arcade. O smoke final foi repetido no checkpoint Release limpo, cobrindo as
mesmas tres rotas e cinco partidas completas de Arcade. Nao houve regressao
percebida; o jogo permaneceu em 60 FPS e com frametime extremamente estavel.
Estado: **S1-255 processado e promovido como checkpoint Release limpo**.

Das cinco funcoes interpretadas confirmadas pela campanha Expert, quatro agora
sao nativas: `0x8017DA9C`, `0x80190EB8`, `0x80190FAC` e `0x8018F10C`. Resta
somente **`0x8016FC28`**, mantida fora das seeds ate que suas duas familias de
closure sejam separadas, medidas e aprovadas por um novo orcamento explicito.

## Funcoes formais pendentes ja delimitadas

Excluindo o S1-252 rejeitado, permanecem **483 palavras formais confirmadas**
na fila, sem contar closures ainda interpretadas nem PCs cuja boundary
continua pendente.

| Prioridade | Funcao formal | Palavras | Evidencia e risco | Estado |
|---:|---|---:|---|---|
| 1 | `0x80103384..0x801038B3` | 332 | milhares de observacoes em Bonus e Versus; grande demais para um unico micro-lote | pendente de particionamento/auditoria |
| 2 | `0x8017566C..0x801758C7` | 151 | 530 observacoes no Bonus; jump table e chamadas indiretas | pendente de auditoria de fluxo |

O S1-252 permanece apenas como candidato rejeitado, com custo real medido de
2.805 palavras. Isso confirma que nao e necessario iniciar outra descoberta
profunda agora e que nenhuma funcao da fila pode ser selecionada antes de sua
closure completa ser medida.

## PCs ainda fora dos ranges nativos

Lista bruta para preservar toda a evidencia. Itens interiores devem ser
marcados como alias quando sua funcao formal for auditada.

```text
0x80103384
0x80106BD4 0x80106CB0 0x80106CB8 0x80106DB0
0x80106E8C 0x80106E94 0x80106E9C 0x80106F74
0x8010773C
0x8016FC28 0x8016FC84
0x80172DD0 0x80172E58
0x8017566C 0x801757E4
0x80181F7C 0x80181FCC
0x80182004 0x8018200C 0x80182014 0x8018201C
0x80182028 0x80182038 0x80182040 0x80182084
0x80182090 0x80182098 0x801820C4 0x801820CC
0x801820F0 0x80182210 0x80182224
0x801829F4 0x80182A54 0x80182A60 0x80182A68
0x80182A8C 0x80182BFC 0x80182CC8 0x80182F74
0x801830B8 0x801830CC 0x8018312C 0x80183144
0x801831C0 0x80183708 0x80183710
0x8019E6D0
```

## Quarentena

| PC | Motivo | Estado |
|---|---|---|
| `0x8019E6D0` | origem historicamente nao reproduzida de forma confiavel e suspeita de regressao aleatoria | observacao somente; fora das seeds |

## Proxima decisao

1. Manter `0x8016FC28` fora das seeds enquanto sua closure alcancavel completa
   nao estiver separada por familia e medida em area isolada.
2. Pre-auditar a rota frequentemente executada da raiz sem reincorporar por
   acidente a familia Options/Memory Card iniciada por `0x80191C84`.
3. Fixar um limite explicito de palavras antes de selecionar qualquer lote
   S1-256; uma expansao acima do limite deve ser rejeitada.
4. Usar a watchlist para confirmar a rota reproduzivel de `0x8016FC28` e manter
   os quatro candidatos S1-252 sem hit apenas como observacao historica.
