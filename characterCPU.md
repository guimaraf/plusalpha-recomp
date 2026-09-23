# Homologação de Personagens Controlados por CPU (IA de Combate)

Este documento acompanha a evolução da cobertura e homologação nativa de todos os 26 personagens (23 padrão + 3 variantes de chefes CPU desbloqueáveis) de *Street Fighter EX Plus Alpha* (`SLUS-005.48`) quando operados pela Inteligência Artificial da CPU.

---

## 1. Visão Arquitetural da CPU AI

O sistema de inteligência artificial de combate do jogo é composto por três camadas:

1. **Núcleo de Decisão e Estratégia (Core AI Engine - `0x80155000..0x80158500`)**:
   - Avaliação de distância (espaçamento neutro).
   - Reação defensiva (bloqueio alto/baixo, recuperação pós-knockdown).
   - Encadeamento de ataques normais, golpes especiais e *Super Cancels*.
   - Gestão da barra de super e agressividade conforme o nível de dificuldade.
   - *Nota*: Parte desta camada já foi homologada no lote **S1-291** (Cluster de Dummy/Treino: 7 funções, 250 palavras em `0x801555A8..0x80156AD0`).
2. **Tabelas de Dados de Golpes por Personagem (`0x801B0000..0x801B6000`)**:
   - Dados estáticos contendo os pesos de prioridade de cada golpe e rotas de combos específicos para cada lutador.
3. **Dispatches Específicos de Golpes (`0x80126...`, `0x80129...`, `0x8014C...`, `0x80160...`)**:
   - Funções cinemáticas e físicas que são engatilhadas quando a CPU seleciona uma rota de ataque.

---

## 2. Metodologia de Testes Padronizada

Para isolar o comportamento da CPU sem dependência de aleatoriedade dos modos Arcade/Survival:

1. **Ambiente**: Modo **Versus** com o **Controle 2 desconectado** (ativação automática de P2 = COM / CPU).
2. **Configuração de Dificuldade (Game Level)**:
   - Ajustar o **Game Level no MÁXIMO (Level 8 / Hardest)** no menu *Options*.
   - **Justificativa Técnica**: Níveis mais baixos induzem pausas artificiais (*idle frames*) e baixas probabilidades de reação. No nível máximo, a CPU elimina janelas de espera, busca ativamente *hit-confirms*, encadeia combos complexos, executa *Super Cancels* assim que enche a barra e estressa as rotinas mais profundas de reversais e aproximação rápida.
3. **Postura do Jogador 1**:
   - Não atacar.
   - Manter postura defensiva (bloqueios em pé/agachado, absorção de dano, permitir que a CPU encha a barra de super).
   - Permitir que a CPU exercite toda a sua árvore de ações: aproximação (*footsies*), golpes normais em cadeia, especiais, supers e combos de finalização.
4. **Fluxo de Telemetria**:
   - Snapshot **before**: No início do Round 1 (após o anunciador "Fight").
   - Gameplay: Defender e tomar ataques até a derrota / KO.
   - Snapshot **after**: Imediatamente após o KO (durante o replay / pose de vitória).

---

## 3. Tabela de Rastreamento do Elenco (CPU AI)

| # | Personagem | Status CPU | Sessão Telemetria | Candidatos Main EXE | Observações |
|:---:|:---|:---:|:---:|:---:|:---|
| 1 | **Ryu** | Homologado (Core AI) | `discovery-74` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | Core AI Engine (`0x801550C8..0x80158500`) 100% nativo. Próximo alvo: dispatches específicos de outros lutadores. |
| 2 | **Ken** | Homologado | `discovery-75` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 276.036 static hits, 0 misses no Main EXE. Shoryuken flamejante, Shoryu Reppa e Shinryuken 100% cobertos no binário estático. |
| 3 | **Chun-Li** | Homologado | `discovery-76` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 279.897 static hits, 0 misses no Main EXE. Hyakuretsukyaku, Kikoken, Senretsukyaku e Hazanshou 100% nativos. Micro-oscilações isoladas em RAM dinâmica (52,6M insns em overlay catalogadas para Track 2). |
| 4 | **Guile** | Homologado | `discovery-78` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 1.134.699 static hits, 0 misses no Main EXE em 4 lutas. Ambos os Supers de carga (*Somersault Strike* e *Opening Gambit*) confirmados e 100% nativos. |
| 5 | **Zangief** | Homologado | `discovery-79` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 778.583 static hits, 0 misses no Main EXE em 3 lutas. Spinning Piledriver, Double Lariat, Banishing Flat e Final Atomic Buster 100% nativos. |
| 6 | **Dhalsim** | Homologado | `discovery-81` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 1.054.833 static hits, 0 misses no Main EXE em 3 lutas. Membros elásticos, Yoga Fire e Yoga Inferno 100% nativos (cinemática de Drill já coberta no S1-287). |
| 7 | **Hokuto** | Homologado | `discovery-85` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 993.384 static hits, 0 misses no Main EXE em 3 lutas. Pipeline de armas e props (`0x80164D9C..0x80166170`) 100% promovido via S1-301 e S1-302. |
| 8 | **Cracker Jack** | Homologado | `discovery-86` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 360.153 static hits, 0 misses no Main EXE. Investidas de boxe, tacadas de beisebol e supers 100% nativos (cinemática de upper coberta em S1-280). |
| 9 | **Doctrine Dark** | Homologado | `discovery-87` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 376.111 static hits, 0 misses no Main EXE. Kill Wire, cabo/choque elétrico, facas (Kill Blade), minas terrestres e supers 100% nativos no binário estático. |
| 10 | **Pullum Purna** | Homologado | `discovery-89` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 649.143 static hits, 0 misses no Main EXE em 2 lutas. Piruetas, Drill Purrus e danças acrobáticas 100% nativos (motor cinemático de membros compartilhado). |
| 11 | **Darun Mister** | Homologado | `discovery-90` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 697.776 static hits, 0 misses no Main EXE em 3 lutas. Lariats, Ganges DDT, Indra Bridge e supers de agarrão 100% nativos (tabela global 0x801B33F0 e física de grapplers). |
| 12 | **Kairi** | Homologado | `discovery-92` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 481.577 static hits, 0 misses no Main EXE em 2 lutas. Shinki Hatsu Dou, Maryu Rekkou e sub-cluster de combate (`0x80162244..0x80162570`) 100% nativos via S1-303. |
| 13 | **Sakura** | Homologado | `discovery-93` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 982.944 static hits, 0 misses no Main EXE em 3 lutas. Erradicação de 100% dos 9 candidatos legados de `discovery-63` (Core AI promovido em S1-293..S1-300). Hadoken, Shouoken, Shunpukyaku e Haru Ichiban 100% nativos. Micro-oscilações isoladas em RAM dinâmica (164,6M insns em overlay catalogadas para Track 2). |
| 14 | **Blair Dame** | Homologado | `discovery-94` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 416.982 static hits, 0 misses no Main EXE. Shoot Upper, Slider, Mirage Kick, Spinning Knee e Super Mirage Combination 100% nativos. 55,4M insns em overlay dinâmico arquivadas para Track 2. |
| 15 | **Allen Snider** | Homologado | `discovery-95` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 210.044 static hits, 0 misses no Main EXE. Soul Force, Rising Dragon, Justice Fist, Vaulting Kick e Fire Force 100% nativos. 29,5M insns em overlay dinâmico arquivadas para Track 2. |
| 16 | **Skullomania** | Homologado | `discovery-96` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 306.039 static hits, 0 misses no Main EXE. Skullo Crusher, Skullo Slider, Skullo Head, Skullo Dive, Skullo Dash e Super Skullo Slider 100% nativos. 35,3M insns em overlay dinâmico arquivadas para Track 2. |
| 17 | **Akuma** | Homologado | `discovery-97` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 455.919 static hits, 0 misses no Main EXE. Gou Hadoken (solo/ar), Shakunetsu, Gou Shoryuken e Tatsumaki 100% nativos. 82,4M insns em overlay dinâmico arquivadas para Track 2. |
| 18 | **Garuda** | Homologado | `discovery-98` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 289.224 static hits, 0 misses no Main EXE. Shusui, Kizan, Raiga, Soukon Dan e Kienshou 100% nativos. 48,7M insns em overlay dinâmico arquivadas para Track 2 (spin de lâminas 0x80092294). |
| 19 | **M. Bison** | Homologado | `discovery-99` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 564.441 static hits, 0 misses no Main EXE em 2 lutas. Psycho Crusher, Scissor Kick, Head Press e Knee Press Nightmare 100% nativos. 67,9M insns em overlay dinâmico arquivadas para Track 2. |
| 20 | **Cycloid-β** | Homologado | `discovery-100` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 376.839 static hits, 0 misses no Main EXE. Moveset híbrido e Super de facas/lâminas 100% nativos. 43,0M insns em overlay dinâmico arquivadas para Track 2. |
| 21 | **Cycloid-γ** | Homologado | `discovery-101` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 294.501 static hits, 0 misses no Main EXE. Moveset híbrido, teleporte e Super de chutes aéreos 100% nativos. 33,8M insns em overlay dinâmico arquivadas para Track 2. |
| 22 | **Bloody Hokuto** | Homologado | `discovery-102` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 235.842 static hits, 0 misses no Main EXE. Pipeline de adagas, cortes rápidos e 2 Supers 100% nativos (S1-301/S1-302). 27,6M insns em overlay dinâmico arquivadas para Track 2. |
| 23 | **Evil Ryu** | Homologado | `discovery-103` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 360.870 static hits, 0 misses no Main EXE. Hadouken sombrio, Shoryuken, Ashura Senku e 2 Supers 100% nativos. 71,1M insns em overlay dinâmico arquivadas para Track 2. |
| 24 | **Akuma (CPU / Boss)** | Homologado | `discovery-104` / `discovery-109` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 415.845 static hits (CPU) e 3.584.080 static hits (P1), 0 misses no Main EXE. Variante de chefe, Zanku Hadoken duplo, Shun Goku Satsu e supers 100% nativos e validados em `discovery-109`. 74,6M insns em overlay dinâmico arquivadas para Track 2. |
| 25 | **Garuda (CPU / Boss)** | Homologado | `discovery-105` / `discovery-108` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 356.634 static hits (CPU) e 3.484.378 static hits (P1), 0 misses no Main EXE. Variante de chefe, super armor, lâminas, Super Kienshou e contragolpe defensivo exclusivo (Tabela 0x801B33F0 slot 12 promovido em S1-304) 100% nativos com ZERO candidatos em `discovery-108`. 60,1M insns em overlay dinâmico arquivadas para Track 2. |
| 26 | **M. Bison (CPU / Boss)** | Homologado | `discovery-106` / `discovery-110` | **ZERO CANDIDATOS** (100% nativo no Main EXE) | 297.756 static hits (CPU) e 3.399.945 static hits (P1), 0 misses no Main EXE. Chefe final, teleporte contínuo, Psycho Crusher e Super 100% nativos e validados em `discovery-110`. 34,5M insns em overlay dinâmico arquivadas para Track 2. |

---

## 4. Estratégia de Promoção da CPU AI

Devido à arquitetura modular do motor:
- A promoção das funções do **Core AI Engine (`0x80155000..0x80158500`)** trará ganhos globais cumulativos para todos os lutadores.
- A cada personagem testado, promoveremos primeiramente as funções comuns do motor de IA e em seguida os eventuais dispatches de golpes específicos que forem descobertos.
