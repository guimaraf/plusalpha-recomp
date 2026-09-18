# Registro de Personagens 100% Nativos (Main EXE SLUS-005.48)

Este documento registra os personagens testados e homologados com **100% de execução nativa** no executável estático (`Main EXE`), detalhando sessões de validação, subsistemas cobertos e o mapeamento de casos especiais de overlay dinâmico (Track 2) a serem tratados posteriormente.

---

## 1. Tabela de Homologação de Personagens (Track 1 - Main EXE)

| Personagem | Status Main EXE | Sessão Validadora | Checkpoint | Cobertura Estática de Golpes / Ações |
|---|:---:|---|:---:|---|
| **Ryu** | **100% Nativo** (0 misses) | Baselines Iniciais | S1-266 | Hadouken, Shoryuken, Tatsumaki Senpuukyaku, Shinku Hadouken, colisões normais e supers. |
| **Ken** | **100% Nativo** (0 misses) | Baselines Iniciais | S1-266 | Shoryuken flamejante, Hadouken, Tatsumaki, Shoryu Reppa, Shinryuken, transições de combo. |
| **Garuda** | **100% Nativo** (0 misses) | `gameplay-discovery-08` | S1-270 | Soukon Dan, Kizan, Raiga, projéteis múltiplos, espinhos e transformações de malha. |
| **Kairi** | **100% Nativo** (0 misses) | `gameplay-discovery-08` | S1-270 | Shinki Hatsu Dou, Maryu Rekkou, Shoushuu Renbu, recuo e cancelamentos de ataque. |
| **Akuma (Gouki)** | **100% Nativo** (0 misses) | `gameplay-discovery-13` & `16` | S1-273 / S1-274 | Gou-Hadouken, Shakunetsu, Gou-Shoryuken, Tatsumaki aéreo/chão, Messatsu Gou Shoryu. |
| **M. Bison (Vega)** | **100% Nativo** (0 misses) | `gameplay-discovery-15`, `16`, `17` | S1-274 | Psycho Shot, Double Knee Press, Head Press, Somersault Skull Diver, Knee Press Nightmare. |
| **Chun-Li** | **100% Nativo** (0 misses) | `gameplay-discovery-20` | S1-275 | Hyakuretsu Kyaku, Kikoken, Spinning Bird Kick, Hazan Tenshou Kyaku, Senretsu Kyaku, cancelamentos e golpes de carga. |
| **Guile** | **100% Nativo** (0 misses) | `gameplay-discovery-22` | S1-276 | Sonic Boom, Flash Kick (Somersault), ataques normais de carga, Opening Gambit, Double Somersault. |
| **Sakura** | **100% Nativo** (0 misses) | `gameplay-discovery-25` | S1-277 | Hadoken, Shouoken (antiação), Shunpukyaku, Midare Zakura, Haru Ichiban, cancelamentos e colisões vetoriais. |
| **Pullum Purna** | **100% Nativo** (0 misses) | `gameplay-discovery-26` | S1-277 | Drill Purrus, Tenresuu, Prim Rose, Prapera Dance, Resall Dance, Gradus Pearl, transições e giros. |
| **Doctrine Dark** | **100% Nativo** (0 misses) | `gameplay-discovery-28` | S1-278 | Kill Wire, Dark Wire, facadas, Dark EX-Plo (bombas), Dark Shackle, Kill Sword, transições de combate. |
| **Darun Mister** | **100% Nativo** (0 misses) | `gameplay-discovery-30` | S1-279 | Lariat, Ganga Lariat, Brahma Lariat, Indra Bridge, Daisharin, Twilight Collar, Hasin Shake. |
| **Cracker Jack** | **100% Nativo** (0 misses) | `gameplay-discovery-31` & `33` | S1-280 | Dash Straight, Dash Upper, Batting Hero, Soccer Ball Kick, Crazy Jack, Raging Buffalo, Home Run Hero, cenário e props. |
| **Allen Snider** | **100% Nativo** (0 misses) | `gameplay-discovery-31` & `33` | S1-280 | Soul Force, Justice Fist, Vaulting Kick, Rising Dragon, Fire Force, Triple Break, transições de golpe e cenário. |
| **Zangief** | **100% Nativo** (0 misses) | `gameplay-discovery-36` & `37` | S1-281 / S1-282 | Spinning Piledriver, Atomic Suplex, Final Atomic Buster, Double Lariat, Banishing Flat, tabela global de agarrões `0x801B33F0`. |
| **Blair Dame** | **100% Nativo** (0 misses) | `gameplay-discovery-38` & `39` | S1-283 / S1-284 | Shoot Kick, Lightning Knee, Sliding D-Kick, Spin Kick, Mirage Kick, ação/combate `0x8013E930`, vetores de deslizamento `0x8014901C`. |
| **Skullomania** | **100% Nativo** (0 misses) | `gameplay-discovery-40` & `41` | S1-285 | Skullo Crusher, Skullo Slider, Skullo Head, Skullo Dive, Skullo Dash, Super Skullo Crusher/Slider, trajetória `0x8012A7E4`, ação acrobática 3D `0x801441B0..AD8`, máquina de combate `0x80160790..AA4`. |

---

## 2. Micro-Relatório de Casos Especiais & Arquitetura de Overlays (Track 2)

Durante os testes de combate de alta densidade, o isolamento de telemetria desmascarou a divisão exata entre o código estático da ROM (`SLUS-005.48`) e os módulos dinâmicos carregados em RAM (`0x80020000..0x800F2000`).

### Caso 1: Teleporte do Akuma (*Ashura Senku*)
- **Comportamento Observado**: Ao executar repetidamente o teleporte do Akuma, notou-se uma leve variação (micro-ripple) na linha de frametime, enquanto o restante do combate manteve estabilidade cravada a 60 FPS.
- **Diagnóstico Técnico**:
  - O Main EXE permaneceu com **EXATAMENTE 0 MISSES**.
  - A variação decorre da rotina em RAM dinâmica **`0x80045ACC`** (região `0x80045000..0x80046000`, Capture 1 em `overlay_captures.json`), que disparou um pico de **+31.318 instruções interpretadas** no fallback.
  - Essa rotina é responsável pelo loop de cálculo de sombras/rastros translúcidos e controle de frames de invulnerabilidade do teleporte.
- **Tratamento Planejado (Track 2)**:
  - Não deve ser adicionada a `seeds/entry_funcs.txt` (não existe no arquivo físico `SLUS_005.48`).
  - Será compilada nativamente via framework de **Overlay Cache / TCC JIT** na etapa dedicada aos módulos dinâmicos em RAM.

---

### Caso 2: Pisão e Efeito de Chamas do Bison (*Head Press & Somersault Skull Diver*)
- **Comportamento Observado**: Teste intensivo de acertos e *whiffs* do pisão com mãos e pés em chamas (`gameplay-discovery-17`).
- **Diagnóstico Técnico**:
  - O Main EXE registrou um novo recorde de **+210.765 dispatches nativos** e **ZERO misses** (0 novos candidatos estáticos).
  - Toda a física macro de colisão, despacho de ações e gerenciamento de rounds rodou 100% em C nativo.
  - A lógica específica do golpe, os pontos de ancoragem das chamas (*VFX particle emitters*) e os vetores de descida do *Skull Diver* rodaram no bloco de overlay dinâmico em RAM:
    - **`0x8004485C` até `0x80044DE8`**: Bloco de rotinas com ~40.000 execuções cada.
    - **`0x80093588` e `0x80093D70`**: Renderizador dinâmico de sprites/efeitos em RAM (~16,4 milhões de instruções).
- **Tratamento Planejado (Track 2)**:
  - O conjunto `0x80044xxx` compõe o módulo de habilidades exclusivas do Bison em RAM e será tratado no lote de overlays de personagens.

---

### Caso 3: Poses de Introdução, Comemoração e Replay da Chun-Li
- **Comportamento Observado**: Leve variação transitória na linha de frametime nas bordas da luta (início do round e tela de K.O./vitória), com frametime cravado e ultra-estável a 60 FPS durante todo o combate ativo (`gameplay-discovery-20`).
- **Diagnóstico Técnico**:
  - O Main EXE registrou **EXATAMENTE 0 MISSES** e o fallback interpretado despencou de 9,15M para apenas 111k instruções (-98,8%).
  - A variação transitória decorre das rotinas em RAM dinâmica:
    - **`0x80048960`**: Inicialização de esqueleto/animação de entrada (~8,9 milhões de instruções interpretadas em RAM).
    - **`0x80046EEC` e `0x800477D0`**: Pose de vitória ("Yatta!") e processamento pós-K.O. (~4 milhões de instruções).
- **Tratamento Planejado (Track 2)**:
  - Rotinas em RAM tratadas via cache dinâmico / TCC sharding para eliminação de qualquer ripple nas bordas do round.

---

### Caso 4: Cenário e Action Subsystem de Cracker Jack & Allen Snider (Micro-lote S1-280)
- **Comportamento Observado**: Micro-variações contínuas na linha de frametime durante a partida com Cracker Jack no seu cenário (`gameplay-discovery-32`), enquanto o primeiro teste (`gameplay-discovery-31`) registrou zero misses mas alto custo de overlay em RAM.
- **Diagnóstico Técnico**:
  - A rota do cenário e postura de P2 de Cracker Jack acionou a entrada `0x801AFC80` da Action Dispatch Table, despachando para um gap estático no Main EXE (`0x8011A8DC..0x8011B3B8`).
  - Uma única rotina interna, **`0x8011AFBC`**, foi chamada **153.072 vezes** pelo interpretador de fallback (média de ~64 chamadas/frame), gerando chaveamento massivo entre x64 e MIPS.
- **Resolução Implementada (S1-280)**:
  - Promoção de 8 funções nativas (`0x8011A8DC`, `0x8011AB7C`, `0x8011ABD4`, `0x8011AC1C`, `0x8011AC50`, `0x8011AFBC`, `0x8011B180`, `0x8011B238`), totalizando +663 palavras.
  - Validação em `gameplay-discovery-33`: **0 misses no Main EXE**, erradicação completa das 153k chamadas em fallback, queda de **-91,1%** nas instruções interpretadas e frametime 100% limpo em ambas as orientações de combate (normal e invertida).

---

### Caso 5: Jitter Transiente de Inicialização e Estabilização Plena de Frametime (Micro-lote S1-284)
- **Comportamento Observado**: Durante a sessão `gameplay-discovery-39` (Blair Dame vs Zangief), notou-se um transitório inicial de frametime na transição da tela de carregamento/apresentação para o início do Round 1. Logo em seguida, durante todo o restante do combate, o frametime estabilizou de forma completamente limpa e cravada a 60 FPS.
- **Diagnóstico Técnico**:
  - **Main EXE 100% Isento de Misses**: A telemetria registrou `static_text_misses: []` (0 novos candidatos e 0 quedas de contexto em código estático da ROM).
  - **Origem do Jitter Inicial**: Decorre do ciclo de staging de recursos do PlayStation e carga dinâmica em RAM:
    1. *Streaming de CD-ROM / ISO9660*: Leitura de blocos de áudio XA/CDDA e amostras SPU/VAG dos personagens para a memória de som.
    2. *Carregamento de Módulos Dinâmicos (Track 2)*: Alocação dos blocos de overlay em RAM (`0x80020000..0x800F2000`) contendo tabelas de golpes específicos dos personagens e scripts de introdução.
    3. *Setup de VRAM*: Upload de texturas 3D/sprites 2D e paletas de cores (CLUTs) nos buffers da GPU do PS1.
  - **Comportamento em Luta Ativa**: Assim que os buffers de RAM e VRAM estão estabelecidos, o despachador de ações (`0x801AFC70`), o motor de agarroes (`0x801B33F0`), a máquina de combate (`0x8013E930..0x8013EB60`) e as sub-rotinas de movimentação/sliding (`0x8014901C..0x801495D4`) operam 100% em código de máquina nativo x64, eliminando completamente quedas de frametime por fallback do interpretador.
- **Tratamento Planejado (Track 2)**:
  - O transitório inicial de streaming será mitigado futuramente na etapa de OVL Caching/JIT e otimização de I/O de disco.

---

### Caso 6: Super Combo Teatral do Skullomania (*Skullo Dream*)
- **Comportamento Observado**: Durante as sessões `gameplay-discovery-40` e `41` (Skullomania vs Ryu), a linha de frametime permaneceu cravada e ultra-estável durante todo o combate ativo, com uma leve micro-variação transitória ocorrendo exclusivamente durante a animação cinematográfica do *Skullo Dream*.
- **Diagnóstico Técnico**:
  - **Main EXE 100% Isento de Misses**: Zero quedas de contexto no código estático da ROM (`candidates.txt` vazio após a promoção do S1-285).
  - **Origem da Micro-Variação em RAM**: O golpe teatral *Skullo Dream* aciona um loop cinematográfico de poses e rastros em RAM dinâmica (`0x80020000..0x800F2000`):
    - **`0x80093E4C`**: Despachador dinâmico de pose/animação em RAM que disparou um pico massivo de **13,9 milhões de instruções interpretadas** na sessão 40 e **8,4 milhões** na sessão 41.
    - **`0x80092C2C` e `0x80092F00`**: Loop de atualização dos jogadores com ~5M e ~2M de instruções interpretadas cada.
- **Tratamento Planejado (Track 2)**:
  - Essas rotinas pertencem estritamente aos módulos dinâmicos em RAM e serão convertidas para código de máquina nativo na etapa de Overlay Cache / TCC JIT, eliminando a oscilação durante o Super.

---

## 3. Quarentena Obrigatória no Main EXE (Interpretação Segura)

Os únicos endereços dentro do espaço do executável principal (`0x80100000..0x801BF000`) mantidos intencionalmente sob interpretação são:

1. **`0x801AB1F4`**: Loop de leitura busy-wait do registrador de hardware SIO/Joypad (`0x1F801044` bit `0x80`). Recompilar estaticamente quebra o timing de pooling de entrada do controle.
2. **`0x801AB2C0`**: Monkey-patch de código auto-modificável (SMC) que substitui 5 instruções em tempo de execução para sincronização com a BIOS.

Qualquer hit nesses dois endereços é ignorado pelos filtros de telemetria como comportamento normal e esperado da emulação de hardware.
