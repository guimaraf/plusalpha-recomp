# Cobertura estática — SLUS-00548

## Estado desta revisão

Esta revisão reaplica, sobre a baseline estável `f0c5753`, os micro-lotes
históricos S1-214 a S1-225.

| Estado | Seeds | Palavras únicas | Cobertura | Blocos | Indiretas |
|---|---:|---:|---:|---:|---:|
| Baseline `f0c5753` | 384 | 75.645 / 195.584 | 38,6765% | 10.809 | 90 |
| S1-220 validado | 408 | 85.099 / 195.584 | 43,5102% | 12.048 | 108 |
| S1-221 validado | 424 | 86.532 / 195.584 | 44,2429% | 12.300 | 111 |
| S1-222 validado | 457 | 89.157 / 195.584 | 45,5850% | 12.711 | 111 |
| S1-223 validado | 460 | 89.219 / 195.584 | 45,6167% | 12.729 | 111 |
| S1-224 validado | 473 | 90.517 / 195.584 | 46,2804% | 12.841 | 111 |
| S1-225 validado | 482 | 91.336 / 195.584 | 46,6991% | 13.004 | 117 |

O S1-225 acrescentou 819 palavras únicas e 9 seeds à baseline anterior. A
origem histórica registrou 348 `ACCEPT`, 133 `WARN` estruturais conhecidos e
uma rejeição heurística auditada em `0x801A4278`.

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
