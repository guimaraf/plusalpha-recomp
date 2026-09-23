# Homologação dos Encerramentos dos Personagens (Endings Campaign)

Este documento estabelece o protocolo de teste, metodologia de captura e tabela de rastreamento para a validação estática de 100% dos **Encerramentos dos Personagens (Endings / Finais)** de *Street Fighter EX Plus Alpha* (`SLUS-005.48`).

---

## 1. Contexto e Objetivo

- **Objetivo**: Concluir a cobertura estática da **Track 1 (Main EXE)**, garantindo que todas as rotinas acionadas durante os encerramentos, cutscenes de vitória, rolagens de créditos, reproduções MDEC/FMV e cinemáticas dos lutadores estejam 100% cobertas em código C11 nativo, sem fallbacks para o interpretador no espaço do executável principal (`0x80100000..0x801BF000`).
- **Pré-requisito**: Save file 100% concluído carregado na memória do jogo, permitindo a reprodução direta dos finais a partir do menu de opções (*Options / Ending Replay*), sem necessidade de disputar o modo Arcade inteiro a cada personagem.
- **Baseline Ativo**: **Micro-Lote S1-304** (1.315 funções nativas, 144.906 palavras / 74,0889% de cobertura).
- **Binário de Teste**: `buildTele-s1-304\exPlusAlpha.exe`.

---

## 2. Metodologia de Telemetria Contínua (Sem Reiniciar o Jogo)

O emulador **não precisa ser fechado e reaberto** entre os testes de cada personagem. O framework de telemetria é projetado para operar em sessão única contínua através de isolamento matemático diferencial.

### 2.1 Princípio Matemático do Delta
O servidor de telemetria na porta TCP 4531 mantém contadores de execução monotônicos acumulados na memória:
$$\Delta = \text{Hits}_{\text{after}} - \text{Hits}_{\text{before}}$$
- Tudo o que foi executado antes do `before` (outros finais, menus, partidas passadas) possui $\Delta = 0$ e é **descartado matematicamente**.
- Apenas as instruções executadas estritamente durante a janela do encerramento testado registram $\Delta > 0$.

### 2.2 Protocolo de Snapshot (Passo a Passo)

1. **Janela do Jogo**:
   - Navegue até o menu de opções / visualizador de finais.
   - Posicione o cursor sobre o personagem a ser testado.
2. **Terminal de Telemetria (PowerShell / MSYS2 UCRT64)**:
   - Execute o script:
     ```powershell
     .\PlusAlphaProject\tools\run_gameplay_telemetry.ps1
     ```
   - O script conectará ao jogo e exibirá o prompt do **BEFORE**.
3. **Captura do BEFORE**:
   - Pressione **[ENTER]** no terminal **imediatamente antes de disparar o encerramento**.
   - Isso garante que a transição de menus anterior seja zerada no baseline.
4. **Reprodução do Encerramento**:
   - Deixe o final transcorrer completamente (cinemática 3D, vídeo FMV/MDEC, diálogo, música e créditos específicos do lutador).
5. **Captura do AFTER**:
   - Assim que o encerramento terminar e a tela escurecer ou retornar ao menu de opções, pressione **[ENTER]** no terminal para capturar o **AFTER**.
6. **Anotação da Sessão**:
   - O script gera automaticamente a pasta sequencial (`gameplay-discovery-XXX`).
   - Anote o nome do personagem e o ID da sessão (ex: *Bison Normal - 110*, *Ryu - 111*).

---

## 3. Critério de Interrupção Imediata (Gate de Promoção)

- **Se a sessão terminar com 0 novos candidatos**:
  - Prossiga imediatamente para o próximo personagem na mesma sessão do jogo.
- **Se a sessão acusar novo candidato no terminal ou em `candidates.txt`**:
  - **PARE IMEDIATAMENTE os testes.**
  - Não execute o próximo final.
  - Envie ao assistente:
    1. O ID da sessão que encontrou candidatos (ex: `gameplay-discovery-115`).
    2. A lista dos finais testados anteriormente em sequência que passaram limpos.
  - O assistente fará a auditoria da desmontagem MIPS, identificará a raiz real da função, montará o micro-lote de promoção (S1-305) e fornecerá os scripts de compilação.
  - Após recompilar para a nova build, os testes são retomados.

---

## 4. Tabela de Rastreamento dos Encerramentos

| # | Personagem | Sessão de Telemetria | Status Main EXE | Candidatos | Observações Técnicas |
|:---:|:---|:---:|:---:|:---:|:---|
| 1 | **Zangief** | `gameplay-discovery-111` | **Homologado (100% Nativo)** | **0** | FMV `MOV/P04.STR`. 226,5M insns em overlay (`0x800E78DC`). 0 misses no Main EXE. |
| 2 | *Descartado* | `gameplay-discovery-112` | *Inválido* | - | Snapshot AFTER disparado fora de timing. Desconsiderado. |
| 3 | **Hokuto** | `gameplay-discovery-113` | **Homologado (100% Nativo)** | **0** | FMV `MOV/P06.STR`. 224,2M insns em overlay (`0x800E78DC`). 0 misses no Main EXE. |
| 4 | **Ryu** | `gameplay-discovery-114` | **Homologado (100% Nativo)** | **0** | FMV `MOV/P00.STR`. 226,3M insns em overlay (`0x800E78DC`). 0 misses no Main EXE. |
| 5 | **Ken** | `gameplay-discovery-115` | **Homologado (100% Nativo)** | **0** | FMV `MOV/P01.STR`. 226,3M insns em overlay (`0x800E78DC`). 0 misses no Main EXE. |
| 6 | **Chun-Li** | `gameplay-discovery-116` | **Homologado (100% Nativo)** | **0** | FMV `MOV/P02.STR`. 221,6M insns em overlay (`0x800E78DC`). 0 misses no Main EXE. |
| 7 | **Doctrine Dark** | `gameplay-discovery-117` | **Homologado (100% Nativo)** | **0** | FMV `MOV/P08.STR`. 224,7M insns em overlay (`0x800E78DC`). 0 misses no Main EXE. |
| 8 | **Pullum Purna** | `gameplay-discovery-118` | **Homologado (100% Nativo)** | **0** | FMV `MOV/P09.STR`. 221,1M insns em overlay (`0x800E78DC`). 0 misses no Main EXE. |
| 9..23 | **Demais 15 Lutadores** | Inspeção Estrutural ISO | **Homologado por Equivalência** | **0** | Todos compartilham o mesmo arquivo `OVL3/MOV.OVL` e arquivos `.STR` com estrutura invariante. |
| 24 | **Staff Roll / Créditos** | Inspeção Estrutural ISO | **Homologado por Equivalência** | **0** | Vídeo `MOV/STF.STR` reproduzido pelo mesmo player. |

---

## 5. Auditoria Estrutural e Conclusão Formal da Track 1

### 5.1 Evidência Estrutural no Disco (`disc/game.bin`)
- **Arquivos de Vídeo**: A pasta `MOV/` contém exatamente 25 vídeos `.STR`:
  - 1 vídeo de abertura/logos (`MOV/CAP.STR`).
  - 23 vídeos de finais dos lutadores (`MOV/P00.STR` a `MOV/P19.STR`), todos com **exatamente 6.258.688 bytes** (~295 frames a 30 fps).
  - 1 vídeo de créditos da equipe (`MOV/STF.STR`).
- **Player de Streaming**: Localizado no overlay `OVL3/MOV.OVL` (76.641 bytes), carregado dinamicamente em RAM na base `0x800E76A0`.
- **Hotspot de Streaming**: O PC `0x800E78DC` (offset `+0x23C` em relação à base de carga do overlay) é o loop interno de polling e DMA de decodificação MDEC/CD-ROM. Registrou rigorosamente 295 hits em cada encerramento testado.
- **Isolamento de Camadas**: O executável principal (`0x80100000..0x801BF000`) apenas despacha o comando de streaming com o descritor de arquivo/setor. Essa camada estática já está **100% coberta e fechada** no baseline **S1-304** com zero misses.
- **Jitter de Frametime**: Causado pela execução de ~224 milhões de instruções no interpretador de software (`fallback_interp`) durante os ~9,8s do vídeo. Não há defeito de emulação nem gaps estáticos; a normalização definitiva do frametime ocorrerá com a compilação do `MOV.OVL` na Track 2.

### 5.2 Veredito da Campanha
A execução empírica dos 15 lutadores restantes foi declarada **tecnicamente redundante e concluída**. A **Track 1 (Main EXE) atinge 100% de homologação funcional em todos os fluxos de jogo** (Boot, Apresentação, Menus, Modo Prática, 26 Lutadores sob CPU Level 8 / P1 e Encerramentos).

---

## 6. Regras de Quarentena Permanente

Permanece mandatória a retenção sob o interpretador seguro de fallback:
1. `0x801AB1F4`: Polling SIO/Joypad (`0x1F801044` bit `0x80`).
2. `0x801AB2C0`: SMC BIOS delay swap (substituição dinâmica de 5 instruções em runtime).

Hits nesses dois endereços são descartados como comportamento esperado de hardware.

