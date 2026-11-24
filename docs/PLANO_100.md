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
- Evidência conferida: `0x80103E24..0x80103E3C` faz `lui/addiu 0x801AF960; addu; lw; jalr`. A tabela contém `0x8016FC28`, `0x801040E8`, `0x8010A5FC`, `0x80169B78`, `0x8010ABC8`, `0x8010ACD8`, `0x8010ADE8`, `0x8017566C`. `0x8010A5FC` e outras não estão nos ranges nem em `seeds/entry_funcs.txt`.
- **Reconciliado na Fase 0:** as 154.846 palavras eram a soma bruta das linhas `R` do manifesto S1-309. Três aliases repetem o mesmo range (`0x8013B070`, `0x8013B10C` e `0x8019CB4C`), o que conta 202 palavras duas vezes. O valor único do S1-309 é 154.644. A geração online atual (154.639) perdeu mais 5 palavras, `0x8019CB8C..0x8019CB9F`, e a entrada `0x8019CB8C`, que o S1-309 despachava. Essa entrada é um alias sem predecessor direto e é candidata ao primeiro micro-lote da Fase 2.
- **Raízes P1** (ver `track1/functions_uncovered.csv` e `roots.csv`):
  - funções: `0x8018D298`, `0x8010A5FC`, `0x8010AFDC`, `0x80102FAC`, `0x80131A3C`, `0x80162848`, `0x80102D80`, `0x80107EF0`, `0x8010809C`, `0x80107D80`, `0x8017FEC0`, `0x8016321C`, `0x8010ABC8`, `0x8010ACD8`, `0x8016313C`, `0x80127320`, `0x80162B18`, `0x8019F9E4`, mais cerca de 36 outras;
  - tabelas: `0x801AF960`, `0x801AF874`, `0x801B037C`, `0x801B1B20`, `0x801B3374`, `0x801B7EF0`, `0x801B85A0`.
- **Maiores clusters sem referência** (`track1/D_clusters.csv`): `0x80180018` (983), `0x80169984` (935), `0x8019AD94` (505), `0x80129E1C` (476), `0x8018D974` (422).
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

### Fase 2 — EXE: raízes chamadas por tabela (de ~79% para ~84,2%)

Micro-lotes conforme a governança de `docs/newWords.md`: pré-auditoria do fechamento, orçamento, aliases e jump tables. Começar pela tabela `0x801AF960` e pelas maiores raízes.

### Fase 3 — Código sem referência e variantes divergentes

- Com o inventário do disco, procurar referências aos 114 clusters nos overlays e nos dados. O que for referenciado vira seed; o que não for vira exclusão "morto provado".
- Explicar as 45 variantes divergentes comparando RAM e disco: patch em runtime, SMC ou outro ocupante.
- **Aceite:** EXE com 100% do código real.

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
