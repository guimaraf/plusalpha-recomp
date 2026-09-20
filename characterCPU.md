# Homologação de Personagens Controlados por CPU (IA de Combate)

Este documento acompanha a evolução da cobertura e homologação nativa de todos os 23 personagens de *Street Fighter EX Plus Alpha* (`SLUS-005.48`) quando operados pela Inteligência Artificial da CPU.

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
| 1 | **Ryu** | Em Homologação | `discovery-71` | S1-297 validado (+3 funcs, +413 pal; 1.135+ hits erradicados); Gap 3 fechado; restam 29 candidatos (todos no Gap 6) | Shoryuken, Hadoken, Tatsumaki, Shinku Hadoken. |
| 2 | **Ken** | Pendente | — | — | Shoryuken flamejante, Shoryu Reppa, Shinryuken. |
| 3 | **Chun-Li** | Pendente | — | — | Hyakuretsukyaku, Kikoken, Senretsukyaku, Hazanshou. |
| 4 | **Guile** | Pendente | — | — | Sonic Boom, Flash Kick, Somersault Strike. |
| 5 | **Zangief** | Pendente | — | — | Spinning Piledriver, Double Lariat, Final Atomic Buster. |
| 6 | **Dhalsim** | Pendente | — | — | Yoga Fire, Yoga Flame, Yoga Blast, Yoga Inferno. |
| 7 | **Hokuto** | Pendente | — | — | Chirenki, Gekhou, Kyakuho, Shirase Ondo. |
| 8 | **Cracker Jack** | Pendente | — | — | Batting Hero, Final Punch, Crazy Jack, Raging Buffalo. |
| 9 | **Doctrine Dark** | Pendente | — | — | Kill Wire, Dark Shackle, Kill Blade, EX-prominence. |
| 10 | **Pullum Purna** | Pendente | — | — | Prim Doll, Drill Purrus, Resarc Dance, Pra ダンス. |
| 11 | **Darun Mister** | Pendente | — | — | Lariat, Ganges DDT, Brahma Stomp, Twilight Collar. |
| 12 | **Kairi** | Pendente | — | — | Shinki Hatsu Dou, Maryu Rekkou, Garyu Hishou. |
| 13 | **Sakura** | Em Investigação | `discovery-63` | 9 funções detectadas | Hadoken, Shouoken, Haru Ichiban, Midare Zakura. |
| 14 | **Blair Dame** | Pendente | — | — | Shoot Upper, Slider, Mirage Kick, Spinning Knee. |
| 15 | **Allen Snider** | Pendente | — | — | Soul Force, Rising Dragon, Triple Break, Fire Force. |
| 16 | **Skullomania** | Pendente | — | — | Skullo Crusher, Skullo Slider, Super Skullo Crusher. |
| 17 | **Akuma** | Pendente | — | — | Gou Hadoken, Shakunetsu, Messatsu Gou Shoryu, Shun Goku Satsu. |
| 18 | **Garuda** | Pendente | — | — | Shusui, Kizan, Raiga, Soukon Dan. |
| 19 | **M. Bison** | Pendente | — | — | Psycho Crusher, Scissor Kick, Head Press, Knee Press Nightmare. |
| 20 | **Cycloid-β** | Pendente | — | — | Moveset híbrido estático. |
| 21 | **Cycloid-γ** | Pendente | — | — | Moveset híbrido dinâmico. |
| 22 | **Bloody Hokuto** | Pendente | — | — | Moveset agressivo e cancels rápidos. |
| 23 | **Evil Ryu** | Pendente | — | — | Shun Goku Satsu, Messatsu Gou Shoryu variante. |

---

## 4. Estratégia de Promoção da CPU AI

Devido à arquitetura modular do motor:
- A promoção das funções do **Core AI Engine (`0x80155000..0x80158500`)** trará ganhos globais cumulativos para todos os lutadores.
- A cada personagem testado, promoveremos primeiramente as funções comuns do motor de IA e em seguida os eventuais dispatches de golpes específicos que forem descobertos.
