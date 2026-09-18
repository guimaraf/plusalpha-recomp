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

## 3. Quarentena Obrigatória no Main EXE (Interpretação Segura)

Os únicos endereços dentro do espaço do executável principal (`0x80100000..0x801BF000`) mantidos intencionalmente sob interpretação são:

1. **`0x801AB1F4`**: Loop de leitura busy-wait do registrador de hardware SIO/Joypad (`0x1F801044` bit `0x80`). Recompilar estaticamente quebra o timing de pooling de entrada do controle.
2. **`0x801AB2C0`**: Monkey-patch de código auto-modificável (SMC) que substitui 5 instruções em tempo de execução para sincronização com a BIOS.

Qualquer hit nesses dois endereços é ignorado pelos filtros de telemetria como comportamento normal e esperado da emulação de hardware.
