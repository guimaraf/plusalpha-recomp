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
| 1 | **Ryu** | - | Pendente | - | - |
| 2 | **Ken** | - | Pendente | - | - |
| 3 | **Chun-Li** | - | Pendente | - | - |
| 4 | **Guile** | - | Pendente | - | - |
| 5 | **Zangief** | - | Pendente | - | - |
| 6 | **Dhalsim** | - | Pendente | - | - |
| 7 | **Hokuto** | - | Pendente | - | - |
| 8 | **Cracker Jack** | - | Pendente | - | - |
| 9 | **Doctrine Dark** | - | Pendente | - | - |
| 10 | **Pullum Purna** | - | Pendente | - | - |
| 11 | **Darun Mister** | - | Pendente | - | - |
| 12 | **Kairi** | - | Pendente | - | - |
| 13 | **Sakura** | - | Pendente | - | - |
| 14 | **Blair Dame** | - | Pendente | - | - |
| 15 | **Allen Snider** | - | Pendente | - | - |
| 16 | **Skullomania** | - | Pendente | - | - |
| 17 | **Akuma** | - | Pendente | - | - |
| 18 | **Garuda** | - | Pendente | - | - |
| 19 | **M. Bison** | - | Pendente | - | - |
| 20 | **Cycloid-β** | - | Pendente | - | - |
| 21 | **Cycloid-γ** | - | Pendente | - | - |
| 22 | **Bloody Hokuto** | - | Pendente | - | - |
| 23 | **Evil Ryu** | - | Pendente | - | - |
| 24 | **Finais Especiais / Extras** | - | Pendente | - | Qualquer final desbloqueável adicional no menu Options. |

---

## 5. Regras de Quarentena Permanente

Permanece mandatória a retenção sob o interpretador seguro de fallback:
1. `0x801AB1F4`: Polling SIO/Joypad (`0x1F801044` bit `0x80`).
2. `0x801AB2C0`: SMC BIOS delay swap (substituição dinâmica de 5 instruções em runtime).

Hits nesses dois endereços são descartados como comportamento esperado de hardware.
