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
| **Hokuto** | **100% Nativo** (0 misses) | `gameplay-discovery-42`, `43` & `85` | S1-286 / S1-302 | Chuuhou, Kaishuu, Shingetsu, Kyaku Houugi, Kiren'eki, Shirase Gatana, colisões, defesas, família GTE `0x8019D860..0x8019DA54` e pipeline de armas/adagas 3D (`0x80164D9C..0x80165DAC`). |
| **Dhalsim** | **100% Nativo** (0 misses) | `gameplay-discovery-46` | S1-287 | Yoga Fire (`0x8015A530`), Yoga Flame, Yoga Blast, deformação elástica dos membros (`0x8014B2B4`), caixas de colisão elásticas (`0x8014B6B0`) e ossos de animação (`0x80194BB4..EE4`). |
| **Cycloid-β** | **100% Nativo** (0 misses) | `gameplay-discovery-47` | S1-287 | Modelo poligonal azul; moveset híbrido do elenco SF totalmente compartilhado com rotinas nativas pré-existentes. |
| **Cycloid-γ** | **100% Nativo** (0 misses) | `gameplay-discovery-48` | S1-287 | Modelo poligonal dourado; moveset híbrido do elenco EX e teleports (100% de dispatches estáticos nativos no Main EXE; variações restritas ao overlay dinâmico em RAM). |
| **Bloody Hokuto** | **100% Nativo** (0 misses) | `gameplay-discovery-49` & `85` | S1-287 / S1-302 | Versão corrompida de Hokuto, adaga permanente e ataques rápidos de sangue; compartilha 100% das sub-rotinas cinemáticas, matrizes e pipeline de props (S1-286 / S1-302). |
| **Evil Ryu** | **100% Nativo** (0 misses) | `gameplay-discovery-50` | S1-287 | Ashura Senku, Messatsu Gou Shoryu, Shun Goku Satsu, Hadouken sombrio; compartilha matrizes cinemáticas, transformadas e dispatches de projéteis de Ryu e Akuma. |
| **Akuma (CPU / Boss)** | **100% Nativo** (0 misses) | `gameplay-discovery-104` | S1-303 | Variante desbloqueável via Expert Mode / Save 100%. IA de chefe ultra-agressiva, Zanku Hadoken duplo, Messatsu Gou Hado/Shoryu 100% nativos no Main EXE. |
| **Garuda (CPU / Boss)** | **100% Nativo** (0 misses) | `gameplay-discovery-105` | S1-303 | Variante desbloqueável via Expert Mode / Save 100%. IA de chefe, super armor nativa, lâminas e Kienshou 100% nativos no Main EXE. |
| **M. Bison (CPU / Boss)** | **100% Nativo** (0 misses) | `gameplay-discovery-106` | S1-303 | Variante desbloqueável via Expert Mode / Save 100%. IA de chefe final ultra-agressiva, teleporte contínuo e dispatches estáticos 100% nativos no Main EXE. |

---

### Resumo do Roster (23 Personagens Base + 3 Chefes CPU Desbloqueáveis)
- **Fileira Superior (8)**: Zangief [OK], Cracker Jack [OK], Hokuto [OK], Ryu [OK], Ken [OK], Chun-Li [OK], Doctrine Dark [OK], Guile [OK]
- **Fileira Central (8)**: Pullum Purna [OK], Darun Mister [OK], Kairi [OK], Sakura [OK], Dhalsim [OK], Allen Snider [OK], Blair Dame [OK], Skullomania [OK]
- **Fileira Inferior / Chefes & Secretos (7)**: Akuma [OK], M. Bison [OK], Garuda [OK], Evil Ryu [OK], Bloody Hokuto [OK], Cycloid-β [OK], Cycloid-γ [OK]
- **Variantes Especiais de Chefes CPU (3)**: Akuma (CPU) [OK], Garuda (CPU) [OK], M. Bison (CPU) [OK]
- **Progresso de Homologação**:
  - **Elenco Base Versus**: **23 / 23 personagens (100,00%)** com 100% de execução nativa no Main EXE!
  - **Variantes Chefes CPU**: **3 / 3 (100,00%)** com 100% de execução nativa no Main EXE!
  - **Total Geral do Elenco**: **26 / 26 personagens (100,00%)** com **100% de execução estática nativa (0 misses)**!

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

### Caso 6: Super Combo Teatral do Skullomania (*Skullo Dream*) - Resolvido (S1-285, S1-305 & Track 2)
- **Comportamento Observado**: Durante as sessões `gameplay-discovery-40`, `41`, `137`, `138` e `139`, a linha de frametime permaneceu cravada a 60 FPS durante todo o combate ativo. Ao acionar o especial teatral cinematográfico (*Skullo Dream*), identificou-se a divisão exata entre ROM estática e overlay em RAM.
- **Diagnóstico Técnico**:
  - **Main EXE Text (S1-305)**: O *Skullo Dream* acionou a entrada 0 da Action Table (`0x801B1B48 -> 0x8013B070`), com JALs internos para setup de matrizes de câmera 3D e GTE (`0x8013B070..0x8013B328`).
  - **Resolução Implementada (S1-305)**: Promoção de 5 funções nativas (+1.148 palavras: `0x8013B070`, `0x8013B078`, `0x8013B10C`, `0x8013B114`, `0x8013B328`), selando o gap até o Modo Treino (`0x8013BFA8`).
  - **Validação em `gameplay-discovery-139`**: **0 CANDIDATOS NO MAIN EXE**, erradicação de 100% dos misses estáticos, +380.190 dispatches nativos e absorção plena do impacto de processamento da cinemática.
  - **Track 2 (RAM Overlay)**: O módulo de combate em RAM (`0x00020000:0x2906ED7E`) foi compilado em 263 DLLs de shard, erradicando os 10,3M de instruções de movimentação acrobática do Skullomania e chutes de Blair Dame.

---

### Caso 7: Cinemática de Membros Elásticos do Dhalsim e Pipeline de Animação de Ossos (Micro-lote S1-287)
- **Comportamento Observado**: Durante a sessão `gameplay-discovery-45` (Dhalsim vs Ryu), foram detectados 8 candidatos residuais (2.002 hits) ao acionar ataques com membros estendidos.
- **Diagnóstico Técnico**:
  - A mecânica única do Dhalsim de esticar braços e pernas mobiliza sub-rotinas cinemáticas específicas de deformação e caixas de contato móveis:
    - `0x8014B21C` (Root dispatch de combate na tabela `0x801B1BA8`).
    - `0x8014B2B4` (Cálculo cinemático de alcance e deformação elástica dos membros).
    - `0x8014B6B0` (Atualização de posturas e caixas de colisão móveis).
    - `0x8015A530` (Projétil Yoga Fire).
    - `0x80194BB4..0x80194EE4` (Pipeline de orientação de matrizes e interpolação de ossos de animação 3D).
- **Resolução Implementada (S1-287)**:
  - Promoção de 9 funções nativas (+780 palavras).
  - Validação em `gameplay-discovery-46`: **0 candidatos no Main EXE**, frametime cravado e homologação oficial do Dhalsim como 19º lutador 100% nativo.

---

### Caso 8: Compartilhamento Estrutural de Movesets em Chefes e Personagens Bônus (Cycloids, Bloody Hokuto, Evil Ryu)
- **Comportamento Observado**: Testes de combate com Cycloid-β (`gameplay-discovery-47`), Cycloid-γ (`gameplay-discovery-48`), Bloody Hokuto (`gameplay-discovery-49`) e Evil Ryu (`gameplay-discovery-50`).
- **Diagnóstico Técnico**:
  - Todas as sessões registraram **EXATAMENTE 0 CANDIDATOS NO MAIN EXE** (`candidates.txt` vazio) logo no primeiro teste.
  - **Herança Cinemática**:
    - **Cycloid-β**: Reutiliza integralmente as tabelas e rotinas de golpes normais/especiais já compiladas do elenco Street Fighter.
    - **Cycloid-γ**: Reutiliza a base de combate dos lutadores EX. As flutuações de frametime observadas concentram-se no overlay dinâmico em RAM (`0x80048930` e `0x8004880C`), sem nenhum miss na ROM estática.
    - **Bloody Hokuto**: Herda 100% das sub-rotinas cinemáticas, matrizes de rotação e vetores da Hokuto padrão (promovidas em S1-286).
    - **Evil Ryu**: Compartilha dispatches cinemáticos, rotas de Hadouken e colisões com Ryu e Akuma.
- **Conclusão de Ciclo**: Todos os 23 lutadores do jogo foram homologados com **100% de execução nativa** no Main EXE.

---

### Caso 9: Pipeline de Armas/Props e Renderizador 3D de Adagas da Hokuto (Micro-lotes S1-301 e S1-302)
- **Comportamento Observado**: Durante a campanha de CPU AI (`gameplay-discovery-83` e `84`), foram descobertos candidatos ao redor do pipeline de props da Hokuto (`0x80164D9C..0x80165DAC`).
- **Diagnóstico Técnico**:
  - A Hokuto (e variantes como Bloody Hokuto) utiliza um despachador global de acessórios/props de armas que verifica o Character ID (`0x80164D9C`, 89 palavras).
  - O renderizador poligonal 3D de adagas e leque opera nas sub-rotinas `0x80165130` (266 palavras) e `0x80165DAC` (241 palavras), com chamadas GTE nativas.
- **Resolução Implementada (S1-301 e S1-302)**:
  - **S1-301**: Promoção de `0x80165130` (266 palavras).
  - **S1-302**: Promoção de `0x80164D9C` e `0x80165DAC` (330 palavras).
  - Validado em `gameplay-discovery-85` com **zero candidatos e 993.384 static hits** no Main EXE.

---

### Caso 10: Churn de Loop Dinâmico em RAM durante Combate CPU (Sakura #13 - Sessão `gameplay-discovery-93`)
- **Comportamento Observado**: Durante o teste de combate em 3 lutas contra a Sakura Level 8 (`gameplay-discovery-93`), observou-se alta ocorrência de micro-variações no frametime, com zero novos candidatos no Main EXE.
- **Diagnóstico Técnico**:
  - **Main EXE 100% Isento de Misses**: 982.944 static hits nativos e 0 misses.
  - **Origem do Jitter em RAM Dinâmica**: Saturação do interpretador em fallback em código dinâmico com **+164.611.395 instruções interpretadas** e **+7.318.116 hits** em overlay:
    - **`0x80092280`**: 42.114.686 instruções (88.170 hits) — frame update / loop dinâmico de combate.
    - **`0x8004A44C`**: 39.595.929 instruções (88.170 hits) — shared battle engine (`OVL-001A`), operando em sincronia direta com `0x80092280`.
    - **`0x8004922C`**: 23.867.322 instruções (15.499 hits) — cinemática e renderizador de golpes em RAM.
    - **`0x80049500`**: 10.625.735 instruções (15.499 hits) — partículas e emissores de efeitos especiais.
    - **`0x80091334`**: 10.067.308 instruções (15.499 hits) — despachador de colisão dinâmica.
- **Tratamento Planejado (Track 2)**:
  - Catalogado no pipeline de Overlays para geração de DLLs de shard via TCC/JIT, eliminando os handoffs entre x64 e MIPS.

---

## 3. Homologação do Core AI Engine (Lotes S1-291 a S1-300)

Após a homologação completa dos 23 personagens sob controle humano (P1), iniciou-se a campanha de homologação dos personagens operados pela CPU (Level 8 / Hardest).

- **O Desafio do Core AI Engine (`0x80155000..0x80158500`)**:
  - Quando operados pela IA no nível máximo de agressividade, os lutadores acionam árvores profundas de avaliação de neutro, *hit-confirms*, cancelamentos sequenciais, simulação de inputs e reversais.
- **Campanha de Promoção em Micro-Lotes (S1-291 a S1-300)**:
  - **S1-291 / S1-292**: Configuração de dummies de treino e flags de transição neutra.
  - **S1-293**: Gap 2 e Gap 7 (Helpers de recovery e transição de bloqueio).
  - **S1-294**: Gap 4 (Aproximação e temporização de pulos).
  - **S1-295**: Gap 5 (Seleção de supers e cancelamentos).
  - **S1-296 / S1-297**: Gap 3 Parte 1 e Parte 2 (Posicionamento, evasão, hit-confirms e combos; erradicação de 1.500+ hits).
  - **S1-298 / S1-299 / S1-300**: Gap 6 Partes 1, 2 e 3 (Curta distância, dashes, vantagens de frames, reversais, matriz de projéteis e finalizadores; erradicação de 1.540+ hits).
- **Resultado na Sessão `gameplay-discovery-74`**:
  - **0 CANDIDATOS NO MAIN EXE TEXT**.
  - O Core AI Engine agora forma um **bloco contíguo de 13.368 bytes (3.342 palavras)** de código C11 nativo de `0x801550C8` até `0x80158500`.
  - Garante que todo o elenco, seja controlado por humanos ou pela IA de alta dificuldade, execute com **zero fallbacks no Main EXE**.

---

## 4. Quarentena Obrigatória no Main EXE (Interpretação Segura)

Os únicos endereços dentro do espaço do executável principal (`0x80100000..0x801BF000`) mantidos intencionalmente sob interpretação são:

1. **`0x801AB1F4`**: Loop de leitura busy-wait do registrador de hardware SIO/Joypad (`0x1F801044` bit `0x80`). Recompilar estaticamente quebra o timing de pooling de entrada do controle.
2. **`0x801AB2C0`**: Monkey-patch de código auto-modificável (SMC) que substitui 5 instruções em tempo de execução para sincronização com a BIOS.

Qualquer hit nesses dois endereços é ignorado pelos filtros de telemetria como comportamento normal e esperado da emulação de hardware.
