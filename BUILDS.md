# Arquitetura de Builds do Projeto (Street Fighter EX Plus Alpha)

Este documento define a separação das categorias de builds do projeto, seus papéis técnicos, ciclo de vida do launcher e as versões mantidas para comparação e auditoria histórica.

---

## 1. Build de Release para Publicação (`buildNoCopyright-s1-*`)

- **Diretório**: `PlusAlphaProject/buildNoCopyright-s1-268/`
- **Executável Principal**: `exPlusAlpha.exe` (~12.29 MB, *stripped*)
- **Título da Janela**: `Ex Plus Alpha`
- **Finalidade**: Distribuição pública 100% livre de direitos autorais (*Clean-Room Pipeline*), contendo **0 bytes** de ativos ou código proprietário da Sony/Capcom.

### Ferramenta de Compilação Interna Portátil (`compileBuild/`)
A build de release incorpora um ecossistema de compilação portátil e autocontido:
- **TinyCC 0.9.27** (compilador C ultrarrápido).
- **Python 3.11.9 embeddable** + `psxrecomp-game.exe`.
- Parser nativo ISO9660 (`disc_extractor.cpp`) para extração de `SLUS_005.48`.
- Headers do runtime e scripts de compilação local (`compile_game_core.bat`, `compile_tcc_overlays.bat`).

### Comportamento do Launcher na Release
O frontend foi instrumentado para verificar a presença dos arquivos pré-compilados do jogo:
1. **Primeira Execução (Arquivos Ausentes)**:
   - Como `game_core.dll` e `cache/` **não existem** na distribuição, o launcher detecta automaticamente essa ausência e exibe a **primeira tela / wizard de setup**.
   - Nessa tela, o usuário seleciona a imagem de disco original (.cue/.bin/.iso), a BIOS e clica no botão de **Compilar**.
   - O processo extrai `SLUS_005.48`, recompila as funções em C e gera `game_core.dll` e os shards dinâmicos em `cache/` em poucos segundos.
2. **Pós-Instalação**:
   - Um botão **"Remove Compilers"** na interface permite excluir a pasta `compileBuild/` (~65 MB), tornando a pasta enxuta e 100% independente.
3. **Execuções Subsequentes**:
   - Com `game_core.dll` já presente, a tela inicial de setup/build **não aparece mais** — o launcher vai direto para a inicialização do jogo.

---

## 2. Build de Telemetria e Instrumentação (`buildTele-s1-*`)

- **Diretório**: `PlusAlphaProject/buildTele-s1-268/`
- **Executável Principal**: `exPlusAlpha.exe` (~217.95 MB, com telemetria e código estático integrado)
- **Perfil de Compilação**: `RelWithDebInfo` (`-O2 -g -DNDEBUG`) com `PSX_DEBUG_TOOLS=ON` e `PSX_STATIC_RUNTIME=ON`.
- **Finalidade**: Testar, debugar e instrumentar rotas de combate, menus e modos de jogo para identificar instruções interpretadas (*misses*) e *hotspots* de overlays para guiar os próximos micro-lotes (ex: **S1-269**).

### Totalmente Pronta para Testes Imediatos
Diferente da release, a build de telemetria é preparada para máxima produtividade de desenvolvimento:
- **Tudo Pré-Compilado**:
  - Código C do jogo integrado estaticamente (`SLUS_005.48_full.c` e `SLUS_005.48_dispatch.c` com as 1.113 funções nativas até S1-268).
  - DLLs dinâmicas (`game_core.dll`) e cache completo de overlays (`cache/SLUS-00548/gcc` e `cache/SLUS-00548/tcc`) já copiados e sincronizados.
- **Zero Etapas Manuais de Compilação**: Não é necessário extrair disco nem compilar nada; o desenvolvedor roda os testes imediatamente.
- **Ignora Tela de Setup**: Como todos os arquivos e módulos do jogo já estão gerados e presentes, o launcher não abre o wizard de build — ele inicia diretamente no jogo com o servidor de telemetria ouvindo na porta TCP **`4531`**.

### Execução da Telemetria
- **Iniciar jogo instrumentado**:
  ```cmd
  PlusAlphaProject\buildTele-s1-268\run_telemetry.bat
  ```
  *(ou via `tools/run_gameplay_telemetry.ps1`)*
- **Capturar dados em tempo real (em terminal separado)**:
  ```powershell
  python tools/observe_gameplay.py
  python tools/observe_menus_navigation.py
  python tools/observe_boot_to_charselect.py
  ```

---

## 3. Registro Histórico de Comparação (Checkpoints de Validação)

Para evitar qualquer tipo de regressão (frametime, estabilidade, colisões, hitboxes ou áudio), o projeto preserva duas versões de referência em checkpoints de release limpa (`PSX_DEBUG_TOOLS=OFF`, monolítico `RelWithDebInfo`):

### A. `buildClean-ucrt-s1-266`
- **Marco**: Conclusão da grande campanha de erradicação de menus.
- **Métricas**: 125.435 palavras de cobertura estática (64,13%), 1.108 funções.
- **Finalidade**: Gabarito estável de menus, navegação, telas de opções e combate inicial.

### B. `buildClean-ucrt-s1-268`
- **Marco**: Integração da Máquina de Estados de Match (FSM - S1-267) e do Cluster de Processamento de Entidades/Frames (S1-268).
- **Métricas**: 126.830 palavras de cobertura estática (64,84%), 1.113 funções nativas promovidas, 18.271 entradas de dispatch.
- **Finalidade**: Gabarito oficial de combate ativo a 60.0 FPS fixos com **100% de dispatch nativo no Main EXE** (zero misses em rounds completos de luta).

> **Diretriz de Testes**: Qualquer nova build ou micro-lote promovido no futuro deve ser comparado diretamente contra `buildClean-ucrt-s1-268` para certificar que nenhum comportamento regrediu.
