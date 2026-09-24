# Catálogo de Colisões e Interações de Projéteis (Track 2 - RAM Overlay)

Este documento registra o mapeamento de engenharia reversa das rotinas de **colisão, absorção, reflexão, cancelamento mútuo e hit-stop de projéteis** executadas no subsistema de combate dinâmico em RAM (`0x80020000..0x800F2000`).

Essas rotinas serão compiladas e promovidas de forma consolidada após o mapeamento do elenco.

---

### 1. Estruturas e Offsets Globais de Projéteis Identificados

| Registrador / Offset | Descrição Arquitetural |
|:---|:---|
| `offset 0x1354($s0)` | Array de entidades de projéteis ativos do lutador (`ProjectileEntity[]`). |
| `offset 0x1515($s0)` | Estado de reação e flags de impacto / bloqueio de projétil. |
| `offset 0x1F800008` | Scratchpad RAM (Fast DMA) para matrizes de transformação de partículas de impacto. |

---

### 2. Tabela de Rotinas Catalogadas (Descobertas em Combate)

| Endereço (PC) | Instruções / Hits Típicos | Função MIPS / Diagnóstico | Sessão de Descoberta | Matchup |
|:---|---:|:---|:---:|:---:|
| `0x8008E25C` | 278.449 insns (5.347 hits) | **Handler mestre de colisão e cancelamento mútuo de projéteis** (compara structs `0x1354` de P1 e P2). | `discovery-132` | Ryu x Guile |
| `0x8008FC6C` | 112.366 insns (5.914 hits) | **Processador de hit-stop de projétil** atingindo guarda ou alvo. | `discovery-132` | Ryu x Guile |
| `0x80091F24` | 96.632 insns (376 hits) | **DMA de partículas de impacto** para Scratchpad RAM (`0x1F800008`). | `discovery-132` | Ryu x Guile |
| `0x80091C60` | 94.376 insns (376 hits) | Sub-rotina de dissipação de partículas de projétil após colisão. | `discovery-132` | Ryu x Guile |
| `0x80090BF0` | 79.734 insns (510 hits) | Atualizador de flags de frame para projéteis em voo. | `discovery-132` | Ryu x Guile |
| `0x8008E714` | 13.680 insns (207 hits) | **Emissor balístico e física de fogo** (Yoga Fire / Yoga Flame). | `discovery-134` | Zangief x Dhalsim |
| `0x8008E99C` | 9.012 insns (277 hits) | **Renderizador de sprites de fogo** e expansão de chamas. | `discovery-134` | Zangief x Dhalsim |
| `0x8008FA1C` | 5.867 insns (494 hits) | Loop de persistência e expiração do fogo ativo na tela. | `discovery-134` | Zangief x Dhalsim |
| `0x8008E6C0` | 2.100 insns (207 hits) | Handler de ativação e verificação de alcance de projétil de fogo. | `discovery-134` | Zangief x Dhalsim |
| `0x8008E398` | 1.830 insns (180 hits) | Sub-rotina de inicialização de parâmetros de impacto de fogo. | `discovery-134` | Zangief x Dhalsim |
| `0x80047EFC` | 904.415 insns (460 hits) | **Detonação e dano em área de minas / armadilhas** (*Dark EX-Plo* / *Dark Shackle*). | `discovery-135` | D. Dark x Hokuto |
| `0x8008E798` | 594.897 insns (5.836 hits) | **Atualizador de entidades de bombas em RAM** (`struct Entity` tipo `0x13`). | `discovery-135` | D. Dark x Hokuto |
| `0x80047DE8` | 158.622 insns (6.070 hits) | Sub-rotina de plantio, armamento e contagem regressiva de minas terrestres. | `discovery-135` | D. Dark x Hokuto |
| `0x8008E394` | 370.004 insns (5.208 hits) | **Parâmetros de impacto, contato e reflexão de projéteis** (*Soul Force* / *Batting Hero*). | `discovery-140` | Jack x Allen |

---

### 3. Matriz de Lutadores com Mecânicas Especiais de Projétil

| Lutador | Mecânica Exclusiva | Interação Esperada |
|:---|:---|:---|
| **Darun Mister** | Soco pesado / Brahma Lariat | Destruição física de projéteis no impacto. |
| **Doctrine Dark** | *Dark Wire* / *Kill Wire* (Chicote) | Interceptação e anulação de projéteis a média distância. |
| **Cracker Jack** | *Batting Hero* (Bastão de Baseball) | Reflexão balística do projétil de volta contra o oponente. |
| **Dhalsim** | *Yoga Fire* / *Yoga Flame* | Projétil de arco curto e barreira de fogo persistente. |
| **Chun-Li** | *Kikoken* | Projétil de dissipação rápida. |
| **Guile** | *Sonic Boom* | Projétil cortante com alta prioridade de cancelamento. |
| **Ryu / Ken** | *Hadouken* / *Shinku Hadouken* | Projétil padrão e feixe multi-hit perfurante. |
| **Akuma (Gouki)** | *Gou-Hadouken* / *Zanku Hadouken* | Projétil diagonal aéreo e projétil duplo de fogo. |
| **Allen Snider** | *Soul Force* | Projétil de rápida recuperação. |
| **Kairi** | *Shinki Hatsu Dou* | Projétil espiritual com trajetória retilínea. |
| **Garuda** | *Soukon Dan* | Projéteis múltiplos teleguiados. |
| **M. Bison** | *Psycho Shot* | Projétil espiral com carga. |
