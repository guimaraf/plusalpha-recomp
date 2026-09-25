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
- **DLLs Nativas no Cache**: 1.943
- **Funções Únicas em DLLs**: 3.215
- **Palavras em DLLs**: 25.657 palavras (102.628 bytes)
- **Cobertura de Elenco**: 26/26 lutadores (100% homologado: 23 jogáveis + 3 chefes CPU)
- **Motores de Projéteis / Fogo**: 14/14 rotinas validadas (100%)

## 3. Total Nativo Consolidado (Track 1 + Track 2)
- **Total de Funções Nativas**: 4.572 (1.357 estáticas + 3.215 dinâmicas)
- **Total de Palavras Nativas**: 180.493 palavras (721.972 bytes de código nativo)
- **Status Geral do Projeto**: Track 1 Homologada (incl. Bonus Stage); Track 2 do Bonus Stage em promoção

