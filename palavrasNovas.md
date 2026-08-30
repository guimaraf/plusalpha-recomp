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

- Checkpoint promovido: **S1-261 Release limpo**, incorporando a baseline S1-260.
- Ultimo checkpoint Release limpo: **S1-261**.
- Cobertura: **111.379 / 195.584 palavras (56,9469%)**.
- Funcoes geradas: **1.059**.
- Entradas do dispatcher: **16.667**.
- Auditor codegen: **CLEAN**.
- Configuracao validada: **Release**, `PSX_DEBUG_TOOLS=OFF`, runtime estatico.
- Ranges SHA-256:
  `0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F`.
- Executavel S1-261 Release SHA-256:
  `11E39E8400412A71BEAD05317548798C60B7EB18C3EDE72ABA8A47B159D51A8D`.

O checkpoint cumulativo S1-261 incorpora S1-251, S1-253, S1-254, S1-255 e os
lotes S1-256 a S1-260. A regressao Release percorreu Expert Mode com retorno a
selecao, Bonus Barril com Guile e Pause, Versus Doctrine Dark x Skullomania,
varias partidas de Arcade, Survival, Options e Memory Card. Nao houve regressao
percebida; turbo loading, audio, controles, 60 FPS e frametime permaneceram
estaveis.

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
| S1-256 | `0x8016FC28`, `0x801910A4`, `0x801914C0`, `0x80191C84`, `0x80192D6C`, `0x801930BC` | 622 | 111.116 | processado; checkpoint S1-261 |
| S1-257 | `0x8019FC6C..0x8019FCE3` | 30 | 111.146 | processado; checkpoint S1-261 |
| S1-258 | `0x8017566C..0x801758C7` | 151 | 111.297 | processado; checkpoint S1-261 |
| S1-259 | `0x801939A0..0x80193A17` | 30 | 111.327 | processado; checkpoint S1-261 |
| S1-260 | `0x80103BD8..0x80103CA7` | 52 | 111.379 | processado; checkpoint S1-261 |

Total promovido desde S1-239: **5.060 palavras**.

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
sao nativas: `0x8017DA9C`, `0x80190EB8`, `0x80190FAC` e `0x8018F10C`. Nesse
grupo especifico resta somente `0x8016FC28`.

A campanha `s1-253-function-watch-02` tambem comprovou a familia separada de
Options/Memory Card. Nela, `0x8016FC28` chama `0x80191C84`, que alcanca tres
folhas ainda interpretadas. Portanto, na baseline S1-255 a closure direta
residual possui **cinco funcoes e 586 palavras**, nao apenas a raiz de 39:

| Funcao | Range | Palavras | Hits interpretados conhecidos | Estado S1-255 |
|---|---|---:|---:|---|
| `0x8016FC28` | `0x8016FC28..0x8016FCC3` | 39 | 9.888 | raiz candidata S1-256 |
| `0x801910A4` | `0x801910A4..0x801912D7` | 141 | 16.068 | closure direta residual |
| `0x801914C0` | `0x801914C0..0x80191587` | 50 | 2.471 | closure direta residual |
| `0x80191C84` | `0x80191C84..0x80192127` | 297 | 2.470 | closure principal residual |
| `0x80192D6C` | `0x80192D6C..0x80192E57` | 59 | 1.728 | closure direta residual |
| **Total** |  | **586** | **32.625** | **preparacao S1-256** |

A closure direta isolada deve reproduzir exatamente 1.054 funcoes,
**111.080/195.584 palavras (56,7940%)** e o ranges SHA-256 historico
`2F3A18F08ED029E7D5D7227E60DC6AA38367187D9D9DD9DE2DD91C4713BBA7E1`.
Esse resultado e apenas a primeira etapa do gate S1-256; ele nao autoriza
sozinho a alteracao dos fontes principais.

O risco indireto esta nos dois `JALR` de `0x80191C84`. Um usa a celula dinamica
`0x80020800`; o outro seleciona seis destinos externos pela tabela em
`0x801B8538`: `0x80192128`, `0x80193174`, `0x801930BC`, `0x8019319C`,
`0x801931C4` e `0x80192F60`. Esses destinos nao pertencem a closure direta
automatica.

A primeira tentativa de descoberta foi contaminada por tres instancias do
observador compartilhando o mesmo `pc_watch` global. Ela foi descartada para a
decisao. A repeticao limpa `s1-256-function-watch-15`, executada com uma unica
instancia durante 35 segundos na rota
`options-memory-card-complete-clean`, encontrou seis funcoes e 18.384 hits,
todos interpretados:

| Funcao | Hits | Primeiro frame | Ultimo frame | Classificacao |
|---|---:|---:|---:|---|
| `0x8016FC28` | 1.661 | 2.508 | 4.582 | raiz da closure direta |
| `0x801910A4` | 11.443 | 2.508 | 4.582 | closure direta |
| `0x801914C0` | 1.660 | 2.508 | 4.581 | closure direta |
| `0x80191C84` | 1.661 | 2.508 | 4.582 | closure direta e seletor indireto |
| `0x80192D6C` | 963 | 2.508 | 4.581 | closure direta |
| `0x801930BC` | 996 | 2.721 | 4.130 | unico destino da tabela observado |
| **Total** | **18.384** |  |  |  |

Os outros cinco destinos da tabela tiveram zero hit e permanecem fora do lote.
A celula `0x80020800` ficou estavel em `0x80021CD8` no inicio e no fim; por ser
RAM dinamica, esse valor nao e uma seed formal do executavel.

`0x801930BC` foi delimitada em `0x801930BC..0x8019314B`, com **36 palavras** e
SHA-256 de corpo
`5517E77195FAC935A53239E03F694A61EB20463795186296C8516D2B6EEB34AE`.
Seus cinco JAL alcancam somente funcoes ja nativas: `0x80123E8C`,
`0x801931FC`, `0x8019326C`, `0x8019327C` e `0x801A75F4`. O unico JALR fica em
`0x80193134` e usa a celula `0x800D6400`, destinada a callback de modulo
carregado em RAM. A funcao nativa `0x801010C4` ja usa esse mesmo padrao de
chamada e continuacao. Nao ha COP2/GTE, MULT, DIV, BREAK ou scratchpad estatico
no corpo auditado.

Com a evidencia dinamica, o lote S1-256 candidato passa a ter duas seeds
explicitas (`0x8016FC28` e `0x801930BC`), **seis funcoes e 622 palavras**. A
projecao final e de 1.055 funcoes e **111.116/195.584 palavras (56,8124%)**.
O usuario executou `PlusAlphaProject/tools/preaudit_s1_256_sources.ps1`. A
pre-auditoria `s1-256-preview-02` gerou duas previas descartaveis:

1. `stage1-direct-closure`: exige exatamente cinco funcoes, 586 palavras e o
   SHA-256 historico do incidente S1-252;
2. `stage2-full-batch`: acrescenta explicitamente somente `0x801930BC` e exige
   exatamente seis funcoes e 622 palavras sobre a baseline S1-255.

As duas etapas terminaram com auditoria codegen `CLEAN`. A primeira reproduziu
exatamente 1.054 funcoes, 586 palavras e o SHA-256 historico
`2F3A18F08ED029E7D5D7227E60DC6AA38367187D9D9DD9DE2DD91C4713BBA7E1`.
A segunda acrescentou somente `0x801930BC`, totalizando 1.055 funcoes, 622
palavras e o novo ranges SHA-256
`300F1B44336410C0F0DADAF746D2973D27ABCCF4EB391A36891D827DA67057C6`.
Seeds/fontes principais, BIOS e build foram preservados durante a previa.

Depois da aprovacao, somente `0x8016FC28` e `0x801930BC` foram ativadas em
`PlusAlphaProject/seeds/entry_funcs.txt`. Foram preparados os tres scripts
independentes exigidos pela metodologia:

- `PlusAlphaProject/tools/generate_s1_256_sources.ps1`;
- `PlusAlphaProject/tools/compile-run_s1_256_telemetry.sh`;
- `PlusAlphaProject/tools/telemetry_before_after_s1_256.sh`.

O modo `-ValidateOnly` do gerador passou sobre a baseline S1-255 depois da
ativacao das seeds, sem gerar fontes. Os parsers do Windows PowerShell 5.1, do
Bash MSYS2 e dos dois blocos Python embutidos no coletor tambem passaram.

O coletor formal exige as seis entradas nativas sem hits interpretados, observa
os retornos `0x801920A4` e `0x8019313C`, registra as celulas `0x80020800` e
`0x800D6400` e mantem como guards os outros cinco destinos da tabela
`0x801B8538`. Se qualquer guard executar, o gate fica insuficiente em vez de
aceitar silenciosamente nova closure indireta. A coleta formal
`s1-256-telemetry-01` confirmou as seis funcoes exclusivamente nativas, 13.815
hits obrigatorios, retornos indiretos presentes, cinco guards zerados,
`miss_total=0`, zero abort e frametime P95 de 16,795 ms. Estado: **S1-256
aprovado provisoriamente por telemetria e regressao manual**.

## Candidato S1-257 - dispatcher permanente da tela de titulo

O observador automatico corrigido isolou a janela
`tela-titulo-confirmacao-v2` durante 3,251 segundos, sem transicao para outra
tela. Os snapshots foram completos: 135/135 PCs estaticos, 94/94 PCs dinamicos
e zero entradas descartadas. `0x8019FC6C` foi interpretada 199 vezes, taxa de
61,21 entradas/s, confirmando execucao praticamente uma vez por frame.

Boundary formal: `0x8019FC6C..0x8019FCE3`, 120 bytes, **30 palavras**, SHA-256
`02427D01908F1F36539549CBE3C02C69E2BA4F24F4F240A186909D3A26D926CE`.
O corpo nao possui JAL direto, jump absoluto, COP2/GTE, MULT, DIV, syscall ou
BREAK. Ha dois branches internos, um retorno em `0x8019FCDC` e um JALR em
`0x8019FCB4`, cuja continuacao e `0x8019FCBC`.

O JALR percorre oito slots em `0x801BEEC4..0x801BEEE0`. Uma leitura durante a
tela de titulo encontrou os oito slots zerados e contador `0x00000369`; outra
leitura no primeiro frame controlavel de Versus Ryu x Ken encontrou novamente
os oito slots zerados e contador `0x00000713`. O inicializador vizinho
`0x8019FC14` zera a tabela e registra o dispatcher; o setter vizinho
`0x8019FCE4` permanece fora do lote. A previa isolada
`s1-257-preview-01` confirmou exatamente uma funcao e 30 palavras, com
1.056 funcoes projetadas, cobertura de 111.146/195.584 palavras (56,8278%),
ranges SHA-256
`A10B9A83A30D0CB0280F36898971A2D99F804ABC094461994B137F55B635E6CD` e
auditoria codegen `CLEAN`. A geracao principal reproduziu esse manifesto.

A coleta `s1-257-telemetry-01` atravessou a tela de titulo, uma transicao e o
retorno ao titulo. Embora nao seja uma janela exclusiva para localizacao, ela
e valida como gate tecnico ampliado: `0x8019FC6C` teve 1.352 hits nativos e
zero interpretados; a continuacao `0x8019FCBC` teve exatamente 10.816 hits
nativos, oito por chamada da raiz; o setter `0x8019FCE4` permaneceu zerado.
Os oito callbacks ficaram zerados em BEFORE e AFTER, o contador cresceu de
`0x00000C92` para `0x000011E2`, `miss_total` permaneceu zero e nao houve abort,
handoff, bloqueio ou divergencia de texto. O usuario nao percebeu regressao.
Decisao: **S1-257 processado e promovido na baseline de trabalho**.

## Lote em andamento e funcoes formais pendentes

Com as 30 palavras do S1-259 ja processadas, permanecem **332 palavras
formais confirmadas pendentes** na fila, sem contar closures ainda
interpretadas nem PCs cuja boundary continua pendente.

| Prioridade | Funcao formal | Palavras | Evidencia e risco | Estado |
|---:|---|---:|---|---|
| 1 | `0x80103384..0x801038B3` | 332 | dispatcher global de apresentacao/interface; dois destinos JAL distintos ainda fora dos ranges (`0x80103BD8`, `0x8016EA0C`) | adiar ate medir a closure direta |

### S1-259 - `0x801939A0`

A candidata formal ocupa `0x801939A0..0x80193A17`, 120 bytes/**30
palavras**, entre os ranges nativos `0x80193920..0x8019399F` e
`0x80193A18..0x80194273`. O corpo possui SHA-256
`37B07726C20B9FBADA32ADF7CC1ED776D342F0F742F1FEA3734EA48EB6A26179`.
Nao ha JAL, JALR, COP2/GTE, MULT, DIV, syscall ou BREAK. Seis branches e tres
jumps absolutos permanecem dentro do corpo; o retorno normal ocorre por
`JR $ra` em `0x80193A10`. O caller direto encontrado no executavel e o JAL em
`0x80134EF8`.

A telemetria S1-258 registrou 378 observacoes em pagina modificada. A campanha
posterior demonstrou que esse total corresponde exatamente a 63 frames com
seis chamadas por frame na tela `Options -> Ranking`. A leitura das 30 palavras
vivas coincidiu com o executavel e reproduziu exatamente o SHA-256 acima; a
marcacao modificada pertence a codigo vizinho, nao ao corpo candidato.

O script `PlusAlphaProject/tools/preaudit_s1_259_sources.ps1` prepara somente
uma previa isolada. O orcamento rigido e **uma funcao/30 palavras**, projetando
1.058 funcoes e 111.327/195.584 palavras (**56,9203%**). Qualquer closure ou
range adicional rejeita a previa. A seed e os fontes principais permanecem na
baseline S1-258 ate a geracao principal pelo usuario.

A previa `s1-259-preview-01` foi executada e aprovada: adicionou somente
`0x801939A0`, mediu 30 palavras/1.058 funcoes, produziu ranges SHA-256
`C0E7A0A37DB76E98E731D4E9CA5A0882DE02802E8CDADA5805E07C83DE15999F` e
terminou a auditoria codegen com status CLEAN. A seed foi registrada uma vez
em `entry_funcs.txt`. Foram preparados gerador principal, compilacao UCRT64 e
telemetria formal S1-259 dirigida ao Mode Select, a raiz nativa e o retorno ao
caller `0x80134F00`.

As coletas formais `s1-259-telemetry-01` e `s1-259-telemetry-02` terminaram
sem misses, aborts, bloqueios ou divergencias e com regressao manual limpa. A
segunda janela percorreu Mode Select, Options, algumas subtelas e retornou ao
Mode Select. Mesmo assim, ambas registraram zero hit na raiz `0x801939A0` e no
retorno `0x80134F00`; portanto, o gate positivo continua **insuficiente**. O
frametime da segunda coleta permaneceu limpo: P50 16,683 ms, P95 16,755 ms e
maximo 17,228 ms.

Para evitar novas tentativas dirigidas a uma rota presumida, foi criado
`PlusAlphaProject/tools/observe_s1_259_watch_events.sh`, alimentado somente por
`seeds/s1_259_event_watchlist.txt`. Ele observa exclusivamente a entrada nativa
`0x801939A0`, congela no primeiro hit, solicita uma tag da tela/transicao e
permite rearmar depois da mudanca de contexto. Essa campanha apenas localiza a
rota positiva; nao substitui uma nova telemetria formal e nao promove o lote.

Tres sessoes do observador localizaram a funcao somente em `Options -> Ranking`
entre as telas e modos percorridos. Cinco eventos reproduziveis somaram **1.262
hits nativos e zero interpretados**: 258, 186, 228, 216 e 374 hits. O padrao
permaneceu em aproximadamente seis chamadas por frame, com corpo vivo e caller
exatos, `miss_total=0`, zero abort, zero handoff inesperado e nenhuma
divergencia de texto.

A coleta formal `s1-259-telemetry-03`, executada dentro de Ranking, durou 13
segundos e confirmou **4.752 hits nativos e zero interpretados** na raiz. O
corpo permaneceu exato e estavel, a candidata nao apareceu nas observacoes do
interpretador, o delta de misses foi zero e nao houve abort, bloqueio, handoff
ou divergencia. O frametime ficou em P50 16,682 ms, P95 16,745 ms e maximo
17,929 ms. O texto de rota em `metadata.txt` permaneceu herdado do coletor
original, mas a rota efetivamente executada e atestada pelo usuario foi
`Options -> Ranking`.

O retorno fixo `0x80134F00` permaneceu zerado e fez o resumo automatico marcar
o gate como insuficiente. A evidencia demonstrou que esse retorno nao pertence
ao caminho exercitado por Ranking; ele nao representa fallback da candidata.
Com a raiz amplamente exercitada, exclusivamente nativa, os guards limpos e a
regressao manual aprovada, a decisao tecnica e: **S1-259 processado e promovido
provisoriamente na baseline de trabalho**.

### Descoberta do proximo gate sobre a S1-259

A candidata global `0x80103384..0x801038B3` possui 1.328 bytes/**332
palavras** e SHA-256
`7BC970EBE34267125EFD878140DDD4A9637404E57EFCF7E32211A5073C0DCE32`.
Seus sete destinos JAL diretos sao `0x80103A74`, `0x80103B1C`,
`0x80103BD8`, `0x80103CA8`, `0x80125024`, `0x8016EA0C` e `0x80193A18`.
Cinco ja pertencem a baseline S1-259; os dois ramos ainda interpretados
expandem a closure direta para outras quatro funcoes.

| Etapa sugerida | Funcao | Palavras | SHA-256 do corpo | Dependencias novas |
|---|---|---:|---|---|
| ramo curto | `0x80103BD8..0x80103CA7` | 52 | `533D35036FC79CA6AE38DCC80BB9A148F200E4FC42477662428072A212450918` | nenhuma |
| ramo maior | `0x8016EA0C..0x8016EA5F` | 21 | `5BC9322758913EAD6D97B1C276357E53C103C37B6BFE94594DD04BFA0FC59B9C` | `0x8016EA60`, `0x8016EAE8` |
| ramo maior | `0x8016EA60..0x8016EAE7` | 34 | `3A083B12B88A50FD0040D62650DA4B52555B591489F34EE999EBDE3A628B5387` | nenhuma |
| ramo maior | `0x8016EAE8..0x8016F1AF` | 434 | `C93DEF8DD510FA6A9D66EFAB7469C53927D2F45231407F90E2AD58E03C5BE10A` | `0x8016F560`, `0x8016FB64` |
| ramo maior | `0x8016F560..0x8016F667` | 66 | `8ABDB0EBCC4758FE178847F5966AFDAD3451B0A4A084467D9F3E9781E4911BA3` | nenhuma |
| ramo maior | `0x8016FB64..0x8016FC27` | 49 | `F73BCA9D56A85EB08B8A05A81B25F1B798969FA4B3357B6E5E9F417C93FDF650` | nenhuma |
| raiz final | `0x80103384..0x801038B3` | 332 | `7BC970EBE34267125EFD878140DDD4A9637404E57EFCF7E32211A5073C0DCE32` | os dois ramos acima |

A closure integral mede **sete funcoes/988 palavras**: 52 palavras no ramo
curto, 604 no ramo maior e 332 na raiz. Nenhuma funcao possui JALR. A funcao
`0x8016EAE8` contem dois `MULTU`, em `0x8016EC34` e `0x8016ED34`, e por isso o
ramo maior exige telemetria propria. A estrategia preliminar mais segura e
promover primeiro o ramo curto, depois o ramo maior e somente por ultimo a
raiz, evitando um lote unico de 988 palavras.

Para localizar as rotas foi criado
`PlusAlphaProject/tools/observe_s1_259_next_gate_events.sh`, com a lista
`seeds/s1_260_gate_watchlist.txt`. A raiz global e apenas contexto e nao
interrompe a procura. O observador congela somente quando uma das seis
dependencias executa, solicita a tag da tela/transicao e salva os corpos vivos
de todas as sete funcoes. Nenhuma seed foi selecionada e nenhuma previa, fonte
ou build foi gerada nesta etapa.

#### Decisao do micro-lote S1-260 - Pause

A sessao valida `s1-260-gate-discovery-02` registrou o ramo curto
`0x80103BD8` em cinco eventos independentes de Pause: Bonus Game (27 hits),
confirmacao no Bonus Game (12), Arcade com Ryu (27), `whath-game` (15) e
Survival (11). Foram **92 hits, todos interpretados**, e o corpo vivo permaneceu
identico nos cinco eventos. A execucao ocupou janelas com cadencia aproximada
de uma chamada a cada dois frames, associando o ramo ao estado de Pause nos
contextos observados.

A raiz `0x80103384` somou 6.730 hits interpretados, mas ja estava ativa antes
do Pause e continua classificada apenas como contexto global. As cinco funcoes
do ramo maior (`0x8016EA0C`, `0x8016EA60`, `0x8016EAE8`, `0x8016F560` e
`0x8016FB64`) ficaram zeradas em todos os eventos. Os contadores criticos
registraram zero aborts, native handoffs, bloqueios de texto, paginas
divergentes e mismatches exatos.

Fica aprovado para **pre-auditoria isolada**, sem promocao ainda, o micro-lote
S1-260 contendo somente `0x80103BD8..0x80103CA7`: uma funcao/**52 palavras**,
SHA-256
`533D35036FC79CA6AE38DCC80BB9A148F200E4FC42477662428072A212450918`.
Se a closure permanecer exata, a projecao sera 1.059 funcoes e
111.379/195.584 palavras (**56,9469%**). A raiz de 332 palavras e o ramo maior
de 604 palavras permanecem explicitamente fora das seeds.

O gate foi codificado em
`PlusAlphaProject/tools/preaudit_s1_260_sources.ps1`. Ele protege a baseline
S1-259, exige exatamente uma nova funcao/52 palavras, valida boundary,
vizinhas, dois callers diretos, dois callees ja nativos e o fluxo MIPS, gera
somente em `local/preaudit/s1-260-preview-NN` e confirma ao final que seeds,
fontes principais, `.gitignore` e BIOS permaneceram intactos.

A previa isolada `s1-260-preview-01` foi aprovada com **1.059 funcoes**,
111.379/195.584 palavras (**56,9469%**) e ranges SHA-256
`0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F`.
A auditoria codegen terminou `CLEAN`, com zero chamadas diretas nao resolvidas,
misses de `call_by_address`, misses de tail-call, labels sem destino ou achados
reais. A seed `0x80103BD8` fica selecionada para a geracao principal S1-260;
naquele ponto, a aprovacao ainda dependia da telemetria e da regressao manual.

A coleta formal `s1-260-telemetry-01` durou 136 segundos. Antes da janela, a
raiz e os dois retornos estavam zerados. Durante tres ciclos de Pause no Bonus
com Guile, `0x80103BD8` registrou **625 hits nativos e zero interpretados**. Os
625 retornos ocorreram por `0x8010344C`; `0x801035BC` permaneceu zerado e fica
como flag de observacao, sem bloquear a promocao. O PC de retorno interpretado
pertence a raiz global ainda interpretada e nao caracteriza fallback da
candidata.

O corpo vivo BEFORE/AFTER coincidiu com o SHA-256 aprovado, os dois callers
JAL/delay permaneceram exatos, a candidata desapareceu das observacoes do
interpretador e o delta de `miss_total` foi zero. Aborts, native handoffs,
`text_native_blocked`, paginas divergentes e mismatches exatos permaneceram
zerados/estaveis. O frametime foi P50 16,683 ms, P95 16,771 ms e maximo
17,276 ms; o perfil registrou 79,47% estatico, 9,81% interpretador e 6,07% GPU.

A regressao manual posterior cobriu Arcade, Survival, Versus Doctrine Dark x
Skullomania e Bonus, incluindo FPS, frametime, Pause, audio, controles e
retorno ao gameplay, sem regressao percebida. Decisao: **S1-260 processada e
promovida**. O checkpoint Release limpo S1-261 foi preparado para o smoke final.

O checkpoint `buildClean-ucrt-s1-261` foi compilado localmente em Release, com
`PSX_DEBUG_TOOLS=OFF` e runtime estatico. O executavel possui SHA-256
`11E39E8400412A71BEAD05317548798C60B7EB18C3EDE72ABA8A47B159D51A8D`.
O smoke final percorreu Expert Mode com retorno a selecao, Bonus com Guile e
tres ciclos de Pause, Versus Doctrine Dark x Skullomania, varias partidas de
Arcade, Survival, Options e Memory Card. Turbo loading, audio, controles,
60 FPS e frametime foram verificados sem regressao percebida. Decisao:
**S1-261 promovido como checkpoint Release limpo**.

### Preparacao S1-258 - `0x8017566C`

A raiz formal ocupa `0x8017566C..0x801758C7`, 604 bytes/**151 palavras**,
com SHA-256 de corpo
`5DA650C3D1A23F0C9E8359253D73D3741BE92D12BB348ECBCEB94A2FEE3014E2`.
Ela possui 24 sites JAL para 19 destinos distintos; todos ja pertencem aos
ranges nativos S1-257. Nao ha branch externo, COP2/GTE, MULT, DIV, syscall ou
BREAK. Os cinco jumps absolutos permanecem dentro do corpo.

O risco residual e inteiramente indireto. O JR em `0x801756A8` usa um indice
limitado a 19 entradas e consulta a jump table em `0x801AC9C0`. Seus 19 slots
apontam para nove destinos distintos, todos internos ao corpo. Os JALR em
`0x80175840` e `0x80175880` leem, respectivamente, as celulas dinamicas
`0x80020800` e `0x800D6404`, retornando por `0x80175848` e `0x80175888`.
Os callbacks continuam sendo o gate dinamico da telemetria formal.

O coletor `PlusAlphaProject/tools/observe_s1_257_indirect_context.sh` foi
preparado para a baseline executada S1-257 e registra internamente o candidato
futuro S1-258. A area `0x801BC9C0` coletada pelo formato anterior contem dados
de diagnostico, nao a jump table. O endereco correto da jump table e
`0x801AC9C0`. O fluxo atual arma raiz, entrada interior e
retornos antes da rota, aguarda um Enter dedicado para iniciar imediatamente,
e somente depois coleta corpo vivo, estado indireto e as duas celulas de
callback em BEFORE e AFTER. A seed principal foi ativada depois da aprovacao
da previa isolada. Limite
preliminar: **151
palavras e uma funcao**; qualquer closure direta adicional ou destino indireto
externo bloqueia a S1-258 antes da pre-auditoria.

Para evitar novas buscas por rota presumida, foi criado o observador orientado
a eventos `PlusAlphaProject/tools/observe_s1_257_watch_events.sh`, alimentado
por `seeds/s1_257_event_watchlist.txt`. A lista inicial contem `0x8017566C` e
`0x80103384`, ambas ainda interpretadas na baseline S1-257. O script consulta
somente `pc_watch_dump` a cada 500 ms, congela no primeiro incremento, pede ao
usuario uma tag da tela/transicao e grava o pacote apenas depois do evento. O
rearme e manual e deve ocorrer somente apos mudar de contexto, evitando eventos
duplicados de uma funcao permanente. As tags localizam a funcao no fluxo do
jogo; elas nao equivalem a captura automatica do caller MIPS.

A sessao `s1-257-watch-events-01` localizou `0x8017566C` exclusivamente no
Mode Select entre os contextos percorridos: 61 hits interpretados nos frames
6542..6602, sincronizados com 61 hits de `0x80103384`. A candidata ficou zerada
na apresentacao Arika, abertura, titulo, Options, Game Option, Sound Option,
Memory Card Option e Memory Card Load. Isso demonstra que as observacoes
anteriores durante a preparacao do Bonus provinham do Mode Select, nao do
gameplay do Bonus.

Na mesma sessao, `0x80103384` apareceu aproximadamente uma vez por frame em
todas essas telas: 41 hits na apresentacao Arika, 64 na abertura, 61 no titulo,
61 no Mode Select, 63 em Options, 61 em Game Option, 61 em Sound Option, 62 em
Memory Card Option e 61 em Memory Card Load. O ultimo evento preservou seu dump
bruto apesar de a tag receber sequencias ANSI pendentes e exceder o limite de
caminho do Windows. O observador agora limpa o buffer antes da tag, rejeita
caracteres de controle e limita o nome normalizado a 48 caracteres.

O script `PlusAlphaProject/tools/preaudit_s1_258_sources.ps1` implementa o gate
isolado: baseline S1-257 exata, corpo e boundary fixos, 24 sites JAL/19 destinos
ja nativos, jump table interna exata, dois JALR conhecidos e orcamento rigido de
uma funcao/**151 palavras**. A closure deve resultar em 1.057 funcoes e
111.297/195.584 palavras (**56,9050%**); qualquer funcao adicional bloqueia a
previa. O modo `-ValidateOnly` passou sem gerar fontes.

A previa `s1-258-preview-01` foi executada pelo usuario e aprovada: adicionou
somente `0x8017566C`, mediu 151 palavras/1.057 funcoes, produziu ranges SHA-256
`B085DB02B291233F95A55B6F6F25FAACE48147BC5FF273B6518D811F98A73E1E` e
terminou a auditoria codegen com status CLEAN. A seed foi registrada uma vez
em `entry_funcs.txt` e promovida para os fontes principais pelo gerador
S1-258.

Os fontes principais reproduziram o manifesto da previa e foram usados na
build de telemetria S1-258. A coleta `s1-258-telemetry-01` durou 51 segundos
no Mode Select. A raiz `0x8017566C` teve 1.297 hits nativos e zero
interpretados; a entrada interior `0x801757E4` teve 1.283 hits e zero
interpretados. Corpo vivo e jump table permaneceram exatos e estaveis;
`miss_total`, aborts, native handoffs, `text_native_blocked` e divergencias
permaneceram zerados. Os retornos JALR `0x80175848` e `0x80175888` nao foram
exercitados e permanecem como flags de observacao, sem fallback detectado.

O frametime medido foi P50 16,683 ms, P95 16,780 ms e maximo 17,473 ms. Na
mesma execucao, o usuario validou Bonus Barril com Guile, Versus Doctrine Dark
x Skullomania no cenario de Skullomania, Trial e varias partidas de Arcade.
Nao houve regressao percebida e a linha de frametime permaneceu extremamente
limpa. Decisao: **S1-258 aprovada provisoriamente e adotada como baseline de
trabalho**.

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
0x80172DD0 0x80172E58
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

1. Preservar S1-261 como baseline limpa antes de iniciar outra descoberta de
   funcoes interpretadas.
2. Na proxima rodada, usar um observador sobre a build de telemetria apropriada
   para localizar primeiro a rota reproduzivel, antes de selecionar qualquer
   nova seed.
3. Manter os dois retornos JALR S1-258 como flags de observacao, sem bloquear o
   proximo lote enquanto continuarem sem fallback ou regressao.
4. Manter `0x8019E6D0` em quarentena ate nova evidencia reproduzivel e auditoria
   formal de boundary e closure.
