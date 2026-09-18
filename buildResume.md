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
