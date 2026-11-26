# Plano para concluir a recompilação (100%)

Análise estática de 2026-11-24 (somente leitura; sem build e sem execução do jogo).
Relatório interativo e artefatos (fora do repositório):
`F:\GitRevised\alphaplus\relatorios\plano-100-recompilacao.html` e
`F:\GitRevised\alphaplus\relatorios\plano-100-evidencias\` (`track1/` = EXE, `track2/` = overlays).

## 1. Diagnóstico

O "100%" anterior era 100% dos **caminhos jogados**, não 100% do código do jogo.

### EXE principal (`SLUS_005.48`, 195.584 palavras)

| Classe | Palavras | % | Ação |
|---|---:|---:|---|
| Compilado (`generated-online/SLUS_005.48_full.ranges`) | 154.639 | 79,07 | — |
| Código alcançável só por tabela de ponteiros / endereço tomado (187 funções) | 9.978 | 5,10 | Fase 2 |
| Código válido sem referência estática no EXE (114 clusters) | 9.645 | 4,93 | Fase 3 |
| Dados (`0x801AB3E8..0x801C0000`, strings, tabelas, zeros, padding) | 21.279 | 10,88 | Fora do denominador |

- Teto real do EXE: **174.305 palavras de código (89,12%)**.
- Evidência conferida: `0x80103E24..0x80103E3C` faz `lui/addiu 0x801AF960; addu; lw; jalr`. A tabela tem 27 entradas, indexadas pelo byte de cena `0x801D39B8`. Os alvos `0x8016FC28` (seleção), `0x801040E8` (luta) e `0x8017566C` (modo) já estavam cobertos. Faltavam 11: `0x8010A5FC`, `0x80169B78`, `0x8010ABC8`, `0x8010ACD8`, `0x8010ADE8`, `0x8017FEC0`, `0x8010AFDC`, `0x80107D80`, `0x80107EF0`, `0x8010809C` e `0x801085E0`.
- **Reconciliado na Fase 0:** as 154.846 palavras eram a soma bruta das linhas `R` do manifesto S1-309. Três aliases repetem o mesmo range (`0x8013B070`, `0x8013B10C` e `0x8019CB4C`), o que conta 202 palavras duas vezes. O valor único do S1-309 é 154.644. A geração online atual (154.639) perdeu mais 5 palavras, `0x8019CB8C..0x8019CB9F`, e a entrada `0x8019CB8C`, que o S1-309 despachava. Essa entrada é um alias sem predecessor direto e é candidata ao primeiro micro-lote da Fase 2.
- **Raízes P1** (ver `track1/functions_uncovered.csv` e `roots.csv`):
  - funções: `0x8018D298`, `0x8010A5FC`, `0x8010AFDC`, `0x80102FAC`, `0x80131A3C`, `0x80162848`, `0x80102D80`, `0x80107EF0`, `0x8010809C`, `0x80107D80`, `0x8017FEC0`, `0x8016321C`, `0x8010ABC8`, `0x8010ACD8`, `0x8016313C`, `0x80127320`, `0x80162B18`, `0x8019F9E4`, mais cerca de 36 outras;
  - tabelas: `0x801AF960`, `0x801AF874`, `0x801B037C`, `0x801B1B20`, `0x801B3374`, `0x801B7EF0`, `0x801B85A0`.
- **Maiores clusters sem referência** (`track1/D_clusters.csv`): `0x80180018` (983), `0x80169984` (935; promovido no F2-L19), `0x8019AD94` (505), `0x80129E1C` (476), `0x8018D974` (422; promovido no F2-L20).
- **Stubs PsyQ descobertos:** `0x8019376C`, `0x8019377C`, `0x8019FB74`, `0x801AB1D0`.

### Overlays do disco (59 imagens de código)

| Arquivo | Base | Estado |
|---|---|---|
| `OVL/PLxx_1.OVL` (26, slot P1) | `0x80043000` | parcial; sem cobertura: PL01, 02, 04, 05, 07, 0E, 17 |
| `OVL2/PLxx_2.OVL` (26, slot P2) | `0x8008CA00` | parcial; sem cobertura: PL00, 03, 06, 08, 09, 0B, 0F, 13, 15, 16, 19 |
| `OVL3/BONUS.OVL` | `0x80018800` | 94% dos bytes; 4 variantes divergem do disco |
| `OVL3/OPTS.OVL` | `0x80020800` | 57% dos bytes |
| `OVL3/MOV.OVL` | `0x800D6400` | 38 de 41 alvos JAL |
| `OVL3/QUES.PAC` | `0x800D6400` | 52 de 52 alvos JAL |
| `OVL3/MC_M.OVL`, `MC_I.OVL` (memory card) | `0x800D6400` | **0%**; interpretado na telemetria (`0xD6424`, `0xD8EE0`, `0xDA010`…) |
| `OVL3/END.OVL` (endings) | `0x800D6400` | **0%** |

- 98,8% das 3.884 variantes retidas batem byte a byte com o disco: os overlays têm posição fixa e vêm pré-relocados.
- 45 variantes não batem com o disco: 41 na zona MC/END e 4 no BONUS.
- **Entrada fora do `switch` do despachante é interpretada.** Contam as entradas, não só os ranges.
- Modos sem evidência de execução:
  - memory card;
  - 16 de 23 endings e os créditos;
  - Arcade completo;
  - lutas de Survival e de Team Battle;
  - Watch;
  - cada lutador nos dois slots.
- PCs quentes de luta fora dos ranges: `0x8004C9B0`, `0x8008DD80`.

## 2. Definição de 100%

100% = todas as palavras de **código real** do EXE e das 59 imagens de overlay compiladas nativamente, com todas as entradas no despachante. As únicas exceções são as de uma lista versionada e justificada:

- dados;
- BIOS/kernel `0x8000xxxx` em HLE, por decisão arquitetural;
- quarentenas `0x801AB1F4..0x801AB238` (SIO) e `0x801AB2C0..0x801AB2F0` (SMC), com limite superior exclusivo; o intervalo `0x801AB2F0..0x801AB35C` já é compilado;
- código provado morto.

## 3. Fases

### Fase A — Infraestrutura de execução autônoma (pré-requisito das fases de validação)

Autorizado pelo usuário em 2026-11-24. O agente pode compilar, executar o jogo, testar e corrigir sozinho, **sempre no segundo monitor** e **sem usar o teclado nem o mouse do usuário**.

- **Monitor.** O segundo monitor é o índice 1 em ordem de enumeração: retângulo `x=1920..3840, y=0..1080`. O monitor 0 (`0..1920`) é do usuário. Use `EnumDisplayMonitors`, como em `PlusAlphaProject/tools/position_netplay_windows.py`, e mova a janela do jogo para o monitor 1 com `SetWindowPos(..., SWP_NOACTIVATE)` logo que ela surgir. Se o monitor 1 não existir, não execute: avise o usuário.
- **Foco.** Nunca use `SendInput`, computer-use, automação de mouse/teclado ou foco de janela. Toda entrada de controle vai pela porta TCP de debug (`debug_port = 4531`), com `set_input`, `press`, `clear_input` e `input_route_*`. Para ver o jogo, use `screenshot_file`, `present_shot` e `get_frame` e leia o PNG; não use captura de tela do desktop. Se a criação da janela roubar o foco, registre o fato e corrija no launcher, por exemplo com uma opção de posição inicial e de não ativar a janela.
- **Isolamento.**
  - Build próprio em `PlusAlphaProject/build-auto-<timestamp>/`. Nunca toque nos builds de release, em `buildTele-s1-309-bezeus`, nos saves, no `gametime.save` nem nas sessões do usuário.
  - `memcard_dir` e savestates do teste ficam numa pasta de evidências da sessão, fora do repositório (por exemplo `F:\GitRevised\alphaplus\relatorios\auto-<data>\`).
  - Disco e BIOS são somente leitura e nunca são copiados para fora do projeto.
- **Recursos.** Um build por vez, com prioridade `BelowNormal` e número de jobs limitado. Silencie o áudio do jogo se o runtime oferecer essa opção; se não oferecer, avise.
- **Ciclo.**
  1. Cenário.
  2. Savestate.
  3. Telemetria (`dispatch_stats`, `overlay_interp_hot`, `static_text_misses`, `frame_perf`).
  4. Classificação do miss.
  5. Correção (seed ou AOT).
  6. Regeneração e build.
  7. Reexecução.
  8. `verificador`.
  9. Sugestão de commit.
- **Parada.** Pare e reporte quando houver evidência contraditória, regressão sem causa clara, risco a saves ou sessões, falta do monitor 1, ou necessidade de juízo humano. Juízo humano inclui percepção de lag, áudio e qualidade visual subjetiva; a validação final de "sensação" (RivaTuner, input) continua com o usuário.
- **Aceite da fase.** Um script único que faz build isolado, executa no monitor 1, injeta uma rota de input (boot até uma luta), salva screenshots e telemetria e encerra com `quit`, sem tocar no foco do usuário.

**Resultado (2026-11-24):**

- Comando: `python PlusAlphaProject/tools/auto_session.py all --route boot_to_fight`. O subcomando `build` compila; `run --build-dir build-auto-X` só executa.
- Rota versionada: `PlusAlphaProject/tools/auto_routes/boot_to_fight.json`. Percorre boot, título, Arcade e Ryu × Allen até o KO, com savestates nos slots 1 a 3.
- Build isolado em `PlusAlphaProject/build-auto-<ts>/`, com `-Jobs 4`, prioridade BelowNormal e overlays preparados dentro da pasta do build. Leva cerca de 17 min. O run leva cerca de 110 s.
- Execução:
  - o jogo abre com `--hidden-window`, áudio `SDL_AUDIO_DRIVER=dummy` e porta 4631;
  - memcard e savestates vão para `relatorios/auto-<data>/<run>/`;
  - encerra com `quit`, e o kill, quando necessário, é só pelo PID iniciado pelo script.
- **Screenshot e display apagado:** o screenshot tolera `display disabled` (display apagado pelo jogo em transições, ex.: saída do Game Over) com até 8 esperas de 15 frames, registradas em `display_retries` no `run.json`; com `display_retries` > 0 o screenshot é de um frame posterior.
- **Foco:** a janela fica oculta e apenas posicionada no monitor 1. Num teste com a janela visível (`SWP_SHOWWINDOW|SWP_NOACTIVATE`), o jogo ficou em primeiro plano por cerca de 17 s durante a luta. Por isso mostrar a janela virou opt-in (`--show-window`), que devolve exit 3 se o jogo pegar o foco. A causa ainda não foi identificada; o suspeito é um raise do próprio runtime. O `run.json` registra o foreground a cada passo.
- **Limites do runtime:** `static_text_misses` e `overlay_interp_hot` não existem no submódulo `psxrecomp`; o substituto é `dirty_ram_stats.per_pc`. `frame_perf` não tem amostras no renderer software. O `quit` responde `ok:false` ("emu busy or frozen"), mas o processo sai com código 0.
- **Primeira medição (Ryu × Allen, frame ~6600):**
  - `dispatch_stats.miss_total` = 0 no EXE;
  - `dirty_ram_stats`: 14,1 M instruções de overlay interpretadas e 92.080 handoffs nativos;
  - os PCs mais quentes são de `PL_1` (`0x80049E50`, `0x80048834`, `0x8004A278`) e de `PL_2` (`0x80090414`), mais a quarentena SMC `0x801AB2DC`.
  Esses números são a linha de base da Fase 1.

### Fase 0 — Métrica oficial

- Um script determinístico mede o EXE e cada overlay (palavras de código e entradas), a partir dos ranges e do disco, aplicando a lista de exclusões.
- Reconciliar a diferença 154.846 × 154.639 e corrigir `docs/progress.md`, `docs/newWords.md` e `docs/newChat.md`.
- **Aceite:** um número reproduzível por comando e uma guarda que falha se a cobertura cair.

**Resultado (2026-11-24):**

- Script: `python PlusAlphaProject/tools/coverage_metric.py`. Com `--json PATH` gera o relatório determinístico. `--check` é a guarda: sai com 1 se a cobertura cair em relação a `PlusAlphaProject/coverage/baseline.json`. `--update-baseline` atualiza a linha de base, sempre de forma explícita.
- As exclusões versionadas ficam em `PlusAlphaProject/coverage/exclusions.json`. São três categorias:
  - dados: 21.254 palavras;
  - padding: 25;
  - quarentenas: 29.
- EXE: **154.639 de 174.276 palavras de código (88,7322%)**, 1.359 funções e 21.908 entradas no despachante. Nenhuma palavra compilada cai nas exclusões.
- Overlays: 164.988 de 442.006 palavras (37,33%), com 3.840 de 3.885 variantes casando com o disco e 45 sem casamento. O denominador ainda é provisório: conta o arquivo inteiro. A Fase 1 deve trocá-lo pelo extent de código.

### Fase 1 — Overlays AOT a partir do disco (maior ganho)

- Criar `PlusAlphaProject/aot/overlays.json` para `psxrecomp/tools/aot_overlay_pipeline.py`, com o método `fixed_address_files`:
  - 26 `PL_1` em `0x80043000`;
  - 26 `PL_2` em `0x8008CA00`;
  - BONUS, OPTS, MOV, QUES (extent de código), MC_M, MC_I e END.
- Entradas: tabelas de ponteiros no início de cada overlay, mais as raízes conhecidas (`game.toml [[overlays]]` e o despachante atual).
- Gerar com o subcomando `static`, que tem guarda de CRC, e substituir `prepare_retained_overlays.py`.
- **Aceite:**
  - 52 de 52 combinações lutador × slot cobertas, além de MC e END;
  - despachante dentro do orçamento;
  - sem regressão.

**Resultado (2026-11-24):**

- Perfil versionado em `PlusAlphaProject/aot/overlays.json`, gerado por `aot/gen_profile.py`. São 59 imagens:
  - PL_1 e PL_2 (52) e BONUS, OPTS, MC_M, MC_I e END pelo método `fixed_address_files`;
  - MOV e QUES.PAC por `fixed_address_extents`, com sha256.
  O perfil não declara `static_output`: a saída vai para `<build>/static-overlays`.
- `build_online.ps1 -OverlaySource aot|retained`. O padrão é `aot`. `-Release` ou `-RetainedOverlayDir` continuam nas retidas, então o release não mudou. O CMake valida `AOT_STATIC_AUDIT.json`: 59 recipes, `all_pairs_valid` e guardas de CRC. A geração leva menos de 1 min; o build limpo completo, cerca de 10,5 min.
- Correção geral no `psxrecomp`: `recompiler_project_root()`, em `tools/aot_overlay_pipeline.py`. Projetos sem `bios/SCPH1001.toml` passam a usar o framework.
- Link: `--export-all-symbols` só vale para as retidas, porque o AOT estoura o limite de ordinais de export. Isso é seguro com `overlay_cache = false`; se o cache de DLL for ligado num build AOT, será preciso revisar.
- **Cobertura estática:**
  - overlays: 164.988 → **328.016 palavras (40,5% → 80,4%)**, com o denominador de 407.741 (MOV e QUES por extent);
  - 52 de 52 imagens PL cobertas (antes eram 40), e MC_M, MC_I e END deixaram de estar em 0;
  - 18.184 endereços no despachante (antes 3.495, todos preservados) e 50.738 variantes, todas casando com o disco;
  - nenhum arquivo regrediu.
- **Runtime** (rota `boot_to_fight`, Ryu × Allen), comparando com as retidas:
  - instruções de overlay interpretadas: 14,05 M → 1,18 M (cerca de 12× menos);
  - handoffs: 91.134 → 35.243;
  - EXE com 0 misses e guest a 60 fps.
  - O que sobra interpretado é a quarentena SMC (`0x801AB2DC`), código da BIOS/kernel (`0xC88`, `0xCF0`) e resíduos de baixa frequência.
- **Pendências:**
  - as 45 variantes retidas divergentes continuam interpretadas até a Fase 3;
  - 56 possíveis alvos de jump table sem entrada ficam como risco aceito, a conferir na Fase 4;
  - os scripts de diagnóstico (`build_online_diagnostics.ps1`, `build_input_observation.ps1`) agora usam AOT por padrão;
  - a validação de sensação de jogo do AOT continua com o usuário, antes de promovê-lo ao release.

### Fase 2 — EXE: raízes chamadas por tabela (de ~79% para ~84,2%; meta original, estado atual 99,7716% com F2-L23 — ver Andamento)

Micro-lotes conforme a governança de `docs/newWords.md`: pré-auditoria do fechamento, orçamento, aliases e jump tables. Começar pela tabela `0x801AF960` e pelas maiores raízes.

**Andamento (2026-11-24; F2-L5 em diante, 2026-11-25):**

- **Etapa 2.0 (infraestrutura):**
  - geração isolada por build: `build_online.ps1 -GeneratedDir/-SeedsFile` e `PSX_GENERATED_DIR`;
  - `tools/seed_preview.py`, que mede o fechamento exato em ~1 s, sem compilar C, e aplica o orçamento de ≤1.200 palavras e ≤10 funções por lote;
  - builds incrementais com `auto_session.py --reuse-build`;
  - passos `read_ram`, `fntrace` e `dispatch_misses`;
  - rota `survey_post_fight`;
  - `codegen_audit_game.py` corrigido para shards e para o despachante de 5 campos.
- **Fechamento real é maior que o estimado:** as 58 raízes P1/A2 acrescentam cerca de 13,7 mil palavras, o que, na estimativa da epoca, levaria o EXE a ~96,6%; a medicao real esta em 99,7716% (F2-L23; 99,5145% no F2-L22; 99,0846% no F2-L21; 98,4924% no F2-L20; 98,0160% no F2-L19; 97,36% no F2-L18; 96,83% no F2-L17; 96,79% no F2-L16 e 96,18% no F2-L15, este com denominador 174.276; a partir do L16 o denominador e 174.246). Parte do que a Fase 3 trataria como "sem referência" é alcançada por essas raízes.
- **Correção no recompilador** (`function_analysis.cpp`):
  - um `jal` em palavra emitida mas não visitada passa a virar raiz;
  - um alias absorvido passa a ser exportado com evidência de qualquer função final.
  Com as seeds atuais, a base fica byte a byte igual. No AOT, `MC_M` ganha a raiz `0x800DCA14`. O hash de codegen mudou de `1b6950cb` para `d3d005b3`.
- **F2-L1** (`0x80169B78`, `0x8010ADE8`, com `0x8016A3A4` pelo fechamento):
  - +1.375 palavras, chegando a **156.014 de 174.276 (89,52%)**, e 22.121 entradas;
  - na rota pós-luta, os PCs do EXE interpretados caíram de 149 para 38, e as instruções interpretadas, 49,8%;
  - `miss_total` = 0.
- **F2-L2** (`0x8013009C`; `0x80130138` e `0x80130294` entram pelo fechamento):
  - por quê: é o despachante por tipo cujos 30 PCs interiores eram interpretados após a luta (3.783 hits em `0x8013009C`);
  - +288 palavras, chegando a **156.302 (89,69%)**, 1.370 funções e 22.161 entradas;
  - PCs do EXE interpretados na rota pós-luta: 38 → 8. `miss_total` = 0.
- **F2-R1 (correção do resolvedor):** `sltiu; beq; sll (delay); lui [; addiu]; addu; lw; nop; jr` passa a ser reconhecido, com todas as provas de limite e base. Hash de codegen `d3d005b3` → `e13692f6`; BIOS idêntico. EXE: mesmas 156.302 palavras, 1.370 funções, 22.161 entradas, 37 `jr` resolvidos (`0x80169BF4`, `0x801548A0`, `0x80198074` entre eles). AOT: 280 switches, entradas 61.189 → 61.226. Rotas: PCs interpretados do EXE 8 → 6 (`0x801548BC` e `0x80198350` saem), `miss_total` = 0.
- **F2-L3** (oito raízes da tabela `0x801AF960`, índices 2, 4, 5, 12, 22–24 e 26, mais o alias `0x8019CB8C`):
  - +1.131 palavras, chegando a **157.433 de 174.276 (90,34%)**, 1.379 funções e 22.360 entradas; audit `CLEAN`;
  - `boot_to_fight` e `survey_post_fight` só com a quarentena interpretada; `miss_total` = 0;
  - rotas novas `survey_modes` e `survey_options`: modos do Mode Select (Team Battle só até a seleção; em Practice, só Training Mode), submenus de Option (Memory Card só até a tela de slot, sem load nem save) e derrota, continue e game over;
  - execução observada só em `0x801085E0`; os outros oito alvos ainda não foram alcançados;
  - o `jr` de `0x8010B030` tem uma forma não reconhecida: `0x8010B1BC` e `0x8010B230` ficam sem entrada (41 → 42 `jr` indiretos);
  - próximos candidatos com execução observada: `0x8017FEC0` (cena 8, resultado do Survival) e `0x80129E0C` (modo Watch, com ponteiro em `0x801B0404`); `0x8017FEC0` foi promovido em F2-L4 e `0x80129E0C` em F2-L5.
- **F2-L4** (`0x8017FEC0`, índice 8 da tabela, resultado do Survival; `0x80180010` e `0x8018097C` pelo fechamento):
  - +1.072 palavras, chegando a **158.505 de 174.276 (90,95%)**, 1.382 funções e 22.495 entradas; audit `CLEAN`;
  - PCs do EXE interpretados: `survey_modes` 151 → 52 e `survey_options` 105 → 6, nenhum novo; `miss_total` = 0;
  - próximo candidato com execução observada: `0x80129E0C` (modo Watch, 46 PCs interpretados; promovido em F2-L5).
- **F2-L5** (`0x80129E0C`, modo Watch, com ponteiro em `0x801B0404`; fechamento entre `0x80126DC4` e `0x8012A588`):
  - +749 palavras, chegando a **159.254 de 174.276 (91,38%)**, 1.388 funções e 22.590 entradas; audit `CLEAN`; métrica igual à prevista;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332) e `survey_modes` (446), todas completas com `miss_total` = 0; `survey_options` não foi refeita neste lote;
  - PCs do EXE interpretados: `survey_modes` 52 → 6 (saem os 46 do modo Watch; restam só os 6 da quarentena), `boot_to_fight` e `survey_post_fight` 6 → 6; nenhum PC novo;
  - o modo Watch foi alcançado (snapshots `misses_m_watch_*`), mas `0x80129E0C` não tem hits de fntrace: o fntrace da rota só arma os alvos da tabela `0x801AF960`. A execução compilada é inferida pela saída dos PCs interpretados, não medida por contagem;
  - próximos candidatos: as raízes auditadas restantes são estáticas (tabelas de handlers `0x801B0380..0x801B0404`, `0x801B3450..0x801B3474` e de estados `0x801AF888/0x801AF88C`), sem execução observada; desfecho (F2-L6): seis dessas raízes foram promovidas, também sem execução observada; fila em `relatorios/fase2/fila.json`;
  - evidências em `relatorios/fase2/L5/`.
- **F2-L6** (seis raízes estáticas de tabelas de handlers, sem execução observada: `0x80102D80`, `0x80102FAC`, `0x80126878`, `0x80129148`, `0x80162848`, `0x8016321C`):
  - +895 palavras, chegando a **160.149 de 174.276 (91,89%)**, 1.398 funções e 22.734 entradas; audit `CLEAN`; métrica igual à prevista;
  - rotas `boot_to_fight` (48 passos) e `survey_post_fight` (332), com `miss_total` = 0 e só os 6 PCs da quarentena interpretados, como em F2-L5; nenhum PC novo; `survey_modes` (446 passos) também completa, com `miss_total` = 0 em 99 snapshots, os mesmos 6 PCs da quarentena, nenhum PC novo e nenhuma espera de display;
  - ponteiros: `0x801AF888` e `0x801AF88C` (tabela de estados), `0x801B0380` e `0x801B03EC` (tabela de handlers do modo, a mesma de `0x80129E0C`), `0x801B3458` e `0x801B3474`; `0x80131A3C` foi excluído na pré-auditoria (origem fraca);
  - incidente: a `survey_post_fight` falhou duas vezes com `display disabled` logo após a leitura do byte de cena 7 no Game Over (`survey_try1`, passo 248; `survey_try2`, passo 280), sem causa nas seeds. Correção aplicada no `auto_session.py` (commit `6673184`; validada por teste unitário; não recorreu na 3ª execução): o screenshot espera 15 frames e tenta até 8 vezes (`display_retries`); na 3ª execução a rota completou com `display_retries` = 0 em 58 screenshots; `survey_options` não refeita desde F2-L4;
  - próximo, registrado em F2-L6 (promovido em F2-L7, abaixo): `0x8012F484` (ponteiro `0x801B1BD8`) e `0x8013497C` (`0x801B1C00`), +1.195 palavras previstas; evidências em `relatorios/fase2/L6/`.
- **F2-L7** (`0x8012F484` e `0x8013497C`, ponteiros `0x801B1BD8` e `0x801B1C00`, na tabela contígua `0x801B1BC0..0x801B1C1C`; sem execução observada):
  - fechamento: `0x8012F484` +774 palavras, 3 funções, 140 entradas; `0x8013497C` +421 palavras, 3 funções, 75 entradas (raízes estáticas, borda de prólogo, palavra anterior `jr ra`+nop);
  - +1.195 palavras, chegando a **161.344 de 174.276 (92,58%)**, 1.404 funções e 22.949 entradas; `codegen_audit_game.py` CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` com `exit_code` 0 em 28,4 s;
  - pré-auditoria com `seed_preview.py` dentro do orçamento (1.195 ≤ 1.200 palavras; 6 ≤ 10 funções), 0 perdas, 0 em quarentena, 0 `jalr`, 0 `jr` não-`$ra`, 0 SMC;
  - rotas (checkpoint de 3 lotes, L5 a L7; evidências em `relatorios/fase2/L7/r2/`): `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 checkpoints) e `survey_modes` (446 passos, 99 checkpoints) completas, `miss_total` = 0; só os 6 PCs da quarentena interpretados, nenhum PC novo;
  - `0x8012F484` e `0x8013497C` não estão na lista de alvos do fntrace de nenhuma rota: não há execução observada, e a instrumentação atual não permite afirmar que não são chamados;
  - rota `survey_options`: completou (417 passos, 90 checkpoints), miss_total 0, so a quarentena interpretada; conjunto de PCs igual ao de F2-L6 nas rotas comparaveis;
  - histórico: a primeira tentativa do L7 (sessão anterior) parou nas rotas por máquina ocupada (timeouts de `wait_frames`/`starvation_watchdog`, ambiente); o patch foi salvo e reaplicado, e a reexecução r2 passou;
  - próximo, registrado em F2-L7 (promovido em F2-L8, abaixo): `0x80141A30` + `0x80135E50` + `0x80129384`.
- **F2-L8** (`0x80141A30`, `0x80135E50` e `0x80129384`; ponteiros `0x801B1B64`, `0x801B1C0C` e `0x801B03F4`; sem execução observada):
  - fechamento: `0x80141A30` +644 palavras, 3 funções, 65 entradas; `0x80135E50` +510 palavras, 3 funções, 44 entradas; `0x80129384` +20 palavras, 1 função, 7 entradas (raízes estáticas, borda de prólogo, palavra anterior `jr ra`+delay);
  - +1.174 palavras, chegando a **162.518 de 174.276 (93,25%)**, 1.411 funções e 23.065 entradas; `codegen_audit_game.py` CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` com `exit_code` 0 em 159,9 s;
  - pré-auditoria com `seed_preview.py` dentro do orçamento (1.174 ≤ 1.200 palavras; 7 ≤ 10 funções), 0 perdas, 0 em quarentena, 0 `jalr`, 0 `jr` não-`$ra`, 0 SMC;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses) e `survey_modes` (446 passos, 99 snapshots de misses) completas, `miss_total` = 0; só os 6 PCs da quarentena interpretados, o mesmo conjunto do F2-L7; nenhum PC novo; `survey_options` não foi rodada (não é lote de checkpoint);
  - as três raízes não estão nos alvos do fntrace das rotas de L8: não há execução observada, e isso não prova que não são chamadas;
  - próximo candidato: F2-L9 (promovido);
  - evidências em `relatorios/fase2/L8/`.
- **F2-L9** (`0x80132ED4` e `0x8012E858`; sem execução observada):
  - fechamento: `0x80132ED4` +633 palavras, 3 funções, 53 entradas; `0x8012E858` +460 palavras, 3 funções, 66 entradas (raízes estáticas, borda de prólogo);
  - +1.093 palavras, chegando a **163.611 de 174.276 (93,88%)**, 1.417 funções e 23.184 entradas; `codegen_audit_game.py` CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` com `exit_code` 0 em 134,5 s;
  - pré-auditoria com `seed_preview.py` dentro do orçamento (1.093 ≤ 1.200 palavras; 6 ≤ 10 funções), 0 perdas, 0 em quarentena, 0 `jalr`, 0 `jr` não-`$ra`, 0 SMC;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses) e `survey_modes` (446 passos, 99 snapshots de misses) completas, `miss_total` = 0; só os 6 PCs da quarentena interpretados, o mesmo conjunto do F2-L8; nenhum PC novo; `survey_options` não foi rodada (o checkpoint de quatro rotas foi feito no F2-L10);
  - as duas raízes não estão nos alvos do fntrace das rotas de L9: não há execução observada, e isso não prova que não são chamadas;
  - próximo candidato: F2-L10 (promovido); checkpoint de quatro rotas feito no F2-L10;
  - evidências em `relatorios/fase2/L9/`.
- **F2-L10** (`0x801371C8` e `0x80135010`; ponteiros `0x801B1C18` e `0x801B1C04`; sem execução observada; checkpoint de quatro rotas):
  - fechamento: `0x801371C8` +753 palavras, 7 funções, 118 entradas; `0x80135010` +382 palavras, 3 funções, 47 entradas (raízes estáticas, borda de prólogo, palavra anterior `jr ra`+delay; tabela `0x801B1BC0..0x801B1C1C`);
  - +1.135 palavras, chegando a **164.746 de 174.276 (94,53%)**, 1.427 funções e 23.349 entradas; `codegen_audit_game.py` CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` com `exit_code` 0 em 139,3 s;
  - pré-auditoria com `seed_preview.py` dentro do orçamento (1.135 ≤ 1.200 palavras; 10 ≤ 10 funções), 0 perdas, 0 em quarentena, 0 `jalr`, 0 `jr` não-`$ra`, 0 SMC;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses), `survey_modes` (446 passos, 99 snapshots de misses) e `survey_options` (417 passos, 90 snapshots de misses) completas, `miss_total` = 0; só os 6 PCs da quarentena interpretados, o mesmo conjunto do F2-L9 (em `survey_options`, também o do F2-L7); nenhum PC novo;
  - as duas raízes não estão nos alvos do fntrace das rotas de L10: não há execução observada, e isso não prova que não são chamadas;
  - candidatos adiados, sem promoção: `0x80135608` e `0x80147624` têm `jr` não-`$ra` = 1 no fechamento (jump table); requerem investigador/resolvedor antes de promover;
  - próximo candidato: F2-L11 (promovido);
  - evidências em `relatorios/fase2/L10/`.
- **F2-L11** (`0x801453A8`, `0x8018D298` e `0x80127320`; ponteiros `0x801B1B7C`, `0x801B7EF0` e `0x801B039C`; sem execução observada):
  - fechamento: `0x801453A8` +610 palavras, 3 funções, 72 entradas; `0x8018D298` +439 palavras, 1 função, 72 entradas; `0x80127320` +55 palavras, 1 função, 4 entradas (raízes estáticas, borda de prólogo);
  - +1.104 palavras, chegando a **165.850 de 174.276 (95,17%)**, 1.432 funções e 23.497 entradas; `codegen_audit_game.py` CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` com `exit_code` 0 em 170,9 s;
  - pré-auditoria com `seed_preview.py` dentro do orçamento (1.104 ≤ 1.200 palavras; 5 ≤ 10 funções), 0 perdas, 0 em quarentena, 0 `jalr`, 0 `jr` não-`$ra`, 0 SMC;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses) e `survey_modes` (446 passos, 99 snapshots de misses) completas, `miss_total` = 0; só os 6 PCs da quarentena interpretados, o mesmo conjunto do F2-L10; nenhum PC novo; `survey_options` não foi rodada (checkpoint de quatro rotas feito no F2-L13);
  - as três raízes não estão nos alvos do fntrace das rotas de L11: não há execução observada, e isso não prova que não são chamadas;
  - próximo candidato: F2-L12 (promovido);
  - evidências em `relatorios/fase2/L11/`.
- **F2-L12** (`0x8012EF88`, `0x801236EC`, `0x80198BE4` e `0x8019B168`; ponteiro `0x801B1BD4` para `0x8012EF88`; sem execução observada):
  - fechamento: `0x8012EF88` +365 palavras, 4 funções, 72 entradas (o callee `0x8012F090` entra no fechamento e não é seed, por redundância); `0x801236EC` +137 palavras, 1 função, 28 entradas; `0x80198BE4` +102 palavras, 1 função, 17 entradas; `0x8019B168` +117 palavras, 3 funções, 32 entradas (raízes estáticas, borda de prólogo; os três alvos de `jal` têm origem mais fraca, aceitos só por evidência estática);
  - +721 palavras, chegando a **166.571 de 174.276 (95,58%)**, 1.441 funções e 23.646 entradas; `codegen_audit_game.py` CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` com `exit_code` 0 em 360,9 s;
  - pré-auditoria com `seed_preview.py` dentro do orçamento (721 ≤ 1.200 palavras; 9 ≤ 10 funções), 0 perdas, 0 em quarentena, 0 `jalr`, 0 `jr` não-`$ra`, 0 SMC;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses) e `survey_modes` (446 passos, 99 snapshots de misses) completas, `miss_total` = 0 nas telemetrias finais; só os 6 PCs da quarentena interpretados, o mesmo conjunto do F2-L11; nenhum PC novo; `survey_options` não foi rodada (checkpoint de quatro rotas feito no F2-L13);
  - as quatro raízes não estão nos alvos do fntrace das rotas de L12: não há execução observada, e isso não prova que não são chamadas;
  - próximo candidato: F2-L13 (promovido);
  - evidências em `relatorios/fase2/L12/`.
- **F2-L13** (`0x80128524`, `0x80129BE0`, `0x801356A4`, `0x80162B18` e `0x801627AC`; ponteiros `0x801B03C4`, `0x801B0400`, `0x801B3468` e `0x801B3450`; sem execução observada; checkpoint de quatro rotas):
  - fechamento: `0x80128524` +170 palavras, 4 funções, 28 entradas; `0x80129BE0` +139 palavras, 3 funções, 13 entradas; `0x80162B18` +50 palavras, 1 função, 14 entradas; `0x801627AC` +24 palavras, 1 função, 6 entradas (raízes estáticas, borda de prólogo); `0x801356A4` +105 palavras, 1 função, 14 entradas (alvo de `jal` 0x0C04D5A9 em `0x8013565C`, dentro da função `0x80135608`, que segue bloqueada por jump table; `jr ra` em `0x8013569C` antes do alvo; origem mais fraca);
  - +488 palavras, chegando a **167.059 de 174.276 (95,86%)**, 1.451 funções e 23.721 entradas; `codegen_audit_game.py` CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` com `exit_code` 0 em 146,2 s;
  - pré-auditoria com `seed_preview.py` dentro do orçamento (488 ≤ 1.200 palavras; 10 ≤ 10 funções), 0 perdas, 0 em quarentena, 0 `jalr`, 0 `jr` não-`$ra`, 0 SMC;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses), `survey_modes` (446 passos, 99 snapshots de misses) e `survey_options` (417 passos, 90 snapshots de misses) completas, `miss_total` = 0 nas telemetrias finais; só os 6 PCs da quarentena interpretados, o mesmo conjunto do F2-L12 (em `survey_options`, também o do F2-L10); nenhum PC novo;
  - as cinco raízes não estão nos alvos do fntrace das rotas de L13: não há execução observada, e isso não prova que não são chamadas;
  - próximo candidato: F2-L14 (promovido);
  - evidências em `relatorios/fase2/L13/`.
- **F2-L14** (`0x801287CC`, `0x80131A3C`, `0x8019735C`, `0x80197370`, `0x8019743C`, `0x8019FA90`, `0x8019FCE4` e `0x801A74F8`; ponteiros em `0x801B03C8`, `0x801ABAA8`, `0x801B85C8`, `0x801B85B4`, `0x801B85A4` e `0x801BEEA8`, e `lui/addiu` em código coberto para `0x8019FCE4` e `0x801A74F8`; sem execução observada):
  - fechamento: `0x801287CC` +68 palavras, 3 funções, 12 entradas; `0x80131A3C` +212 palavras, 1 função, 16 entradas (par de callbacks com `0x801317E4` após a string "HIT"; origem estática); `0x8019735C` +5, `0x80197370` +20, `0x8019743C` +9 (cada uma 1 função; 1, 4 e 2 entradas); `0x8019FA90` +34, 1 função, 6 entradas; `0x8019FCE4` +11, 1 função, 3 entradas; `0x801A74F8` +10, 1 função, 2 entradas (bordas em prólogo ou `jr ra`+delay);
  - +369 palavras, chegando a **167.428 de 174.276 (96,07%)**, 1.461 funções e 23.767 entradas; `codegen_audit_game.py` CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` com `exit_code` 0 em 133,8 s;
  - pré-auditoria com `seed_preview.py` contra a base F2-L13 (167.059 palavras): +369 palavras, +10 funções, +46 entradas, 0 perdas, 0 em quarentena, 0 `jalr`, 0 `jr` não-`$ra`, 0 SMC;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses) e `survey_modes` (446 passos, 99 snapshots de misses) completas, `miss_total` = 0 nas telemetrias finais; só os 6 PCs da quarentena interpretados, o mesmo conjunto do F2-L13; nenhum PC novo; `survey_options` não foi rodada (checkpoint de quatro rotas feito no F2-L15);
  - as oito raízes não estão nos alvos do fntrace das rotas de L14: não há execução observada, e isso não prova que não são chamadas;
  - próximo candidato: F2-L15 (promovido);
  - evidências em `relatorios/fase2/L14/` e `relatorios/fase2/scan_L15/`.
- **F2-L15** (`0x8012DB4C`, `0x80118010`, `0x80118018`, `0x801627A4`, `0x8016280C`, `0x80162AA8`, `0x8016313C` e `0x80196B18`; ponteiros `0x801B1BC4`, `0x801AFCC4`, `0x801AFCC8`, `0x801B3404`, `0x801B340C`, `0x801B341C`, `0x801B3428` e `0x801B85D8`; sem execução observada; checkpoint de quatro rotas; último lote de raízes auditáveis da varredura `scan_L15`):
  - fechamento: `0x8012DB4C` +85 palavras, 3 funções, 24 entradas (tabela `0x801B1BC0..`); `0x80118010` +2 e `0x80118018` +2 (1 função e 1 entrada cada; borda `jr ra`+delay e prólogo); `0x801627A4` +2, 1 função, 1 entrada; `0x8016280C` +15, 1 função, 3 entradas; `0x80162AA8` +28, 1 função, 7 entradas; `0x8016313C` +56, 1 função, 8 entradas (tabela `0x801B33F0..`); `0x80196B18` +6, 1 função, 1 entrada (borda `jr ra`+delay; tabela `0x801B85A4..`); todas com origem de tier T1 (ponteiro em tabela de dados com vizinhos cobertos);
  - +196 palavras, chegando a **167.624 de 174.276 (96,18%)**, 1.471 funções e 23.813 entradas; `codegen_audit_game.py` CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` com `exit_code` 0 em 126,0 s;
  - pré-auditoria com `seed_preview.py` contra a base F2-L14 (167.428 palavras): +196 palavras, +10 funções, +46 entradas, 0 perdas, 0 em quarentena, 0 `jalr`, 0 `jr` não-`$ra`, 0 SMC; orçamento OK;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses), `survey_modes` (446 passos, 99 snapshots de misses) e `survey_options` (417 passos, 90 snapshots de misses) completas, `miss_total` = 0 nas telemetrias finais; só os 6 PCs da quarentena interpretados, o mesmo conjunto do F2-L14 (em `survey_options`, também o do F2-L13); nenhum PC novo;
  - as oito raízes não estão nos alvos do fntrace das rotas de L15: não há execução observada, e isso não prova que não são chamadas;
  - fronteira da Fase 2 descrita em Pendências;
  - evidências em `relatorios/fase2/L15/` e `relatorios/fase2/scan_L15/`.
- **F2-L16** (`0x80135608` e `0x80147624`; ponteiros `0x801B1C08` e `0x801B1B8C`; jump tables `0x801ABBEC` e `0x801ABC6C`, resolvidas pelo resolvedor da F2-R1; sem execução observada; checkpoint de quatro rotas):
  - +1.030 palavras, chegando a **168.654 de 174.246 (96,79%)**, 1.476 funções e 23.938 entradas; métrica igual à prevista; `codegen_audit_game.py` STATUS CLEAN sobre o C gerado do build do lote (`audit_build.txt`: 1.476 funções e 23.938 entradas; o `audit.txt` com 1.471/23.813 leu `generated-online` porque o `out_dir` do `game.toml` é resolvido a partir da raiz do projeto); build incremental `build-auto-p2infra` ok em 203,8 s;
  - correção de exclusões de padding (`PlusAlphaProject/coverage/exclusions.json`): `0x801AB370` (delay slot de `jr ra`) sai do padding; +31 palavras de padding de alinhamento; denominador do EXE 174.276 → 174.246. Os percentuais de F2-L1 a F2-L15 usam 174.276;
  - rotas `boot_to_fight` (48 passos), `survey_post_fight` (332), `survey_modes` (446) e `survey_options` (417) completas, `miss_total` 0; só os seis PCs da quarentena interpretados (em `boot_to_fight`, o agregado lista cinco e a telemetria final, seis); nenhum PC novo;
  - alvos novos sem execução observada: não estão nas listas de fntrace de `auto_routes`;
  - contador da quarentena: os seis PCs ficam fixos enquanto o interpretador cresce de 1.000.427 para 2.238.724 insns em `survey_modes`; execução só no boot, então não servem como evidência de execução por rota;
  - evidências em `relatorios/fase2/L16/`.
- **F2-L17** (`0x8019F9E4` e `0x801A15A8`; ponteiro `0x801BEEA0` para `0x8019F9E4`; `lui/addiu` em `0x801A14E8`, código coberto, para `0x801A15A8`; sem execução observada):
  - fechamento: `0x8019F9E4` +46 palavras, 2 funções, 6 entradas; `0x801A15A8` +20, 1 função, 4 entradas (bordas `jr ra`+nop; `0x8019F9E4` também em prólogo). Indiretos do fechamento: `jr t2` em `0x8019FB78` (thunk BIOS B0:18) e `jalr v0` em `0x801A15E0`, sem execução observada;
  - +66 palavras, chegando a **168.720 de 174.246 (96,83%)**, 1.479 funções e 23.948 entradas; métrica igual à prevista; `auto_session.py audit` STATUS CLEAN sobre `build-auto-p2infra\generated` (1.479 funções, 23.948 entradas); build incremental `build-auto-p2infra` ok em 151,6 s;
  - rotas `boot_to_fight` (48/48) e `survey_post_fight` (332/332), `miss_total` 0, só os seis PCs da quarentena interpretados, nenhum PC novo; `survey_modes` e `survey_options` não foram rodadas (lote não-checkpoint); `display_retries` 1 em `survey_post_fight`;
  - o agregado de `boot_to_fight` deste lote lista os seis PCs (com `0x801AB2E8`), diferente do L16 (ver Pendências);
  - alvos novos sem execução observada: não estão no fntrace de `survey_post_fight` (a única rota deste lote com fntrace);
  - ferramenta: `python PlusAlphaProject/tools/auto_session.py audit --build-dir <build> [--out arquivo]`, que gera `<build>/audit_build.toml` com `out_dir` absoluto e falha se o `full_c` não estiver em `<build>/generated` ou se o STATUS não for CLEAN (a skill, etapa 5, passou a usá-lo); o problema de `generated-online` que motivou isso está descrito no bloco F2-L16 de `docs/newWords.md`;
  - evidências em `relatorios/fase2/L17/`.
- **F2-L18** (P01 da política 2a, 21 raízes sem referência estática; sem execução observada):
  - 21 raízes de `relatorios/fase2/L18/seeds.txt`, de `0x8010169C` a `0x80124394`, incluindo `0x8010F290`; +928 palavras, +21 funções, +112 entradas; 0 perdas, 0 em quarentena, 0 `jalr`, 0 SMC e 1 `jr` não-`$ra` no fechamento (`0x8010F2E8`, jump table `0x801AB72C` com 17 entradas). A pré-auditoria é reprovada pelo orçamento padrão de 10 funções (`preview_default.txt`) e aprovada com `--allow-over-budget`, dentro do orçamento excepcional de 25 funções (`preview.txt`);
  - métrica observada igual à prevista (`relatorios/fase2/L18/metric.json`): **169.648 de 174.246 (97,3612%)**, 1.500 funções e 24.060 entradas; auditoria de codegen CLEAN (`relatorios/fase2/L18/audit.txt`); build incremental `build-auto-p2infra` (`reused_build` true) em 152,5 s;
  - rotas `boot_to_fight` (48/48) e `survey_post_fight` (332/332), `miss_total` 0, só os seis PCs da quarentena interpretados e nenhum PC novo (`agregado_rotas.json`); `survey_modes` e `survey_options` não foram rodadas;
  - execução observada: nenhuma; as 21 raízes não aparecem em `relatorios/fase2/L18/survey_post_fight/fntrace_alvos.json`, a única rota com fntrace deste lote. Isso não prova que não são chamadas.
- **F2-L19** (16 raízes do lote P02 da política 2a, lista em `relatorios/fase2/L19/seeds.txt`; checkpoint de quatro rotas; sem execução observada):
  - +1.141 palavras, chegando a **170.789 de 174.246 (98,0160%)**, 1.518 funções e 24.231 entradas; auditoria de codegen CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` ok em 163,8 s;
  - rotas `boot_to_fight` (48/48), `survey_post_fight` (332/332), `survey_modes` (446/446) e `survey_options` (417/417), `miss_total` 0; só os seis PCs da quarentena interpretados, nenhum PC novo;
  - execução observada das raízes: nenhuma. Nenhuma das 16 sementes está entre os 12 endereços de fntrace armados nas rotas; isso não prova que não são chamadas;
  - revisão cumulativa do checkpoint (revisor, L16 a L19, somente leitura): sem achados bloqueantes;
  - evidências em `relatorios/fase2/L19/`.
- **F2-L20** (24 raízes do lote P03 da política 2a, lista em `relatorios/fase2/L20/seeds.txt`; não-checkpoint; sem execução observada):
  - +830 palavras, chegando a **171.619 de 174.246 (98,4924%)**, 1.543 funções e 24.378 entradas; auditoria de codegen CLEAN; métrica igual à prevista; build incremental `build-auto-p2infra` ok em 151,6 s (`exit_code` 0);
  - rotas `boot_to_fight` (48/48) e `survey_post_fight` (332/332), `miss_total` 0; só os seis PCs da quarentena interpretados, nenhum PC novo. `survey_modes` e `survey_options` não foram rodadas; o `quit` de `boot_to_fight` retornou erro ("emu busy or frozen"), causa não investigada;
  - destaques: `0x8018D974` (tela OPTION MODE, dev) com jump tables `0x801ADD48` e `0x801ADD68` (7 entradas cada); `0x80193474` (PadInit) arrasta o thunk BIOS B0:15; `0x8019366C` tem único chamador em `0x801935D4`, dentro da órfã `0x801935BC` (PadStop), fora deste lote;
  - execução observada das raízes: nenhuma. As 24 sementes não estão entre os 11 endereços armados no fntrace de `survey_post_fight`; isso não prova que não são chamadas;
  - revisao de codegen dos indiretos (revisor): sem achados (jump tables, 7 jalr e thunk B0:15 conferidos contra o EXE);
- **F2-L21** (25 raízes do lote P04 da política 2a, sem chamador estático; não-checkpoint; sem execução observada; lista em `relatorios/fase2/L21/seeds.txt`):
  - +1.032 palavras, chegando a **172.651 de 174.246 (99,0846%)**, 1.568 funções e 24.490 entradas; métrica igual à prevista; auditoria de codegen CLEAN; build incremental `build-auto-p2infra` ok em 130,0 s;
  - rotas `boot_to_fight` (48/48) e `survey_post_fight` (332/332), `miss_total` 0; só os seis PCs da quarentena interpretados e nenhum PC novo (em `boot_to_fight`, o agregado está vazio; ver Pendências); `survey_modes` e `survey_options` não foram rodadas; o `quit` das duas rotas retornou erro ("emu busy or frozen"), causa não investigada;
  - execução observada das raízes: nenhuma (`relatorios/fase2/L21/survey_post_fight/fntrace_alvos.json`); restam 1.595 palavras sem cobertura;
  - revisão de codegen dos jalr (revisor): sem achados (11 jalr em CPS com $ra e delay slot corretos, guardas de debug e mult/mflo de 0x8019AB24 conferidos);
  - evidências em `relatorios/fase2/L21/`.
- **F2-L22** (25 raízes do lote P05 da política 2a, sem chamador estático; checkpoint de quatro rotas; sem execução observada; lista em `relatorios/fase2/L22/seeds.txt`):
  - +749 palavras, chegando a **173.400 de 174.246 (99,5145%)**, 1.593 funções e 24.589 entradas; métrica igual à prevista; auditoria de codegen CLEAN; build incremental `build-auto-p2infra` ok em 147,7 s; restam 846 palavras sem cobertura;
  - rotas `boot_to_fight` (48/48), `survey_post_fight` (332/332), `survey_modes` (446/446) e `survey_options` (417/417), `miss_total` 0 nas quatro; só os seis PCs da quarentena interpretados e nenhum PC novo; em `boot_to_fight` o agregado lista os seis PCs (`relatorios/fase2/L22/agregado_rotas.json`); o `quit` das quatro retornou erro ("emu busy or frozen"), causa não investigada;
  - execução observada das raízes: nenhuma; nenhuma das 25 sementes aparece entre os alvos do fntrace nem entre os PCs interpretados. Isso não prova que não são chamadas;
  - destaques: classe D2 com palpites de libgs/libgte e um dump de matriz via GPU_printf (rótulos incertos); 0 `jalr` no fechamento;
  - revisão cumulativa do checkpoint (revisor): sem achados bloqueantes; os cabeçalhos de L20 e L21 em `PlusAlphaProject/seeds/entry_funcs.txt` ganharam a ressalva de rótulos de biblioteca não confirmados (só comentário);
  - próximo: P06, aplicado no F2-L23 (abaixo);
  - evidências em `relatorios/fase2/L22/`.
- **F2-L23** (24 raízes do lote P06 da política 2a, sem chamador estático externo; não-checkpoint; sem execução observada; lista em `relatorios/fase2/L23/seeds.txt`):
  - +448 palavras, chegando a **173.848 de 174.246 (99,7716%)**, 1.617 funções e 24.669 entradas; métrica igual à prevista; auditoria de codegen CLEAN; build incremental `build-auto-p2infra` ok em 149,0 s; restam 398 palavras sem cobertura;
  - rotas `boot_to_fight` (48/48) e `survey_post_fight` (332/332), `miss_total` 0; só os seis PCs da quarentena interpretados e nenhum PC novo; `survey_modes` e `survey_options` não foram rodadas; o `quit` das duas rotas retornou erro ("emu busy or frozen"), causa não investigada;
  - `0x801A58B0` tem uma única referência (`jal` em `0x801A3108`), dentro da seed `0x801A303C` do próprio lote; por isso fica sem referência estática externa;
  - execução observada das raízes: nenhuma; nenhuma das 24 sementes aparece entre os alvos do fntrace de `survey_post_fight` (mesmos alvos e contagens do L22) nem entre os PCs interpretados. Isso não prova que não são chamadas;
  - próximo: P07 (lista "25f", índice 6; 5 endereços: `0x801A7B10`, `0x801A903C`, `0x801A92A8`, `0x801AA1A0` e `0x801AA4F8`), ainda não aplicado; P08 no F2-L25, que é checkpoint;
  - evidências em `relatorios/fase2/L23/`.
- **Rota `versus_pl0c_pl12` (investigação, sem lote; 2026-11-25):**
  - arquivo novo `PlusAlphaProject/tools/auto_routes/versus_pl0c_pl12.json` (commitado em 85f72dd) e suporte a `port` (1 ou 2) no passo `press` de `PlusAlphaProject/tools/auto_session.py` (commitado em 85f72dd). Hipótese estática (`relatorios/fase2/orfas/versus_pl0c_pl12_proposta.json`): sequência ↑↑↓↓←→←→ Select Start (padrão em `0x8004324C` do overlay) dispara o estado 0x10 e o handler `0x8015547C`;
  - evidências em `relatorios/fase2/orfas/rota_versus_5/`: luta alcançada com ids `[0x801D4EA2]` = 0x0C e `[0x801D63CA]` = 0x0D (`03_luta_pronta.png`). Na luta a sequência não disparou: `fntrace` de `0x8015547C` com 0 hits (`fntrace_classe16_A/B/C.json`, frames 6.511, 6.838 e 7.176); `[0x801D63B7]` lido como 8 e 0 (`run.json`), nunca 0x10; `miss_total` 0 (`misses_m_*.json`), só quarentena;
  - conclusão: hipótese não confirmada (estado 0x10 não atingido). `0x8015547C` segue como classe A, fora dos lotes de `lotes_propostos.json`.
- **Pendências:**
  - **Política para órfãos (2026-11-25, 2a; `docs/newWords.md` §1):** raízes sem chamador estático podem ser promovidas por análise estática em lotes auditados por `seed_preview.py`, marcadas sem execução observada, com orçamento excepcional de ≤1.200 palavras e ≤25 funções (P01–P08). Mapa em `relatorios/fase2/orfas/mapa_orfas.json`: 5.526 palavras sem cobertura após F2-L17, das quais 75 (`0x8015547C`, classe A) têm caminho estático. P01–P06 aplicados (F2-L18 a F2-L23); P07–P08 propostos em `relatorios/fase2/orfas/lotes_propostos.json` (`lotes_resultado.json`: 144 raízes, 5.345 palavras, 150 funções).
  - o resolvedor de jump table não reconhecia a forma com `sll` no delay slot: resolvido em F2-R1; restam 42 `jr` indiretos de outras formas (41 após F2-R1, mais o de `0x8010B030` em F2-L3);
  - a rota não é determinística: a validação compara PCs interpretados, não screenshots;
  - os alvos dos índices 8 (Survival, byte de cena lido) e 26 (só pelo hit de `0x801085E0`) já são alcançados por rota; 2, 4, 5, 12 e 22–24 ainda não;
  - `generated-online/` e `coverage/baseline.json` só serão promovidos no fim da fase, com a validação de sensação do usuário.
  - divergência do agregado de `boot_to_fight` (L16: cinco PCs no agregado, seis na telemetria final; L17: seis no agregado, com `0x801AB2E8`): provável diferença de momento de amostragem, não confirmada. No L19, o agregado de `boot_to_fight` lista os seis PCs (`relatorios/fase2/L19/agregado_rotas.json`). No L21, o agregado de `boot_to_fight` tem `exe_pcs_interpretados` vazio, mas `relatorios/fase2/L21/boot_to_fight/telemetry_luta_final.json` lista os seis PCs; divergência não resolvida.
  - **Fronteira da Fase 2 (atualizada no F2-L23):** restam 398 palavras sem cobertura após o F2-L23 (174.246 - 173.848); após o F2-L22 eram 846 (174.246 - 173.400); após o F2-L21 eram 1.595 (174.246 - 172.651); após o F2-L20 eram 2.627 palavras sem cobertura (174.246 - 171.619); após o F2-L19 eram 3.457 (174.246 - 170.789); após o F2-L18 eram 4.598 (174.246 - 169.648). O texto abaixo é o registro do F2-L17, mantido como histórico. A fronteira de F2-L15/L16 esgotava as raízes estáticas auditáveis das varreduras `scan_L7` e `scan_L15`; com o F2-L17 foram promovidas `0x8019F9E4` e `0x801A15A8`; restavam 5.526 palavras sem cobertura após o F2-L17 (hoje, após o F2-L23: 398; após o F2-L22: 846; após o F2-L21: 1.595; após o F2-L20: 2.627; após o F2-L19: 3.457; após o F2-L18: 4.598; cálculo no F2-L17: 174.246 − 168.720; após o L16 eram 5.592 = 174.246 − 168.654; antes do L16 eram 6.652 = 174.276 − 167.624, com denominador antigo). Pela classificação por faixa de `scan_L15` (152 faixas, medida antes do L14 e não recalculada após o L16): ~2.119 palavras só alcançáveis por jump table ou `jalr` (17 faixas; candidatos citados que seguiam pendentes após o L18 e seguem pendentes após o F2-L20: `0x801935BC` e `0x801AB180` (`0x8018D974` e `0x80193474` foram promovidos no F2-L20) (`0x8010F290` foi promovido no F2-L18) (`0x80135608`, `0x80135848`, `0x80147624` e `0x801477F8` foram promovidos no L16; `0x8019F9E4` e `0x801A15A8` no L17)), que exigem investigação F2-Rx (resolvedor de jump table); ~4.016 palavras órfãs, sem referência estática no EXE nem nos overlays (hipótese: SDK sem uso), que só viram seed com evidência de execução ou decisão explícita do usuário; ~327 encadeadas a órfãos; ~96 em fragmentos sem borda de função e ~31 em zeros soltos (possível ajuste de exclusões). As 63 palavras restantes (6.652 = 6.589 + 63) estão na classe "raiz auditável" da varredura, sem candidato atribuído no arquivo; `candidatos.json` marca `0x8019F9E4` como JT e `0x801A15A8` como jalr, o que sugere, mas não prova, que sejam essas. O próximo passo deixa de ser micro-lote de seeds e passa a ser: (1) investigação F2-Rx das jump tables (feita, sem mudança no recompilador; as 2 tabelas do L16 e as 2 raízes do L17 (`0x8019F9E4`, JT; `0x801A15A8`, `jalr`) saíram da lista; após o F2-L18, 4 dos 11 sítios seguem pendentes); (2) política para órfãos decidida em 2026-11-25 (2a; ver `docs/newWords.md` §1); (3) revisar exclusões de padding (feito no F2-L16, com a correção de padding descrita no bloco F2-L16).

### Fase 3 — Código sem referência e variantes divergentes

- Com o inventário do disco, procurar referências aos 114 clusters nos overlays e nos dados. O que for referenciado vira seed; o que não for vira exclusão "morto provado".
- Explicar as 45 variantes divergentes comparando RAM e disco: patch em runtime, SMC ou outro ocupante.
- **Aceite:** EXE com 100% do código real.
- Pendente (não executado): rota `watch_sweep` (Watch/CPU x CPU) cobrindo todos os ids de personagem nos dois lados (overlays `PLxx_1` e `PLxx_2`), coletando misses de overlay, como base de evidência de execução para a Fase 3.
- Pendente: teste manual do usuário de CPU/temperatura com a máquina ociosa; sem resultado registrado.

### Fase 4 — Validação dos modos pendentes (autônoma, pela Fase A)

- **Cenários:**
  - memory card (save e load);
  - Arcade completo com os endings dos 23 lutadores e os créditos;
  - Survival;
  - Team Battle;
  - Watch;
  - cada lutador em P1 e em P2;
  - códigos secretos.
- **Aceite:** 0 instruções de jogo interpretadas fora da BIOS e das quarentenas, e 0 handoffs.

### Fase 5 — Fechamento

- Ligar a métrica ao build de release.
- Atualizar a documentação e as notas de release.
- Decidir entre modelo fiel e exclusão documentada para as quarentenas SMC/SIO, conforme `psxrecomp/CLAUDE.md`.

## 4. Ordem recomendada

A → 0 → 1 → 2 → 3 → 4 → 5. Sugerir commit ao fim de cada fase e antes de trocar de subsistema (`psxrecomp/` ↔ `PlusAlphaProject/`).
