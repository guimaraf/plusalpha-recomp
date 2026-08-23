# Cobertura estática — SLUS-00548

## Estado desta revisão

Esta revisão reaplica, sobre a baseline estável `f0c5753`, os micro-lotes
históricos S1-214 a S1-225 e os checkpoints locais S1-227 a S1-230.

| Estado | Seeds | Palavras únicas | Cobertura | Blocos | Indiretas |
|---|---:|---:|---:|---:|---:|
| Baseline `f0c5753` | 384 | 75.645 / 195.584 | 38,6765% | 10.809 | 90 |
| S1-220 validado | 408 | 85.099 / 195.584 | 43,5102% | 12.048 | 108 |
| S1-221 validado | 424 | 86.532 / 195.584 | 44,2429% | 12.300 | 111 |
| S1-222 validado | 457 | 89.157 / 195.584 | 45,5850% | 12.711 | 111 |
| S1-223 validado | 460 | 89.219 / 195.584 | 45,6167% | 12.729 | 111 |
| S1-224 validado | 473 | 90.517 / 195.584 | 46,2804% | 12.841 | 111 |
| S1-225 validado | 482 | 91.336 / 195.584 | 46,6991% | 13.004 | 117 |
| S1-227 validado | 488 | 92.482 / 195.584 | 47,2851% | 13.164 | 119 |
| S1-228 validado | 490 | 94.434 / 195.584 | 48,2831% | 13.517 | 121 |
| S1-229 validado | 492 | 95.649 / 195.584 | 48,9043% | 13.717 | 126 |
| S1-230 validado | 494 | 97.804 / 195.584 | 50,0061% | 13.877 | 126 |
| Candidato S1-230 | 494 | 97.804 / 195.584 | 50,0061% | 13.877 | 126 |
| Candidato S1-229 | 492 | 95.649 / 195.584 | 48,9043% | 13.717 | 126 |

O S1-225 acrescentou 819 palavras únicas e 9 seeds à baseline anterior. A
origem histórica registrou 348 `ACCEPT`, 133 `WARN` estruturais conhecidos e
uma rejeição heurística auditada em `0x801A4278`.

O S1-227 reaproveita o lote registrado como S1-226 no histórico, renumerado
localmente para separar a build inicial sem fontes regenerados da validação
efetiva. Ele acrescentou 1.146 palavras únicas e 6 seeds à baseline anterior.

O S1-228 reaproveita o checkpoint histórico S1-227 e adiciona duas raízes, com
oito corpos, 7.992 bytes/1.998 palavras de corpo e ganho único de 1.952
palavras. A cobertura passa a 94.434 palavras (48,2831%).

O S1-229 reaproveita o checkpoint histórico S1-228 e adiciona duas raízes, com
dez corpos, 5.456 bytes/1.364 palavras de corpo e ganho único de 1.215
palavras. A cobertura passa a 95.649 palavras (48,9043%).

O S1-230 reaproveita o checkpoint histórico S1-229 e adiciona duas raízes, com
três corpos, 8.620 bytes/2.155 palavras de corpo e ganho único de 2.155
palavras. A cobertura passa a 97.804 palavras (50,0061%), o primeiro marco
local acima de 50%.

O S1-230 é o próximo candidato local e o primeiro marco acima de 50%. Ele
reaproveita o checkpoint histórico S1-229 e adiciona duas raízes, com três
corpos, 8.620 bytes/2.155 palavras de corpo e ganho único esperado de 2.155
palavras. A cobertura projetada passa a 97.804 palavras (50,0061%).

O S1-229 é o próximo candidato local. Ele reaproveita o checkpoint histórico
S1-228 e adiciona duas raízes, com dez corpos, 5.456 bytes/1.364 palavras de
corpo e ganho único esperado de 1.215 palavras. A cobertura projetada passa a
95.649 palavras (48,9043%).


## Situação da validação

Os micro-lotes S1-214 a S1-220 foram revalidados no projeto atual em build
limpa UCRT64 (`buildClean-ucrt-s1-220`), por aproximadamente 20 minutos de
gameplay. Não houve lag percebido; FPS e frametime permaneceram estáveis,
inclusive sob observação externa pelo RivaTuner.

Assim, 43,5102% passa a ser a baseline estável para os cenários testados. A
aprovação não equivale a cobertura total de personagens, cenários, modos e
transições: cada novo lote continuará exigindo contraprova no projeto atual.

O S1-221 foi revalidado em build limpa UCRT64 (`buildClean-ucrt-s1-221`), por
aproximadamente 20 minutos de gameplay, sem lag percebido e com FPS e frametime
estáveis sob observação externa pelo RivaTuner. Assim, 44,2429% passa a ser a
baseline estável para os cenários testados.

O S1-222 foi revalidado em build limpa UCRT64 (`buildClean-ucrt-s1-222`), por
aproximadamente 20 minutos de gameplay, sem lag percebido e com FPS e frametime
estáveis sob observação externa pelo RivaTuner. Assim, 45,5850% passa a ser a
baseline estável para os cenários testados.

O S1-223 foi revalidado em build limpa UCRT64 (`buildClean-ucrt-s1-223`), por
aproximadamente 20 minutos de gameplay, sem lag percebido e com FPS e frametime
estáveis. Assim, 45,6167% passa a ser a baseline estável para os cenários
testados.

O S1-224 foi revalidado em build limpa UCRT64 (`buildClean-ucrt-s1-224`), por
aproximadamente 20 minutos de gameplay, sem lag percebido e com FPS e frametime
estáveis. Assim, 46,2804% passa a ser a baseline estável para os cenários
testados.

O S1-225 foi revalidado em duas builds UCRT64 por aproximadamente 20 minutos,
em vários modos: a limpa `buildClean-ucrt-s1-225`, com FPS e frametime estáveis,
e a instrumentada `buildClean-ucrt-s1-225-tele`, sem regressão de gameplay ou
queda de FPS. A telemetria introduziu a irregularidade de frametime esperada,
sem impacto perceptível. Assim, 46,6991% passa a ser a baseline estável para os
cenários testados.

O S1-227 foi revalidado com os fontes do jogo regenerados em duas builds UCRT64
por aproximadamente 20 minutos, em vários modos: a limpa
`buildClean-ucrt-s1-227`, com FPS e frametime estáveis, e a instrumentada
`buildClean-ucrt-s1-227-tele`, sem regressão de gameplay ou queda de FPS. A
telemetria introduziu a irregularidade de frametime esperada, sem impacto
perceptível. A auditoria do generated confirmou 949 funções, 14.122 entradas
de dispatcher e zero destinos ou labels ausentes. Assim, 47,2851% passa a ser a
baseline estável para os cenários testados.

O S1-228 foi validado com os fontes do jogo regenerados em duas builds UCRT64
por aproximadamente 20 minutos, em vários modos: a limpa
`buildClean-ucrt-s1-228` e a instrumentada `buildClean-ucrt-s1-228-tele`.
Ambas permaneceram estáveis, sem queda de FPS ou regressão de frametime. A
auditoria do generated confirmou 957 funções, 14.488 entradas de dispatcher e
zero destinos ou labels ausentes. Assim, 48,2831% passa a ser a baseline estável
para os cenários testados.

O S1-229 foi validado com os fontes do jogo regenerados em build limpa UCRT64
por aproximadamente 20 minutos, em vários modos. FPS e frametime permaneceram
estáveis, sem queda percebida. A auditoria do generated confirmou 967 funções,
14.710 entradas de dispatcher e zero destinos ou labels ausentes. Assim,
48,9043% passa a ser a baseline estável para os cenários testados.

O S1-230 foi validado com os fontes do jogo e o BIOS regenerados, em build
limpa UCRT64 por aproximadamente 20 minutos, em vários modos. FPS e frametime
permaneceram estáveis, sem queda percebida. A auditoria do generated confirmou
970 funções, 14.870 entradas de dispatcher e zero destinos ou labels ausentes.
Assim, 50,0061% passa a ser a baseline estável para os cenários testados.

O S1-230 está aplicado somente como **candidato**. Antes de aprová-lo, é
obrigatório regenerar as fontes, auditar o `generated/` e executar a validação
em build limpa UCRT64. A build com telemetria fica reservada para diagnóstico de
uma regressão, não como etapa obrigatória deste lote.

O S1-229 está aplicado somente como **candidato**. Antes de aprová-lo, é
obrigatório regenerar as fontes, auditar o `generated/` e executar a validação
em build limpa UCRT64. A build com telemetria fica reservada para diagnóstico de
uma regressão, não como etapa obrigatória deste lote.

Os próximos testes de desempenho devem usar uma build limpa, sem observadores,
sem autocaptura/autocompilação de overlays e com cache somente para leitura.
Também devem incluir rotas nas quais os lags aleatórios foram percebidos.

### Gate aplicado

- fontes gerados a partir deste arquivo de seeds;
- auditoria do código gerado sem destinos diretos, tail-calls ou labels ausentes;
- aproximadamente 20 minutos de gameplay em build limpa UCRT64;
- FPS e frametime estáveis, inclusive no RivaTuner;
- nenhuma queda aleatória percebida em comparação com a baseline de 38,6765%.

Se ocorrer regressão, a bisseção interna deve seguir os limites já documentados
no arquivo de seeds: S1-214, S1-215, S1-216, S1-217, S1-218, S1-219 e S1-220.

## Significado do percentual

A cobertura representa palavras MIPS únicas alcançáveis dentro da janela
configurada da imagem principal. Não representa percentual de gameplay pronto,
percentual de tempo executado estaticamente nem garante que todo o denominador
de 195.584 palavras seja código.

Entradas interiores e aliases podem fazer a contagem bruta dos arquivos C
gerados ser maior que a cobertura única oficial. Para registrar um checkpoint,
usar sempre a métrica de endereços únicos do manifesto, nunca a soma bruta dos
corpos emitidos.
