# Metodologia para fontes, builds e testes

Este arquivo define o fluxo obrigatório para qualquer nova promoção de código
nativo do Street Fighter EX Plus Alpha. Ele existe para preservar estabilidade,
impedir lotes maiores do que o planejado e permitir que qualquer sessão retome
o trabalho sem depender de memória de conversa.

## Regras inegociáveis

- O Codex nunca executa geração, compilação ou o jogo. O usuário executa tudo
  localmente e envia os resultados.
- Não editar C gerado manualmente. `PlusAlphaProject/generated/` é sempre
  produto do gerador.
- Cada micro-lote recebe três scripts independentes: geração de fontes,
  compilação e telemetria. Um script nunca acumula responsabilidade dos outros.
- O coletor não compila, não abre nem fecha o jogo.
- Uma telemetria aprova apenas provisoriamente. A promoção integral exige um
  checkpoint limpo posterior.
- `palavrasNovas.md` é a fonte de verdade: candidato, boundary, closure,
  tamanho medido, evidência, teste e decisão devem ser atualizados ali.

## Quando cada etapa é necessária

| Situação | Regenerar BIOS | Gerar fontes do jogo | Compilar | Coletar |
|---|---:|---:|---:|---:|
| Apenas telemetria de uma build existente | não | não | não | sim |
| Novo seed ou mudança em `entry_funcs.txt` | não | sim | sim | sim |
| Alteração no emissor da BIOS ou aviso de BIOS stale | sim | não, salvo mudança no jogo | sim | conforme risco |
| Alteração em runtime/CMake sem seed novo | não, salvo emissor BIOS | não | sim | smoke/regressão |
| Checkpoint limpo após lotes aprovados | não | não | sim, Release sem debug | não obrigatoriamente |

Somente mudanças que afetam o emissor da BIOS justificam regenerá-la: por
exemplo `full_function_emitter.cpp`, `strict_translator.cpp`, descoberta de
funções da BIOS, modelo de ciclos da BIOS ou suas seeds. Seeds do jogo e
`SLUS_005.48_*` não exigem BIOS nova.

## Pré-auditoria obrigatória do candidato

Nenhum endereço observado é promovido diretamente para seed. Antes de criar os
scripts do lote, registrar em `palavrasNovas.md`:

1. Boundary formal: início, fim, bytes, palavras e SHA-256 do corpo.
2. Callers e aliases: separar entrada formal de PC interno, retorno ou destino
   de tabela.
3. Fluxo: branches, JAL, JALR, JR, jump tables, callbacks e RAM dinâmica.
4. Closure alcançável: toda chamada `JAL` direta deve ser expandida
   recursivamente até uma função já nativa ou até uma função ainda interpretada.
5. Orçamento: palavras da raiz **mais toda a closure nova**. O tamanho real do
   lote é esse total, não o tamanho da seed original.
6. Risco: COP2/GTE, scratchpad, DIV/MULT, BREAK, self-modifying code, BIOS,
   fluxo indireto ou rotas sem evidência tornam o lote de maior risco.

Uma geração de fontes pode revelar novas closures diretas. Por isso, antes de
tocar os artefatos principais, a prévia de geração deve ocorrer em uma área
descartável/isolada e o delta de `SLUS_005.48_full.ranges` deve ser medido. Se
o delta exceder o orçamento, o candidato é rejeitado; ele não deve ser
“aceito” alterando o número esperado de funções.

### Incidente de referência: S1-252

`0x8016FC28` parecia ter 39 palavras, mas continha dois `JAL` diretos para
funções interpretadas. A descoberta alcançável expandiu a closure para 12
funções e 2.805 palavras. Esse caso é a razão do gate de closure acima: uma
raiz pequena não significa um micro-lote pequeno.

## Contrato dos scripts do lote

Para um lote chamado `S1-XYZ`, criar estes arquivos em
`PlusAlphaProject/tools/`:

| Arquivo | Responsabilidade exclusiva |
|---|---|
| `generate_s1_XYZ_sources.ps1` | validar baseline/seed/closure; gerar fontes do jogo; rodar auditoria codegen; não compilar nem regenerar BIOS |
| `compile-run_s1_XYZ_telemetry.sh` | validar ranges e símbolos; configurar e compilar a build isolada de telemetria; não abrir o jogo nem coletar |
| `telemetry_before_after_s1_XYZ.sh` | preparar, coletar BEFORE e AFTER da mesma execução aberta; não gerar nem compilar |
| `compile-run_s1_XYZ_checkpoint.sh` | somente quando solicitado; compilar checkpoint limpo Release com `PSX_DEBUG_TOOLS=OFF` |

### Contrato do gerador de fontes

O `generate_s1_XYZ_sources.ps1` deve conter todos estes gates:

- seed nova aparece exatamente uma vez; seeds anteriores aprovadas continuam
  aparecendo exatamente uma vez; seeds em quarentena aparecem zero vezes;
- SHA-256 e número de funções da baseline esperada;
- hashes de bytes da raiz e das estruturas de controle relevantes;
- lista explícita de ranges já aprovados que não podem desaparecer;
- lista explícita da closure aprovada e das funções proibidas;
- número esperado de funções e palavras **após medir a closure**;
- execução de `codegen_audit_game.py --config game.toml` após a geração;
- mensagem final com cobertura, SHA do manifest e a frase de que BIOS/build não
  foram iniciados.

Se surgir função fora da closure aprovada, o script deve falhar e o lote fica
**bloqueado**. Não corrigir o gate para aceitar automaticamente a expansão.
Primeiro registrar o delta em `palavrasNovas.md`, auditar o novo alcance e
decidir se o lote continua adequado.

### Contrato do script de compilação

O script de telemetria deve usar diretório novo e isolado, por exemplo
`buildClean-ucrt-s1-XYZ-tele`, e validar antes de chamar CMake:

- MSYS2 UCRT64, `cmake`, `ninja`, `nm`, `objdump` e `nproc` disponíveis;
- manifest com a raiz, closure aprovada e contagem exata de funções;
- ausência de funções proibidas;
- configuração `RelWithDebInfo`, `PSX_DEBUG_TOOLS=ON` e
  `PSX_STATIC_RUNTIME=ON`;
- executável produzido, símbolos esperados e ausência das DLLs de runtime que
  deveriam ser estáticas.

O script encerra mostrando o caminho do executável. O usuário o abre
manualmente depois.

### Contrato do coletor

O coletor deve aceitar somente `prepare`, `before` e `after`.

- `prepare`: verifica a build, cria um diretório de coleta único, grava
  metadados, arma filtros/traces e persiste um pequeno arquivo de estado.
- `before`: exige o estado preparado e o cenário correto já ativo; faz o
  snapshot inicial, limpa a janela de medição e preserva a instrumentação.
- `after`: exige a mesma sessão na fase BEFORE; desarma o filtro, coleta o
  snapshot final, grava `summary.md`, limpa o arquivo de estado e **não fecha o
  jogo**.

Todo run deve guardar: versão/lote, hashes do manifest e executável, cenário,
personagens, rota, duração, stats do dispatcher, misses de texto estático,
entradas de função, traces de rotas indiretas quando aplicáveis, dirty RAM e
latência (`p50`, `p95`, máximo e fases). Um ring incompleto, miss novo, abort,
`native_handoff` inesperado ou rota não comprovada impede promoção automática.

## Descoberta interativa de alcance com múltiplos PCs

A campanha multi-PC é uma etapa de **descoberta de rota**, separada do coletor
de aprovação de um micro-lote. Por isso, ela pode manter uma sessão interativa
com vários confrontos em vez do contrato `prepare/before/after`. Seus resultados
localizam onde os candidatos executam, mas nunca promovem uma seed sozinhos.

O arquivo `PlusAlphaProject/seeds/function_watchlist.txt` contém somente
endereços formais já delimitados ou candidatos explicitamente mantidos em
observação. Inserir um endereço nessa lista:

- não altera `entry_funcs.txt`;
- não gera fontes;
- não aprova closure ou orçamento;
- não transforma um PC interior em função formal;
- apenas permite contar sua execução nativa ou interpretada.

Com a build de telemetria compatível aberta manualmente, iniciar no UCRT64:

```bash
bash tools/observe_function_watchlist.sh
```

O runtime carrega toda a watchlist uma vez. Para cada confronto:

1. Escolher os personagens no jogo; o segundo personagem determina o cenário.
2. Informar um identificador normalizado, como `ken-ryu` ou `skullo-ddark`.
3. No primeiro frame controlável do gameplay, pressionar Enter no terminal para
   zerar os contadores e iniciar a janela.
4. Executar uma rota curta mas representativa: repouso, movimento, agachar,
   pular, golpes normais, defesa/dano, agarrão, especial/super quando possível e
   pelo menos um final de round.
5. Pressionar Enter novamente para congelar e registrar aquela janela.
6. Voltar à seleção de personagens e repetir sem fechar o jogo.
7. Digitar `fim` quando toda a campanha estiver concluída.

Durante a janela, o script consulta os contadores uma vez por segundo e anuncia
somente o primeiro hit de cada função. A contagem continua silenciosamente até
o encerramento. Cada confronto gera `summary.md`, `hits.csv`, `result.json` e
um log de eventos; a campanha mantém `campaign-summary.md` e
`scenario-matrix.csv`.

Os identificadores usam tokens simples sem espaços. O segundo token representa
o personagem dono do cenário; personagens que compartilham cenário continuam
recebendo confrontos separados, pois personagem, IA e ações podem mudar a rota
mesmo quando o fundo é igual.

Zero hits significa apenas **não observado naquela rota**. Não prova que a
função seja impossível no confronto, pois ela pode depender de golpe, estado,
round, IA ou evento não exercitado. Uma função com hits passa a ter uma rota
preferencial conhecida; somente então ocorre pré-auditoria completa da closure,
medição de palavras, seleção do micro-lote e telemetria formal no mesmo cenário.

O observador multi-PC usa contadores de 64 bits, sem ring finito de hits, e uma
tabela hash para consultar até 128 endereços com custo constante. Ele não usa
`fn_filter`, não compila, não abre e não fecha o jogo.

## Descoberta automática de funções ainda interpretadas

Quando os endereços ainda não são conhecidos, usar a build S1-256 de
telemetria já aberta e executar no UCRT64:

```bash
bash tools/observe_interpreted_functions.sh
```

O script não usa watchlist. Ele compara snapshots cumulativos de
`static_text_misses` e `overlay_interp_hot` para mostrar somente os PCs que
entraram no interpretador dentro de cada janela. Para código estático, consulta
uma vez por segundo; código dinâmico/RAM é consultado a cada cinco segundos. O
terminal anuncia cada endereço novo uma única vez. O polling ocorre somente
nesta campanha de descoberta e não substitui a telemetria formal de aprovação.

Fluxo recomendado para um personagem:

1. Escolher o personagem ativo e deixar o adversário parado.
2. Informar uma tag ampla, por exemplo `ryu-vs-ken-descoberta`.
3. Pressionar Enter e executar movimentos e golpes livremente.
4. Quando surgir `[INTERPRETADO]`, pressionar Enter para encerrar a janela.
5. Informar uma descrição opcional do golpe suspeito.
6. Abrir outra janela, como `ryu-hadoken-confirmacao`, e repetir somente o
   golpe para confirmar a associação.
7. Continuar com outras ações ou digitar `fim` para encerrar a campanha.

Cada janela gera `summary.md`, `interpreted.csv`, `result.json` e os snapshots
brutos BEFORE/AFTER. A campanha gera `campaign-summary.md` e
`interpreted-matrix.csv`, relacionando PCs e rotas. Uma tag sem resultados é
evidência útil de que nenhum novo PC interpretado foi observado naquela janela.

Os resultados são **PCs de entrada**, não funções formais automaticamente. O
relatório separa código pristine, página modificada, runtime e RAM dinâmica.
Antes de inserir qualquer endereço em `entry_funcs.txt`, confirmar boundary,
bytes, callers, fluxo indireto, closure alcançável e orçamento de palavras.

## Timeline temporizada sem polling durante o jogo

Quando o objetivo for correlacionar lag com a frequência das funções, usar o
observador temporizado em vez do observador interativo:

```bash
bash tools/observe_function_watchlist_timer.sh
```

Uso direto:

1. Abrir manualmente a build S1-253 de telemetria já recompilada.
2. Executar o comando acima no UCRT64.
3. Informar uma tag, por exemplo `expert-mode-complete-timer`.
4. Posicionar o jogo no começo da rota e pressionar Enter.
5. Fazer a rota completa, incluindo o ponto onde ocorreu o lag.
6. Pressionar Enter novamente somente depois de voltar ao ponto final desejado.
7. Repetir com outra tag ou digitar `fim`.

Durante a janela não há consulta TCP, Python, JSON nem gravação em disco. A
thread da emulação faz somente a consulta hash já existente e publica
contadores atômicos quando uma função da lista é encontrada. Uma thread SDL de
baixa prioridade, agendada pelo Windows separadamente da thread do jogo,
amostra esses contadores em RAM a cada 100 ms. Não há afinidade forçada com um
núcleo específico; o escalonador pode usar qualquer um dos 16 processadores
lógicos disponíveis.

Depois do segundo Enter, o script para a amostragem e só então transfere os
dados. Cada tag gera:

- `timeline.csv`: frames, ciclos e deltas de hits a cada amostra;
- `hits.csv`: totais nativos e interpretados por função;
- `summary.md`: duração, maior período sem novo frame e funções encontradas;
- `timer_dump.json`: evidência bruta completa da linha temporal.

O limite padrão é 15 minutos por tag. Se `Buffer saturado` aparecer como `SIM`,
a cauda da timeline ficou incompleta e a coleta deve ser repetida com uma rota
menor. Esse observador exige somente recompilar localmente a build de
telemetria depois da mudança no runtime; **não exige gerar novas fontes**.

## Comandos canônicos

Os comandos abaixo são etapas separadas. Substituir `S1_XYZ` pelo nome do lote
existente; não executar uma etapa que não tenha sido solicitada.

### Regenerar a BIOS — somente quando necessário

No PowerShell, o script canônico compila apenas o emissor da BIOS, gera os C da
BIOS e atualiza `SCPH1001.emitter.sha`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "F:\GitRevised\alphaplus\plusalpha-recomp\psxrecomp\tools\regen_bios.ps1"
```

Não editar ou apagar manualmente `psxrecomp/generated/SCPH1001.emitter.sha`.

### Gerar fontes do jogo — somente depois da pré-auditoria aprovada

No PowerShell, executar o wrapper específico do lote:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "F:\GitRevised\alphaplus\plusalpha-recomp\PlusAlphaProject\tools\generate_s1_XYZ_sources.ps1"
```

### Compilar a telemetria — somente após fontes auditados

No UCRT64:

```bash
bash /f/GitRevised/alphaplus/plusalpha-recomp/PlusAlphaProject/tools/compile-run_s1_XYZ_telemetry.sh
```

### Coletar — com a mesma execução do jogo aberta manualmente

No UCRT64, no menu e na pré-condição indicada pelo lote:

```bash
bash /f/GitRevised/alphaplus/plusalpha-recomp/PlusAlphaProject/tools/telemetry_before_after_s1_XYZ.sh prepare
```

Com o cenário ativo, sem inputs:

```bash
bash /f/GitRevised/alphaplus/plusalpha-recomp/PlusAlphaProject/tools/telemetry_before_after_s1_XYZ.sh before
```

No ponto final indicado, sem inputs:

```bash
bash /f/GitRevised/alphaplus/plusalpha-recomp/PlusAlphaProject/tools/telemetry_before_after_s1_XYZ.sh after
```

## Guia de teste dentro do jogo

O cenário de coleta deve ser escolhido pela evidência da função, não por hábito.
Registrar personagens, estágio e tela de BEFORE/AFTER em `metadata.txt`.

### Coleta padrão para Bonus Barril

1. Abrir manualmente a build de telemetria.
2. No menu, destacar Bonus Barril e executar `prepare` antes de escolher o
   personagem.
3. Escolher Guile. Quando o cenário estiver ativo e o controle liberado,
   executar `before` sem inputs.
4. Jogar o Bonus normalmente, eliminando barris quando possível.
5. Ao terminar o tempo, permanecer na tela `Replay/Exit`, sem inputs, e
   executar `after`.

O BEFORE no menu não substitui o BEFORE no gameplay: objetos, colisores e
rotinas de cenário podem não existir antes de a luta/Bonus iniciar.

### Rotas manuais de regressão

Após a coleta, sem fechar o jogo, executar ao menos:

| Área | Rota mínima | Observar |
|---|---|---|
| Versus | Doctrine Dark × Skullomania, cenário Skullomania | sprites, efeitos, áudio, FPS e frametime |
| Versus | Guile × Hokuto, cenário Hokuto | efeitos de cenário e animações exclusivas |
| Bonus | Barril completo | colisores, objetos repetidos, transição final e replay |
| Trial | uma sessão completa | regras, timer, transições e input |
| Arcade | várias lutas e cenários | fundos, partículas, áudio e estabilidade prolongada |

Registrar FPS, frametime, stutter, travamento, áudio, input perdido, tela preta,
falha de retorno de menu e comportamento diferente do original. A telemetria
pode causar pequenas oscilações durante a própria coleta; o foco principal é o
gameplay fora dela e a comparação entre runs equivalentes.

## Decisão após o teste

| Resultado | Decisão |
|---|---|
| Gate técnico completo, sem miss/abort e regressão manual limpa | aprovado provisoriamente |
| Rota necessária não observada | preparar coleta direcionada; não promover |
| Miss, abort, handoff, travamento ou regressão | rejeitar/suspender; preservar logs e criar reprodução mínima |
| 3–5 micro-lotes aprovados, aumento relevante ou risco elevado | solicitar checkpoint limpo |
| Checkpoint Release limpo e regressão completa aprovada | promoção integral e versionamento somente quando autorizado |

Ao encerrar qualquer decisão, atualizar `palavrasNovas.md` com tamanho medido da
closure, status, links/nomes das coletas e motivo da decisão. Nunca apagar a
evidência de um candidato rejeitado: marcar como `rejeitado` ou `watchlist`.

## Recuperação após geração ou teste interrompido

- Se a geração revelar closure acima do orçamento: não compilar; registrar o
  delta; restaurar os fontes a partir da lista de seeds da última baseline
  aprovada usando um procedimento específico e revisado.
- Se `prepare` foi executado mas o jogo fechou: não reutilizar o estado; remover
  apenas o arquivo de estado daquele coletor e iniciar um novo run.
- Se BEFORE/AFTER falhar: preservar a pasta de telemetria, não sobrescrever os
  logs e informar a fase, mensagem completa e versão da build.
- Não usar `git clean -fdX`, `git reset --hard` ou exclusão manual de árvores
  geradas para recuperação sem uma autorização explícita e alvos verificados.
