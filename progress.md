# Status de Progresso do Projeto: Street Fighter EX Plus Alpha (SLUS-005.48)

## 1. Track 1: Recompilação Estática (Main EXE)
- **Funções Nativas**: 1.357 (+13 no lote S1-308)
- **Palavras Recompiladas**: 154.836 palavras (619.344 bytes)
- **Cobertura do Main EXE**: 79,1660% (base 195.584 palavras)
- **Misses em Gameplay, Menus, Pause, Command List e Bonus Stage**: 0 (100% nativo em todos os fluxos de execução)
- **Menu de Pause Principal (`0x80172DD0..0x8017566C`)**: HOMOLOGADO (S1-306, Teste 164)
- **Command List & Submenus 3D (`0x80183734..0x80185CC0` e GTE `0x8019`)**: HOMOLOGADO (S1-307, Teste 165)
- **Bonus Stage (Barril), Transição Option→Bonus e Tela de Recorde/Iniciais (`0x801495D4..0x8014B21C`, `0x8016F668..0x8016FB64`, `0x80181F7C..0x80183734`)**: HOMOLOGADO (S1-308, Teste 167 — 0 misses)

## 2. Track 2: Recompilação Dinâmica (Overlays de Combate e Modos Especiais)
- **DLLs Nativas no Cache**: 2.140 DLLs (+197 novas DLLs de Bonus Stage / Replay / Records com sincronização dual-base)
- **Funções Únicas em DLLs**: 3.764 funções únicas
- **Cobertura de Elenco**: 26/26 lutadores (100% homologado: 23 jogáveis + 3 chefes CPU)
- **Motores de Projéteis / Fogo**: 14/14 rotinas validadas (100%)
- **Bonus Stage (Barril) & Replay (Track 2)**: 100% HOMOLOGADO (Teste 171 — +4,09M dispatches nativos, 0 misses estáticos, erradicação dos 288M de instruções de overlay).

## 3. Total Nativo Consolidado (Track 1 + Track 2)
- **Total de Funções Nativas**: 5.121 (1.357 estáticas + 3.764 dinâmicas)
- **Total de Código Nativo**: 1.357 funções estáticas + 2.140 DLLs ativas no cache
- **Status Geral do Projeto**: Track 1 100% Homologada; Track 2 (Elenco 26/26 + Projéteis + Bonus Stage/Replay/Records) 100% Homologado. 60.0 FPS sólido em todos os modos.



