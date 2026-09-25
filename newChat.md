# Briefing e Instruções para Continuidade no Novo Chat

## 1. Regras Mandatórias de Atuação (User Rules & Constraints)
- **Tom e Comunicação**: Estritamente técnico, franco e direto. Sem floreios, sem elogios ou desculpas desnecessárias. Vá direto ao ponto.
- **Correção Imediata**: Se o usuário propuser uma abordagem tecnicamente falha ou insegura, corrija-o imediatamente com justificativa técnica.
- **Host Ownership Inviolável**: O assistente **NUNCA** executa comandos de compilação de código nativo, recompilador (`psxrecomp-game.exe`), scripts de telemetria ou comandos de gameplay. Toda a compilação, execução do jogo e telemetria é realizada pelo **Operador** através de scripts PowerShell (`.ps1`). O assistente gera/edita os scripts, analisa logs e direciona a arquitetura.

---

## 2. Contexto do Projeto e Repositório
- **Projeto**: Recompilação Nativa C11 de *Street Fighter EX Plus Alpha* (USA, `SLUS-005.48`).
- **Diretório Principal**: `f:\GitRevised\alphaplus\plusalpha-recomp`
- **Subdiretórios Críticos**:
  - `PlusAlphaProject/`: Projeto CMake, fontes C geradas, binários (`buildTele-s1-308/exPlusAlpha.exe`) e scripts de build.
  - `PlusAlphaProject/tools/`: Scripts de automação PowerShell (`compile_track2_bonus_barrel_overlay.ps1`, etc.).
  - `PlusAlphaProject/local/telemetry/`: Sessões de telemetria (`gameplay-discovery-168/`, `gameplay-discovery-167/`, etc.).
  - `psxrecomp/`: Core do recompilador estático/dinâmico e runtime MIPS R3000A.

---

## 3. Estado Atual do Projeto

### A. Track 1: Recompilação Estática (Main EXE `SLUS-005.48`)
- **Status**: **100% HOMOLOGADO** (Micro-lote S1-308).
- **Métricas Atuais**:
  - **1.357 funções nativas** compiladas no executável principal.
  - **154.836 palavras MIPS** (619.344 bytes) — **79,1660%** do executável base (`195.584` palavras).
  - **Misses Estáticos em Runtime**: **RIGOROSAMENTE ZERO** em todos os fluxos (Boot, FMVs, Menus, Options, Seletor de Modos, Seleção de Lutadores, Combate 26/26, Pause, Command List, Bonus Stage Barril, Replay e Tela de Recordes/Iniciais). Teste 168 confirmou 1.157.625 static hits e 0 misses.
- **Documentos de Referência**: [`progress.md`](progress.md) e [`buildResume.md`](buildResume.md).

### B. Track 2: Recompilação Dinâmica (Shards .DLL de Overlays)
- **Base Homologada Prévia**: 26/26 lutadores + projéteis/chamas = **1.943 DLLs nativas** no cache.
- **Campanha do Bonus Stage (Barril), Replay & Records (Lotes 1 e 2 - Testes 168 a 171)**:
  - **Lote 1 (Teste 168)**: Compilou 155 novas DLLs. Erradicou `0x8001D4B4` (260M), `0x80047E78` (26.4M), `0x8001BF44` (14M), etc. (+309M de instruções eliminadas).
  - **Captura Intra-Gameplay (Teste 169)**: Capturou os opcodes MIPS limpos durante o combate ativo dos barris, gerando o shard `04148C1D` (69 funções) com base inicial `0x00016000`.
  - **Diagnóstico Dual-Base (Teste 170)**: O playthrough completo revelou que o runtime exige a variante `0x00018000` quando iniciado a partir de opções/menus.
  - **Sincronização Dual-Base & Homologação Definitiva (Teste 171)**:
    - O script `compile_track2_bonus_barrel_overlay.ps1 -SyncOnly` sincronizou os pares `00016000 <-> 00018000`, elevando o cache para **2.140 DLLs nativas**.
    - **+4.095.435 dispatches nativos de overlay** (+2.447.881 dispatches nativos a mais que no Teste 170).
    - **ERRADICAÇÃO DE 100% DOS HOTSPOTS DO BONUS STAGE**:
      - `0x8001910C` (260.187.000 insns) -> **ZERO** (100% nativo)
      - `0x80019B30` (9.007.810 insns) -> **ZERO** (100% nativo)
      - `0x8001BA70` (4.649.941 insns) -> **ZERO** (100% nativo)
      - `0x8001AB70` (2.938.137 insns) -> **ZERO** (100% nativo)
      - `0x8001952C` (2.605.162 insns) -> **ZERO** (100% nativo)
      - `0x80018DE0` (2.601.779 insns) -> **ZERO** (100% nativo)
      - `0x8001C1C0` (1.745.409 insns) -> **ZERO** (100% nativo)
      - `0x8001B4C8`, `0x8001C260`, `0x8001C1EC`, `0x8001B6C0`, `0x8001C180`, `0x8001B740`, `0x8001B598`, `0x8001B604`, `0x8001B7C0`, `0x8001B670` -> **TODOS ZERADOS** (100% nativos).
    - **Instruções de Overlay de Jogo no Delta**: Despencaram de **288.770.000** (Teste 170) para **21.928** (Teste 171) — **99,9924% de redução**.
    - O restante das instruções interpretadas no delta (1.305.494 insns) restringe-se exclusivamente a rotinas de interrupção e timer de baixo nível da BIOS/Kernel PSX (`0x80004498`, `0x800000B0`, `0x80000C80`), sem impacto no framerate estável de 60.0 FPS.

---

## 4. Estado da Arte e Conclusão de Metas
- **Track 1 (Main EXE SLUS-005.48)**: 100% Homologado, 0 misses estáticos.
- **Track 2 (Personagens & Combate 26/26)**: 100% Homologado.
- **Track 2 (Bonus Stage Barril, Replay, Records)**: 100% Homologado.
- **Total de Shards Nativos Ativos**: 2.140 DLLs e 2.140 manifestos `.ranges`.
- **Frametime**: 60.0 FPS sólido em todos os modos de jogo.
