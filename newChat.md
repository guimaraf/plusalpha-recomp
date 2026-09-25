# Briefing e Instruções para Continuidade no Novo Chat

## 1. Regras Mandatórias de Atuação (User Rules & Constraints)
- **Tom e Comunicação**: Estritamente técnico, franco e direto. Sem floreios, sem elogios ou desculpas desnecessárias. Vá direto ao ponto.
- **Correção Imediata**: Se o usuário propuser uma abordagem tecnicamente falha ou insegura, corrija-o imediatamente com justificativa técnica.
- **Host Ownership Inviolável**: O assistente **NUNCA** executa comandos de compilação de código nativo C/C++, invocação do recompilador (`psxrecomp-game.exe`), scripts de telemetria ou comandos de gameplay. Toda a compilação, execução do jogo e telemetria é realizada exclusivamente pelo **Operador** através de scripts PowerShell (`.ps1`). O assistente gera/edita os scripts, analisa logs e direciona a arquitetura.

---

## 2. Contexto do Projeto e Repositório
- **Projeto**: Recompilação Nativa C11 de *Street Fighter EX Plus Alpha* (USA, `SLUS-005.48`).
- **Diretório Principal**: `f:\GitRevised\alphaplus\plusalpha-recomp`
- **Subdiretórios Críticos**:
  - `PlusAlphaProject/`: Projeto CMake, fontes C geradas, binários (`buildTele-s1-309/exPlusAlpha.exe`) e scripts de build.
  - `PlusAlphaProject/tools/`: Scripts de automação PowerShell (`compile_track2_training_mode.ps1`, `compile_track2_expert_mode.ps1`, `run_gameplay_telemetry.ps1`, etc.).
  - `PlusAlphaProject/local/telemetry/`: Sessões de telemetria (`gameplay-discovery-179/`, `gameplay-discovery-178/`, etc.).
  - `psxrecomp/`: Core do recompilador estático/dinâmico e runtime MIPS R3000A.
  - `buildTele-s1-309/cache/`: Diretório do cache nativo de DLLs e manifestos `.ranges`.

---

## 3. Estado Atual do Projeto (Checkpoint Teste 179)

### A. Track 1: Recompilação Estática (Main EXE `SLUS-005.48`)
- **Status**: **100% HOMOLOGADO** (Micro-lote S1-309, commit `d4c0bc8`).
- **Métricas Atuais**:
  - **1.358 funções nativas** compiladas no executável principal.
  - **154.846 palavras MIPS** (619.384 bytes) — **79,1711%** do executável base (`195.584` palavras). Os 20,83% restantes são constantes, tabelas de salto (*jump tables*), strings e código arcade inacessível.
  - **Misses Estáticos em Runtime**: **RIGOROSAMENTE ZERO** em todos os fluxos testados (Boot, FMVs, Menus, Options, Seletor de Modos, Seleção de Lutadores, Combate 26/26, Pause, Command List, Bonus Stage Barril, Replay, Records, Expert Mode e Training Mode).
- **Documentos de Referência**: [`progress.md`](progress.md) e [`buildResume.md`](buildResume.md).

### B. Track 2: Recompilação Dinâmica (Shards .DLL de Overlays)
- **Status Atual do Cache**: **2.219 DLLs nativas** e **2.219 manifestos `.ranges`** (3.843 funções dinâmicas).
- **Campanhas Homologadas**:
  1. **Elenco Completo de Personagens**: 26/26 lutadores (23 jogáveis + 3 chefes CPU) 100% nativos (1.943 DLLs base).
  2. **Motores de Projéteis / Chamas**: 14/14 rotinas homologadas (100%).
  3. **Bonus Stage (Barril), Replay & Records (Testes 168-171)**: 100% nativo (+4,09M dispatches nativos, 2.140 DLLs).
  4. **Expert Mode (Testes 172-175)**: 100% nativo com Ken e Skullomania (+590k dispatches nativos, 2.216 DLLs).
  5. **Training Mode (Testes 176-179)**: 100% nativo com Ken x Ryu (+675k dispatches nativos, 2.219 DLLs).
     - **Resíduo de código de jogo interpretado**: **RIGOROSAMENTE ZERO**.
     - **Native handoffs (quebras de contexto)**: **ZERO**.
     - **Raízes MIPS declaradas em `game.toml` sob `[[overlays]]` (`load_addr = "0x80020000"`)**:
       - `0x80047E78` (função hospedeira de física/colisão que cobre o alias interno `0x8004809C`).
       - `0x80046BC8`, `0x8004649C`, `0x80044818` (rotinas de HUD/pause de treino).
     - **Script de automação**: [`PlusAlphaProject/tools/compile_track2_training_mode.ps1`](PlusAlphaProject/tools/compile_track2_training_mode.ps1).

---

## 4. Diretrizes para o Próximo Chat (Campanha do Pente Fino)

O usuário está realizando testes adicionais para verificar se restou algum resíduo em modos ou combinações específicas.

Quando o usuário apresentar os resultados de um novo teste:
1. **Separar Imediatamente BIOS Sony vs. Código do Jogo**:
   - A linha global `Fallback Interprete` do sumário de telemetria é dominada em > 99,5% pela BIOS Sony (`0x80004498`, `0x80000C80`, `0x800000B0`, `0x8000641C`).
   - A BIOS Sony é mantida interpretada propositalmente para sincronismo de hardware sem regressões. Variações na contagem da BIOS refletem apenas o tempo decorrido de execução (wall-clock time).
   - O foco da auditoria deve ser estritamente em **código do jogo fora da faixa `0x8000xxxx`**.
2. **Se surgirem hotspots de jogo interpretados (faixa `0x8001xxxx` a `0x800Fxxxx`)**:
   - Verificar se há capturas no arquivo `overlay_captures.json` da sessão.
   - Detectar chaves com `detect_capture_keys.py`.
   - Inspecionar se o hotspot é uma raiz legítima de função MIPS (`addiu $sp, $sp, -imm` ou logo após `jr $ra`) ou uma continuação/alias interno.
   - Se for raiz não identificada automaticamente (chamada indireta), adicioná-la a `game.toml` sob `[[overlays]]`.
   - Se for continuação interna, identificar sua função hospedeira.
   - Gerar/executar script PowerShell dedicado para compilar os shards para o cache.
3. **Se surgir algum miss estático no Main EXE (`0x80101000..0x801C0000`)**:
   - Trata-se de evento raro (Track 1 está com 0 misses há dezenas de testes).
   - Seguir rigorosamente o protocolo de isolamento: preview de fechamento alcançável (*reachable closure*), validação de orçamento de palavras e geração do micro-lote sem quebrar a compilação existente.
