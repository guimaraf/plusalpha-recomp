# Briefing para continuar em um novo chat

Briefing curto e atual (2026-11-25). O histórico anterior (Track 2, telemetria S1) está em [`archive/`](archive/); os scripts S1 removidos ficam na tag git `arquivo-ferramentas-s1`.

## Regras de trabalho
- Responda em português do Brasil, de forma técnica e direta; corrija de imediato propostas tecnicamente erradas.
- Execução autônoma (build, jogo, rotas) só pelo protocolo da "Fase A" de [`PLANO_100.md`](PLANO_100.md): build isolado, jogo no monitor 1, entrada só pela porta TCP de debug, saves/savestates fora de `gameFiles/saves/`, um build por vez.
- Sem commits sem pedido do usuário; preserve saves, sessões, BIOS e caminhos de fallback.

## Onde está o estado
- Plano e "Andamento": [`PLANO_100.md`](PLANO_100.md) (Fase 2 em curso).
- Lotes, governança e tabela de resultados (§6): [`newWords.md`](newWords.md).
- Números por faixa: [`progress.md`](progress.md).

## Fluxo de trabalho
- Build de trabalho: `PlusAlphaProject/build-auto-p2infra`.
- Lote da Fase 2: skill `plusalpha-fase2-lote` (ponta a ponta), com `PlusAlphaProject/tools/auto_session.py` (build, rotas, run.json), `seed_preview.py` (pré-auditoria das seeds) e `coverage_metric.py` (métrica oficial; `--check` contra `PlusAlphaProject/coverage/baseline.json`).
- Seeds em `PlusAlphaProject/seeds/entry_funcs.txt` (um escritor por vez). Fila em `relatorios/fase2/fila.json`.

## Métrica atual (F2-L6, commit `c3efa55`)
- EXE: 160.149 / 174.276 palavras (91,8939%), 1.398 funções, 22.734 entradas de dispatcher.
- `baseline.json` só será promovido no fim da Fase 2.
- Quarentenas: `0x801AB1F4..0x801AB237` (SIO) e `0x801AB2C0..0x801AB2EF` (SMC).

## Pendências principais
- Validação de sensação do usuário para os lotes recentes (as raízes de F2-L5/L6 não têm execução observada).
- Resolver o `jr` indireto em `0x8010B030` (restam 42 `jr` indiretos no EXE).
- Rotas sem cobertura: `survey_options` não foi refeita desde F2-L4; modos ainda sem rota.
- Próximo candidato provisório: F2-L7 (`0x8012F484`, `0x8013497C`).

## Lembrete de triagem
O BIOS Sony continua interpretado de propósito; avalie só código do jogo fora de `0x8000xxxx`. Miss estático no EXE (`0x80101000..0x801C0000`) segue o protocolo de fechamento, orçamento de palavras e micro-lote isolado.
