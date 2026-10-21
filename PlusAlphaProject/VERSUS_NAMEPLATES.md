# Nameplates — fase 1

O filtro combina a opção existente, o modo efetivo Versus e a detecção de HUD
na cena de luta. Não altera identidade, input, pacing ou algoritmo de rede.
As duas caixas novas exibem `0` fixo; ainda não existe contagem de vitórias.
O nome exibido aceita oito caracteres (acentos combinantes não consomem outra
posição). A identidade online permanece intacta.

## Evidência local — SLUS-00548, 21/10/2026

Observação em cópia isolada da build de diagnóstico existente, sem recompilar,
porta 4533, saves/configurações próprios. A navegação foi feita pelos controles
normais do jogo, usando o comando de botão virtual `press` do diagnóstico.
Nenhuma rotina foi chamada artificialmente, nenhum endereço de RAM foi escrito.

Captura local (ignorada pelo Git):
`captures/versus-mode-dedicated/trace.jsonl` e `markers.jsonl`.
A identificação/hash do executável consta do registro `executable` da captura:
SHA-256 `71e25dec57608600225ac744c866b237efbbde49d3f4696014edbbbf10f8f9cc`.
A coleta terminou com `status.json`: `complete=true`, sem interrupção ou erro.

| Ação observada | Cena `0x801D39B8` | Modo `0x801DC9D0` |
|---|---|---|
| Seleção de modos com Arcade destacado | 7 | 0 |
| Apenas destacar Versus | 7 | 0 |
| Confirmar Versus, seleção de personagens VS MODE | 0 | 1 |
| Voltar do Versus à seleção de modos | 7 | 1 |
| Confirmar Arcade, seleção de personagens | 0 | 0 |
| Abrir Practice, submenu Training/Expert | 7 | 5 |
| Confirmar Training, seleção de personagens | 0 | 5 |
| Training em gameplay com HUD de vida | 1 | 5 |
| Option menu | 0 | 7 |
| Reentrar no Versus após os outros modos | 0 | 1 |
| Gameplay Versus confirmado, frame 31161 | 1 | 1 |
| Retorno do gameplay Versus ao menu, frame 36381 | 7 | 1 |

O marcador inicial `practice-character-select` foi nomeado antes de identificar
o submenu; o marcador seguinte `practice-submenu-confirmed` corrige a descrição.
Não interpretar esse primeiro marcador como seleção de personagens.
O marcador `versus-gameplay` também foi antecipado (a leitura ainda era cena 0).
Usar `versus-gameplay-confirmed`, com cena 1, para evidência de gameplay Versus.

Na confirmação de modos, o PC **0x80176590** escreveu o byte de modo:
captura seq 853, frame 9139: `0 -> 1` (Versus);
seq 865, frame 11046: `1 -> 0` (Arcade);
seq 887, frame 12841: `0 -> 5` (Practice).
O PC é compartilhado pelos modos; não é um gatilho exclusivo de Versus.

Fonte gerado `generated-online/SLUS_005.48_full_31.c`, função `func_80175F60`:
PC `0x80176584` lê um byte de `s0 + 3`; os PCs `0x80176588` e `0x8017658C` formam
`0x801E0000 - 13872 = 0x801DC9D0`; `0x80176590` armazena o byte.
É código do executável principal (região iniciada em `0x80101000`, tamanho
`0xBF000`, conforme `game.toml`), não um PC de overlay. Os campos `func` nos
históricos de escrita são contexto diagnóstico, não nomes de funções decompiladas.

O retorno à seleção também foi registrado com cena 7; a captura contém escritas
em `0x801D39B8`, incluindo PC `0x80103F5C`. O modo permanece 1 nesse retorno.
Logo, testar somente `mode == 1` não basta para representar o contexto ativo.

`versus_active` é reconstruído a partir da RAM a cada tick da HUD, com cena 7
excluída. A visibilidade exige ainda cena 1 e HUD observado nessa cena. Isso
evita depender de um latch externo que não acompanha snapshots. O estado visual
de HUD é limpo ao sair do Versus ou da cena de luta. O comportamento existente
do replay dentro da cena de luta foi preservado nesta fase.

## Repetir a observação

Use uma instalação dedicada de uma build com `PSX_DEBUG_TOOLS=ON`. As duas
janelas incluem os campos observados e bytes vizinhos ainda não classificados;
o coletor não decide modos automaticamente. Ele consulta RAM e histórico de
mudanças sem pausar o jogo.
Os blocos lidos por requisições diferentes não são um snapshot atômico.

```powershell
.\PlusAlphaProject\tools\observe_versus_mode.ps1 -Launch `
  -GameDir 'CAMINHO_DA_COPIA_DEDICADA' -Port 4533 -Label contrast-routes `
  -Output '.\PlusAlphaProject\captures\versus-mode-N' -Seconds 180
```

O lançamento acrescenta `PSX_WTRACE_BOOT_RANGES` apenas ao ambiente do processo
novo: `0x1d39b8-0x1d39d8,0x1dc9d0-0x1dca10`. Não inicia captura se a porta
estiver ocupada. Sem `-Launch`, consulta uma instância que já recebeu essas
faixas ao iniciar. Capturas existentes nunca são sobrescritas.

Marcadores opcionais em outro terminal (afastar o foco pode afetar o momento
dos inputs; os marcadores incluem frame e leituras próprias):

```powershell
python -B .\PlusAlphaProject\tools\observe_versus_mode.py mark `
  --port 4533 --output '.\PlusAlphaProject\captures\versus-mode-N' `
  --label versus-character-select
```

Registrar menu, destaque sem confirmação, confirmação, seleção, gameplay,
troca de personagens e retorno ao menu; contrastar Arcade, Training e Option.
Repetir entrada/saída de Versus. O PC amostrado em `registers` não é prova de
quem escreveu a RAM: usar `pc` dos eventos `writes`. PCs de overlays encontrados
em investigações futuras precisam de código/hash/geração correspondentes;
o histórico de escritas isolado não comprova a identidade de um overlay.

## Build e validação pelo usuário

O agente não executa build nem compila testes. Para gerar uma pasta nova:

```powershell
.\PlusAlphaProject\tools\build_online_diagnostics.ps1 `
  -BuildDirName build-online-diagnostics-versus-nameplates-1 -Jobs 2
```

Sem alterar geração/emissores, esta mudança não requer `-Generate` por si só.
Se a verificação de insumos pedir regeneração, seguir o fluxo de `ONLINE.md`.

Validar no executável novo:

- opção desligada: nenhuma barra ou caixa;
- menu, Arcade e Training: nenhuma barra ou caixa;
- gameplay Versus: nomes salvos e dois zeros amarelos;
- seleção de personagens: oculto; revanche: reaparece;
- retorno à seleção de modos: oculto mesmo com byte de modo ainda em 1;
- redimensionamento/tela cheia: alinhamento com a área do jogo, sem encobrir HUD;
- nomes UTF-8, oito caracteres, excedentes ignorados na apresentação;
- online: nomes nos mesmos lados e filtro pelo modo efetivo;
- rollback/save state: revalidar o modo restaurado, sem visibilidade residual.

Os testes C++ existentes `tools/tests/test_player_nameplates.cpp` e
`test_player_nameplates_state.cpp` foram atualizados, mas precisam ser compilados
e executados localmente pelo usuário. Não confundir a observação da build antiga
com validação visual ou de rollback do código novo. Nenhum comportamento de
vitórias foi implementado nesta etapa.

Verificação sem build: sintaxe Python e PowerShell, `git diff --check`, sete
pares de cena/modo conferidos na captura e quatro casos do coletor exercitados
em memória (paginação/limite de cursor, ausência de eventos, histórico reiniciado
e histórico sobrescrito). A instância dedicada foi deixada na seleção de modos.
