# Cobertura estática — SLUS-00548

## Estado desta revisão

Esta revisão reaplica, sobre a baseline estável `f0c5753`, somente os
micro-lotes históricos S1-214 a S1-220 do checkpoint `a4e8913`.

| Estado | Seeds | Palavras únicas | Cobertura | Blocos | Indiretas |
|---|---:|---:|---:|---:|---:|
| Baseline `f0c5753` | 384 | 75.645 / 195.584 | 38,6765% | 10.809 | 90 |
| S1-220 validado | 408 | 85.099 / 195.584 | 43,5102% | 12.048 | 108 |
| Candidato S1-221 | 424 | 86.532 / 195.584 | 44,2429% | 12.300 | 111 |

O S1-221 acrescenta 1.433 palavras únicas e 16 seeds à baseline aprovada. A
origem histórica registrou 302 `ACCEPT`, 122 `WARN` estruturais conhecidos e
zero `REJECT`.

## Situação da validação

Os micro-lotes S1-214 a S1-220 foram revalidados no projeto atual em build
limpa UCRT64 (`buildClean-ucrt-s1-220`), por aproximadamente 20 minutos de
gameplay. Não houve lag percebido; FPS e frametime permaneceram estáveis,
inclusive sob observação externa pelo RivaTuner.

Assim, 43,5102% passa a ser a baseline estável para os cenários testados. A
aprovação não equivale a cobertura total de personagens, cenários, modos e
transições: cada novo lote continuará exigindo contraprova no projeto atual.

O S1-221 está aplicado somente como **candidato**. Ele ainda exige geração,
auditoria do novo generated e validação local antes de substituir a baseline
de 43,5102%.

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
