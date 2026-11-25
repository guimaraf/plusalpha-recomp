# PlayStation 1 (PSX) — SIO0 → Input disponível → Input processado

**Documento técnico para consulta e implementação com Codex**  
**Data de revisão:** 20 de outubro de 2026  
**Escopo:** PlayStation original (PS1/PSX), conexão de controle pela porta serial **SIO0**, jogos que usam rotinas da BIOS e jogos com leitura direta dos registradores. Não confundir com SIO1, PS2 ou USB.

## 1. Objetivo e resposta curta

Determinar **quanto tempo decorre entre o estado físico de um botão e seu uso pelo jogo** exige distinguir camadas:

1. **Transmissão SIO0:** transferência síncrona de bytes entre console e controle.
2. **Disponibilidade do input:** bytes recebidos e interpretados; possivelmente copiados para buffers da BIOS.
3. **Consumo pelo jogo:** instante em que o programa consulta os buffers ou registradores.
4. **Resposta visual:** lógica, renderização, saída de vídeo e latência de exibição.

**Não há um único valor universal de “SIO → input processado”.** Em comunicação padrão (~250 kbit/s), **5 bytes** de um controle digital requerem aproximadamente **0,161 ms** de clock serial, sem os intervalos de handshake/execução; em modo analógico, **9 bytes** requerem aproximadamente **0,289 ms**. Esses tempos **não representam** latência física total nem tempo até o jogo reagir.

O procedimento padrão da BIOS (`InitPAD2` + `StartPAD2`) atualiza buffers durante **interrupções VBlank**. Consequentemente, a fase temporal do polling pode introduzir espera de até aproximadamente um período de VBlank antes do próximo ciclo de leitura (em uma aproximação de 60 Hz, ~16,7 ms; em uma de 50 Hz, 20 ms). Isso **não significa** que o SIO possui um atraso intrínseco desse tamanho. Jogos com leitura direta podem adotar outra cadência.

## 2. Documentação principal

Fontes prioritárias (especificação comunitária técnica PSX-SPX):

- Registradores SIO e fórmula de baud rate: https://psx-spx.consoledev.net/serialinterfacessio/
- Sinais elétricos, transferência por byte e ACK: https://psx-spx.consoledev.net/ps1/sio/controllersandmemorycards/controller-and-memory-card-signals/
- Sequência da comunicação com controles: https://psx-spx.consoledev.net/ps1/sio/controllersandmemorycards/controllers-communication-sequence/
- Modos digital/analógico e comandos: https://psx-spx.consoledev.net/dev/ps1/sio/controllersandmemorycards/controllers-configuration-commands/
- BIOS — funções de controle: https://psx-spx.consoledev.net/ps1/kernelbios/joypad-functions/
- BIOS — VBlank e timers: https://psx-spx.consoledev.net/ps1/kernelbios/timer-functions/
- PDF técnico consolidado: https://psx-spx.consoledev.net/psx-spx.pdf

**Natureza das fontes:** PSX-SPX é documentação técnica comunitária de engenharia reversa; não deve ser descrita como manual oficial da Sony. Cada valor abaixo identifica o que é diretamente documentado ou calculado.

## 3. SIO0: temporização da transmissão

### 3.1 Parâmetros documentados

- A taxa serial **padrão** usada pelo kernel é aproximadamente **250 kHz**.
- Os bits são transmitidos **LSB primeiro**.
- Clock ocioso em nível alto, com transição de saída na borda descendente e amostragem na borda ascendente (descrita como CPOL=1, CPHA=1).
- A transmissão é **full-duplex por byte**: o console transmite e recebe simultaneamente.
- Para SIO0, a fórmula documentada é:

```text
BitsPerSecond = 33868800 / MAX(((Reload * Factor) AND NOT 1), 1)
```

- Configuração de referência: registrador `BR = 0x0088` (136 decimal), com fator compatível com a configuração padrão; nesse cenário:

```text
baud = 33_868_800 / 136 = 249_035,2941 bits/s
Tbit = 136 / 33_868_800 s = 4,0151 µs
Tbyte = 8 * Tbit = 32,1209 µs
```

**Observação:** a fórmula depende de `Factor` (modo configurado). Os cálculos com divisor 136 pressupõem o fator apropriado para o cenário padrão de referência. Inspecionar `MR` e `BR` da implementação real, em vez de assumir que toda comunicação opera no mesmo divisor.

### 3.2 Pacotes de leitura típicos

O comando normal `0x42` lê botões e, quando habilitados, dados analógicos. A comunicação tem os seguintes pares de bytes (o primeiro byte recebido na seleção é alta impedância/sem informação válida):

| Índice | Console envia | Controle responde | Significado |
|---:|---|---|---|
| 1 | `0x01` | Hi-Z | Seleção do controle |
| 2 | `0x42` | `idlo` | Comando de leitura e identificação |
| 3 | `0x00` (TAP) | `idhi` (tipicamente `0x5A`) | Confirmação/identificação |
| 4 | `0x00` (MOT) | `swlo` | Botões, byte baixo |
| 5 | `0x00` (MOT) | `swhi` | Botões, byte alto |
| 6–9 | `0x00` | `adc0..adc3` | 4 bytes analógicos, quando presentes |

Identificadores usuais: `0x5A41` para controle digital e `0x5A73` para pad em modo analógico. Os campos transmitidos nas posições de motor podem mudar caso o rumble tenha sido configurado; a sequência acima usa valores neutros para leitura típica.

### 3.3 Duração serial mínima calculada

Usando o divisor 136 de referência:

| Tipo | Bytes na transação | Bits | Clock serial acumulado |
|---|---:|---:|---:|
| Controle digital (`0x41`) | 5 | 40 | **160,605 µs = 0,1606 ms** |
| Controle analógico (`0x73`) | 9 | 72 | **289,134 µs = 0,2891 ms** |

Arredondando a baud rate para 250 kHz obtém-se 160 µs e 288 µs. **São estimativas da duração do clock, não medições de latência ponta a ponta.** Não incluem pausas entre bytes, ACK, espera do driver, execução de interrupções, nem momento da coleta física do botão.

### 3.4 Handshake `/ACK` e tratamento de IRQ

Segundo PSX-SPX:

- O dispositivo deve manter `/ACK` baixo por **pelo menos 2 µs** para solicitar o próximo byte.
- O driver de controle da BIOS ignora pulsos `/ACK` que ocorram nos primeiros **2–3 µs** (~100 ciclos) após o último clock serial.
- O driver considera timeout se `/ACK` não for ativado em até **100 µs** após o último pulso SCK.
- SIO0 apresenta o estado de `/ACK` por meio do bit DSR no registrador de status.
- No último byte da transação, o periférico não precisa sinalizar continuação com outro `/ACK`.

**Cuidado fundamental:** `100 µs` é o **limite de espera/timeout**, não um atraso fixo somado a cada byte. `2 µs` é largura mínima do pulso ACK, não uma medição do tempo entre bytes. Não se deve multiplicar esses valores e declarar o resultado como latência real de um controle.

## 4. Da interface ao programa: caminhos de software

### 4.1 Leitura pela BIOS

A documentação das funções `InitPAD2(buf1, 0x22, buf2, 0x22)` e `StartPAD2()` registra:

- Buffers separados para porta 1 e porta 2.
- `StartPAD2()` registra o handler `PadCardIrq`.
- Com o subsistema habilitado, **os pads 1 e 2 são lidos em interrupções VBlank** e os dados são salvos nos buffers.
- Layout básico de cada buffer: offset `0x00` = status; `0x01` = ID; `0x02..0x21` = dados, incluindo estado de botões.
- Atenção ao estado inicial: `InitPAD2` zera os buffers, então é recomendável tratar o período anterior à primeira atualização válida.

Pipeline conceitual:

```text
Botão altera estado físico
    ↓ (instante arbitrário em relação ao polling)
Próxima rotina de leitura do controle (p. ex., no VBlank)
    ↓
SIO0 transmite a transação: bytes + ACK + overhead do driver
    ↓
BIOS grava os dados no buffer
    ↓
Código do jogo consulta o buffer (na sua própria cadência)
    ↓
Jogo atualiza estado/simulação e, possivelmente, a imagem
```

**Não equiparar VBlank à duração da transmissão.** O VBlank determina quando o polling padrão acontece; o barramento transmite em escala de centenas de microssegundos para transações usuais.

### 4.2 Leitura direta do hardware

Um jogo ou programa pode controlar SIO0 diretamente. Nesse caso, a frequência das transações, a sincronização com VBlank, o uso de interrupções e o tempo de entrega ao gameplay dependem da implementação. **Não pressupor que todos os jogos de PS1 usam polling da BIOS a exatamente 50/60 Hz.**

## 5. Modelo de latência e limites de interpretação

Definir pontos temporais:

```text
t0: mudança física no botão
t1: início da próxima transação de leitura que observa esse estado
t2: byte final necessário já recebido/validado
t3: estado armazenado no buffer ou estrutura acessível
t4: código do jogo efetivamente consome esse estado
t5: consequência apresentada ao usuário
```

Então:

```text
L_leitura   = t3 - t0
L_consumo   = t4 - t0
L_visual    = t5 - t0
L_serial    = t2 - t1
L_software  = t4 - t3
```

**Atenção:** `t2 - t1` inclui handshake e pausas se `t1` for o início da transação e `t2` o recebimento completo; portanto pode superar a soma da duração puramente serial dos bytes.

Se as leituras ocorrem periodicamente a cada `T` e a fase do botão for uniformemente distribuída, **espera até a próxima leitura** pode ser modelada aproximadamente por:

```text
0 ≤ L_espera_poll < T
E[L_espera_poll] ≈ T/2
```

Exemplos *ideais*, usando `T = 1/f` (não são medições de um jogo real):

| Cadência hipotética | Período T | Espera média de fase | Espera máxima aproximada |
|---|---:|---:|---:|
| 60 Hz | 16,667 ms | 8,333 ms | 16,667 ms |
| 50 Hz | 20,000 ms | 10,000 ms | 20,000 ms |
| 30 Hz | 33,333 ms | 16,667 ms | 33,333 ms |

**Importante:** 30 fps de renderização não implica necessariamente 30 Hz de polling. Da mesma forma, um padrão de vídeo NTSC ou PAL não define sozinho o instante em que o jogo lê o buffer. Para determinar a latência real, identificar a implementação específica.

## 6. O que o Codex deve observar em um emulador ou implementação

### 6.1 Checklist de correção

- [ ] Separar o subsistema SIO0 do loop de atualização dos jogos.
- [ ] Modelar período de bit a partir de `MR`, `BR` e frequência de referência, sem hardcode universal de 250 kHz.
- [ ] Transmitir e receber bytes simultaneamente e LSB-first.
- [ ] Distinguir `0x01` (seleção de controle) do endereço do memory card.
- [ ] Implementar resposta ao comando `0x42`, identificação e tamanhos de transação por modo.
- [ ] Modelar `/ACK` em termos de evento, largura, timing e timeout conforme aplicável.
- [ ] Atualizar registradores e sinalização de interrupção SIO0 no momento correto.
- [ ] Verificar o comportamento da BIOS que faz polling no VBlank.
- [ ] Não inserir um frame de latência artificial na transmissão SIO0.
- [ ] Não assumir que o frame rate do jogo seja idêntico ao polling do controle.
- [ ] Evitar ler o estado moderno do controle diretamente no instante em que o jogo consulta um buffer antigo, se isso violar a emulação temporal.
- [ ] Testar os modos digital e analógico, desconexões/timeout e as duas portas.

### 6.2 Instrumentação sugerida

Adicionar timestamps ou contadores de ciclos a eventos como:

```text
HOST_INPUT_CHANGE
SIO0_SELECT_ASSERT
SIO0_BYTE_TX_START
SIO0_BYTE_TX_END
SIO0_ACK_ASSERT
SIO0_ACK_RELEASE
SIO0_TRANSACTION_COMPLETE
PAD_BUFFER_UPDATED
GAME_PAD_BUFFER_READ   (se observável)
VBLANK_IRQ_BEGIN
VBLANK_IRQ_END
VIDEO_FRAME_PRESENT
```

Produzir tabela CSV com `event`, `cycles`, `time_us`, `port`, `tx_byte`, `rx_byte`, `pad_mode`, `frame_index`; converter ciclos em microssegundos usando o clock relevante. O evento `GAME_PAD_BUFFER_READ` só é diretamente observável se a instrumentação tiver visibilidade das leituras de memória da CPU ou da lógica específica do jogo.

### 6.3 Testes de validação

1. **Digital:** transação de 5 bytes, resposta com ID digital, botões nos bytes 4–5.
2. **Analógico:** transação de 9 bytes, 4 bytes adicionais de eixos.
3. **Baud rate:** comparar a duração efetiva com `33868800 / MAX(((Reload*Factor) AND NOT 1),1)` para configurações relevantes.
4. **ACK:** validar que a continuação entre bytes dependa do handshake e que atraso de até 100 µs seja entendido como timeout do driver da BIOS, não atraso intrínseco.
5. **VBlank/BIOS:** testar se o buffer muda na rotina de polling, não arbitrariamente após todo evento de input do sistema operacional.
6. **Latência por fase:** variar a fase de alteração do botão em relação à leitura e comparar `t3-t0`, `t4-t0`.
7. **Sem regressão:** controle desconectado, ambas as portas e jogos que acessam registradores diretamente.

## 7. O que ainda exige medição

Não foi identificado um valor técnico universal e oficial para **“botão físico pressionado → ação processada pela lógica do jogo”**. Esse número varia por controle, firmware, temporização do jogo, arquitetura de polling, região/vídeo, emulador e display. Para afirmar um valor específico, será necessário delimitar **modelo de controle, jogo, rotina, método de leitura e marco temporal considerado**.

Para análise com hardware real, um analisador lógico nos sinais SCK/MOSI/MISO/ACK pode medir `t1` e `t2`; o tempo físico `t0` pede instrumentação do botão; o consumo pelo jogo `t4` pede instrumentação de software ou depuração de acesso à memória.

## 8. Instrução curta para o Codex

> Use este documento como referência técnica inicial para auditar a temporização de SIO0 do PlayStation 1. Separe (a) transferência serial, (b) entrega do input ao buffer da BIOS, (c) leitura pelo código do jogo e (d) resposta em vídeo. Verifique no código os registradores MR/BR, TX/RX, ACK/IRQ, comando `0x42`, tamanhos de pacote digital/analógico, VBlank e agendamento do polling. Não transforme estimativas de duração serial em latência total e não acrescente atraso fixo de 16,7 ms ao SIO. Gere evidências com logs de ciclos e testes determinísticos antes de concluir que existe erro de timing.

---

**Notas de confiabilidade:** Os valores de baud rate, comprimento de pacote, sinais e comportamento das funções BIOS vêm da especificação PSX-SPX. Os tempos serializados em microssegundos e as esperas por fase de polling são **cálculos derivados**, explicitamente sujeitos às premissas acima. Nenhum destes números deve ser anunciado como medição universal de *input lag* do PS1.
