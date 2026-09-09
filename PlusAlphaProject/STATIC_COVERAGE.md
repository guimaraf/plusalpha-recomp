# Cobertura estática — SLUS-00548

## Estado desta revisão

Esta revisão reaplica, sobre a baseline estável `f0c5753`, os micro-lotes
históricos S1-214 a S1-225 e os checkpoints locais S1-227 a S1-239.

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
| S1-237/P4-1 validado | 508 | 106.077 / 195.584 | 54,2360% | 14.877 | 127 |
| S1-239 validado | 513 | 106.319 / 195.584 | 54,3598% | 14.930 | 127 |
| S1-261 validado | 545 | 111.379 / 195.584 | 56,9469% | 15.680 | 127 |
| S1-262 validado | 546 | 112.315 / 195.584 | 57,4255% | 15.820 | 127 |
| S1-263 validado | 547 | 120.341 / 195.584 | 61,5291% | 17.228 | 127 |
| S1-264 validado | 550 | 120.558 / 195.584 | 61,6400% | 17.258 | 127 |
| S1-265 validado | 558 | 121.539 / 195.584 | 62,1416% | 17.424 | 127 |
| S1-266 validado | 564 | 125.435 / 195.584 | 64,1336% | 18.079 | 127 |
| S1-267 validado | 565 | 126.371 / 195.584 | 64,6121% | 18.200 | 127 |
| S1-268 validado | 566 | 126.830 / 195.584 | 64,8468% | 18.271 | 127 |


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

O S1-237 reaproveitou o micro-lote histórico P4-1 e adicionou uma raiz, com três
corpos contíguos, 3.648 bytes/912 palavras de corpo e ganho único de 912
palavras. A cobertura passou a 106.077 palavras (54,2360%).

O S1-238 reaproveitou o lote registrado historicamente como S1-236 e adicionou
quatro raízes independentes, com quatro corpos, 876 bytes/219 palavras de corpo
e ganho único de 219 palavras. A cobertura passou a 106.296 palavras (54,3480%).

O S1-239 reaproveitou o último lote já descoberto no histórico, registrado
originalmente como S1-237, e adicionou uma raiz. O intervalo emitido possui 112
bytes/28 palavras de corpo e ganho único de 23 palavras. A cobertura passou a
106.319 palavras (54,3598%).


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

O S1-237/P4-1 foi validado com os fontes do jogo regenerados em build limpa
UCRT64 (`buildClean-ucrt-s1-237`), por aproximadamente 20 minutos e em vários
modos. O Shungoku-Satsu da Sakura foi repetido várias vezes, com as pétalas
corretas e sem regressão percebida. FPS e frametime permaneceram estáveis. A
auditoria do generated confirmou 1.018 funções, 15.870 entradas de dispatcher e
zero destinos ou labels ausentes. Assim, 54,2360% passa a ser a baseline estável
para os cenários testados.

O S1-238 foi validado com os fontes do jogo regenerados em build limpa UCRT64
(`buildClean-ucrt-s1-238`), por aproximadamente 20 minutos e em vários modos.
Foram disputadas várias partidas Guile x Hokuto no cenário da Hokuto, sem lag ou
regressão percebida; FPS e frametime permaneceram estáveis. A auditoria do
generated confirmou 1.022 funções, 15.918 entradas de dispatcher e zero destinos
ou labels ausentes. Assim, 54,3480% passa a ser a baseline estável para os
cenários testados.

O S1-239 foi validado com fontes do jogo regenerados em build limpa UCRT64
(`buildClean-ucrt-s1-239`), por aproximadamente 20 minutos e em vários modos.
Partidas Guile x Hokuto no cenário da Hokuto permaneceram sem lag ou regressão
percebida, com FPS em 60. Houve pequena oscilação visual de frametime entre 15 e
17 ms, por isso a contraprova de telemetria foi executada.

A coleta de 43 s na build instrumentada confirmou `0x8019CB78` e `0x8019CBA8`
com pelo menos 4.096 registros de fntrace cada, sem fallback candidato. Não houve
aborts, bloqueio nativo ou mismatch de endereço. O frametime do intervalo teve
P50 de 16,684 ms, P95 de 16,766 ms e máximo de 17,416 ms; portanto a variação
observada é compatível com present/agendamento e não caracteriza stutter. A
auditoria do generated confirmou 1.023 funções, 15.924 entradas de dispatcher e
zero destinos ou labels ausentes. Assim, 54,3598% passa a ser a baseline estável
para os cenários testados. Com este lote, esgota-se o material histórico já
descoberto; a próxima etapa será descoberta nova.

Os micro-lotes inéditos S1-240, S1-241 e S1-242 foram primeiro validados em
builds instrumentadas próprias. As coletas confirmaram alcance nativo dos
candidatos, ausência de fallback, zero abort, bloqueio nativo, página divergente
ou mismatch de endereço. No S1-242, o fechamento de `0x80137FE8`, `0x80138084`
e `0x8013827C` produziu 107/1/107 hits, 215/215 registros fntrace completos e
confirmou as duas relações de chamada internas. O frametime instrumentado teve
P50 de 16,683 ms, P95 de 16,741 ms e máximo de 17,594 ms.

O conjunto cumulativo foi então validado no checkpoint limpo UCRT64
(`buildClean-ucrt-s1-242`), em `Release`, com `PSX_DEBUG_TOOLS=OFF` e runtime
estático. Foram percorridos Versus Doctrine Dark x Skullomania no cenário do
Skullomania, Versus Guile x Hokuto no cenário da Hokuto, Bonus Barril, Bonus
Trial e várias lutas no Arcade. Não houve regressão percebida; FPS permaneceu em
60 e o frametime observado ficou entre 16,4 e 16,8 ms. A auditoria do generated
confirmou 1.028 funções, 15.985 entradas de dispatcher e zero destinos ou labels
ausentes. Assim, 106.825/195.584 palavras, ou 54,6185%, passam a ser a nova
O micro-lote S1-264 promoveu os três alvos diretos do overlay de menu e seleção
0x80020000 para C nativo (0x801912D8, 0x80191588 e 0x801961BC), somando 217
palavras. A validação diferencial entre menus-exploration-01 e menus-exploration-02
confirmou a erradicação total dos 5.102 misses dessas funções (-100%) e reduziu os
fallbacks de interpretador em 24,17% (-1.251.656 chamadas). A auditoria do generated
confirmou 1.078 funções, 17.250 entradas de dispatcher e zero erros. A cobertura
oficial atinge 120.558/195.584 palavras (61,6400%).

O micro-lote S1-265 promoveu o fechamento completo da tabela de Options / Memory Card
0x801B8538 e seus helpers para C nativo (0x80192128, 0x80192E58, 0x80192F60, 0x8019314C,
0x80193174, 0x8019319C, 0x801931C4 e 0x8019328C), somando 981 palavras únicas (+8 funções).
A validação diferencial entre menus-exploration-02 e menus-exploration-03 confirmou a
eliminação de 100% dos 1.118 misses observados nas entradas dessa tabela e seus helpers,
reduzindo os PCs únicos não compilados observados de 63 para 52. A auditoria do generated
confirmou 1.086 funções, 17.416 entradas de dispatcher, 17.424 blocos e status CLEAN. A cobertura
oficial atinge 121.539/195.584 palavras (62,1416%).

O micro-lote S1-266 promoveu os dispatchers centrais de UI/Animação (0x8016A84C),
Opções/Sound Test (0x8018C880), helpers de cursor de menus (0x80125594 e 0x801258D4),
caller direto de thunks (0x80124400) e thunk de syscall BIOS B0:51 (0x801932BC),
expandindo 22 funções nativas e somando 3.896 palavras únicas. A validação
diferencial entre menus-exploration-03 e menus-exploration-04 confirmou a
erradicação total de 50 dos 52 PCs não compilados observados (-96,15%), eliminando
100% dos 2.591 misses dessas rotinas e reduzindo os fallbacks de interpretador
em 482.594 chamadas (-12,7%). A rota inteira de menus agora opera 100% nativa no EXE
principal, restando estaticamente apenas o loop de hardware polling de joypad
(0x801AB1F4 e 0x801AB2C0). A auditoria do generated confirmou 1.108 funções, 18.069
entradas de dispatcher, 18.079 blocos e status CLEAN. A cobertura oficial atinge
125.435/195.584 palavras (64,1336%).

O micro-lote S1-267 promoveu a FSM central de combate e Round State Manager
(0x80106BD4, 936 palavras, jump table 0x801AB5BC de 9 casos), eliminando 10 dos 13
misses estáticos observados em combate e aumentando o dispatch nativo em mais de 40.000
chamadas. A auditoria confirmou 1.109 funções nativas, 18.200 entradas de dispatcher e
status CLEAN. A cobertura oficial atingiu 126.371/195.584 palavras (64,6121%).

O micro-lote S1-268 promoveu o cluster de processamento de entidades e frame update da luta
(0x80117224, 0x8011726C, 0x80117328 e 0x80117564, totalizando 459 palavras e 4 funções),
conectando perfeitamente 0x801171DC a 0x80117950 no Main EXE. A validação diferencial de telemetria
(gameplay-discovery-03) confirmou a erradicação de 100% dos últimos 3 misses do Main EXE
(reduzindo misses estáticos a zero) e cortou os fallbacks de interpretador em 60% (-132.634 chamadas).
A validação em build limpa (buildClean-ucrt-s1-268) foi executada em Versus completo (D.Dark vs Ryu)
e 4 lutas consecutivas no Arcade, com frametime 100% liso a 60 FPS fixos e zero regressões.
A auditoria confirmou 1.113 funções nativas, 18.271 entradas de dispatcher e status CLEAN.
A cobertura oficial atinge 126.830/195.584 palavras (64,8468%).

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
