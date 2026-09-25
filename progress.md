# Status de Progresso do Projeto: Street Fighter EX Plus Alpha (SLUS-005.48)

## 1. Track 1: Recompilação Estática (Main EXE)
- **Funções Nativas**: 1.358 (+1 no lote S1-309)
- **Palavras Recompiladas**: 154.846 palavras (619.384 bytes)
- **Cobertura do Main EXE**: 79,1711% (base 195.584 palavras)
- **Misses em Gameplay, Menus, Pause, Command List, Bonus Stage e Expert Mode**: 0 (100% nativo em todos os fluxos de execução)
- **Menu de Pause Principal (`0x80172DD0..0x8017566C`)**: HOMOLOGADO (S1-306, Teste 164)
- **Command List & Submenus 3D (`0x80183734..0x80185CC0` e GTE `0x8019`)**: HOMOLOGADO (S1-307, Teste 165)
- **Bonus Stage (Barril), Transição Option→Bonus e Tela de Recorde/Iniciais (`0x801495D4..0x8014B21C`, `0x8016F668..0x8016FB64`, `0x80181F7C..0x80183734`)**: HOMOLOGADO (S1-308, Teste 167 — 0 misses)
- **Expert Mode Dispatcher (`0x8014C6E0`)**: HOMOLOGADO (S1-309, Testes 173-174 — 0 misses)

## 2. Track 2: Recompilação Dinâmica (Overlays de Combate e Modos Especiais)
- **DLLs Nativas no Cache**: 2.216 DLLs (+76 novas DLLs de Expert Mode: Testes 172-174)
- **Funções Únicas em DLLs**: 3.840 funções únicas
- **Cobertura de Elenco**: 26/26 lutadores (100% homologado: 23 jogáveis + 3 chefes CPU)
- **Motores de Projéteis / Fogo**: 14/14 rotinas validadas (100%)
- **Bonus Stage (Barril) & Replay (Track 2)**: 100% HOMOLOGADO (Teste 171 — +4,09M dispatches nativos, 0 misses estáticos, erradicação dos 288M de instruções de overlay).
- **Expert Mode (Desafios do Ken & Lógica de Combos - Track 2)**: 100% HOMOLOGADO (Teste 174 — +590k dispatches nativos, erradicação de 99,83% das instruções de overlay, 0x80047E78 e 0x800E64D8 zerados).

## 3. Total Nativo Consolidado (Track 1 + Track 2)
- **Total de Funções Nativas**: 5.198 (1.358 estáticas + 3.840 dinâmicas)
- **Total de Código Nativo**: 1.358 funções estáticas + 2.216 DLLs ativas no cache
- **Status Geral do Projeto**: Track 1 100% Homologada; Track 2 (Elenco 26/26 + Projéteis + Bonus Stage + Expert Mode) 100% Homologado. 60.0 FPS sólido em todos os modos.



