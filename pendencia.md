# Pendências — Fase 2 (cobertura do EXE)

Estado em 2026-11-26, após o lote F2-L26 (commit `2a1e651`, em `origin/main`).

## Onde estamos

- EXE (`SLUS_005.48`): **174.051 de 174.246 palavras de código cobertas (99,8881%)**, 1.628 funções, 24.708 entradas de dispatch.
- Faltam **195 palavras**. A quarentena SIO/SMC (29 palavras) já fica fora da métrica e continua interpretada de propósito.
- A fila de órfãs (lotes P01–P08, política 2a) está **esgotada**: 144 raízes aplicadas entre F2-L18 e F2-L26.
- Toda a cobertura das órfãs é **estática**. Nenhuma delas foi vista executando, porque o fntrace não estava armado para elas.
- Histórico detalhado: `docs/PLANO_100.md` (Fase 2, "Andamento" e "Pendências") e `docs/newWords.md` (§1 governança e §6 lotes).
- Evidências e relatórios (fora do repositório): `F:\GitRevised\alphaplus\relatorios\fase2\`, começando por `sessao-2026-11-26.html`.

## 1. Bloqueia o fechamento da Fase 2

### 1.1 Validação de sensação de jogo (usuário)

`generated-online/` e `coverage/baseline.json` só podem ser promovidos depois que o usuário testar uma build nova e aprovar. Essa promoção é o último passo formal da Fase 2.

**Build para testar (99,8881%): `release\Jogar.bat`, na raiz do repositório**

- `release\` é uma build **Release limpa**, gerada em 2026-11-26, e não é versionada (excluída só pelo `.git/info/exclude` desta máquina).
  - `CMAKE_BUILD_TYPE=Release` (`-O3`) e `PSX_DEBUG_TOOLS=OFF`: sem servidor TCP de debug, sem gravação por bloco e sem os buffers de diagnóstico.
  - Continuam ativos, de propósito: o relatório de crash `psx_last_run_report.json` e o heartbeat anti-travamento (`psx_freeze_heartbeat_*.json`, cerca de 1 KB/s).
  - Código: cópia exata de `build-auto-p2infra\generated` e `static-overlays` do F2-L26 (commit `2a1e651`). O manifesto sha256 bate com a origem. Snapshot e build em `PlusAlphaProject\build-release-online-9988\`; logs em `F:\GitRevised\alphaplus\relatorios\fase2\release-9988\`.
  - `exPlusAlpha.exe` com sha256 `575E64ED98D8D9BFE2AA7D65DC42F12F30BE2AB63C56F87201775777CA5D8D9F`.
  - Smoke test: 30 s vivo, sem relatório de crash e sem porta de debug em escuta.
- O `Jogar.bat` abre o launcher normal, para você escolher o renderer e desligar as opções de aceleração. Ele usa o disco em `PlusAlphaProject\disc-a\`, a BIOS em `gameFiles\bios\` (caminhos absolutos desta máquina) e o memory card em `release\memcard\` (vazio, separado dos saves normais).
- O `game.toml` vem com `renderer = "software"`. Escolha o renderer no launcher antes de medir frame time.
- `input.ini` e `keybinds.ini` são recriados no primeiro uso. Para usar os seus, copie-os para `release\`.
- O que observar: frame time e FPS (RivaTuner), engasgo ao salvar (que apareceu no teste anterior), input e latência, áudio, menus, luta completa e modos (Arcade, Versus, Survival, Options).
- Se der erro ou travar, os arquivos de diagnóstico ficam em `release\`: `psx_last_run_report.json`, `psx_freeze_heartbeat_*.json`, `psx_freeze_dump_*.json` e `starvation_dump.jsonl`. Guarde esses arquivos.
- A build de desenvolvimento `PlusAlphaProject\build-auto-p2infra\exPlusAlpha.exe` (`RelWithDebInfo`, `PSX_DEBUG_TOOLS=ON`) **não serve** para avaliar a sensação de jogo, porque a instrumentação pode causar engasgos.

**Resultado do teste do usuário (2026-11-26, depois de reiniciar o computador, `release\Jogar.bat`):**

- No geral a linha de frame time (RivaTuner) ficou estável.
- **Micro engasgo ao executar especiais.** Suspeita, não confirmada: o efeito do especial (flash, tela amarela que pisca no KO por especial, som diferente) passa por código ainda interpretado, por carga de overlay ou de áudio, ou por um caminho que as rotas automáticas nunca exercitaram. As rotas (`boot_to_fight`, `survey_*`) não fazem especiais nem KO por especial.
- Engasgo no save: ainda não reportado neste teste. Medido depois no pente fino (sessão 6): 2 frames a cada 16 durante o load e o save, porque o jogo espera o cartão de forma síncrona (§4, "Memory card").
- **Sensação NÃO aprovada.** A promoção de `generated-online/` e do baseline fica bloqueada até o pente fino abaixo.

**Pente fino (próximo passo, num chat dedicado):** sessão manual de modo Arcade (dificuldade mínima, de preferência até zerar), com especiais, combos, super e KO por especial. O jogo roda na build de desenvolvimento com telemetria, e o agente acompanha pela porta de debug.

- Build: `PlusAlphaProject\build-auto-p2infra\exPlusAlpha.exe` (`RelWithDebInfo`, `PSX_DEBUG_TOOLS=ON`, mesmo código do F2-L26, porta `debug_port = 4531` do `game.toml`). Serve para coletar PCs e misses, **não** para medir frame time, porque a instrumentação causa engasgos próprios.
- O que coletar:
  - PCs do EXE interpretados fora da quarentena SIO/SMC;
  - misses de overlay e PCs de overlay interpretados (personagens e efeitos);
  - momento (frame) de cada engasgo, cruzado com o que estava na tela;
  - `starvation_dump.jsonl` e `psx_freeze_*`, se aparecerem.
- Não existe ferramenta pronta para acompanhar uma sessão manual: o `auto_session.py` só roda rotas. A sessão vai precisar de um script de coleta pela porta TCP, só de leitura, sem enviar input.
- Saída esperada: lista de PCs e alvos novos para seeds (EXE) ou para a Fase 3 (overlays), e o diagnóstico do engasgo nos especiais.

**Roteiro do gameplay guiado** (o usuário joga normalmente; o agente só observa e analisa):

1. **Preparação (agente):** script de coleta só de leitura pela porta TCP 4531, sem enviar input e sem tirar o foco da janela. Medir a linha de base dos PCs interpretados (esperados: só os 6 da quarentena) antes de o usuário começar.
2. **Abertura (usuário):** roda a build de desenvolvimento com o launcher. O agente passa o comando exato e confirma a conexão.
3. **Sessão (usuário):** modo Arcade na dificuldade mínima, de preferência até zerar, variando os personagens. Exercitar:
   - especiais de cada personagem;
   - combos e cancelamentos;
   - super e excel;
   - KO por especial e por super (tela amarela piscando, som diferente);
   - telas entre lutas, continue, final do Arcade e créditos;
   - save no memory card (para conferir o engasgo do save visto antes).
4. **Durante a sessão:** o usuário avisa o momento de cada engasgo ("agora", com o que aconteceu). O agente anota o frame e cruza com os PCs e misses daquele instante.
5. **Fechamento (agente):**
   - classificar cada PC ou miss novo (seed do EXE, Fase 3 de overlay, ou sem relação, como ambiente ou instrumentação);
   - diagnosticar o engasgo nos especiais;
   - registrar tudo aqui e em `docs/PLANO_100.md`, com evidências em `F:\GitRevised\alphaplus\relatorios\fase2\pente-fino\`.
6. **Depois:** corrigir o que estiver ao alcance da Fase 2 (seeds novas com execução observada, em lotes normais). Gerar uma nova build Release limpa, para o usuário medir o frame time de novo. Só com a sensação aprovada: promover `generated-online/` e o baseline e fechar a Fase 2.

**Resultado do pente fino (2026-11-26, sessão guiada):**

- **Exercitado (observado):** Arcade (Darun, Zangief, Sakura, Akuma), Prática com cancelamentos de especial, Versus x CPU (Akuma contra Bison) com KO por especial e replay do KO, e Expert Mode (menu/lição, especiais, combinação, troca de música). Fechamento: o jogo saiu normalmente (`psx_last_run_report.json` com `reason = atexit`); nenhum `psx_freeze_dump` nem `starvation_dump` novo; 0 misses de dispatch na sessão inteira.
- **Diagnóstico do micro engasgo nos especiais:** queda de 1 frame (às vezes 2) no início do especial. Durante um vblank inteiro (564.480 ciclos) o guest não envia nada à GPU, porque a lógica do jogo passa do orçamento. Essa lógica é do EXE nativo (laço de objetos `0x8010C314..0x8010C3CC` e rotinas por objeto). O runtime então repete o frame (present_skip). Não é disco (0 comandos de CD perto das quedas), código interpretado, áudio (0 underruns) nem loop do host (16,7 ms estável). O som (KEYON `0x0A460`) só coincide: há quedas sem KEYON. A queda não é certa em todo especial (Akuma: 1 queda em 2 golpes).
- **Casos sustentados a 30 fps:** só a combinação do Expert Mode no primeiro SUCCESS das lições 6 e 7 (~0,8 s, libgte por software `0x8019D270`/`0x8019DF20` e laço `0x80147xxx`), que se repete no MiSTer e, menor, no DuckStation. **Correção (2026-11-26):** o trecho de ~3,4 s a 30 fps registrado antes como "replay do KO" (Versus x Bison, 72642–72845) era o menu de pausa (Start): `0x80189204` é o laço de espera da pausa, que redesenha a cada 2 vblanks com o cenário congelado. Na sessão 5 (Versus, Akuma x Kairi, KOs com level 1, 2 e 3 e replays completos) o replay rodou a 60 fps, sem esse laço, como no MiSTer.
- **Modelo de ciclos:** o investigador conferiu que é igual ao Beetle/R3000A em MULT/DIV, GTE, RAM e custo base. Write queue e DMA cycle steal não são modelados (o runtime fica mais barato que o hardware nesses eixos). Não há correção de ciclos justificada. Não há traço de ciclos de referência; a comparação com o hardware é a do A/B abaixo, que mede o resultado visível (frames perdidos) no SUCCESS do Expert Mode e, num segundo vídeo do MiSTer (`.reference/streetSpeciais.mp4`, Akuma), nos especiais: o hardware perde 1 frame no início do especial (hadouken saindo, arranque do level 3) e nos efeitos de impacto, como o recomp. Um A/B do mesmo combate (Versus, Akuma x Kairi, KO com level 1, 2 e 3 e com Hadouken; vídeos `.reference/ak*.mp4` x sessão 5 do recomp) mostrou as perdas nos mesmos pontos (início de especial, cancelamento, impacto, flash do KO, kanji do level 3) e os replays a 60 fps nos dois; nesse combate, nenhum trecho do recomp perde mais que o MiSTer (no SUCCESS do Expert, ao contrário, o recomp perde ~5 frames a mais: ~24 x 19). Nos flashes de KO o MiSTer mostra mais imagens repetidas (level 2: ~40 x 7), mas os métodos diferem (vídeo conta imagens idênticas; o recomp conta vblanks sem troca de frame). Para a contagem exata falta gravar o recomp em vídeo e analisar com o mesmo script (§4). Origem do bit 17 do SR e do IRQ de DMA nesses vblanks: não identificada.
- **Classificação:**
  - Fase 2: nenhuma seed nova (nenhum PC do EXE fora da quarentena). Ao fim, os PCs interpretados são 6 da quarentena, 12 do kernel (BIOS HLE) e 3 em RAM de overlay.
  - Fase 3: `0x800222D4` e `0x80024E8C` (RAM baixa, chamados do EXE, ext_ra `0x801931B4` e `0x801931DC`; classificar se overlay ou bloco copiado) e `0x800E6F4C` (Expert Mode, dentro de overlay, ext_ra `0x800E65A4`).
  - Runtime/fidelidade: quedas nos especiais, no flash do KO e na combinação do Expert Mode; o A/B mostrou que são do jogo original.
- **A/B feito (2026-11-26): os engasgos são do jogo original.** Mesmo disco (USA, SLUS_005.48), Expert Mode com Ryu, lições 6 e 7. No SUCCESS de cada lição, o MiSTer FPGA (vídeo da placa de captura, `.reference/sfMister.mp4`, não versionado) perde 19 frames em ~0,73 s (30 fps), o recomp ~24 frames em ~0,78 s e o DuckStation limpo (`duckstation/`, não versionado) só 2–3. O MiSTer também perde 1 frame isolado num impacto com efeito. Conclusão: o recomp está fiel ao hardware (o DuckStation roda esse trecho mais rápido que o console); não há correção de timing nem seed de Fase 2. Limite: a correspondência dos eventos do recomp com as lições é por horário e relato (sem imagem do recomp nesses frames).
- **Diferença só de apresentação (opcional, fora da Fase 2):** quando o jogo repete um frame, o recomp pula o swap (`present_skip`, `gpu_gl_renderer.c`), e o RivaTuner mostra um pico de 33 ms; DuckStation e MiSTer repetem a imagem a cada vblank e a linha fica em 60. A imagem vista é a mesma. Apresentar o frame repetido deixaria o frame time reto (e pode ajudar com VRR). Melhoria futura, também opcional: overclock de CPU desligado por padrão para eliminar a lentidão original.
- A promoção de `generated-online/` e do baseline continua aguardando a aprovação explícita do usuário, agora com o diagnóstico de que os engasgos são do original.
- Evidências: `F:\GitRevised\alphaplus\relatorios\fase2\pente-fino\` (`notas_sessao_guiada.md`, `sessao-2` a `sessao-4`, `coleta_pente_fino.py`).

**Sessão 6: Arcade completo com o card de tudo liberado (2026-11-26, 14:13–14:35, build de telemetria, 76.049 frames, cerca de 21 min):**

- **Exercitado:**
  - load e save do memory card;
  - Arcade na dificuldade fácil com personagem secreto, até o chefe final;
  - a luta secreta contra o Akuma especial (liberada por perfects);
  - continue (2 derrotas) e game over;
  - End Collection com 3 finais (FMV): o final equivalente a vencer o Bison, o da Skullomania e o da Sakura.
  - Replays foram cortados com Start, porque já tinham sido analisados na sessão 5.
  - Nas sessões anteriores o usuário já tinha passado por todos os personagens, dos dois lados.
- **Cobertura:**
  - 0 misses de dispatch e 0 misses de overlay na sessão inteira;
  - nenhum PC do EXE interpretado fora da quarentena;
  - interpretados no fim: 6 da quarentena, 12 do kernel (BIOS) e 1 em RAM de overlay (`0x800222D4`, já na lista da Fase 3).
  - Chefe final, Akuma especial, continue, game over e finais **não trouxeram nenhum PC novo**.
  - O jogo fechou normalmente, sem `psx_freeze_dump` e sem `starvation_dump`.
- **Quedas de frame:** 83 no total.

  | Trecho | Quedas | Natureza |
  |---|---|---|
  | Load e save do card | 8 | 2 frames cada (§4, "Memory card") |
  | Arcade (lutas, chefe, Akuma especial, continue) | 70 | 1 frame cada, no padrão já diagnosticado como do jogo original (especiais, impactos, KO) |
  | Entrada dos vídeos de final | 2 | 3 frames cada (67 ms), na hora do seek do CD que inicia o FMV (frames 68804 e 72451) |
  | Boot e menus | 3 | — |

  - Nos FMVs o contador do OpenGL mostra 15 fps porque o vídeo foi gravado a ~15 fps. O jogo segue com 60 flips por segundo, e o áudio fica normal. É o mesmo caso da apresentação do frame repetido (opcional, §4).
- **Observação (vista uma única vez em todo o projeto): tela travada/marrom de ~0,5 s ao entrar no cenário do Dhalsim** (14:23:38, frames 36341–36347). Sem miss e sem PC novo. Detalhe no §2.
- **Classificação:**
  - Fase 2: nenhuma seed nova.
  - Fase 3: nada novo.
  - Dhalsim: só observação, sem ação agora (§2).
  - Memory card: trabalho futuro (§4).
- Evidências: `pente-fino\sessao-6\` (`marks.jsonl` com os trechos, `quedas\`, `hitches\hitch_36344.json`, `atencao\dhalsim_38959.json`, `memcard\`) e `sessao-6-console.log`.

**Sessão 7: telas complementares (2026-11-26, 14:50–15:31, build de telemetria, 146.980 frames, ~41 min):**

- **Exercitado:**
  - fase bônus do barril (overlay `BONUS.OVL`);
  - Treinamento, com a tela de configuração (CPU pula/defende) e o replay do treino;
  - Expert com Ken, Skullomania, Pullum Purna e outros, voltando à seleção do Expert;
  - save no memory card;
  - Team Battle 5x5 duas vezes: derrota com "sair" e vitória completa contra 5 Skullomania;
  - menu de save state do recomp (Select+L1).
- **Cobertura:**
  - 0 misses de dispatch e de overlay;
  - interpretados no fim: 6 da quarentena, 12 do kernel (BIOS) e mais 4 PCs:

    | PC | Classe | Entradas | Origem | Destino |
    |---|---|---|---|---|
    | **`0x80184994`** | EXE | 185 | caso 1 da jump table da tela final do Team Battle | **Fase 2**, §1.4 |
    | `0x800E6F4C` | overlay | 2.186 | Expert, já conhecido | Fase 3 |
    | `0x8004744C` | overlay | 75 | rotina da Skullomania, `PL06` | Fase 3, §3 |
    | `0x80090E4C` | overlay | 75 | a mesma rotina da Skullomania, no outro lado da luta | Fase 3, §3 |

  - O jogo fechou normalmente (`reason = atexit`).
- **Quedas:** 131, sendo 128 de 1 frame (especiais, impactos e KO, padrão do original; o especial da Kairi caiu nas rotinas `0x8010D754`/`0x8010D7AC` do catálogo) e 3 de 2 frames (save no cartão).
- **Engasgo severo:** um só, de 4,2 s às 15:19:01, quando o usuário abriu o menu de save state do recomp. Não é defeito: o jogo fica parado enquanto o menu está aberto, e o perfil do host fica em `ntdll.dll`/`win32u.dll` (thread esperando). Todos os 179.394 underruns de áudio da sessão (cerca de 4,1 s de amostras a 44,1 kHz) são desse momento. O contador do coletor é em amostras, então os 5.966 do Dhalsim na sessão 6 equivalem a cerca de 135 ms.
- **Ainda sem cobertura manual:**
  - concluir um desafio do Expert (§1.3);
  - o final do Arcade depois de vencer o chefe, com créditos ou staff roll se existirem nesta versão. É preciso zerar sem perfects, para não cair no Akuma especial. O overlay `OVL3/END.OVL` já está compilado (224 palavras); a End Collection (sessão 6) não trouxe PCs novos.
- Evidências: `pente-fino\sessao-7\` (`marks.jsonl`, `pcs_novos.jsonl`, `quedas\`, `hitches\hitch_102276.json`, `resumo.json`) e `sessao-7-console.log`.

**O que falta para fechar a Fase 2 (estado após a sessão 7):**

1. **Aprovação da sensação pelo usuário.** O pente fino não achou nada de cobertura do EXE. Os engasgos de especial, KO e Expert são do original (A/B com o MiSTer). O caso do Dhalsim fica só como observação (§2) e não bloqueia.
2. **§1.2 (195 palavras): decidido.** Ficam em espera sem exclusão; a métrica segue em 99,8881%. Revisitar depois dos overlays.
3. **Achado da sessão 7 (§1.4):** caso 1 da jump table da tela final do Team Battle (`0x80184994`) roda interpretado; corrigir num micro-lote.
3b. **Exercícios complementares de telas (§1.3):** pausa em cada contexto, configurações, Treinamento e, se possível, o fim de um desafio do Expert.
4. **Só com aprovação explícita:** promover `generated-online/`, atualizar o baseline (depois de qualquer mudança de exclusões) e registrar o fechamento em `docs/PLANO_100.md`.
5. **Commit dos registros** (`pendencia.md`, `docs/PLANO_100.md`), quando o usuário pedir.

**Se a sensação for aprovada (depois do pente fino):** promover `generated-online/` a partir de `build-auto-p2infra/generated`, atualizar a linha de base com `python PlusAlphaProject/tools/coverage_metric.py ... --update-baseline` e registrar o fechamento da Fase 2 em `docs/PLANO_100.md`.

### 1.2 Decisão sobre as 195 palavras restantes (usuário)

Nenhum destes grupos é caso de micro-lote de seeds:

| Grupo | Palavras | Situação | Opções |
|---|---|---|---|
| Instalador do SDK: `0x801AB180`, `0x801AB35C`, `0x801AB380` | 54 | Bloqueado: sem chamador estático e vizinho da quarentena SIO/SMC. `0x801AB1E0` salta para `0x801AB1F4`, que está na quarentena | Investigação F2-Rx, ou deixar interpretado |
| Função `0x8015547C` (classe A) | 75 | Sem referência estática no EXE. Os overlays têm um caminho estático, mas a hipótese da rota `versus_pl0c_pl12` (sequência no versus) não confirmou execução | Prova de execução, promoção explícita sem execução observada, ou passar para a Fase 3 |
| Resto: epílogos mortos (`lw ra/sp; jr ra` sem referência), bloco copiado para o kernel (`0x8019F1B8..F1F0`), palavras de dados (`0x8019C9A0`, `0x8019FB44`) e padding de nops | ~66 | Classificação do investigador feita sobre a base F2-L24 (`relatorios\fase2\F2-Rx\nao_cobertas_grupos.json`), **não reconferida** no estado atual | Marcar dados/padding como exclusão em `exclusions.json` e classificar o código morto (decisão de governança) |

Recomendação do coordenador: excluir dados e padding depois de reconferir a lista sobre o build atual, e deixar o instalador `0x801AB` e `0x8015547C` interpretados ou para a Fase 3.

**Reconferência sobre o F2-L26 (2026-11-26).** `coverage_metric.py` sobre `build-auto-p2infra/generated`, sem tocar no baseline: 174.051 / 174.246 (99,8881%), 0 entradas de dispatch sem cobertura. As 195 palavras ficam em 23 trechos e 6 grupos. A soma fecha em 195:

| Grupo | Palavras | Conteúdo | Classe proposta |
|---|---|---|---|
| Epílogos mortos | 36 | `0x801014C8`, `0x80103370`, `0x8016ADE4`, `0x8018CE00` e `0x8018CF34`: `lw ra/s*; addiu sp; jr ra; nop` sem nenhum salto que chegue a eles. Sobra de compilador, depois de um `return` dentro de laço infinito ou de um desvio incondicional | `morto_provado` |
| Padding de nops | 12 | `0x801932C8`, `0x801932D4`, `0x80193768/778/788`, `0x8019CD5C`, `0x8019DECC`, `0x8019FB70/80` e `0x8019FC0C`: zeros de alinhamento entre funções | `padding` |
| Palavras de dados | 4 | `0x8019C9A0` e `0x8019FB44`: pares que desmontam como `jal` para fora da RAM do jogo (`0x8025CD40`, `0x8001CD40`) seguido de palavra inválida. São constantes no meio do `.text` | `dados` |
| Bloco copiado para o kernel | 14 | `0x8019F1B8..0x8019F1EC`: trecho de tratador de exceção (`$k0`, `mfc0`) que o jogo copia para a RAM da BIOS. Ele roda lá, não neste endereço | `dados` (ou `hle_bios`) |
| Instalador do SDK (vizinho da quarentena SIO) | 54 | `0x801AB180..0x801AB1F0`, `0x801AB35C..0x801AB370` e `0x801AB380..0x801AB3E4`: chamadas `B(4Ch)` e `B(56h)` da BIOS, cópia do tratador para a tabela C0 e espera de ~3,3 M iterações. Não tem chamador estático e não apareceu em nenhuma sessão | interpretado de propósito, ou F2-Rx |
| Função `0x8015547C` | 75 | Lógica real de personagem (campos `+0x05`, `+0x70` e `+0x1519` do objeto, leitura do scratchpad `0x1F800000`, chamadas `0x80159F18` e `0x8015AFEC`). Sem referência estática no EXE e **nunca executada** nas 6 sessões do pente fino (todos os personagens dos dois lados, Arcade, Versus, Prática e Expert) | Fase 3, ou interpretada |

Leitura: **66 palavras** (36 + 12 + 4 + 14) não são código executável neste endereço. Excluí-las levaria a métrica a 174.051 / 174.180 = **99,9259%**. As 129 restantes (54 + 75) são código real que o jogo nunca executou nas sessões observadas: o instalador do SDK, provavelmente uma variante que a biblioteca trouxe sem uso, e uma rotina de personagem alcançável só por ponteiro (overlay) ou morta. A exclusão em `exclusions.json` e a mudança de baseline só com a aprovação do usuário.

**Decisão do usuário (2026-11-26): não excluir agora.**
- **As 66 palavras ficam em espera**, documentadas aqui com a classe proposta.
  - Não entram em `exclusions.json`. A métrica continua em 99,8881%.
  - Não confundir com a quarentena SIO/SMC: aquela é código que roda interpretado de propósito.
  - Revisitar quando os overlays estiverem fechados (Fase 3).
  - Observação: nenhum exercício de jogo vai cobri-las, porque não são executadas naquele endereço. Ao fim, a saída é a exclusão documentada.
- **As 129 restantes** (instalador do SDK e `0x8015547C`) são as que os exercícios novos podem revelar. Elas também ficam em espera.

Lista completa com desmontagem: `relatorios\fase2\F2-Rx\nao_cobertas_l26.txt`.

### 1.4 Achado da sessão 7: caso de jump table não compilado (`0x80184994`) — Fase 2

Primeiro PC do EXE fora da quarentena com execução observada desde o F2-L26.

- **Quando:** 2026-11-26 15:16:48, frame 94355. Na tela final do Team Battle 5x5 (sair/continuar/repetir), depois da luta contra o Garuda; o usuário escolheu sair. 75 entradas interpretadas, `ext_ra 0x801843BC`.
- **Onde:**
  - Função `func_8018491C` (`0x8018491C..0x80184E00`, `SLUS_005.48_full_38.c`), chamada por `jal` em `0x801843B4`.
  - É a máquina de estados da tela de resultado: logo após a tabela vêm as strings "YOU WIN", "YOU LOSE" e "NO GAME".
  - O estado `[s1+0]` passa por um teste `< 5` e depois por `jr $v0` em `0x80184970`, que lê a tabela `0x801ACB20` (montada em `$at` com `lui`/`addiu`/`addu`).
  - Alvos da tabela: `0x80184978`, **`0x80184994`**, `0x80184B40`, `0x80184C90` e `0x80184D64`.
- **Causa:**
  - O `jr` é compilado como CPS (`cpu->pc = alvo; return`).
  - Os casos 0, 2, 3 e 4 têm rótulo e entrada.
  - O caso 1 (`0x80184994`) fica no meio do bloco `block_80184978`. Não tem rótulo nem entrada no dispatch, por isso vai ao interpretador.
  - O resolvedor de jump table não reconheceu essa forma: é um dos 41 `jr` indiretos do §2.
- **Pré-auditoria (2026-11-26, `curador-seeds`, só leitura; evidências em `relatorios\fase2\F2-L27\`: `preview.txt`, `preview.json` e `jr_nao_resolvidos.txt`).**
  - **Seed não serve.** O `seed_preview 0x80184994` dá rc 0, +0 palavras, +0 funções, **+0 entradas** e borda=NAO. O alvo é o fallthrough do caso 0 (`0x80184990 sb` cai em `0x80184994`), no meio da função. A governança (§1 do `newWords.md`) diz que alvo de jump table não é raiz.
  - **Causa no resolvedor.** O resolvedor (`resolve_exact_bounded_jump_table`, `psxrecomp/recompiler/src/function_analysis.cpp:764`) aceita três formas. Esta é `sltiu; beq; D; sll; lui; addiu; addu; lw; nop; jr`, em que o delay slot D do `beq` (`addiu s0,s1,0x704`) não tem relação com o índice. Ela cai no ramo delay-scale, que assume `guard_pc = sll_pc-4`: aí está o D, não o `beq`. Por isso falha fechado e o `jr` fica CPS, sem resolver a tabela.
  - **Mesma forma em outros 12 `jr`, 13 no total:** `0x80106C28`, `0x8010B030`, `0x8010F4B0`, `0x8014F590`, `0x8014FEB0`, `0x8016AE54`, `0x8016C790`, `0x8016D8E8`, `0x8016FC58`, `0x80172E34`, `0x801756A8`, `0x80184970` e `0x80192180`. Não foi conferido se todos têm os alvos dentro da função.
  - **Contagem.** A varredura do gerado achou 195 `jr` não-`$ra` sem `switch`, contra os 41 do §2. A diferença (escopo e formas sem tabela) não foi reconciliada.
- **Correção decidida: F2-R2 (resolvedor), não seed.**
  - **Ajuste:** no ramo delay-scale, aceitar um delay slot D arbitrário do `beq`, desde que não seja controle e não escreva o índice, o `scaled_reg` nem a base. Nesse caso, `guard_pc = sll_pc-8` e `bound_pc = sll_pc-12`. As demais checagens ficam.
  - **Paridade:** manter a paridade com `compile_overlays.py` e o verificador Python.
  - **Validação:** rebuild do recompilador, regeneração, auditoria de codegen (os 13 `jr` viram `switch` com `goto`, preservando o delay slot e o `psx_check_interrupts_at`), métrica (palavras iguais; entradas do dispatch podem mudar), as quatro rotas e, por fim, sessão manual até a tela final do Team Battle.
  - **Agentes:** `investigador` → `executor` → `operador-rotas` ‖ `revisor` (esforço alto) → `verificador`.
- **F2-R2 aplicada (2026-11-26); falta só a validação manual.**
  - **Regra implementada:** a variante `delay_scale_free_d` em `resolve_exact_bounded_jump_table` e em `_find_jump_table_targets` (`tools/` e `overlay_toolchain/compile_overlays.py`, idênticos). Ela só vale quando a palavra antes do `sll` não é `beq`, então as formas antigas não mudam.
  - **Allowlist de D:** `nop`, ALU sem trap (`sll/srl/sra[v]`, `addu/subu`, `and/or/xor/nor`, `slt[u]`, `addiu/slti[u]`, `andi/ori/xori`, `lui`) e `sb/sh/sw` só com base `$sp`. Seis dos 13 casos têm D = `sw ..(sp)`.
  - **D é rejeitado** se escreve o índice, o `scaled`, a base, o guard ou o `rt` do LUI.
  - **Conferência dos 13 `jr`:** todos aceitos, todos com os alvos dentro da função, e nenhum outro `jr` de `jr_nao_resolvidos.txt` tem essa forma. O `0x801A29D4` tem a forma `delay_scale` antiga e continua não resolvido; fica para investigação própria.
  - **Testes:** `reachable_discovery_test` (C++) e `check_delay_scale_free_d_jump_table_discovery` (Python), com 5 casos positivos e mais de 20 negativos (D desvio, load, store fora de `$sp`, COP2, trap, escrita em índice, base, guard ou `rt` do LUI, alvo na região protegida e outros).
  - **Carimbos:**
    - hash do codegen: `0xe13692f6` → `0x3ac8904a`;
    - `overlay_toolchain` ressincronizado;
    - `OpenBIOS.emitter.sha` regerado, com o `.c` do OpenBIOS idêntico.
  - **BIOS local SCPH1001** (não rastreada): regerada, com `.c` byte-igual; só o fingerprint mudou.
  - **Build isolado `PlusAlphaProject/build-auto-f2r2`** (não promovido; `build-auto-p2infra`, `generated-online` e baseline ficaram intocados):
    - 56 `switch (_jt_` contra 43 antes (+13). O `0x80184970` tem 5 casos com `goto`, inclusive `block_80184994`.
    - Audit CLEAN.
    - Métrica: **174.051 palavras (99,8881%), 24.708 entradas (+0)**, `.ranges` idêntico.
  - **Quatro rotas:** rc 0, todos os passos ok, miss 0, nenhum PC do EXE fora da quarentena. Resultado igual ao L26.
  - **`verificador`:** aprovou os 9 critérios. As 13 falhas do `ctest` completo são de ambiente e já existiam antes: gcc `-shared` quebrado, `tomllib` ausente, BIOS SCPH5552 indisponível, alvos não compilados e guardas de texto de runtime/UI.
  - **Evidências:** `F:\GitRevised\alphaplus\relatorios\fase2\F2-R2\`.
  - **Pendente:** o usuário joga o Team Battle até a tela final com `build-auto-f2r2\exPlusAlpha.exe`, e o agente confere 0 PCs do EXE fora da quarentena. Depois disso, decidir se promove para `generated-online` e baseline (só com aprovação do usuário).
- **Proposta original (substituída pela F2-R2):** registrar `0x80184994` como entrada (seed/alias, conforme a governança de `docs/newWords.md` para jump tables) ou ensinar essa forma ao resolvedor (F2-Rx, que pode resolver outros `jr` do mesmo padrão).
  - Validação: rota ou sessão manual até a tela final do Team Battle, conferindo 0 PCs do EXE fora da quarentena.
  - A métrica não muda: as palavras já estão cobertas; muda só a entrada no dispatch.

### 1.3 Exercícios complementares de telas (proposta do usuário, 2026-11-26)

Sessões manuais guiadas, no mesmo formato do pente fino: build de telemetria, coletor só leitura e marcas por trecho. O objetivo é pegar código que o Arcade e o Versus não exercitaram, em especial as 129 palavras do §1.2 e PCs de overlay para a Fase 3. Telas a exercitar:

- **Pausa (Start) em cada contexto:**
  - na luta, saindo e voltando para o jogo;
  - voltando ao menu principal;
  - voltando à seleção de personagens;
  - durante o replay;
  - no modo Treinamento e no Expert.
- **Configurações:** Options (botões, som, tela, dificuldade); configuração do modo Treinamento (CPU, guarda, medidor e outros).
- **Expert Mode até o fim (pendência da F2, decisão do usuário em 2026-11-26).**
  - **Plano:** o usuário joga os desafios do Ken, o mais fácil segundo pesquisa externa, até o 15º, ou deixa de fora só um desafio fácil. Ele guarda um save state ou um memory card nesse ponto. Assim a conclusão (16º, tela de "completou tudo") pode ser repetida quantas vezes for preciso, com o coletor ligado.
  - **Plano B:** se não der, marcar a lição como concluída na RAM pela porta de debug, com autorização do usuário, numa sessão separada e com memory card de teste.
- **Expert Mode até o fim de um desafio.** É difícil chegar lá, porque as últimas lições exigem combos longos. A tela de desafio completo provavelmente tem código ainda não visto, mas o Expert fica em overlay (`0x800E6F4C`), então o achado tende a ser da Fase 3. Fica pendente até o usuário conseguir completar uma trilha. Um save com o Expert completo também serviria.
- Outros modos ainda sem exercício manual: Survival, Watch (CPU x CPU) e os índices de modo sem rota (§2).

Se aparecer PC do EXE fora da quarentena, vira candidato a seed com execução observada, num lote normal. PC de overlay vai para a Fase 3. Se `0x8015547C` ou o instalador `0x801AB180` aparecerem, o §1.2 é revisto.

## 2. Pendências técnicas menores (não bloqueiam)

- **Observação: tela travada/marrom ao entrar no cenário do Dhalsim (pente fino, sessão 6, 2026-11-26).** Sem ação agora; o usuário vai tentar reproduzir depois.
  - **O que aconteceu:** no modo Arcade, logo ao começar a carregar o cenário, a tela ficou travada e marrom por cerca de meio segundo, e depois o cenário carregou normalmente. O usuário só viu isso uma vez em todo o tempo de projeto. No Versus (CPU controlando) o mesmo cenário não teve o problema.
  - **Telemetria:** o host ficou ~350 ms travado (4 frames de 84–90 ms) e houve um salto de 5 frames no guest. Todos os 5.966 underruns de áudio da sessão aconteceram nesse ponto. Não houve miss nem PC novo.
  - **Pista do perfil (sessão 7):** o endereço dominante do host no travamento do Dhalsim é o mesmo do menu de save state da sessão 7, em `ntdll.dll` (+0x166464). Ou seja, a thread do jogo estava **esperando** o sistema (driver, disco ou outra thread), e não processando.
  - **Hipótese do usuário:** carga extra da própria telemetria (coletor, observador do cartão e várias consultas rodando) num momento pesado do carregamento. A build de debug não serve para medir sensação (§1.1).
  - **Se reaparecer:** avisar antes de entrar no cenário, para armar a gravação contínua da `gpu_timeline`. Comparar com o renderer por software e com a build release.
  - Evidência: `pente-fino\sessao-6\hitches\hitch_36344.json`, `present_gaps.jsonl`, `snapshots.jsonl` e `atencao\dhalsim_38959.json`.

- **Quit das rotas:** o comando de saída pela porta de debug responde "emu busy or frozen" desde F2-L20/L21. O processo sai com código 0, mas a causa não foi investigada.
- **Agregado do `boot_to_fight`:** às vezes vem com `exe_pcs_interpretados` vazio (L21, L26), enquanto `telemetry_luta_final.json` mostra os 6 PCs da quarentena. Provavelmente é o momento da amostragem; não está confirmado.
- **Execução observada das órfãs:** as 144 raízes P01–P08 têm só cobertura estática. Uma rota com fntrace armado nesses alvos daria evidência, se você quiser.
- **Índices de modo sem rota:** os índices 2, 4, 5, 12 e 22–24 da tabela de modos ainda não são alcançados por nenhuma rota automática. O Expert Mode foi exercitado manualmente no pente fino (sem rota automática); as notas não dizem a qual índice da tabela ele corresponde.
- **`jr` indiretos:** a F2-R2 resolveu 13 (forma `sltiu; beq; D; sll`, §1.4). Restavam 41 de formas que o resolvedor de jump table não reconhece. Eles funcionam pelo dispatch e por fallback e não afetam a métrica.
- **`0x801937DC` (PadStop):** salta pelo ponteiro `[0x801BFD20]`, cujo valor depende da imagem de BIOS (SCPH1001 contra OpenBIOS). O fallback cobre os dois casos, mas isso não foi testado em execução.

## 3. Fora da Fase 2 (Fase 3)

- Overlays: as 45 variantes retidas divergentes continuam interpretadas.
- **PCs de overlay vistos interpretados no pente fino:**
  - `0x800222D4` e `0x80024E8C` (RAM baixa, chamados do EXE);
  - `0x800E6F4C` (Expert Mode);
  - **`0x8004744C`** (sessão 7, 2026-11-26 15:02:38, frame 43388, 15 entradas, `ext_ra 0x80045390`).
    - **Contexto:** apareceu ao sair do Expert e voltar à seleção de personagens. Segundo o usuário, essa tela carrega a tabela de todos os personagens com missões já feitas.
    - **O que é:** continuação de uma rotina de overlay depois de `jal 0x80115574` (EXE). Lê `+0x1D5`, grava `3` em `+0x1513` e incrementa `+0x05`: os mesmos campos de objeto da função `0x8015547C` do EXE (§1.2).
    - **Personagens:** Ken no Expert; depois do Expert o usuário trocou para Skullomania. O PC apareceu 25 s após a troca. Ao repetir a rota com a Skullomania (15:05, frame 52942), o contador subiu de 15 para **75 entradas**: a rotina roda de novo com ela. Com a Pullum Purna no Expert, voltando à mesma seleção (15:07, frame 60655), o contador **ficou em 75**. Conclusão: a rotina é do **overlay da Skullomania** (lógica de golpe dela), não da tela de seleção do Expert nem do código comum.
    - **Hipótese:** uma das variantes divergentes de overlay de personagem (`PLxx`) ou do Expert.
    - **Mesmo código no outro slot de overlay:** `0x80090E4C` (sessão 7, 15:25:15, frame 124478, 15 entradas, `ext_ra 0x8008ED90`, ids em luta `0x0F`/`0x06`), byte a byte igual ao de `0x8004744C`. É a mesma rotina carregada na área de RAM do outro lado da luta. Corrigir a variante resolve os dois endereços. Nessa luta os 5 adversários do Team Battle eram Skullomania (relato do usuário): **confirmado que a rotina é do overlay da Skullomania**. O lado da CPU ficou com o id `0x06` (`[0x801D63CA]`) enquanto o time do usuário mudava, então **Skullomania = id `0x06`** (`PL06`). Na luta anterior, contra o Garuda X, o lado da CPU tinha `0x0B`.
    - **Na Fase 3:** identificar o arquivo e a variante.
- Rota `watch_sweep` (Watch/CPU x CPU com todos os personagens nos dois lados), ainda não executada, como base de evidência para a Fase 3.

## 4. Etapas futuras (fora das fases atuais)

- **Input lag: MiSTer FPGA x recomp.** Aguarda uma câmera com câmera lenta (240 fps ou mais). Método: filmar a tela e o controle juntos e contar os quadros entre o botão descer e o soco aparecer. Cenário: Ryu P1, soco fraco em pé, cerca de 20 repetições em cada plataforma, com o mesmo monitor e o mesmo controle, para que o atraso do monitor e do controle se cancele na diferença. O MiSTer serve de referência de hardware. Do lado do recomp, a parte interna (leitura do pad até a escolha da animação) já é medida por `PlusAlphaProject/tools/capture_input_response.py`, com o perfil `input_response_ryu_p1_square.json`. Um vídeo só da tela (placa de captura) não basta, porque não mostra o instante do botão.
- **Apresentação do frame repetido (Fase 6, melhoria; até lá fica 1:1 com o original):** reapresentar a imagem a cada vblank quando o jogo repete um frame, em vez do `present_skip`, para que a linha de frame time fique reta como no DuckStation e no MiSTer (ver §1.1). Caso visível: no menu de pausa (Start) o jogo redesenha a cada 2 vblanks; com OpenGL o RivaTuner mede 30 fps (swap pulado) e com o renderer por software mede 60 (relato do usuário; a imagem é a mesma).
- **Contagem exata do A/B por vídeo:** gravar o recomp (captura de vídeo a 60 fps da janela, sem OSD) no mesmo combate Akuma x Kairi e analisar com o mesmo método dos vídeos do MiSTer (quadros idênticos), para comparar os totais nos flashes de KO (MiSTer level 2: ~40; recomp pela telemetria: 7).
- **Catálogo de PCs ligados às quedas de frame (pente fino, 2026-11-26).** Todos estão no EXE estático e já rodam nativos. Por isso não são seeds da Fase 2. Também não são alvo de otimização: mudar o custo deles mudaria o timing, que hoje está fiel ao hardware. Ficam como mapa de referência para investigações futuras (A/B, overclock opcional, regressão de timing). Onde a CPU estava no vblank perdido, por `irqctx_ring`, nas sessões 3 a 5:
  - **início de especial, incluindo Hadouken:** laço de objetos `0x8010C314..0x8010C3CC` (23 slots, `jalr` por objeto). Rotinas por objeto: `0x801116FC`, `0x80111714` e `0x80111760` (caller `0x8010F280`), `0x8010C764`, `0x8010D754`, `0x8010D1E8`, `0x80110EB0` e `0x80115FEC`. Vêm junto da KEYON do sample `0x0A460`.
  - **impacto e golpe que derruba:** `0x8013D108`, `0x8013D340` e `0x801948E4`.
  - **flash do KO (frames sem 3D; 7 perdidos no KO com level 2):** `0x80121614`, `0x80121AD8`, `0x8012282C` e `0x80124CCC`. O flash não aparece em todo KO: no mesmo level 2, uma vez teve 7 perdas e na outra nenhuma, com os mesmos PCs interpretados.
  - **SUCCESS do Expert, lições 6 e 7 (~24 perdidos em ~0,8 s):** laço `0x80147A10`, `0x80147B80`, `0x80147CC4` e `0x80147EDC`, com a libgte por software `0x8019D270` (MulMatrix), `0x8019DF20` (RotMatrix), `0x8019DFC8` e `0x8019E054`.
  - **menu de pausa (proposital, a cada 2 vblanks):** `0x80189204`, que espera `[0x801D39E8]`, com o contador `[0x800F6048]`.
  - **PCs interpretados vistos na sessão** (fora o kernel, 12, e a quarentena, 6): `0x800222D4` e `0x80024E8C` (RAM baixa, chamados do EXE, a classificar) e `0x800E6F4C` (overlay do Expert Mode). Os três são candidatos à Fase 3. A sessão 5 (Versus) não teve nenhum PC novo.
- **Memory card: load e save (pente fino, sessão 6, 2026-11-26).** Funciona sem erro, com o card de tudo liberado. Foram 281 transações, sem abort de verdade. No save, 22 escritas `0x57` (setores 1 e 63–80) terminaram com sucesso, e o `card1.mcd` foi gravado às 14:14:57 com o mesmo hash da origem, porque o conteúdo não tinha mudado. Os 36 `abort_other` são leituras do setor `0xFFFF`, que o kernel da BIOS usa para sondar o cartão. Para registro:
  - **Quedas síncronas.** O load teve 5 quedas de 2 frames (50 ms) a cada 16 frames (4670–4734), e o save teve 3 (4974–5006). São do guest: dois vblanks sem flip, com o jogo esperando o cartão via `TestEvent` (stub B(0Bh) em `0x801A7430`), o IRQ do SIO (bit 7) ativo, o `SR` com o bit 17 ligado (`0x40020401`) e o `take_pc` em `0x800D661C`/`0x800D6634` (área de dados; o PC do `irqctx` não é preciso dentro desses blocos).
  - **Interpretado.** As rotinas de cartão são do kernel da BIOS na RAM baixa (`0x25AC`, `0x5B00`, `0x6458`, `0x48D0`, `0x4498`), e parte roda interpretada (`0x80006444`, `0x800065E0..0x80006644`, `0x80004D98`, `0x80004964`, `0x80000C88/0CF0`), ao lado da quarentena SIO do EXE. Não é seed da Fase 2.
  - **Turbo loads e BIOS nativa (hipótese do usuário, 2026-11-26).** A sessão 6 rodou com `turbo_loads = false`, e as quedas apareceram mesmo assim. Portanto não vêm da aceleração de load. Também não são I/O do Windows: o `.mcd` é gravado uma vez, no fim. A espera é o tempo emulado do cartão, isto é, os ACKs e bytes do SIO contados em ciclos do guest. Compilar a BIOS de forma nativa tiraria o custo do interpretador, mas não muda esse tempo emulado, então sozinha não deixa o save instantâneo. Para isso seria preciso uma opção de "cartão rápido" (encurtar o tempo de ACK e de byte do SIO), análoga ao turbo loads e desligada por padrão. Falta medir se o engasgo do save na build release (com o `game.toml` dela) é maior que o desta sessão.
  - **Decisão do usuário (2026-11-26):** o memory card instantâneo (mesmas telas do console, save e load na hora, como no port de Street Fighter III do usuário) fica para a **Fase 6 — Melhorias do port** (`docs/PLANO_100.md`). Ela só começa depois de o port estar igual ao console, com tudo recompilado. Nada disso é feito agora.
  - **Trabalho futuro.** (a) A/B no MiSTer, gravando a mesma tela de load/save, para saber se a espera de 2 frames é do jogo original. (b) Conferir o timing de ACK e de byte do cartão contra o hardware (DuckStation/Mednafen). (c) Avaliar compilar a janela do kernel de cartão (BIOS) e explicar o bit 17 do `SR` nesse trecho, que é o mesmo mistério das sessões anteriores. Evidência em `relatorios\fase2\pente-fino\sessao-6\memcard\` e `sessao-6\quedas\`.
