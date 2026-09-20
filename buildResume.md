# Build & Reverse Engineering Technical History (Build Resume)

This document serves as the historical deep-dive record for all static recompilation micro-batches, pre-audits, incident post-mortems, and dynamic overlay investigations for *Street Fighter EX Plus Alpha* (USA, `SLUS-005.48`).

For the current baseline status, active batches, and concise tracking table, see [`newWords.md`](newWords.md).

---

## 1. Governance & Maintenance Rules

- **Observed PC $\neq$ Function Root**: A runtime program counter hit can be an internal entry, a return site, a jump table destination, or an inline trampoline alias.
- **Promotion Lifecycle**: A candidate is only marked as `processed` after its boundary, callers, internal aliases, reachable closure, indirect control flow, telemetry verification, and regression tests are fully audited and clean.
- **Isolation Gates**: No new seed can be added to `seeds/entry_funcs.txt` without an isolated pre-audit measuring the full reachable closure and establishing a hard word budget. If the closure exceeds the budget, the candidate is quarantined or rejected.
- **SMC / Hardware I/O Isolation**: Self-modifying code (SMC) and direct hardware MMIO busy-wait loops (such as SIO/Joypad monkey-patches) must remain under interpreter execution (`psx_interpreter` / `dirty_ram_interp`) to prevent deadlocks and recursive crashes.

---

## 2. Static Micro-Batches Deep-Dive History

### S1-240 through S1-250 (Early Discovery Phase)
- **S1-240 (`0x8013CB08..0x8013CB8B`)**: 33 words promoted (cumulative: 106,352 words).
- **S1-241 (`0x801102A0..0x8011062F`)**: 228 words promoted (cumulative: 106,580 words).
- **S1-242 (`0x80137FE8`, `0x80138084`, `0x8013827C`)**: 245 words promoted (cumulative: 106,825 words).
- **S1-243 (`0x80162D68..0x8016313B`)**: 245 words promoted (cumulative: 107,070 words).
- **S1-244 (`0x80107A74..0x80107D7F`)**: 195 words promoted (cumulative: 107,265 words).
- **S1-245 (`0x8011D310..0x8011D9B3`)**: 425 words promoted (cumulative: 107,690 words).
- **S1-246 (`0x8011D030`, `0x8011D078`)**: 184 words promoted (cumulative: 107,874 words).
- **S1-247 (`0x801A92B8..0x801A939B`)**: 57 words promoted (cumulative: 107,931 words).
- **S1-248 (`0x801A9DC0..0x801A9FD3`)**: 133 words promoted (cumulative: 108,064 words).
- **S1-249 (`0x8019F6A8`, `0x8019FB64`)**: 125 words promoted (cumulative: 108,189 words).
- **S1-250 (`0x8019F5CC`, `0x8019FB4C`, `0x8019FB84`, `0x8019FB94`)**: 76 words promoted (cumulative: 108,265 words).

---

### Incident S1-252: Uncontrolled Closure Expansion (Post-Mortem)
- **Candidate**: Dispatcher `0x8016FC28` was initially estimated at only 39 words.
- **Root Cause**: The function contained two direct `JAL` instructions targeting uncompiled functions. Reachable discovery recursively expanded the closure to **12 functions and 2,805 words**, contaminating the work sources with 1,054 functions.
- **Corrective Action**: The candidate was immediately rejected and quarantined. Work sources were rolled back to S1-251 (`BB5EA43C...`). This incident established the mandatory rule of **isolated preview and hard word-budget validation** prior to touching main project files.

---

### S1-251 through S1-261 (Stabilization & Checkpoints)
- **S1-251 (`0x8014C708..0x8014C72F`)**: 10 words. Formal wrapper of 40 bytes. Telemetry confirmed 8,736 entries with zero misses.
- **S1-253 (`0x8017D860`, `0x8017DA08`, `0x80191000`)**: 184 words promoted.
- **S1-254 (`0x8017DA9C`, `0x80190EB8`, `0x80190FAC`)**: 155 words promoted.
- **S1-255 (`0x8018F10C..0x80190E6B`)**: 1,880 words promoted. Checkpoint reached 110,494 words.
- **S1-256 (`0x8016FC28`, `0x801910A4`, `0x801914C0`, `0x80191C84`, `0x80192D6C`, `0x801930BC`)**: 622 words promoted.
- **S1-257 (`0x8019FC6C..0x8019FCE3`)**: 30 words. Permanent title screen dispatcher.
- **S1-258 (`0x8017566C..0x801758C7`)**: 151 words. UI text rendering routines.
- **S1-259 (`0x801939A0..0x80193A17`)**: 30 words.
- **S1-260 (`0x80103BD8..0x80103CA7`)**: 52 words. Pause menu state handler.
- **S1-261 Checkpoint**: Cumulative release incorporating S1-251 through S1-260. Full regression verified 60 FPS across Expert Mode, Bonus Stage, Versus (Doctrine Dark vs Skullomania), Survival, Options, and Memory Card.

---

### S1-262 through S1-266 (Menu Eradication Campaign)
- **S1-262 (`0x80103384` + closure)**: 936 words. Reached 112,315 words.
- **S1-263 (`0x80164F00` + closure)**: 8,026 words (9 functions). 3D fight rendering pipeline and GTE math. Codegen audit: CLEAN.
- **S1-264 (`0x801912D8`, `0x80191588`, `0x801961BC`)**: 217 words. Direct targets from overlay `0x80020000` (Character Select & Menus).
- **S1-265 (`0x80192128`, `0x80192E58`, `0x80192F60`, `0x8019314C`, `0x80193174`, `0x8019319C`, `0x801931C4`, `0x8019328C`)**: 981 words. Options and Memory Card jump tables (`0x801B8538`).
- **S1-266 (`0x80124400`, `0x801932BC`, `0x80125594`, `0x801258D4`, `0x8016A84C`, `0x8018C880`)**: 3,896 words (22 native functions expanded). Eradicated 50 out of 52 residual uncompiled menu PCs. Baseline reached **125,435 words (64.1336%)**.
- **Residual Menu Candidates Audit**:
  - `0x801AB1F4` and `0x801AB2C0` were audited and confirmed as PSX BIOS kernel monkey-patches (SIO/Joypad hook and SMC delay swap). Quarantined under interpreter execution to protect entry timing.

---

### S1-267: Match State Machine / FSM (Promoted & Validated)
- **Root**: `0x80106BD4..0x80107A70` (3,744 bytes / **936 words**).
- **Architecture**: Core Round State Manager (Versus and Arcade match loop). Controls round initialization, Fight banner, active combat, KO, victory pose, replay, and post-match menu via jump table `0x801AB5BC` (9 cases).
- **Closure**: All 17 direct JAL calls resolve to pre-existing native functions. Zero closure expansion.
- **Coverage**: Advances static coverage to **126,371 words (64.6121%)** across 1,109 functions. Status: CLEAN.
- **Gameplay Validation (`gameplay-discovery-02`)**:
  - Telemetry verification across active Versus match (Doctrine Dark vs Ryu, 2 full rounds, special moves, combos, supers).
  - Native dispatches surged to **+152,919** (+40,355 additional native dispatches).
  - **100% of the 10 FSM uncompiled misses were completely eradicated** (`0x80106BD4`, `0x80106CB0`, `0x80106CB8`, `0x80106DB0`, `0x80106E8C`, `0x80106E94`, `0x80106E9C`, `0x80106F74`, `0x8010773C`, `0x80107744` dropped to zero).
  - Frametime confirmed rock-solid and ultra-smooth across entire combat session.
  - Remaining uncompiled Main EXE misses reduced to just 3 PCs (Entity update family `0x80117224`).

---

### S1-268: Entity & Frame Processing Cluster (Promoted & Validated)
- **Root**: `0x80117224` (Entity / Frame Processing Cluster).
- **Closure**: Directly resolves `0x80117224` (18 words / 72 bytes), `0x8011726C` (47 words / 188 bytes), `0x80117328` (143 words / 572 bytes), and `0x80117564` (251 words / 1,004 bytes). Total: 4 new native functions, 459 words (1,836 bytes).
- **Bridge**: Perfectly bridges the gap between `0x801171DC` and `0x80117950` in the Main EXE text segment.
- **External Calls**: Direct `JAL` calls to `0x801938B0`, `0x80194A58`, and `0x8010C72C` (all 100% native). All returns are standard `JR $ra` (`r31`); zero indirect branches, zero `JALR`.
- **Coverage**: Advances static coverage to **126,830 words (64.8468%)** across **1,113 functions** and **18,271 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Impact**: Eradicates the last 3 uncompiled Main EXE misses observed in active combat (`0x80117224`, `0x8011726C`, `0x80117328`). Main EXE static code in gameplay reaches 100% native dispatch (zero uncompiled misses), with only runtime-quarantined BIOS/SIO SMC patches remaining under interpreter execution.
- **Clean Gameplay Validation (`buildClean-ucrt-s1-268`)**:
  - Validated clean across a full Versus match (Doctrine Dark vs Ryu, 2 full rounds) followed by 4 consecutive Arcade mode fights with Doctrine Dark.
  - Frametime confirmed rock-solid and ultra-clean at fixed 60.0 FPS, with zero micro-stutter and zero regressions in hitboxes, physics, collision, special moves, supers, or audio. Full overlay cache (58 precompiled DLL shards) successfully integrated and operational.

---

### S1-269: 3D Projectile / Particle & Effect Entity Processor (Promoted & Validated)
- **Root**: `0x8014FE30..0x801502D4` (1,192 bytes / **298 words**).
- **Architecture**: 3D projection, transform, and physics handler for combat projectile entities, visual hitsparks, and special move particle systems (Hadoken, Shoryuken, and collision particles). Features an internal 5-case jump table at `0x801ABDD4` strictly bounded (`sltiu $v0, $fp, 5`) with all branches converging internally to `0x8014FEB8`, `0x8014FEC4`, and `0x8014FECC`.
- **Topological Bridge**: Perfectly bridges the physical gap in Main EXE between `0x8014FD54..0x8014FE30` and `0x801502D8..0x801502FC` (eliminating the 298-word hole).
- **Closure**: All 13 direct JAL calls point to pre-existing native functions (`0x80123910`, `0x801502D8`, `0x801502FC`, `0x80167D28`, `0x80194828`, `0x8019C0B8`, `0x8019C184`, `0x8019D740`, `0x8019D7D0`). Zero closure expansion.
- **Coverage**: Advances static coverage to **127,128 words (64.9991%)** across **1,114 functions** and **18,311 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Impact (`gameplay-discovery-05`)**:
  - Validated clean across full rematch of Ryu vs Ken on Ken's stage (Hadokens, Shoryukens, combos, supers, K.O.).
  - Completely eradicated all 3 misses observed in run 04 (`0x8014FE30`, `0x8014FF98`, `0x8014FFCC` dropped to 0).
  - Interpreter fallbacks plunged from +200,351 down to +92,498 (a reduction of -107,853 interpreted executions).
  - Confirmed frametime stabilization and a cleaner 60 FPS timeline due to elimination of dirty-RAM interpreter transitions during fireball and particle rendering.

---

### S1-270: 3D Trigonometry & Combat Reaction/Collision Cluster (Frentes 1 e 2)
- **Frente 1 (Leaf de Trigonometria e Rotacao 3D Matricial)**:
  - **Raiz**: `0x8019E6D0..0x8019E864` (408 bytes / **102 palavras**).
  - **Funcao**: Folha pura sem frame de pilha (`sp`), sem chamadas externas (`jal`), terminando com `jr $ra`. Executada dezenas de vezes por frame no calculo matricial de rotacao dos modelos 3D dos lutadores.
  - **Validacao (`gameplay-discovery-07`)**: Erradicou 100% dos 5.328 misses observados em Garuda vs Kairi. Dispatches nativos saltaram de +157.489 para +269.103 (+111.614 dispatches nativos adicionais). Operador reportou estabilizacao perceptivel de frametime.
  - **Cobertura F1**: 127.230 palavras (65,0513%) em 1.115 funcoes nativas.
- **Frente 2 (Cluster de Reacao, Dano e Colisao)**:
  - **Intervalo**: `0x80160B54..0x80160F94` (1.088 bytes / **272 palavras**).
  - **Funcoes (5 continuas)**:
    - `0x80160B54`: 240 bytes / 60 palavras (Calculo de flags/offsets de reacao)
    - `0x80160C44`: 152 bytes / 38 palavras (Atualizacao de impacto e status)
    - `0x80160CDC`: 168 bytes / 42 palavras (Tratamento de dano e frames de stun)
    - `0x80160D84`: 256 bytes / 64 palavras (Processador de colisoes e transicoes de estado)
    - `0x80160E84`: 272 bytes / 68 palavras (Mecanica de hit-stop e reacao corporal)
  - **Topologia**: Preenche sem qualquer folga o gap de 272 palavras entre `0x80160AA4` e `0x80160F94`.
  - **Closure**: Todas as 24 chamadas diretas `JAL` apontam para funcoes ja nativas ou internas (`0x8015D3F0`, `0x8015E12C`, `0x8011618C`, `0x80115574`, `0x80160430`, `0x801157A4`, `0x8015A0E8`, `0x8015D040`, `0x8012C288`, `0x80160C44`, `0x80101D68`, `0x80160084`, `0x801690D4`, `0x8015CF38`, `0x80158194`, `0x80159E44`). Zero expansao de closure.
  - **Cobertura Final S1-270**: **127.502 palavras (65,1904%)** em **1.120 funcoes nativas** e **18.388 entradas de dispatch**. Codegen audit: **CLEAN**.
  - **Validacao em Gameplay (`gameplay-discovery-08`)**:
    - Erradicou 100% dos 294 misses do Bloco A (`0x80160C44`, `0x80160CC4`, `0x80160CDC`, `0x80160CFC`, `0x80160D14`, `0x80160D70` zerados).
    - Queda expressiva de -21.826 instrucoes interpretadas no framework.
    - Confirmada estabilizacao extrema e linha de frametime ultralimpa a 60 FPS reportada pelo operador.
    - Restaram apenas 5 PCs residuais de combate (`0x801288DC..0x801289D0`), mapeados para o micro-lote S1-271.

---

### S1-271: Physics & Special Move Vector Calculation Cluster (Staged)
- **Origem / Gatilho**: 5 PCs observados com 364 hits em combate ativo (Garuda vs Kairi, `gameplay-discovery-08`): `0x801288DC` (120 hits), `0x80128988` (120 hits), `0x801289D0` (120 hits), `0x80128930` (2 hits), `0x80128968` (2 hits).
- **Invocacao / Jump Table**: A raiz `0x801288DC` e apontada pelo indice `0x801B03CC` da tabela de dispatch de acoes de combate (`0x801B03BC..0x801B03F8`).
- **Cluster & Limites**:
  - `0x801288DC`: 84 bytes / 21 palavras (Raiz formal; calcula parametros de vetor de acao e chama `0x80128930` e `0x80128988`).
  - `0x80128930`: 88 bytes / 22 palavras (Sub-rotina auxiliar de vetor; chama `0x8012B8F4` nativa).
  - `0x80128988`: 184 bytes / 46 palavras (Calculador de trajetoria e impacto; chama `0x8012B8F4` e `0x8012C628` nativas).
- **Fechamento de Chamadas**: Todas as 5 chamadas diretas `JAL` sao nativas ou internas ao cluster. Zero expansao de closure. Zero jump tables internas, zero `jalr`, zero interacoes arriscadas com hardware/SMC.
- **Topologia**: Ocupa de forma continua o intervalo `0x801288DC..0x80128A40` dentro do gap de fisica `0x80128524..0x80128D74`.
- **Orcamento**: 3 funcoes novas, 356 bytes / **89 palavras**.
- **Cobertura Final S1-271**: **127.591 palavras (65,2359%)** em **1.123 funcoes nativas** e **18.405 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validacao em Gameplay (`gameplay-discovery-09`)**:
  - Erradicou 100% dos 5 misses de fisica de combate (`0x801288DC`, `0x80128930`, `0x80128968`, `0x80128988`, `0x801289D0` zerados).
  - Novos candidatos a promocao estatica no Main EXE: **EXATAMENTE 0**.
  - Dispatch nativo subiu para **+184.536** e fallback do interprete caiu para o minimo historico de **+87.485**.
  - Segmento Text do Main EXE em combate ativo atinge **100% de cobertura estatica nativa** (zero misses em rounds completos de Garuda vs Kairi). Apenas os monkey-patches de BIOS/SIO em `0x801AB1F4` e `0x801AB2C0` permanecem sob interpretador.

---

### S1-272: Defender Hit-Stun, Recoil & Damage Physics Cluster (Promovido e Validado)
- **Origem / Gatilho**: Teste com inversao de papeis (Kairi P1 atacando, Garuda P2 defendendo/recebendo dano, `gameplay-discovery-10`), desmascarando **19.678 hits interpretados** distribuidos em 9 PCs do Main EXE.
- **Topologia**: Ocupa de forma continua o intervalo `0x801202EC..0x80120E44` (2.904 bytes / **726 palavras**), conectando perfeitamente a extremidade de `0x8011FE28` com a funcao nativa `0x80120E44`.
- **Funcoes Promovidas (8 continuas)**:
  - `0x801202EC`: 104 bytes / 26 palavras (3.176 hits; despachador de evento de impacto)
  - `0x80120354`: 516 bytes / 129 palavras (1 hit; atualizador de medidor e status de combate)
  - `0x80120558`: 696 bytes / 174 palavras (3.176 hits; loop de reacao com `jalr` indireto via tabela `0x801AFFA0`)
  - `0x80120810`: 36 bytes / 9 palavras (18 hits; sub-rotina de recoil / knockback)
  - `0x80120834`: 20 bytes / 5 palavras (14 hits; limpeza de flags de colisao)
  - `0x80120848`: 1.088 bytes / 272 palavras (5.107 hits na entrada, 3.061 em `0x80120A48`, 18 em `0x80120954`; processador principal de animacao e impacto de dano, alvo 0 da tabela `0x801AFFA0`)
  - `0x80120C88`: 40 bytes / 10 palavras (handler alternativo; alvo 1 da tabela `0x801AFFA0`)
  - `0x80120CB0`: 404 bytes / 101 palavras (5.107 hits; finalizador de frame de hit-stun / guarda)
- **Resolucao do JALR em `0x801206AC`**: O salto indireto consulta a tabela `0x801AFFA0` cujos unicos dois alvos (`0x80120848` e `0x80120C88`) pertencem a este proprio lote. Sendo ambos promovidos para a tabela de dispatch nativo, o `call_by_address` resolve em tempo de execucao nativo sem qualquer fallback de dirty-RAM.
- **Fechamento de Chamadas**: Todas as 13 chamadas externas diretas JAL apontam para funcoes ja compiladas (`0x801938B0`, `0x8019D740`, `0x8019E870`, `0x8019C0B8`, etc.). Expansao de closure: **ZERO**.
- **Orcamento**: 8 funcoes novas, 2.904 bytes / **726 palavras**.
- **Cobertura Final S1-272**: **128.317 palavras (65,6071%)** em **1.131 funcoes nativas** e **18.528 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validacao em Gameplay (`gameplay-discovery-11`)**:
  - Erradicou 100% dos 19.678 misses observados em Kairi vs Garuda nos 8 PCs do cluster de defesa/hit-stun (`0x801202EC`, `0x80120354`, `0x80120558`, `0x80120810`, `0x80120834`, `0x80120848`, `0x80120A48`, `0x80120CB0` todos zerados).
  - Queda macica no fallback do interpretador de +2.512.419 para o recorde historico absoluto de **+70.140**.
  - Dispatches nativos atingiram **+175.766** com estabilidade e frametime limpo a 60 FPS.
  - Novos candidatos a promocao no Main EXE: **EXATAMENTE 0**. Cobertura de combate no binario principal permanece 100% livre de misses.

---

### S1-273: Action NOP Handler, Special/Effects & Model Rendering Clusters (Promovido e Validado)
- **Origem / Gatilho**: Teste com Akuma vs Bison no cenario do Bison (`gameplay-discovery-12`), revelando 14 PCs candidatos no Main EXE Text com um total de **3.306 hits interpretados**.
- **Cluster A (Action Dispatch NOP Handler)**:
  - `0x8011721C`: 8 bytes / **2 palavras** (2.969 hits / 89,8% do teste; stub `jr $ra; nop` chamado pelos indices 0, 11, 13 e 15 da tabela `0x801AFC70`). Preenche perfeitamente o micro-gap entre `0x801171DC` e `0x80117224`.
- **Cluster B (Subsistema de Movimentos Especiais e Projeteis/Efeitos)**:
  - `0x801338B8`: 1.348 bytes / **337 palavras** (38 hits; raiz formal apontada pelo indice `0x801B1BFC` da tabela de efeitos; despacha para `0x80133DFC` e `0x80134224`).
  - `0x80133DFC`: 1.064 bytes / **266 palavras** (1 hit; setup de vetores de trajetoria e estado).
  - `0x80134224`: 1.880 bytes / **470 palavras** (36 hits na raiz, hits internos em `0x80134348`, `0x801343B4`, `0x801344F0`, `0x801344FC`, `0x80134618`; processador de colisao e fisica de efeito).
  - Fechamento: Todas as 21 chamadas externas diretas sao para rotinas ja nativas (`0x80123BF4`, `0x8010C72C`, `0x80101D18`, `0x80194990`, `0x8015C000`, etc.). Zero saltos indiretos; expansao de closure ZERO.
- **Cluster C (Motor de Renderizacao de Modelo e Cenarios)**:
  - `0x8013FF34`: 152 bytes / **38 palavras** (127 hits; handler apontado pela tabela `0x801B1B58`).
  - `0x8013FFCC`: 552 bytes / **138 palavras** (1 hit na raiz, 2 hits em `0x80140058`; setup de matriz/vertices).
  - `0x801401F4`: 1.448 bytes / **362 palavras** (126 hits; transformador de vertices e iluminacao).
  - `0x8014079C`: 188 bytes / **47 palavras** (Handler apontado por `0x801B1B5C`; possui switch interno com tabela `0x801ABC58` cujos alvos sao todos rotulos locais).
  - Topologia: Conecta perfeitamente o bloco nativo `0x8013F998..0x8013FF34` com o bloco nativo `0x80140858..0x80140CEC`.
  - Fechamento: Todas as chamadas externas sao nativas. Expansao de closure ZERO.
- **Orcamento Total S1-273**: 8 funcoes novas, 6.640 bytes / **1.660 palavras**.
- **Cobertura Final S1-273**: **129.977 palavras (66,4558%)** em **1.139 funcoes nativas** e **18.726 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validacao em Gameplay (`gameplay-discovery-13`)**:
  - Erradicou 100% dos 14 candidatos e 3.306 misses observados em Akuma vs Bison.
  - Novos candidatos a promocao no Main EXE: **EXATAMENTE 0**.
  - Dispatches nativos saltaram para o recorde de **+209.855 hits**.
  - Fallback interpretado despencou de +176.952 para +119.782 (-57.170 instrucoes interpretadas eliminadas).
  - **Diagnostico do Teleporte do Akuma (Ashura Senku)**: O leve ripple no frametime observado durante o teleporte repetido decorre do motor de overlay dinamico em RAM (`0x80045ACC`, +31.318 instrucoes interpretadas no overlay na sessao 13), responsavel pela animacao de rastro/sombras e flags de invulnerabilidade do golpe, enquanto o Main EXE permaneceu 100% livre de misses. Frametime no restante do combate manteve estabilidade extrema.

---

### S1-274 (Frente 1): Combat Action Subsystem - Cluster 1 (Promovido e Validado)
- **Origem / Gatilho**: Teste com inversao de papeis (Bison P1 atacando com P2 inerte, `gameplay-discovery-14`), desmascarando 358 hits no Cluster 1.
- **Topologia & Limites**:
  - `0x8014373C`: 156 bytes / **39 palavras** (179 hits; despachador que chama `0x801437D8` e `0x801439E4`).
  - `0x801437D8`: 524 bytes / **131 palavras** (4 hits na raiz, 4 hits em `0x80143948`; calculo de vetores e coordenadas de ataque).
  - `0x801439E4`: 1.996 bytes / **499 palavras** (171 hits; fisica de impacto e transformacoes 3D do golpe).
- **Fechamento de Chamadas**: Todas as 14 chamadas externas diretas JAL apontam para rotinas ja nativas (`0x8019D740`, `0x8019D7D0`, `0x8019CA30`, `0x8019EFD0`, `0x8019CE70`, `0x8010C72C`, etc.). Zero saltos indiretos; expansao de closure ZERO.
- **Orcamento Frente 1**: 3 funcoes novas, 2.676 bytes / **669 palavras**.
- **Cobertura Final Frente 1**: **130.646 palavras (66,7979%)** em **1.142 funcoes nativas** e **18.792 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validacao em Gameplay (`gameplay-discovery-15`)**:
  - Erradicou 100% dos 358 hits do Cluster 1 (`0x8014373C`, `0x801437D8`, `0x80143948`, `0x801439E4` todos zerados).
  - Queda macica de -168.126 instrucoes interpretadas no fallback (de +547.324 para +379.198).
  - Dispatches nativos atingiram **+108.921**.
  - Restaram no Main EXE apenas os 4 PCs do Cluster 2 (`0x80146B74..0x80147624`, 1.455 hits), mapeados para a Frente 2. Zero novos candidatos adicionais.

---

### S1-274 (Frente 2): Combat Action & Reaction Subsystem - Cluster 2 (Promovido e Validado)
- **Origem / Gatilho**: Teste com inversao de papeis (Bison P1 atacando com P2 inerte, `gameplay-discovery-14` e `15`), restando 1.455 hits no Cluster 2.
- **Topologia & Limites**:
  - `0x80146B74`: 156 bytes / **39 palavras** (721 hits; despachador de evento de impacto/reacao que chama `0x80146C10` e `0x80146E18`).
  - `0x80146C10`: 520 bytes / **130 palavras** (13 hits na raiz, 13 hits em `0x80146D80`; setup de parametros defensivos).
  - `0x80146E18`: 2.060 bytes / **515 palavras** (708 hits; fisica de recoil, animacao de impacto e transicao de estado).
- **Fechamento de Chamadas**: Todas as 14 chamadas externas diretas JAL apontam para rotinas ja nativas (`0x8019D740`, `0x8019D7D0`, `0x8019CA30`, `0x8019EFD0`, `0x8019CE70`, `0x8010C72C`, etc.). Zero saltos indiretos; expansao de closure ZERO.
- **Orcamento Frente 2**: 3 funcoes novas, 2.736 bytes / **684 palavras**.
- **Cobertura Final S1-274**: **131.330 palavras (67,1476%)** em **1.145 funcoes nativas** e **18.861 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validacao em Gameplay (`gameplay-discovery-16`)**:
  - Erradicou 100% dos 1.455 hits do Cluster 2 (`0x80146B74`, `0x80146C10`, `0x80146D80`, `0x80146E18` todos zerados).
  - **Zero misses no Main EXE em combate ativo**. Os unicos registros em fallback sao a quarentena SMC BIOS/SIO (`0x801AB1F4` e `0x801AB2C0`).
  - Queda macica no fallback interpretado de +379.198 para **+75.594** (-303.604 instrucoes interpretadas eliminadas).
  - Telemetria de frametime perfeitamente estavel a 60 FPS com motor de acao/reacao inteiramente nativo.
- **Validacao de Edge-Case: Head Press / Skull Diver de Bison (`gameplay-discovery-17`)**:
  - Teste intensivo do pisao e mergulho com chamas de Bison (acertos e whiffs repetidos).
  - Resultado no Main EXE: **EXATAMENTE 0 MISSES** (0 novos candidatos estaticos). Dispatches nativos: **+210.765**.
  - Diagnostico Arquitetural: O efeito de fogo nos membros e a maquina de estados particular do golpe rodam 100% no overlay dinamico em RAM de Bison (`0x8004485C..0x80044DE8`, ~40k hits) e no despachador de animacao de overlay (`0x80093588..0x80093D70`). O arcabouco estatico no Main EXE para o confronto esta 100% saturado e nativo.

---

### S1-275: Combat Action Subsystem (Carga/Hold) & Overlay Support Leaf (Promovido e Validado)
- **Origem / Gatilho**: Teste Chun-Li vs Guile no cenario do Guile (`gameplay-discovery-18`), revelando 12 PCs candidatos no Main EXE Text com um total de **48.935 hits interpretados**.
- **Bloco 1 (Gap de Carga/Hold `0x8011F5F0..0x801202EC`, 9 funcoes continuas, 3.324 bytes / 831 palavras)**:
  - `0x8011F5F0`: 116 bytes / **29 palavras** (1 hit; setup de registradores e vetores de carga).
  - `0x8011F664`: 76 bytes / **19 palavras** (201 hits; atualizador de flags de estado).
  - `0x8011F6B0`: 52 bytes / **13 palavras** (185 hits; limpeza de buffers de ataque).
  - `0x8011F6E4`: 128 bytes / **32 palavras** (3.290 hits; loop de despacho com `jalr ra, v0` via tabela `0x801AFF08`).
  - `0x8011F764`: 72 bytes / **18 palavras** (3.290 hits; **Raiz formal** apontada pelo indice 10 da tabela de acoes de combate `0x801AFC70` no offset `0x801AFC98`).
  - `0x8011F7AC`: 52 bytes / **13 palavras** (1 hit; transicao de frames e animacao).
  - `0x8011F7E0`: 444 bytes / **111 palavras** (3.290 hits; gerenciador de cancelamento e timing de carga).
  - `0x8011F99C`: 1.164 bytes / **291 palavras** (**34.426 hits**; processador ativo de frames de golpes rapidos e carga, alvo 0 da tabela `0x801AFF08`; contem o sub-caminho `0x8011FA88` com 236 hits).
  - `0x8011FE28`: 1.220 bytes / **305 palavras** (**3.044 hits**; finalizador e transicao pos-ataque, alvo 1 da tabela `0x801AFF08`; contem o sub-caminho `0x8011FF24` com 166 hits).
  - Topologia: Conecta de forma continua e sem qualquer folga a funcao nativa `0x8011F084` ao inicio do lote S1-272 (`0x801202EC`).
- **Bloco 2 (Micro-gap Leaf `0x80167ED4..0x80167EF8`, 1 funcao folha, 36 bytes / 9 palavras)**:
  - `0x80167ED4`: 36 bytes / **9 palavras** (**1.092 hits**; leaf puro sem stack frame chamado por 8 pontos da engine de overlay dinamico em RAM `0x8008FEF4..0x80090040`).
  - Topologia: Conecta perfeitamente a funcao nativa `0x80167E34` a `0x80167EF8`.
- **Fechamento de Chamadas**: Todas as 16 chamadas diretas `JAL` apontam para funcoes ja compiladas no Main EXE (`0x801938B0`, `0x8019DF20`, `0x80194990`, `0x801945F8`, `0x801946C8`, `0x801948DC`, `0x8019CE70`, `0x8019D740`, `0x8019D7D0`, `0x8010C72C`). Zero saltos externos; expansao de closure ZERO.
- **Resolucao do JALR em `0x8011F734`**: O salto indireto consulta a tabela `0x801AFF08` cujos dois unicos destinos (`0x8011F99C` e `0x8011FE28`) foram promovidos no proprio lote, garantindo resolucao nativa direta via `call_by_address`.
- **Orcamento Total S1-275**: 10 funcoes novas, 3.360 bytes / **840 palavras**.
- **Cobertura Final S1-275**: **132.170 palavras (67,5771%)** em **1.155 funcoes nativas** e **20.129 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validacao em Gameplay (`gameplay-discovery-20`)**:
  - Erradicou 100% dos 12 candidatos e 48.935 misses observados em Chun-Li vs Guile.
  - Novos candidatos a promocao no Main EXE: **EXATAMENTE 0**.
  - Dispatches nativos saltaram para **+168.827 hits**.
  - Fallback interpretado despencou de +9.149.650 para +111.159 (-9.038.491 instrucoes interpretadas eliminadas; queda de 98,8%).
  - Confirmado frametime cravado e ultra-estavel a 60 FPS durante todo o combate ativo. As variacoes transitorias nas bordas da luta (inicio do round e K.O./replay/pose de vitoria) decorrem das rotinas em RAM dinamica dos overlays (Track 2: `0x80048960`, `0x80046EEC`, `0x800477D0`).

---

### S1-276: Guile Combat Action Subsystem (Sonic Boom & Flash Kick) (Promovido e Validado)
- **Origem / Gatilho**: Teste com inversao de papeis (Guile P1 atacando com Chun-Li P2 inerte, `gameplay-discovery-21`), revelando 4 PCs candidatos no Main EXE Text com um total de **6.534 hits interpretados**.
- **Topologia & Limites (2 funcoes novas, 1.180 bytes / 295 palavras)**:
  - `0x8011E344`: 104 bytes / **26 palavras** (2.655 hits na entrada, 1 hit em `0x8011E390`; **Raiz formal** apontada pelo indice 9 da tabela de acoes de combate `0x801AFC70` no offset `0x801AFC94`; despacha para `0x8011E3AC` nativa e `0x8011E628`).
  - `0x8011E628`: 1.076 bytes / **269 palavras** (2.655 hits na raiz, 1.223 hits no sub-bloco interno `0x8011E900`; processador de fisica, vetores de impacto e colisoes de golpes do Guile).
- **Fechamento de Chamadas**: Todas as 14 chamadas diretas `JAL` apontam para rotinas ja nativas no Main EXE (`0x801938B0`, `0x8011EA5C`, `0x8019D740`, `0x8019D7D0`, `0x8011EA80`, `0x8019E870`, `0x8019CE70`, `0x80167D28`, `0x8019EA10`). Zero saltos externos, zero saltos indiretos, expansao de closure: **ZERO**.
- **Continuidade do Main EXE**: Conecta perfeitamente o gap antes de `0x8011E3AC` e entre `0x8011E628` e `0x8011EA5C`, estabelecendo mais de 15.000 bytes ininterruptos de codigo estatico nativo entre `0x8011D030` e `0x80120E44`.
- **Orcamento Total S1-276**: 2 funcoes novas, 1.180 bytes / **295 palavras**.
- **Cobertura Final S1-276**: **132.465 palavras (67,7284%)** em **1.157 funcoes nativas** e **20.129 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validacao em Gameplay (`gameplay-discovery-22`)**:
  - Erradicou 100% dos 4 candidatos e 6.534 misses observados em Guile vs Chun-Li (`0x8011E344`, `0x8011E390`, `0x8011E628`, `0x8011E900` todos zerados).
  - Novos candidatos a promocao no Main EXE: **EXATAMENTE 0**.
  - Dispatches nativos mantiveram patamar altissimo: **+309.787 hits**.
  - Fallback interpretado despencou de +2.474.813 para apenas **+23.032** (reducao de 99,1%, novo minimo historico absoluto do projeto).
  - Guile formalmente homologado como o 8º personagem 100% nativo no Main EXE.

---

### S1-277: Sakura Combat Action Subsystem & Collision Vector Leaf (Promovido e Validado)
- **Origem / Gatilho**: Teste Sakura vs Pullum Purna no cenario Plus (`gameplay-discovery-24`), revelando 16 PCs candidatos no Main EXE Text com um total de **39.516 hits interpretados**.
- **Diagnostico Arquitetural**: O trabalho prévio de otimização na Sakura cobriu a Trilha 2 (Overlays dinâmicos em RAM `0x8004xxxx`). No Main EXE estático, a Sakura aciona o **Índice 6 da Tabela Global de Ações** (`0x801AFC70` no offset `0x801AFC88` -> `0x8011BD94`), que ainda não havia sido recompilado estaticamente.
- **Bloco 1 (Cluster de Ação da Sakura `0x8011BD94..0x8011D030`, 8 funções contínuas, 4.764 bytes / 1.191 palavras)**:
  - `0x8011BD94`: 104 bytes / **26 palavras** (1 hit na raiz, 1 hit em `0x8011BDE0`; **Raiz formal** apontada pelo índice 6 da tabela `0x801AFC70` no offset `0x801AFC88`; despacha para `0x8011BDFC` e `0x8011C01C`).
  - `0x8011BDFC`: 544 bytes / **136 palavras** (1 hit; setup de propriedades, buffers de ataque e flags de física).
  - `0x8011C01C`: 816 bytes / **204 palavras** (3.447 hits na entrada, sub-blocos `0x8011C0C4` [1 hit], `0x8011C118` [1 hit], `0x8011C144` [1 hit], `0x8011C288` [1 hit]; loop despachador com `jalr ra, v0` via tabela `0x801AFDF8`).
  - `0x8011C34C`: 36 bytes / **9 palavras** (1 hit; limpeza de buffers e resets de comandos de combate).
  - `0x8011C370`: 20 bytes / **5 palavras** (1 hit; handler atômico de transição de estado).
  - `0x8011C384`: 1.368 bytes / **342 palavras** (**27.420 hits** na raiz, sub-blocos `0x8011C470` [1 hit], `0x8011C4E4` [1 hit], `0x8011C54C` [1 hit], `0x8011C774` [1 hit]; processador primário de física, combos e projéteis da Sakura; Alvo 0 da tabela `0x801AFDF8`).
  - `0x8011C8DC`: 880 bytes / **220 palavras** (**8.636 hits**; processador de colisão corporal, timing de impacto e cancelamento; Alvo 1 da tabela `0x801AFDF8`).
  - `0x8011CC4C`: 996 bytes / **249 palavras** (1 hit; finalizador de frame de ataque, recoil e transição para pose neutra).
  - Topologia: Conecta perfeitamente a função nativa `0x8011B5E4` (termina em `0x8011BD94`) ao início do lote S1-246 (`0x8011D030`), fechando 100% o gap e criando um bloco contínuo nativo de mais de 23 KB entre `0x8011B3B8` e `0x80120E44`.
- **Bloco 2 (Calculador Vetorial de Colisão Leaf `0x8015DDC4..0x8015DE60`, 1 função formal, 156 bytes / 39 palavras)**:
  - `0x8015DDC4`: 156 bytes / **39 palavras** (1 hit; calculador vetorial 3D de distância e caixas de colisão entre lutadores, chamado por `0x8019EFD0`).
  - Topologia: Preenche com precisão absoluta o gap entre a função nativa `0x8015DC78` (termina em `0x8015DDC4`) e `0x8015DE60`.
- **Fechamento de Chamadas**: Todas as 51 chamadas diretas `JAL` apontam para funções já nativas no Main EXE (`0x801938B0`, `0x8019DF20`, `0x8019D740`, `0x8019D7D0`, `0x8019E870`, `0x8019E778`, `0x8019CE70`, `0x8010C72C`, etc.) ou internas ao cluster. Expansão de closure: **ZERO**.
- **Resolução do JALR em `0x8011C1DC`**: O despacho dinâmico lê a tabela `0x801AFDF8`, cujos dois únicos ponteiros (`0x8011C384` e `0x8011C8DC`) pertencem a este próprio micro-lote, garantindo resolução nativa imediata via `call_by_address`.
- **Orçamento Total S1-277**: 9 funções novas, 4.920 bytes / **1.230 palavras**.
- **Cobertura Final S1-277**: **133.695 palavras (68,3568%)** em **1.166 funções nativas** e **20.129 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-25`)**:
  - Erradicou 100% dos 16 candidatos e 39.516 misses observados na sessão 24.
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Dispatches nativos: **+147.240 hits**.
  - Fallback interpretado despencou de +1.370.296 para apenas **+116.517** (redução de 91,5%, -1.253.779 instruções interpretadas eliminadas).
  - Sakura formalmente homologada como a 9ª lutadora 100% nativa no Main EXE estático.
- **Validação Invertida em Gameplay (`gameplay-discovery-26` - Pullum Purna P1 vs Sakura P2)**:
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0** (0 misses de dispatch, 0 misses no Main EXE).
  - Dispatches nativos mantiveram alto volume: **+197.291 hits** (+285.820 delta acumulado).
  - Fallback concentrado 100% em código dinâmico de overlay em RAM (`0x80045xxx`, `0x8008Exxx`, `0x8009xxxx`).
  - Pullum Purna formalmente homologada como a 10ª lutadora 100% nativa no Main EXE estático.

---

### S1-278: Gameplay Status Dispatcher & Combat Vector Transition Cluster (Promovido e Validado)
- **Origem / Gatilho**: Teste Doctrine Dark vs Darun Mister no cenario Darun (`gameplay-discovery-27`), revelando instabilidade e sujeira na linha de frametime causada por **+1.002 Native Handoffs** de contexto e 5 candidatos no Main EXE Text com **160 hits interpretados**.
- **Diagnostico Arquitetural**:
  - O trabalho prévio no D.Dark cobriu a Trilha 2 (Overlays em RAM `0x8004xxxx`, série OVL-002 de bombas e explosivos).
  - No Main EXE estático, o combate ativo de D.Dark e Darun esbarrou em um gap de 268 bytes entre as rotinas nativas `0x80140B6C` (termina em `0x80140CE8`) e `0x80140DF8` (começa em `0x80140DF8`). A cada ataque, o código caía em interpretação no gap e retornava para o bloco nativo seguinte, gerando +1.002 handoffs por frame e oscilação de frametime.
  - Adicionalmente, a tabela global de status do jogo em `0x801AE874` teve seu índice 4 (`0x801AE884` -> `0x80102B10`) acionado com 83 hits interpretados.
- **Topologia & Limites (3 funções novas, 892 bytes / 223 palavras)**:
  - **Bloco 1 (Entrada da Tabela Global de Status, 1 função, 624 bytes / 156 palavras)**:
    - `0x80102B10`: 624 bytes / **156 palavras** (83 hits; despachador formal de modos de jogo apontado pelo índice 4 da tabela `0x801AE874` no offset `0x801AE884`; conecta `0x80102B10` até `0x80102D80`; chama `0x80101D18` nativa).
  - **Bloco 2 (Gap de Combate D.Dark/Darun `0x80140CEC..0x80140DF8`, 2 funções contínuas, 268 bytes / 67 palavras)**:
    - `0x80140CEC`: 76 bytes / **19 palavras** (1 hit; setup de propriedades, buffers de ataque e matrizes de colisão; chama `0x80123A94` nativa; fecha o gap entre `0x80140CE8` e `0x80140D38`).
    - `0x80140D38`: 192 bytes / **48 palavras** (39 hits na raiz, 1 hit em `0x80140DA0` e 36 hits no epílogo `0x80140DE4`; processador ativo de ações, recoil e transições de combate; chama `0x80140DF8`, `0x80123AE0`, `0x80141454`, `0x801411D8` todas nativas; conecta com `0x80140DF8`).
- **Fechamento de Chamadas**: Todas as 6 chamadas diretas `JAL` apontam para funções já nativas no Main EXE (`0x80101D18`, `0x80123A94`, `0x80140DF8`, `0x80123AE0`, `0x80141454`, `0x801411D8`). Zero saltos externos; expansão de closure: **ZERO**.
- **Orçamento Total S1-278**: 3 funções novas, 892 bytes / **223 palavras**.
- **Cobertura Final S1-278**: **133.918 palavras (68,4708%)** em **1.169 funções nativas** e **20.129 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-28`)**:
  - Erradicou 100% dos 5 candidatos e 160 misses observados na sessão 27 (`0x80102B10`, `0x80140CEC`, `0x80140D38`, `0x80140DA0`, `0x80140DE4` todos zerados).
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: despencaram de +1.002 para **0**.
  - Linha de frametime: confirmada visualmente 100% limpa, lisa e cravada sem os micro-stutters da rodada anterior.
  - Dispatches nativos: **+205.138 hits**.
  - Doctrine Dark formalmente homologado como o 11º lutador 100% nativo no Main EXE estático.

---

### S1-279: Darun Mister Combat Subsystem (Lariats, Heavy Impact & Command Throw Dispatcher) (Promovido e Validado)
- **Origem / Gatilho**: Teste com inversão de papéis (Darun Mister P1 atacando vs D.Dark P2 inerte no cenário Darun, `gameplay-discovery-29`), desmascarando 27 candidatos no Main EXE Text com um total de **2.348 hits interpretados**.
- **Diagnóstico Arquitetural**:
  - Os agarrões de comando, arremessos (*Indra Bridge*, *Daisharin*), *Lariats* e o especial de 720 (*Twilight Collar*) dependem de uma infraestrutura compartilhada no Main EXE: a **Tabela Global de Agarrões (`0x801B33F0`)** e os despachadores de física pesada em `0x80128xxx`.
  - A execução não compilada dessa infraestrutura ativou 27 pontos de choque no Main EXE Text.
- **Topologia & Limites (13 funções novas, 2.712 bytes / 678 palavras)**:
  - **Bloco 1 (Gap de Lariat / Grab Linkage `0x80127FB8..0x80128014`, 1 função, 92 bytes / 23 palavras)**:
    - `0x80127FB8`: 92 bytes / **23 palavras** (96 hits na raiz, 96 hits em `0x80127FF8`, 3 hits em `0x80127FF0`, 3 hits em `0x80128000`; conecta perfeitamente `0x80127D1C` a `0x80128014`).
  - **Bloco 2 (Gap de Impacto Pesado & Lariat Engine `0x80128A40..0x80128D74` + Helper `0x8012B86C`, 5 funções, 956 bytes / 239 palavras)**:
    - `0x80128A40`: 308 bytes / **77 palavras** (352 hits; processador primário de impacto do Lariat).
    - `0x80128B74`: 84 bytes / **21 palavras** (352 hits em `0x80128B58`; setup de giro e impulso).
    - `0x80128BC8`: 88 bytes / **22 palavras** (transição pós-acerto; chama `0x8012B86C`).
    - `0x80128C20`: 340 bytes / **85 palavras** (finalizador e cálculo de recoil do Lariat; chama `0x8012B86C`).
    - `0x8012B86C`: 136 bytes / **34 palavras** (helper vetorial de colisão pesada; preenche 100% o gap `0x8012B86C..0x8012B8F4`).
    - Fecha 100% o gap entre `0x80128A40` e `0x80128D74`.
  - **Bloco 3 (Tabela Global de Agarrões `0x801B33F0` em `0x80161584..0x80161C04`, 7 funções contínuas, 1.664 bytes / 416 palavras)**:
    - `0x80161584`: 88 bytes / **22 palavras** (handler de transição apontado por `0x801B3470`).
    - `0x801615DC`: 164 bytes / **41 palavras** (2 hits; setup de agarrão apontado por `0x801B33FC`).
    - `0x80161680`: 364 bytes / **91 palavras** (233 hits na raiz, 135 hits em `0x801616CC`, etc.; processador de colisão corporal de agarrão apontado por `0x801B3448`).
    - `0x801617EC`: 68 bytes / **17 palavras** (4 hits; vetores de elevação de suplex apontados por `0x801B3400`).
    - `0x80161830`: 456 bytes / **114 palavras** (250 hits na raiz, 132 hits em `0x801618CC`, 84 hits em `0x801618F4`, 66 hits em `0x80161994`, etc.; processador de arremesso e dano apontado por `0x801B344C`).
    - `0x801619F8`: 68 bytes / **17 palavras** (3 hits em `0x801619E0`; recoil e soltura apontados por `0x801B342C`).
    - `0x80161A3C`: 456 bytes / **114 palavras** (impacto no chão e recuperação apontados por `0x801B3478`).
    - Fecha 100% o gap e erradica todos os 21 candidatos da região `0x80161xxx`.
- **Fechamento de Chamadas**: Todas as chamadas diretas `JAL` apontam para funções internas ou já nativas no Main EXE (`0x80126614`, `0x801265C0`, `0x8012B730`, `0x8012C628`, `0x8015E12C`, `0x80159E44`, `0x80115574`, etc.). Expansão de closure: **ZERO** (1.169 -> 1.182 funções cravadas).
- **Orçamento Total S1-279**: 13 funções novas, 2.712 bytes / **678 palavras**.
- **Cobertura Final S1-279**: **134.596 palavras (68,8175%)** em **1.182 funções nativas** e **20.129 entradas de dispatch**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-30`)**:
  - Erradicou 100% dos 27 candidatos e 2.348 misses observados na sessão 29 (todos zerados no interpretador).
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: **0** mantidos estritamente.
  - Linha de frametime: confirmada visualmente bem limpa e estável durante os agarrões e lariats.
  - Dispatches nativos mantiveram alta taxa: **+218.855 hits** na janela.
  - Darun Mister formalmente homologado como o 12º lutador 100% nativo no Main EXE estático.

---

### S1-280: Cracker Jack Stage & Action Subsystem (Promovido & Validado)
- **Origem / Gatilho**: Teste invertido de combate (Allen Snider vs Cracker Jack no Cenário do Cracker Jack, `gameplay-discovery-32`), que desmascarou o ponteiro `0x801AFC80` na Action Dispatch Table apontando para `0x8011ABD4`, e expôs a rotina `0x8011AFBC` com 153.072 chamadas interpretadas por luta gerando oscilações perceptíveis de frametime.
- **Topologia & Limites (8 funções novas, 2.652 bytes / 663 palavras)**:
  - **Bloco 1 (Gap de Vetores e Animação do Cenário `0x8011A8DC..0x8011AAFC`, 1 função contínua, 544 bytes / 136 palavras)**:
    - `0x8011A8DC`: 544 bytes / **136 palavras** (processador de transformação e geometria de cenário/combate; encerra com `jr $ra` em `0x8011AAF4`; conecta perfeitamente a `0x8011AAFC`). O endereço `0x8011A9F8` com 1 hit era o retorno de `jal 0x801945F8`.
  - **Bloco 2 (Action Dispatcher Subsystem `0x8011AB7C..0x8011B3B8`, 7 funções contínuas, 2.108 bytes / 527 palavras)**:
    - `0x8011AB7C`: 88 bytes / **22 palavras** (3.445 hits; caller de `0x8011AFBC`).
    - `0x8011ABD4`: 72 bytes / **18 palavras** (3.445 hits; raiz formal da Action Dispatch Table em `0x801AFC80`).
    - `0x8011AC1C`: 52 bytes / **13 palavras** (1 hit; despachador para `0x8011A8DC`).
    - `0x8011AC50`: 876 bytes / **219 palavras** (3.445 hits; transformações geométricas e frame updates).
    - `0x8011AFBC`: 452 bytes / **113 palavras** (**Workhorse central de combate/cenário: 153.072 hits interpretados erradicados!**).
    - `0x8011B180`: 184 bytes / **46 palavras** (3.445 hits; vetores de câmera e colisão).
    - `0x8011B238`: 384 bytes / **96 palavras** (3.445 hits; finalização de buffers; conecta perfeitamente a `0x8011B3B8`).
- **Fechamento de Chamadas**: Todas as chamadas diretas `JAL` e desvios são estritamente internos ao cluster ou apontam para código estático já nativo. Expansão de closure: **ZERO** (1.182 -> 1.190 funções cravadas).
- **Orçamento Total S1-280**: 8 funções novas, 2.652 bytes / **663 palavras**.
- **Cobertura Final S1-280**: **135.259 palavras (69,1565%)** em **1.190 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-33`)**:
  - Erradicou 100% dos 9 candidatos e das 153.072 chamadas interpretadas da sessão 32.
  - O volume de fallback interpretado caiu de 14.701.282 para 1.303.848 instruções (**-91,1%**).
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: **0** mantidos estritamente.
  - Linha de frametime: confirmada limpa e estável em ambas as orientações (direta e invertida).
  - Cracker Jack (13º) e Allen Snider (14º) formalmente homologados como 100% nativos no Main EXE estático.

---

### S1-281: Action Dispatcher Subsystem - Blair Dame & Zangief (Promovido & Validado)
- **Origem / Gatilho**: Teste invertido de combate (Blair Dame vs Zangief no Cenário do Zangief, `gameplay-discovery-35`), que desmascarou o ponteiro `0x801AFC90` na Action Dispatch Table apontando para `0x8011D9B4`, e expôs a rotina interna `0x8011E18C` com 47.970 chamadas interpretadas por luta.
- **Topologia & Limites (5 funções novas, 2.448 bytes / 612 palavras)**:
  - Gap contínuo `0x8011D9B4..0x8011E344`:
    - `0x8011D9B4`: 104 bytes / **26 palavras** (3.846 hits; raiz formal da Action Table em `0x801AFC90`).
    - `0x8011DA1C`: 512 bytes / **128 palavras** (1 hit; setup de buffers e propriedades de ataque).
    - `0x8011DC1C`: 1.776 bytes / **444 palavras** (3.846 hits na entrada, **47.970 hits em `0x8011E18C`**; processador central de estados de combate/reação).
    - `0x8011E30C`: 36 bytes / **9 palavras** (734 hits; handler de transição).
    - `0x8011E330`: 20 bytes / **5 palavras** (712 hits; conector terminal; encerra com `jr $ra` em `0x8011E33C`; conecta perfeitamente a `0x8011E344`).
- **Encaixe e Continuidade**: Conecta `0x8011D310..0x8011D9B3` (S1-245) a `0x8011E344` (S1-276), unificando toda a faixa `0x8011BD94..0x8011F5F0` como um bloco compilado contínuo no Main EXE.
- **Fechamento de Chamadas**: Todas as chamadas diretas `JAL` apontam para funções já nativas ou internas ao bloco. Expansão de closure: **ZERO** (1.190 -> 1.195 funções cravadas).
- **Orçamento Total S1-281**: 5 funções novas, 2.448 bytes / **612 palavras**.
- **Cobertura Final S1-281**: **135.871 palavras (69,4694%)** em **1.195 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-36`)**:
  - Erradicou 100% dos 7 candidatos da sessão 35 e as 47.970 chamadas interpretadas de `0x8011E18C`.
  - O volume de fallback interpretado caiu de 8.624.913 para 1.621.746 instruções (**-81,2%**).
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: **0** mantidos estritamente.
  - Dispatches nativos mantidos em alta taxa: **+201.339 chamadas** em C nativo.

---

### S1-282: Grappling Engine - Zangief Command Throws (Promovido & Validado)
- **Origem / Gatilho**: Teste inicial de Zangief vs Blair Dame (`gameplay-discovery-34`), que ativou a segunda metade da Tabela Global de Agarrões `0x801B33F0` em `0x80161C04..0x80161FE4`, desmascarando 14 candidatos (270 hits em `0x80161CCC` e 90 hits em `0x80161E5C`).
- **Topologia & Limites (7 funções novas, 992 bytes / 248 palavras)**:
  - `0x80161C04`: 8 bytes / **2 palavras** (stub de transição apontado por `0x801B3410`).
  - `0x80161C0C`: 124 bytes / **31 palavras** (handler apontado por `0x801B345C`).
  - `0x80161C88`: 68 bytes / **17 palavras** (setup de arremesso apontado por `0x801B3414; 3 hits`).
  - `0x80161CCC`: 332 bytes / **83 palavras** (impacto corporal e colisão de *Spinning Piledriver* / *Powerbomb* em `0x801B3460`; **270 hits**).
  - `0x80161E18`: 68 bytes / **17 palavras** (transição apontada por `0x801B3418; 1 hit`).
  - `0x80161E5C`: 332 bytes / **83 palavras** (trajetória, elevação e impacto de *Atomic Suplex* / *Final Atomic Buster* em `0x801B3464`; **90 hits**).
  - `0x80161FA8`: 60 bytes / **15 palavras** (recoil pós-arremesso apontado por `0x801B3438`).
- **Encaixe e Continuidade**: Conecta diretamente com `0x80161A3C` (promovido no S1-279), estendendo a Tabela Global de Agarrões até `0x80161FE4`.
- **Fechamento de Chamadas**: Zero saltos indiretos, zero chamadas externas não resolvidas. Expansão de closure: **ZERO** (1.195 -> 1.202 funções cravadas).
- **Orçamento Total S1-282**: 7 funções novas, 992 bytes / **248 palavras**.
- **Cobertura Final S1-282**: **136.119 palavras (69,5962%)** em **1.202 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-37`)**:
  - Erradicou 100% dos 14 candidatos da Tabela de Agarrões da sessão 34.
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: **0** mantidos estritamente.
  - Dispatches nativos alcançaram **+305.438 chamadas** em C nativo com estabilidade máxima.
  - Linha de frametime: confirmada visualmente como extremamente limpa.

---

### S1-283: Core Combat & Action Engine - Blair Dame & Zangief (Promovido & Validado)
- **Origem / Gatilho**: Teste inicial de Zangief vs Blair Dame (`gameplay-discovery-34`), que desmascarou o gap contínuo `0x8013E930..0x8013F7A0` responsável pelo processamento de encadeamento de ataques e colisões (mais de 1.000 hits combinados).
- **Topologia & Limites (3 funções novas, 3.696 bytes / 924 palavras)**:
  - `0x8013E930`: 152 bytes / **38 palavras** (transições e encadeamento de golpes de ataque; **527 hits**).
  - `0x8013E9C8`: 408 bytes / **102 palavras** (setup de propriedades físicas e vetores de impulso; 6 hits).
  - `0x8013EB60`: 3.136 bytes / **784 palavras** (loop central de processamento de animação e combate; **517 hits**).
- **Encaixe e Continuidade**: Conecta `0x8013E764..0x8013E92F` (promovido no S1-146) diretamente a `0x8013F7A0` (S1-177/210), eliminando todo o gap dessa faixa de combate.
- **Fechamento de Chamadas**: Zero saltos indiretos, zero chamadas externas não resolvidas. Expansão de closure: **ZERO** (1.202 -> 1.205 funções cravadas).
- **Orçamento Total S1-283**: 3 funções novas, 3.696 bytes / **924 palavras**.
- **Cobertura Final S1-283**: **137.043 palavras (70,0686%)** em **1.205 funções nativas**. Codegen audit: **CLEAN**. **Marca de 70% de cobertura do binário oficialmente atingida**.
- **Validação em Gameplay (`gameplay-discovery-38`)**:
  - Erradicou 100% dos candidatos de ataque da sessão 34.
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: **0** mantidos estritamente.
  - Dispatches nativos: **+168.833 chamadas** em C nativo.
  - Linha de frametime: confirmada visualmente como extremamente limpa.

---

### S1-284: Movement & Sliding Subroutines - Blair Dame (Promovido & Validado)
- **Origem / Gatilho**: Teste inicial de Zangief vs Blair Dame (`gameplay-discovery-34`), que desmascarou o gap contínuo `0x8014901C..0x801495D4` responsável pelo processamento de deslize no solo (*sliding*), avanço pós-ataque e atrito/recuo de recuperação de solo.
- **Topologia & Limites (3 funções novas, 1.464 bytes / 366 palavras)**:
  - `0x8014901C`: 152 bytes / **38 palavras** (vetores de aceleração no solo e cálculo de deslize / sliding; **32 hits**).
  - `0x801490B4`: 268 bytes / **67 palavras** (transição de avanço e postura pós-ataque; **1 hit**).
  - `0x801491C0`: 1.044 bytes / **261 palavras** (processamento de atrito, recuo e recuperação de solo; **31 hits**).
- **Encaixe e Continuidade**: Conecta diretamente com `0x80148B64..0x8014901C` (função compilada anteriormente), estendendo a cobertura contínua desse bloco até `0x801495D4`.
- **Fechamento de Chamadas**: Zero saltos indiretos `jr $reg`, zero chamadas externas não resolvidas (closure 100% fechada). Expansão de closure: **ZERO** (1.205 -> 1.208 funções cravadas).
- **Orçamento Total S1-284**: 3 funções novas, 1.464 bytes / **366 palavras**.
- **Cobertura Final S1-284**: **137.409 palavras (70,2557%)** em **1.208 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-39`)**:
  - Erradicou 100% dos candidatos de movimento e sliding da sessão 34.
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0** (`candidates.txt` vazio).
  - Native Handoffs: **0** mantidos estritamente.
  - Linha de frametime: confirmada como extremamente estável durante todo o combate, com transient jitter restrito apenas ao carregamento inicial de cena/overlay.
- **Conclusão de Ciclo**: **Zangief (15º)** e **Blair Dame (16º)** oficialmente homologados com **100% de execução nativa** no Main EXE.

---

### S1-285: Acrobatic Action, Trajectory & Combat States - Skullomania (Preparado & Auditado)
- **Origem / Gatilho**: Teste inicial de Skullomania vs Ryu (`gameplay-discovery-40`), que desmascarou 22 candidatos no Main EXE e isolou o micro-ripple do *Skullo Dream* no hotspot dinâmico de RAM `0x80093E4C` (+13.966.308 insns sob interpretação).
- **Topologia & Limites (6 funções novas, 3.788 bytes / 947 palavras distribuídas em 3 gaps contínuos)**:
  - **Gap 1: Cálculo de Trajetória e Vetores Especiais (`0x8012A7E4..0x8012AA74`)**:
    - `0x8012A7E4`: 656 bytes / **164 palavras** (457 hits na entrada e 457 hits no retorno `0x8012AA54`; cálculo de vetores de salto e posicionamento de deslize; 5 chamadas JAL nativas).
  - **Gap 2: Motor de Ação Acrobática e Transformação 3D (`0x801441B0..0x80144AD8`)**:
    - `0x801441B0`: 156 bytes / **39 palavras** (238 hits; handler inicial de ataque acrobático).
    - `0x8014424C`: 332 bytes / **83 palavras** (14 hits na entrada e hits em `0x80144358` e `0x8014436C`; transição de mergulho / *Skullo Dive*).
    - `0x80144398`: 1.856 bytes / **464 palavras** (210 hits; processador central de rotação de malhas, ossos e hitboxes com 73 instruções COP2 GTE).
  - **Gap 3: Máquina de Estados de Ataques e Reações (`0x80160790..0x80160AA4`)**:
    - `0x80160790`: 80 bytes / **20 palavras** (hits em `0x80160790`, `0x801607C0`, `0x801607CC`; despacho de propriedades de ataque).
    - `0x801607E0`: 708 bytes / **177 palavras** (50 hits na entrada e múltiplos blocos internos `0x8016084C..0x80160A90`; loop central de estado de colisão e quebra de guarda).
- **Encaixe e Continuidade**:
  - Gap 1 conecta `0x8012A58C` a `0x8012AA74`.
  - Gap 2 conecta `0x801439E4` (S1-274 F1) a `0x80144AD8`.
  - Gap 3 conecta `0x80160480` a `0x80160AA4` (S1-270 F2).
- **Fechamento de Chamadas**: Todas as 36 chamadas diretas `JAL` apontam para funções já nativas ou internas ao lote. Expansão de closure: **ZERO** (1.208 -> 1.214 funções cravadas). Zero saltos indiretos (`jr $ra` estrito).
- **Orçamento Total S1-285**: 6 funções novas, 3.788 bytes / **947 palavras**.
- **Cobertura Final S1-285**: **138.356 palavras (70,7400%)** em **1.214 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-41`)**:
  - Erradicou 100% dos 22 candidatos da sessão 40 (`candidates.txt` vazio).
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: **0** mantidos estritamente.
  - Linha de frametime: confirmada como extremamente estável durante todo o combate, com micro-variação restrita exclusivamente ao loop do *Skullo Dream* em RAM dinâmica (`0x80093E4C`).
- **Conclusão de Ciclo**: **Skullomania (17º)** oficialmente homologado com **100% de execução nativa** no Main EXE.

---

### S1-286: GTE Vector Math Subroutine Cluster - Hokuto (Preparado & Auditado)
- **Origem / Gatilho**: Teste inicial de Hokuto vs Ryu (`gameplay-discovery-42`), que desmascarou apenas 1 único candidato residual no Main EXE (`0x8019D9FC`, 308 hits).
- **Topologia & Limites (10 funções folha contínuas, 500 bytes / 125 palavras)**:
  - Gap contínuo `0x8019D860..0x8019DA54`:
    - `0x8019D860`: 40 bytes / **10 palavras** (Transformação de rotação GTE; frameless folha; `jr $ra`).
    - `0x8019D888`: 40 bytes / **10 palavras** (Transformação de escala GTE; frameless folha; `jr $ra`).
    - `0x8019D8B0`: 60 bytes / **15 palavras** (Transformação de matriz composta GTE; frameless folha; `jr $ra`).
    - `0x8019D8EC`: 36 bytes / **9 palavras** (Multiplicação vetorial GTE; frameless folha; `jr $ra`).
    - `0x8019D910`: 40 bytes / **10 palavras** (Produto escalar GTE com clamp; frameless folha; `jr $ra`).
    - `0x8019D938`: 40 bytes / **10 palavras** (Produto vetorial GTE; frameless folha; `jr $ra`).
    - `0x8019D960`: 32 bytes / **8 palavras** (Projeção ortogonal GTE; frameless folha; `jr $ra`).
    - `0x8019D980`: 36 bytes / **9 palavras** (Normalização de vetor GTE; frameless folha; `jr $ra`).
    - `0x8019D9A4`: 88 bytes / **22 palavras** (Transformação de vértices e iluminação GTE; frameless folha; `jr $ra`).
    - `0x8019D9FC`: 88 bytes / **22 palavras** (Transformação vetorial MVMVA GTE; 308 hits; `jr $ra`).
- **Encaixe e Continuidade**: Conecta `0x8019D850..0x8019D85C` diretamente a `0x8019DA54..0x8019DA6C`, unificando toda a faixa `0x8019D740` até `0x8019DA6C` como um super-bloco compilado contínuo e 100% nativo.
- **Fechamento de Chamadas**: Todas as 10 funções são folhas puras frameless sem nenhuma chamada externa `JAL`. Expansão de closure: **RIGOROSAMENTE ZERO** (1.214 -> 1.224 funções cravadas). Zero saltos indiretos (`jr $ra` estrito).
- **Orçamento Total S1-286**: 10 funções novas, 500 bytes / **125 palavras**.
- **Cobertura Final S1-286**: **138.481 palavras (70,8038%)** em **1.224 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-43`)**:
  - Erradicou 100% do candidato residual `0x8019D9FC` da sessão 42 (`candidates.txt` vazio).
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: **0** mantidos estritamente.
  - Linha de frametime: confirmada como perfeitamente estável e limpa durante toda a luta.
- **Conclusão de Ciclo**: **Hokuto (18º)** oficialmente homologada com **100% de execução nativa** no Main EXE.

### S1-287: Dhalsim Mechanics & Bone Animation Pipeline (Preparado & Auditado)
- **Origem / Gatilho**: Teste inicial de Dhalsim vs Ryu (`gameplay-discovery-45`), que revelou exatamente 8 registros residuais no Main EXE (total de 2.002 hits):
  - `0x80194BB4` (1.728 hits), `0x8014B430` (72 hits), `0x8014B21C` (46 hits), `0x8014B6B0` (40 hits), `0x8014B524` (36 hits), `0x8014B580` (36 hits), `0x8015A530` (31 hits), `0x8014B2B4` (2 hits).
- **Desmistificação dos Endereços de Retorno**:
  - A auditoria de desmonte MIPS revelou que `0x8014B430`, `0x8014B524` e `0x8014B580` não são raízes de funções, mas sim sítios de retorno de chamadas `jal` (`0x801945F8` e `0x8019C0B8`) situados dentro da função `0x8014B2B4`. Com o chamador no interpretador e o callee nativo, o retorno ativava o fallback no PC seguinte.
- **Topologia & Limites (9 funções em 3 clusters, 3.120 bytes / 780 palavras)**:
  - **Cluster Dhalsim (`0x8014B21C..0x8014BA4C`, 2.096 bytes / 524 palavras)**:
    - `0x8014B21C`: 152 bytes / **38 palavras** (Dispatch raiz de Dhalsim na tabela `0x801B1BA8`; chama `0x8014B2B4`, `0x8014B6B0` e `0x80123AE0`).
    - `0x8014B2B4`: 1.020 bytes / **255 palavras** (Cálculo cinemático de alcance e deformação elástica dos membros).
    - `0x8014B6B0`: 924 bytes / **231 palavras** (Atualização de posturas e caixas de colisão elásticas do Dhalsim).
  - **Cluster Yoga Fire (`0x8015A530..0x8015A600`, 208 bytes / 52 palavras)**:
    - `0x8015A530`: 208 bytes / **52 palavras** (Física e colisão de projétil de fogo; folha pura com epílogo `jr $ra` em `0x8015A5F8`).
  - **Cluster Pipeline de Animação (`0x80194BB4..0x80194EE4`, 816 bytes / 204 palavras)**:
    - `0x80194BB4`: 96 bytes / **24 palavras** (Cálculo de ossos de animação; folha pura; 1.728 hits).
    - `0x80194C14`: 108 bytes / **27 palavras** (Matriz de orientação de ossos; folha pura).
    - `0x80194C80`: 56 bytes / **14 palavras** (Indexação e limites de joints; folha pura).
    - `0x80194CB8`: 384 bytes / **96 palavras** (Aplicação de transformadas e chamadas a `0x8019528C`).
    - `0x80194E38`: 172 bytes / **43 palavras** (Aplicação de transformada secundária).
- **Fechamento de Chamadas (Closure)**:
  - Todos os 13 alvos de saltos `jal` mapeados já são nativos (`0x80123AE0`, `0x801938B0`, `0x80194990`, `0x801948DC`, `0x801946C8`, `0x801945F8`, `0x8019C184`, `0x8019C0B8`, `0x8019CE70`, `0x8019D740`, `0x8019D7D0`, `0x8010C72C`, `0x8019528C`) ou estão inclusos no lote (`0x8014B2B4`, `0x8014B6B0`). Expansão de closure: **ZERO**.
- **Orçamento Total S1-287**: 9 funções novas, 3.120 bytes / **780 palavras**.
- **Cobertura Final S1-287**: **139.261 palavras (71,2026%)** em **1.233 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-46`)**:
  - Erradicou 100% dos 8 candidatos residuais da sessão 45 (`candidates.txt` vazio).
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: **0** mantidos estritamente.
  - Páginas Divergidas: **0**.
  - Linha de frametime: confirmada como extremamente limpa e estável durante toda a luta.
- **Conclusão de Ciclo**: **Dhalsim (19º)** oficialmente homologado com **100% de execução nativa** no Main EXE.
- **Homologação Imediata: Cycloid-β (20º Personagem Nativo)**:
  - Testado na sessão `gameplay-discovery-47` (Cycloid-β vs Ryu, Cenário Ryu).
  - Resultados: **EXATAMENTE 0 candidatos no Main EXE** (`candidates.txt` vazio), 0 native handoffs, 0 páginas divergidas, frametime estável e limpo.
  - Como o moveset de Cycloid-β compartilha dispatches e mecânicas cinemáticas já promovidas, ele rodou 100% nativo logo no primeiro teste.
- **Homologação: Cycloid-γ (21º Personagem Nativo)**:
  - Testado na sessão `gameplay-discovery-48` (Cycloid-γ vs Ryu, Cenário Ryu).
  - Resultados no Main EXE: **EXATAMENTE 0 candidatos a promoção estática** (`candidates.txt` vazio), 339.883 static hits (100% de dispatches estáticos nativos), 0 native handoffs, 0 páginas divergidas.
  - Diagnóstico Técnico do Frametime: A oscilação na linha de frametime não proveio do Main EXE (Track 1, que rodou 100% nativo), mas sim do **Overlay Dinâmico em RAM (Track 2, `0x80040000..0x80090000`)**, cujo total de instruções interpretadas saltou para 40,85 milhões (+6,7M em relação ao Beta), com novos hotspots pesados em `0x80048930` (462k insns) e `0x8004880C` (177k insns) devido aos golpes especiais e teleports do personagem.
- **Homologação Imediata: Bloody Hokuto (22º Personagem Nativo)**:
  - Testado na sessão `gameplay-discovery-49` (Bloody Hokuto vs Ryu, Cenário Ryu).
  - Resultados: **EXATAMENTE 0 candidatos no Main EXE** (`candidates.txt` vazio), 195.889 static hits, 0 native handoffs, 0 páginas divergidas, frametime estável e limpo (volume interpretado em RAM caiu para apenas 25,4M insns).
  - Como Bloody Hokuto compartilha integralmente as sub-rotinas de matriz e cinemática da Hokuto padrão (promovidas em S1-286), ela executou 100% nativa sem nenhum miss.
- **Homologação Imediata: Evil Ryu (23º Personagem Nativo - ELENCO 100% COMPLETO)**:
  - Testado na sessão `gameplay-discovery-50` (Evil Ryu vs Ryu, Cenário Ryu).
  - Resultados: **EXATAMENTE 0 candidatos no Main EXE** (`candidates.txt` vazio), 219.488 static hits, 0 native handoffs, 0 páginas divergidas, frametime perfeitamente limpo e estável.
  - Como Evil Ryu compartilha a base cinemática, dispatches de projéteis (Hadouken) e transformadas de animação com Ryu e Akuma, ele executou 100% nativo sem nenhum miss.
  - **MARCO HISTÓRICO CONCLUÍDO**: **100% dos 23 personagens de Street Fighter EX Plus Alpha estão oficialmente homologados e executam de forma nativa no Main EXE!**

### S1-288: Boot Sequence & Attract/Demo Presentation Pipeline (Preparado & Auditado)
- **Origem / Gatilho**: Varredura de "pente fino" do boot e attract mode (`gameplay-discovery-51`, rota: Boot -> Logos Capcom/Arika -> Vídeo/Render 3D de Apresentação -> Tela Título), que revelou 14 registros residuais no Main EXE:
  - `0x80136648` (1.134 hits), `0x80136824` (1.134 hits), `0x80136AC8` (478 hits), `0x80136D38` (450 hits), `0x80136F5C` (350 hits), `0x8013701C` (350 hits), `0x80102488` (85 hits), `0x80136B64` (16 hits), `0x80136DEC` (16 hits), `0x80136C44` (8 hits), `0x80136C8C` (8 hits), `0x8010250C` (3 hits), `0x80102520` (3 hits), `0x801366E4` (3 hits).
- **Desmistificação dos Endereços de Retorno**:
  - 6 dos 14 registros são sítios de retorno de chamadas `jal` nativas dentro das funções que estavam no interpretador:
    - `0x8010250C` e `0x80102520` (retornos de `jal 0x80194B00` dentro de `0x80102488`).
    - `0x80136C44` e `0x80136C8C` (retornos de `jal 0x801945F8` dentro de `0x80136B64`).
    - `0x80136DEC` (retorno de `jal 0x8016864C` dentro de `0x80136D38`).
    - `0x8013701C` (retorno de `jal 0x8019C0B8` dentro de `0x80136F5C`).
- **Topologia & Limites (8 funções em 2 clusters, 3.888 bytes / 972 palavras)**:
  - **Cluster Setup de Vídeo / Display Pós-Boot (`0x80102488..0x80102838`, 944 bytes / 236 palavras)**:
    - `0x80102488`: 944 bytes / **236 palavras** (Setup inicial de buffers de pacotes de display e inicialização de rendering contexts; fecha perfeitamente o gap entre `0x801021B0` e `0x80102838`).
  - **Cluster Cadeia Contínua de Attract & Demo Play (`0x80136648..0x801371C8`, 2.944 bytes / 736 palavras)**:
    - `0x80136648`: 156 bytes / **39 palavras** (Sequenciador principal do modo Attract / Demo; 1.134 hits).
    - `0x801366E4`: 320 bytes / **80 palavras** (Controle de câmera, projeção e frustum da apresentação; 3 hits).
    - `0x80136824`: 676 bytes / **169 palavras** (Render e matrizes 3D do logotipo do jogo; 1.134 hits).
    - `0x80136AC8`: 156 bytes / **39 palavras** (Dispatcher de combate da demonstração automática; 478 hits).
    - `0x80136B64`: 468 bytes / **117 palavras** (Cinemática e colisões da luta demo; 16 hits).
    - `0x80136D38`: 548 bytes / **137 palavras** (Rotina de IA e seleção de ações na demo; 450 hits).
    - `0x80136F5C`: 620 bytes / **155 palavras** (Resolvedor de animações e matrizes na demo; 350 hits).
- **Fechamento de Chamadas (Closure)**:
  - Todas as chamadas `jal` externas são para rotinas já nativas (`0x80194B00`, `0x80194A44`, `0x801948DC`, `0x80194828`, `0x80123BF4`, `0x8019DF20`, `0x8019CD60`, `0x8019CE70`, `0x8019D740`, `0x8019D7D0`, `0x8019D7A0`, `0x8019D770`, `0x8010D1E8`, `0x80194990`, `0x801946C8`, `0x801945F8`, `0x8016864C`, `0x8010C72C`, `0x8019C0B8`, `0x8019C184`).
  - Chamadas internas ao lote: `0x801366E4`, `0x80136824`, `0x80136B64`, `0x80136D38`, `0x80136F5C`. Expansão de closure: **RIGOROSAMENTE ZERO**.
- **Orçamento Total S1-288**: 8 funções novas, 3.888 bytes / **972 palavras**.
- **Cobertura Final S1-288**: **140.233 palavras (71,6996%)** em **1.241 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay / Boot (`gameplay-discovery-52`)**:
  - Erradicou 100% dos 14 candidatos residuais da sessão 51 (`candidates.txt` vazio).
  - Novos candidatos a promoção no Main EXE: **EXATAMENTE 0**.
  - Native Handoffs: **0** mantidos estritamente.
  - Páginas Divergidas: **0**.
  - Linha de frametime: confirmada como extremamente estável e limpa em todas as telas testadas (logos, render intro, demo fight e tela título).
- **Conclusão de Ciclo**: Inicialização e modo attract 100% nativos no Main EXE. Cobertura estática ultrapassa o marco histórico de 140.000 palavras (71,6996%).

---

### Micro-Lote S1-289: Training Mode HUD & Input Processing Pipeline (Cluster 1)

- **Origem da Descoberta**: Telemetria de combate e treino em `gameplay-discovery-57` (Evil Ryu x Ken no Cenário Training).
- **Diagnóstico Preliminar**:
  - Foram observados 25 candidatos no Main EXE, distribuídos em 4 clusters distintos.
  - Para manter a segurança estrita do projeto e evitar sobrecarga de quase 2.000 palavras (especialmente o risco de closure do Cluster 4 / Pause Menu), adotou-se a estratégia de isolamento por cluster independente.
  - O Micro-Lote S1-289 foca exclusivamente no **Cluster 1** (HUD de comandos, contagem de combo e dano).
- **Funções Promovidas no S1-289 (3 funções, 812 bytes / 203 palavras)**:
  - `0x8013BFA8`: 164 bytes / **41 palavras** (Loop principal de inputs e HUD do modo treino; 7.510 hits).
  - `0x8013C04C`: 32 bytes / **8 palavras** (Limpeza e reset dos buffers de texto/quadros do HUD; 1 hit).
  - `0x8013C06C`: 616 bytes / **154 palavras** (Renderizador de dano acumulado, contagem de combo e inputs; 6.856 hits).
- **Desmistificação de Retornos de Chamada**:
  - A promoção de `0x8013C06C` absorve e elimina 3 registros de retorno de `jal 0x80193A18` (render de fonte na tela):
    - `0x8013C108` (6.856 hits)
    - `0x8013C160` (6.856 hits)
    - `0x8013C188` (6.856 hits)
  - Abutment perfeito: o fim de `0x8013C06C` conecta-se diretamente ao range compilado existente em `0x8013C2D4`.
- **Fechamento de Chamadas (Closure)**:
  - Chamadas externas de `0x8013C06C`: `0x80193A18` (render de fontes, já nativo) e `0x80125154` (já nativo).
  - Chamadas internas ao cluster: `0x8013BFA8` chama `0x8013C04C` e `0x8013C06C`.
  - Expansão de closure: **RIGOROSAMENTE ZERO**.
- **Orçamento Total S1-289**: 3 funções novas, 812 bytes / **203 palavras**.
- **Cobertura Final S1-289**: **140.436 palavras (71,8034%)** em **1.244 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-58`)**:
  - Erradicação de 100% dos candidatos do Cluster 1 (`candidates.txt` sem qualquer registro de `0x8013BFA8`, `0x8013C04C`, `0x8013C06C` ou seus retornos).
  - Mais de 28.000 chamadas interpretadas convertidas para execução nativa C.
  - 511.834 static hits nativos sem nenhum miss ou handoff.

---

### Micro-Lote S1-290: Training Stage 3D Grid & Camera Pipeline (Cluster 2)

- **Origem da Descoberta**: Telemetria de combate e treino em `gameplay-discovery-57` e `gameplay-discovery-58`.
- **Topologia & Limites**:
  - Preenche integralmente a lacuna contígua `[0x80148678..0x8014901C]` (2.468 bytes / 617 palavras) entre os blocos já nativos `[0x80148184..0x80148678]` e `[0x8014901C..0x801491C0]`.
- **Funções Promovidas no S1-290 (3 funções, 2.468 bytes / 617 palavras)**:
  - `0x80148678`: 152 bytes / **38 palavras** (Despachante raiz do ambiente 3D do Training Stage; 102 hits).
  - `0x80148710`: 1.108 bytes / **277 palavras** (Projeção de câmera, frustum e perspectiva do cenário; 3 hits).
  - `0x80148B64`: 1.208 bytes / **302 palavras** (Iluminação e transformação de vértices do grid do chão via GTE; 93 hits).
- **Desmistificação de Retornos de Chamada**:
  - A promoção de `0x80148710` absorve os retornos de `jal 0x801945F8` (GTE) em `0x801487DC` e `0x801487F8`.
  - A promoção de `0x80148B64` absorve o retorno de `jal 0x8019C0B8` (GTE) em `0x80148C74`.
  - Erradica 6 registros observados na telemetria.
- **Fechamento de Chamadas (Closure)**:
  - Todas as chamadas `jal` (`0x80148710`, `0x80148B64`, `0x80123AE0`, `0x801938B0`, `0x80194990`, `0x801948DC`, `0x801945F8`, `0x801946C8`, `0x80194904`, `0x8019DF20`, `0x8019D270`, `0x8019D7D0`, `0x8019D740`, `0x8019C0B8`, `0x8019C184`, `0x8019DA70`, `0x8010C72C`) já são nativas.
  - Expansão de closure: **RIGOROSAMENTE ZERO**.
- **Orçamento Total S1-290**: 3 funções novas, 2.468 bytes / **617 palavras**.
- **Cobertura Final S1-290**: **141.053 palavras (72,1188%)** em **1.247 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-59`)**:
  - Erradicação de 100% dos candidatos do Cluster 2 (`candidates.txt` sem qualquer registro de `0x80148678`, `0x80148710`, `0x80148B64` ou seus retornos GTE).
  - Lacuna `[0x80148678..0x8014901C]` 100% preenchida.
  - 497.503 static hits nativos sem nenhum miss ou handoff.
  - Marco histórico de 141.000 palavras compiladas estaticamente superado.

---

### Micro-Lote S1-291: Training Mode Dummy AI, Recovery & Damage Tracking Pipeline (Cluster 3)

- **Origem da Descoberta**: Telemetria de combate e treino em `gameplay-discovery-57`, `58` e `59` (Evil Ryu x Ken no Cenário Training).
- **Mecanismo de Despacho**:
  - Despachado dinamicamente via tabela indireta `0x801B2E64` (chamada via `jalr` em `0x801551BC` e `0x80158038`).
  - Controla o ciclo de IA do boneco de treino (Ken), detecção de postura, auto-bloqueio (guard), recuperação de queda e acúmulo de dano de combos.
- **Funções Promovidas no S1-291 (7 funções, 1.000 bytes / 250 palavras)**:
  - `0x801555A8`: 20 bytes / **5 palavras** (Incrementador de timer e estado da IA do dummy; 1.047 hits).
  - `0x801555BC`: 76 bytes / **19 palavras** (Lookup de postura e ação na tabela `0x801B3088`; 1.933 hits).
  - `0x801556E4`: 104 bytes / **26 palavras** (Handler de estado de ação secundária do dummy; 26 hits).
  - `0x80156190`: 172 bytes / **43 palavras** (Rotina de recuperação de knockdown e levantada; 1.645 hits).
  - `0x80156458`: 164 bytes / **41 palavras** (Lógica de auto-bloqueio / guard inteligente do dummy; 1.168 hits).
  - `0x801569B0`: 288 bytes / **72 palavras** (Acúmulo de dano e reação a impactos; 1.334 hits).
  - `0x80156AD0`: 176 bytes / **44 palavras** (Gestão da barra de super do dummy; 267 hits).
- **Desmistificação de Retornos de Chamada (7 retornos absorvidos)**:
  - A promoção de `0x80156190` absorve o retorno de `jal 0x8015E12C` em `0x80156210`.
  - A promoção de `0x80156458` absorve os retornos de `jal 0x8015E12C` em `0x801564AC` e `0x801564D8`.
  - A promoção de `0x801569B0` absorve os retornos de `jal 0x8015D8E4` em `0x80156A1C` e `0x80156A6C`, e de `jal 0x8015E12C` em `0x80156A94`.
  - A promoção de `0x80156AD0` absorve o retorno de `jal 0x8015E12C` em `0x80156B70`.
  - Erradica **14 candidatos de uma só vez** em `candidates.txt`.
- **Fechamento de Chamadas (Closure)**:
  - Todas as sub-rotinas chamadas (`0x8015E12C`, `0x8015D474`, `0x8015D8E4`) já são nativas no Main EXE.
  - Chamada interna: `0x801569B0` chama `0x80156AD0`.
  - Expansão de closure: **RIGOROSAMENTE ZERO**.
- **Orçamento Total S1-291**: 7 funções novas, 1.000 bytes / **250 palavras**.
- **Cobertura Final S1-291**: **141.303 palavras (72,2467%)** em **1.254 funções nativas**. Codegen audit: **CLEAN**.
- **Validação em Gameplay (`gameplay-discovery-60`)**:
  - Erradicação de 100% dos candidatos do Cluster 3 (14 candidatos a menos em `candidates.txt`).
  - Mais de 610.000 static hits nativos (marca recorde de 610.907 hits) sem nenhum miss ou handoff.

---

### Micro-Lote S1-292: Combat Callback Stub Pipeline

- **Origem da Descoberta**: Telemetria de combate em `gameplay-discovery-60`.
- **Topologia & Estrutura**:
  - `0x80162680`: 8 bytes / **2 palavras** (Stub folha `jr ra; nop` na tabela de callbacks `0x801B3408`; 2 hits).
  - Abutment perfeito: conecta-se ao range nativo `[0x80162688..0x801627A4]`.
- **Decisão Arquitetural do Menu de Pausa**:
  - O subsistema de Menu de Pausa (`0x80172DD0..0x8017566C`, ~2.599 palavras / 10 funções) foi intencionalmente postergado por solicitação do operador para uma bateria de testes dedicada focada em explorar as telas de pausa de todos os modos de jogo.
- **Fechamento de Chamadas (Closure)**:
  - Função folha pura sem filhas. Expansão de closure: **RIGOROSAMENTE ZERO**.
- **Orçamento Total S1-292**: 1 função nova, 8 bytes / **2 palavras**.
- **Meta de Cobertura S1-292**: **141.305 palavras (72,2477%)** em **1.255 funções nativas**.

---

### Micro-Lote S1-293: CPU AI Core Engine Pipeline (Clusters 1 e 2)

- **Origem da Descoberta**: Telemetria de combate da CPU Level 8 (Ryu vs Ryu, Suzaku Castle) em `gameplay-discovery-65`.
- **Topologia & Estrutura**:
  - **Cluster 1 (Gap 2)**:
    - `0x80155608`: 220 bytes / **55 palavras** (Ponte entre `0x801555BC` e `0x801556E4`; 40 hits; única chamada externa é `jal 0x80123910`, que já é 100% nativa).
  - **Cluster 2 (Gap 7)**:
    - `0x80158050`: 68 bytes / **17 palavras** (Despachante e helper central de ataque da CPU; 216 hits; invocado por 25 rotinas de ataque do Cluster 6; chama internamente `0x80158094`).
    - `0x80158094`: 224 bytes / **56 palavras** (Loop folha de verificação de timers e frames de golpes da CPU; 57 hits; zero chamadas externas).
    - `0x80158174`: 32 bytes / **8 palavras** (Rotina folha de incremento e contagem de estado de ação da CPU; 74 hits; zero chamadas externas).
- **Abutment Estrutural**:
  - `0x80155608` encaixa-se exatamente entre as nativas `0x801555BC..0x80155608` e `0x801556E4..0x8015574C`.
  - `0x80158050..0x80158194` conecta diretamente as nativas `0x80157F2C..0x80158050` e `0x80158194..0x801582B8`.
- **Fechamento de Chamadas (Closure)**:
  - Todas as chamadas são para funções já nativas ou internas ao cluster. Expansão de closure: **RIGOROSAMENTE ZERO**.
- **Orçamento Total S1-293**: 4 funções novas, 544 bytes / **136 palavras**.
- **Meta de Cobertura S1-293**: **141.441 palavras (72,3172%)** em **1.259 funções nativas**.
- **Validação em Gameplay (`gameplay-discovery-66`)**:
  - Validado em combate direto contra Ryu CPU Level 8.
  - Erradicação de 100% dos 4 alvos promovidos (`0x80155608`, `0x80158050`, `0x80158094`, `0x80158174` caíram para ZERO hits).
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Lote S1-294: CPU AI Core Engine Pipeline (Cluster 3 / Gap 4)

- **Origem da Descoberta**: Telemetria de combate da CPU Level 8 em `gameplay-discovery-66` (382 hits).
- **Topologia & Estrutura**:
  - `0x8015623C`: 216 bytes / **54 palavras** (Rotina folha de guarda e temporização defensiva da CPU; 139 hits; zero chamadas externas).
  - `0x80156314`: 324 bytes / **81 palavras** (Cálculo de espaçamento neutro e reação a projéteis; 243 hits; única chamada externa é `jal 0x80123910`, já nativa).
- **Abutment Estrutural**:
  - Preenche 100% da lacuna entre a função nativa `0x80156190..0x8015623C` e a função nativa `0x80156458..0x801564FC`.
- **Fechamento de Chamadas (Closure)**:
  - Nenhuma nova dependência externa. Expansão de closure: **RIGOROSAMENTE ZERO**.
- **Orçamento Total S1-294**: 2 funções novas, 540 bytes / **135 palavras**.
- **Meta de Cobertura S1-294**: **141.576 palavras (72,3862%)** em **1.261 funções nativas**.
- **Validação em Gameplay (`gameplay-discovery-67`)**:
  - Validado em combate direto contra Ryu CPU Level 8.
  - Erradicação de 100% dos 2 alvos promovidos (`0x8015623C` e `0x80156314` caíram para ZERO hits).
  - Total de candidatos residuais no Main EXE caiu de 49 para 40 candidatos.
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Lote S1-295: CPU AI Core Engine Pipeline (Cluster 4 / Gap 5)

- **Origem da Descoberta**: Telemetria de combate da CPU Level 8 em `gameplay-discovery-67`.
- **Topologia & Estrutura**:
  - `0x801564FC`: 152 bytes / **38 palavras** (Helper de lookup de alvos de combate; sem chamadas externas).
  - `0x80156594`: 164 bytes / **41 palavras** (Despacho de aproximação da CPU; 10 hits; chama internamente `0x801566E4`).
  - `0x80156638`: 172 bytes / **43 palavras** (Despacho de recuo tático da CPU; chama internamente `0x801566E4`).
  - `0x801566E4`: 296 bytes / **74 palavras** (Rotina central de tracking horizontal e movimentação; 60 hits; sem chamadas externas).
  - `0x8015680C`: 236 bytes / **59 palavras** (Verificação de colisão e corner pressure; 50 hits; chama internamente `0x801566E4`).
  - `0x801568F8`: 184 bytes / **46 palavras** (Temporizador de pulo e lógica anti-air; 1 hit; sem chamadas externas).
- **Abutment Estrutural**:
  - Preenche 100% da lacuna entre a função nativa `0x80156458..0x801564FC` e a função nativa `0x801569B0..0x80156AD0`.
- **Fechamento de Chamadas (Closure)**:
  - Todas as chamadas são estritamente internas para `0x801566E4`. Expansão de closure: **RIGOROSAMENTE ZERO**.
- **Orçamento Total S1-295**: 6 funções novas, 1.204 bytes / **301 palavras**.
- **Meta de Cobertura S1-295**: **141.877 palavras (72,5401%)** em **1.267 funções nativas**.
- **Validação em Gameplay (`gameplay-discovery-68`)**:
  - Validado em combate direto contra Ryu CPU Level 8.
  - Erradicação de 100% dos 6 alvos promovidos (`0x801564FC..0x801568F8` caíram para ZERO hits), além dos offsets internos associados.
  - Conexão contígua de todo o segmento `0x80156190..0x80156B80` (quase 2,5 KB) 100% nativo.
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

## 3. Dynamic Overlay Track History

Overlays are dynamically loaded into RAM (`0x80020000..0x800F2000`) during fights and character-specific modes.

### OVL-001 Series (Core Battle Engine)
- **OVL-001A (`0x00020000:0xAC1FF1A4`)**:
  - 64 entries (22 roots, 42 internal entries), 4,563 reachable MIPS words.
  - Dominant PCs: `0x8004A44C`, `0x80091878`, `0x8004922C`, `0x80049500`.
  - Telemetry soak: 1,232,009 native dispatches over 3 complete matches with zero fallback and average 59.93 FPS. Approved as isolated dynamic checkpoint.
- **OVL-001B (`0x00020000:0x94E6122F`)**:
  - 122 entries (32 roots, 90 internal entries), 5,313 reachable words. Validated under S1-261 clean baseline.

### OVL-002 Series (Character Action Engine - Doctrine Dark & Ryu)
- **OVL-002A (`0x80092C2C` & `0x80092F00`)**: Core frame update routines for player 1 and player 2.
- **OVL-002B**: Closure resolution for `0x80092C2C`.
- **OVL-002C through OVL-002G (D.Dark Bomb Subsystem)**:
  - Addressed bomb placement, timing, guard checks, and detonation handlers (`0x80045E30`, `0x80045F00`, `0x80045F80`, `0x80045F94`, `0x80045FF8`).
  - Total 2,563 words verified clean across 4 test phases (unhit, hit, blocked, and special).
- **OVL-002H (`0x800465A8`)**: Super explosive bomb throw handler (239 words, jump table `0x8004A610` with 6 targets). Telemetry verified CLEAN with zero fallback.
