# Placar acumulado do Versus

O placar pertence ao framework: P1 vence, depois P2 vence, resulta em 1 x 1.
Nao acompanha nem modifica a sequencia de vitorias original. Preserva revanche
e troca de personagens. Selecao de modos, saida do Versus, nova execucao,
load manual bem-sucedido e desconexao zeram ambos. Empate nao soma.

## Gatilho SLUS-00548

Cena em `0x801D39B8`, modo em `0x801DC9D0`, flags em `0x801D39E4`.
O commit de resultado em `0x80109438` (funcao `0x80109400`, chamada ao atingir
os rounds necessarios) liga `0x400` e grava o vencedor no bit 4: 0=P1, 1=P2.
A rotina nativa `0x80109864` exige `0x400` e exclui resultados com `0x40`.
A implementacao observa essas flags uma vez por frame simulado, inclusive
na ressimulacao, antes dos snapshots de rollback. Nao instala hook por instrucao.

Capturas fornecidas: P1 terminou com flags `0x00300683`; P2, `0x0030069F`.
Ambos passaram de um para dois rounds. A escrita nativa de pontos foi localizada
em `0x80109D74`, mas os novos contadores nao usam esse armazenamento ou seu
limite de 999. Cada contador externo usa uint32 com saturacao, sem overflow.

Uma trava consome cada resultado uma vez e so rearma quando `0x400` limpa.
Trocar de cena ou cortar replay mantendo as flags nao conta novamente.
Reset manual consome o resultado ja presente para nao recriar um ponto antigo.

## Rollback e desenho

Secao opcional `BS_SEC_NAMEPLATES` (`0x16`): 16 bytes little-endian, versao 1,
P1, P2 e trava. O carregamento valida tamanho, versao e trava antes de aplicar
qualquer secao. Snapshots anteriores sem essa secao zeram o placar.
Rollback restaura os contadores e a trava; load manual limpa apos restaurar.
Nomes e visibilidade nao integram essa secao. O provider publica uma copia
protegida para o renderizador, mantendo o filtro Versus ja existente.
Os numeros sao desenhados nas caixas separadas, com ajuste da fonte para caber.
O desenho continua por frame apresentado, sem alterar o jogo ou seu frame pacing.

## Build e validacao local

Na raiz `plusalpha-recomp`:

```powershell
.\PlusAlphaProject\tools\build_versus_score.ps1
```

Cria uma pasta nova com data/hora, SDL3, online e diagnostico; jobs=2.
Nao requer `-Generate` pela mudanca; caso os insumos gerados estejam desatualizados,
o fluxo existente pode solicitar essa opcao. Nao substitui builds ou saves.

O agente nao executou build nem compilou/executou testes C++.
`tools/tests/test_player_nameplates_state.cpp` cobre round parcial, resultado
retido, 1 x 1, exclusao de resultado sem ponto, troca de personagens, reset,
HUD desligada e restauracao/recalculo de vencedor em rollback.

Validar na nova build: entrada 0 x 0; P1/P2 alternados; repeticao do mesmo
vencedor; corte de replay; revanche e troca de personagens; empate real;
volta ao menu; load manual durante luta e resultado; desconexao; online com
rollback. A exclusao de empate segue a rotina nativa, mas precisa desse teste
real. Conferir ambos os pares com a mesma build e ausencia de ponto duplicado
ou desync. Manter o teste anterior de HUD oculta em Arcade e Training.
