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

**Se a sensação for aprovada:** promover `generated-online/` a partir de `build-auto-p2infra/generated`, atualizar a linha de base com `python PlusAlphaProject/tools/coverage_metric.py ... --update-baseline` e registrar o fechamento da Fase 2 em `docs/PLANO_100.md`.

### 1.2 Decisão sobre as 195 palavras restantes (usuário)

Nenhum destes grupos é caso de micro-lote de seeds:

| Grupo | Palavras | Situação | Opções |
|---|---|---|---|
| Instalador do SDK: `0x801AB180`, `0x801AB35C`, `0x801AB380` | 54 | Bloqueado: sem chamador estático e vizinho da quarentena SIO/SMC. `0x801AB1E0` salta para `0x801AB1F4`, que está na quarentena | Investigação F2-Rx, ou deixar interpretado |
| Função `0x8015547C` (classe A) | 75 | Sem referência estática no EXE. Os overlays têm um caminho estático, mas a hipótese da rota `versus_pl0c_pl12` (sequência no versus) não confirmou execução | Prova de execução, promoção explícita sem execução observada, ou passar para a Fase 3 |
| Resto: epílogos mortos (`lw ra/sp; jr ra` sem referência), bloco copiado para o kernel (`0x8019F1B8..F1F0`), palavras de dados (`0x8019C9A0`, `0x8019FB44`) e padding de nops | ~66 | Classificação do investigador feita sobre a base F2-L24 (`relatorios\fase2\F2-Rx\nao_cobertas_grupos.json`), **não reconferida** no estado atual | Marcar dados/padding como exclusão em `exclusions.json` e classificar o código morto (decisão de governança) |

Recomendação do coordenador: excluir dados e padding depois de reconferir a lista sobre o build atual, e deixar o instalador `0x801AB` e `0x8015547C` interpretados ou para a Fase 3.

## 2. Pendências técnicas menores (não bloqueiam)

- **Quit das rotas:** o comando de saída pela porta de debug responde "emu busy or frozen" desde F2-L20/L21. O processo sai com código 0, mas a causa não foi investigada.
- **Agregado do `boot_to_fight`:** às vezes vem com `exe_pcs_interpretados` vazio (L21, L26), enquanto `telemetry_luta_final.json` mostra os 6 PCs da quarentena. Provavelmente é o momento da amostragem; não está confirmado.
- **Execução observada das órfãs:** as 144 raízes P01–P08 têm só cobertura estática. Uma rota com fntrace armado nesses alvos daria evidência, se você quiser.
- **Índices de modo sem rota:** os índices 2, 4, 5, 12 e 22–24 da tabela de modos ainda não são alcançados por nenhuma rota automática.
- **`jr` indiretos:** restam 41 de formas que o resolvedor de jump table não reconhece. Eles funcionam pelo dispatch e por fallback e não afetam a métrica.
- **`0x801937DC` (PadStop):** salta pelo ponteiro `[0x801BFD20]`, cujo valor depende da imagem de BIOS (SCPH1001 contra OpenBIOS). O fallback cobre os dois casos, mas isso não foi testado em execução.

## 3. Fora da Fase 2 (Fase 3)

- Overlays: as 45 variantes retidas divergentes continuam interpretadas.
- Rota `watch_sweep` (Watch/CPU x CPU com todos os personagens nos dois lados), ainda não executada, como base de evidência para a Fase 3.
