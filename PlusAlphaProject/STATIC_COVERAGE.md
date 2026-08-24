# Cobertura estática — SLUS-00548

## Estado desta revisão

Esta revisão reaplica, sobre a baseline estável `f0c5753`, os micro-lotes
históricos S1-214 a S1-225 e os checkpoints locais S1-227 a S1-236.

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
| S1-231 validado | 495 | 100.054 / 195.584 | 51,1565% | 14.144 | 126 |
| S1-232 validado | 496 | 103.128 / 195.584 | 52,7282% | 14.489 | 126 |
| S1-233 validado | 498 | 103.251 / 195.584 | 52,7911% | 14.523 | 127 |
| S1-234 validado | 499 | 103.296 / 195.584 | 52,8141% | 14.533 | 127 |
| S1-235 validado | 503 | 104.876 / 195.584 | 53,6220% | 14.726 | 127 |
| S1-236 validado | 507 | 105.165 / 195.584 | 53,7697% | 14.766 | 127 |

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

O S1-231 reaproveita o checkpoint histórico S1-230 e adiciona uma raiz, com
oito corpos, 9.000 bytes/2.250 palavras de corpo e ganho único de 2.250
palavras. A cobertura passa a 100.054 palavras (51,1565%).

O S1-232 reaproveita o checkpoint histórico S1-231 e adiciona uma raiz, com 24
corpos, 12.296 bytes/3.074 palavras de corpo e ganho único de 3.074 palavras.
A cobertura passa a 103.128 palavras (52,7282%).

O S1-233 reaproveitou o checkpoint histórico S1-232 e adicionou duas raízes,
com dois corpos, 492 bytes/123 palavras de corpo e ganho único de 123 palavras.
A cobertura passou a 103.251 palavras (52,7911%).

O S1-234 reaproveitou o checkpoint histórico S1-233 e adicionou uma raiz, com
um corpo de 180 bytes/45 palavras e ganho único de 45 palavras. A cobertura
passou a 103.296 palavras (52,8141%).

O S1-235 reaproveitou o checkpoint histórico S1-234 e adicionou quatro raízes,
com seis corpos, 6.320 bytes/1.580 palavras de corpo e ganho único de 1.580
palavras. A cobertura passou a 104.876 palavras (53,6220%).

O S1-236 reaproveitou o checkpoint histórico S1-235 e adicionou quatro raízes,
com quatro corpos, 1.156 bytes/289 palavras de corpo e ganho único de 289
palavras. A cobertura passou a 105.165 palavras (53,7697%).


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

O S1-231 foi validado com os fontes do jogo regenerados em build limpa UCRT64
por aproximadamente 20 minutos, em vários modos. FPS e frametime permaneceram
estáveis, sem queda percebida. A auditoria do generated confirmou 978 funções,
15.137 entradas de dispatcher e zero destinos ou labels ausentes. Assim,
51,1565% passa a ser a baseline estável para os cenários testados.

O S1-232 foi validado com os fontes do jogo regenerados em build limpa UCRT64
por aproximadamente 20 minutos, em vários modos. FPS e frametime permaneceram
estáveis, sem queda percebida. A auditoria do generated confirmou 1.002 funções,
15.482 entradas de dispatcher e zero destinos ou labels ausentes. Assim,
52,7282% passa a ser a baseline estável para os cenários testados.

O S1-233 foi validado com os fontes do jogo regenerados em build limpa UCRT64
por aproximadamente 20 minutos, em vários modos. FPS e frametime permaneceram
estáveis, sem queda percebida. A auditoria do generated confirmou 1.004 funções,
15.516 entradas de dispatcher e zero destinos ou labels ausentes. Assim,
52,7911% passa a ser a baseline estável para os cenários testados.

O S1-234 foi validado com os fontes do jogo regenerados em build limpa UCRT64
por aproximadamente 20 minutos, em vários modos. FPS e frametime permaneceram
estáveis, sem queda percebida. A auditoria do generated confirmou 1.005 funções,
15.526 entradas de dispatcher e zero destinos ou labels ausentes. Assim,
52,8141% passa a ser a baseline estável para os cenários testados.

O S1-235 foi validado com os fontes do jogo regenerados em build limpa UCRT64
por aproximadamente 20 minutos, em vários modos. FPS e frametime permaneceram
estáveis, sem queda percebida. A auditoria do generated confirmou 1.011 funções,
15.719 entradas de dispatcher e zero destinos ou labels ausentes. Assim,
53,6220% passa a ser a baseline estável para os cenários testados.

O S1-236 foi validado com os fontes do jogo regenerados em build limpa UCRT64
por aproximadamente 20 minutos, em vários modos. FPS e frametime permaneceram
estáveis, sem queda percebida. A auditoria do generated confirmou 1.015 funções,
15.759 entradas de dispatcher e zero destinos ou labels ausentes. Assim,
53,7697% passa a ser a baseline estável para os cenários testados.

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
