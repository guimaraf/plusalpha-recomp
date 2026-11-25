# Captura causal da resposta ao input

Objetivo: identificar e depois medir a passagem de parado para soco fraco.
Os PCs/endereços de animação e de reconhecimento do soco **ainda não foram
confirmados**. O coletor separa descoberta de medição para não confundir uma
escrita qualquer com o início de uma animação. Funções de animação podem ser
compartilhadas entre parado e golpe: endereço/valor de estado e contexto do
personagem são necessários além do PC.

## Build de diagnóstico, feita pelo usuário

Na raiz `plusalpha-recomp`, crie um diretório separado:

```powershell
.\PlusAlphaProject\tools\build_online.ps1 -BuildDirName build-input-response -Jobs 2
```

Essa build inclui a porta TCP local 4531 e o protocolo `input_response` v1.
Não use a release: os hooks e os comandos são removidos com
`PSX_NO_DEBUG_TOOLS`. Os fontes já gerados podem ser reutilizados; se o CMake
indicar fingerprint de BIOS desatualizado, execute o mesmo comando com
`-Generate`. O agente não executa build.

Abra `PlusAlphaProject/build-input-response/exPlusAlpha.exe`, configure sua BIOS
e disco, escolha OpenGL e entre em VS offline com tempo infinito. Feche outras
instâncias antes da coleta para a porta não apontar para outro processo.
As builds e pastas de teste existentes são preservadas. Inicialmente mantenha
Ryu em P1 e o mesmo cenário, distância, resolução e VSync entre repetições.

## Primeira coleta: descobrir os marcadores

Confirme no jogo qual botão PS1 executa o soco fraco. O exemplo usa Square;
não assume que a tecla física do teclado seja a mesma coisa. Um binding que
também ativa R3 ou outro botão contaminará a captura. Use um binding único
ou o botão correspondente de um controle.

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Mode discovery -Button square
```

Roteiro:

1. Rode o script e volte imediatamente à janela do jogo.
2. Durante os **5 segundos de preparação**, deixe P1 parado, sem apertar nada.
3. Ao aviso `AGORA`/sinal do terminal, dê **um único toque curto** no soco fraco.
4. Solte e não faça mais nada até terminar a janela de **5 segundos**.

O script não envia teclas, não pausa e não altera settings. O relógio da captura
é interno ao runtime, não o tempo de resposta do TCP ou da automação. A mudança
de fase ocorre no limite de frame; o aviso do terminal é somente uma orientação.
Se perder o início, repita em outra pasta; nunca sobrescreva a coleta anterior.

Na descoberta, múltiplos toques do botão escolhido não tornam a aquisição uma
falha: o script avisa e a revisão considera somente o primeiro ciclo antes do
segundo toque, inclusive exigindo o retorno ao idle nesse intervalo. A medição
definitiva continua exigindo exatamente um toque. `valid_capture=true` significa
aquisição aproveitável; `valid_measurement=false` é esperado enquanto os marcadores
não forem confirmados, e não causa erro de saída no modo discovery.

Para reanalisar uma captura já salva sem tocar no jogo ou nos arquivos originais:

```powershell
python -B .\PlusAlphaProject\tools\capture_input_response.py --review 'caminho\capture.json'
```

Saída em `PlusAlphaProject/captures/input-response-AAAAmmdd-HHmmss`:

- `capture.json`: input observado e primeiras mudanças por endereço de RAM,
  com frame, QPC, ciclo emulado, PC produtor, largura e valores anterior/novo.
- `candidates.csv`: prioriza campos estáveis antes do input. `return_pc` e
  `return_frame` indicam a primeira restauração do valor anterior observada.
- `capture.sha256`: identidade dos dados usados posteriormente pelo perfil.
- `arm.json`: configuração/estado inicial do protocolo.

Na descoberta o hook resume escritas em uma tabela limitada, usando memória
somente enquanto armada e retendo os dados após terminar para exportação. Ela
**perturba mais a execução e não serve para calcular latência**. Overflow,
colisões além do limite, botão durante preparação e múltiplos toques são
declarados. Se houver overflow, estreitar a região `--lo/--hi` no script Python
após uma análise dos primeiros dados, sem tratar a captura parcial como prova.

Depois precisamos revisar `capture.json` e os PCs no código gerado/disassembly
para distinguir: buffer de pad/BIOS, reconhecimento do soco pelo jogo, estado do
P1, renderização e animação do oponente. Confirmar com outra coleta de parado,
uma repetição do soco fraco e outro ataque. Um campo estável que muda após o
botão é apenas candidato; não confirma sozinho uma animação.

## Medição após validar o perfil

`tools/input_response_profile.example.json` contém somente o esquema, sem
endereços inventados. Após a análise, preencher uma cópia com os endereços,
valores e PCs confirmados, `verified=true`, o caminho relativo de `capture.json`
e seu SHA-256. Anotar personagem/ação e os controles de validação em review_notes.

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Mode measure -Button square -Profile 'caminho\perfil-validado.json'
```

Esse modo observa só o input e os dois marcadores revisados; não varre RAM nem
faz IO de arquivo durante o intervalo medido. O resultado exige exatamente um
input, um reconhecimento e uma transição idle→ataque, em ordem, sem overflow,
sem botões extras e com estado inicial idle. Perfis ausentes ou ambiguidade
produzem `valid_measurement=false`, não um número estimado.

A régua começa no input do host entregue ao SIO, não no contato elétrico do
controle. Termina na escrita validada de estado de animação, não no primeiro
pixel exibido. Portanto não mede dispositivo, compositor, scanout nem monitor.
A captura é **somente offline**: no online o SIO já recebe o input após a fila
de delay; comparar esses marcadores como se incluíssem a fila seria incorreto.
Instrumentar a amostra do host antes dessa fila será uma etapa separada.

## Testes sem build

```powershell
python -B -m unittest discover -s PlusAlphaProject/tools/tests -p test_capture_input_response.py -v
```

Esses testes cobrem a análise dos eventos e a recusa de resultados incompletos,
ambíguos ou de descoberta. Não executam o runtime C nem validam os PCs do jogo.

## Medição pronta com a build de diagnóstico existente

Não precisa recompilar nem gerar novamente o jogo. O PowerShell agora usa
`measure` por padrão e carrega `tools/input_response_ryu_p1_square.json`.
Na raiz plusalpha-recomp:

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Button square
```

Use uma única instância da build de diagnóstico já utilizada, VS offline,
Ryu P1, parado no chão, sem levar golpes. Square deve executar soco fraco.
São 5 segundos de preparação sem input e 5 de coleta; dê apenas um toque
curto ao sinal e solte. Não use o perfil para outro personagem ou online.
Se precisar descobrir novos marcadores, informe `-Mode discovery` explicitamente.

O perfil verifica o SHA-256 da evidência original antes de armar. Preserve a
pasta da captura 151623 junto ao projeto. O arquivo original não é alterado.
A validação é restrita ao cenário descrito; controles com outro ataque ainda
não foram coletados. Resultado válido significa correspondência com esse perfil.

`latency_ms` mede SIO até seleção interna da animação. `latency_frames` é
a diferença entre índices de frames, não uma duração exata.
`elapsed_frame_equivalents` converte o tempo medido usando o FPS da coleta;
não representa quantos frames foram efetivamente exibidos. O modo measure
observa somente os marcadores, evitando a tabela ampla usada na descoberta.
Envie o novo capture.json para análise. Este procedimento não mede o atraso
físico do controle até o monitor nem o atraso adicional da fila do netplay.

## Vários inputs: somente coleta, análise posterior

Com a mesma build de diagnóstico, sem recompilar:

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Button square -CollectOnly
```

Mantenha Ryu P1 parado em VS offline. Aguarde 5 segundos sem input; na janela
de 5 segundos dê 4 a 5 toques curtos, aproximadamente um por segundo.
Solte entre os toques e espere o personagem voltar ao parado; não faça combos.
O último toque deve ocorrer com tempo para a resposta antes do fim da captura.

O runtime já registra cada input, cada reconhecimento no campo revisado e cada
transição parado→soco. Durante a janela Python apenas apresenta a contagem;
a exportação ocorre após parar. Não calcula pares, médias ou latências.
Salva capture.json, capture.sha256, arm.json e events.csv; não sobrescreve coletas.
A verificação final se limita à integridade (overflow, inputs extras etc.).
`valid_capture=true` não significa que todas as tentativas tiveram resposta.
`valid_measurement=false` com `deferred_offline_analysis` é esperado, sem erro.

Envie o caminho da pasta para análise posterior de cada tentativa, incluindo
tentativas sem resposta, ambíguas ou cortadas no final. A média, mediana,
mínimo, máximo e dispersão devem usar apenas pares causais aproveitáveis,
com os descartes explícitos. O runtime atual não registra retorno ao parado
neste modo: inputs sobrepostos não permitem atribuição segura e serão sinalizados.
O --review atual é de medição única e recusa este arquivo bruto para evitar
classificá-lo incorretamente como captura inválida. O escopo continua sendo
SIO→seleção interna da animação, não latência física até o monitor.


## Sequencia observacional offline (opcional, 20/10/2026)

Esta etapa adiciona observacao; nao otimiza o comportamento do jogo. Referencia
preservada: Alpha Plus 73c02fc, psxrecomp 875076d0 e recomp-ui 7dc5f6f.
Nao sobrescrever as builds existentes nem as capturas versionadas.

O agente nao executa compilacao. Para compilar manualmente na raiz do repositorio:

```powershell
.\PlusAlphaProject\tools\build_input_observation.ps1
```

O script usa dois jobs, diagnosticos habilitados e a pasta NOVA
`PlusAlphaProject/build-input-observation`. Tambem prepara overlays em uma
subpasta dessa build. Recusa uma pasta ja existente; para outra tentativa use
`-BuildDirName build-input-observation-2`. Reutiliza os fontes gerados atuais;
nao passa -Generate e nao troca BIOS, disco, saves ou settings. Aceita
-Msys2Root, -SdlBackend, -BiosPath e -RetainedOverlayDir, como o script existente.
O backend SDL padrao e SDL3: mantenha o mesmo backend da referencia ao comparar.
Se houver erro de fingerprint de BIOS, preserve as pastas e relate o erro antes
de regenerar fontes. A compilacao ainda precisa ser validada pelo usuario.

Abra `PlusAlphaProject/build-input-observation/exPlusAlpha.exe`. Feche outras
instancias para a porta 4531 apontar para esse executavel. Use OpenGL, VS offline,
Ryu P1 parado, Square para soco fraco, mesmas opcoes visuais da referencia.
A primeira investigacao requer apresentacao na thread de emulacao: render thread,
present thread e interpolacao/frame generation desligados. O coletor nao muda
essas opcoes: exporta os dados e sinaliza configuracoes de thread incompativeis.
A timeline exige SIO cycle-paced padrao e recusa PSX_SIO_PAD_SYNC_RX=1.
Nao altera ACKs, baud rate ou a ordem das rotinas.

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Button square -CollectOnly -Timing
```

Sao 5 segundos de preparacao e 5 segundos de captura, 4 a 5 toques separados
por aproximadamente 1 segundo, soltando e aguardando voltar ao parado. A build
antiga continua aceitando o comando SEM -Timing; com -Timing o Python verifica
a capacidade adicional antes de armar e recusa builds antigas. O protocolo
input_response v1 e seus eventos 1/2/3 permanecem separados da nova timeline.
Nenhum pareamento ou calculo de latencia e feito durante a janela.

Arquivos novos de cada coleta: capture.json contem `timeline`, `timing_schema`,
`timing_kinds` e o clock nominal de 33868800 Hz; timeline.csv contem os mesmos
registros brutos e nomes de eventos. events.csv conserva os marcadores v1.
O SHA-256 cobre o capture.json completo. Exportacao somente depois de parar.
A tabela de 65536 registros e alocada ao armar, sem IO/alocacao durante os eventos;
`timing_overflow` invalida a integridade e nunca e ignorado. Nao usar a timeline
mais detalhada como se tivesse o mesmo custo do probe minimo de referencia.

Campos comuns: `seq` e ordem de execucao da timeline, `qpc` usa `status.frequency`,
`cycle` e o contador observado de ciclos emulados, `frame` e o indice do host e
`vblank` e o contador de bordas levantadas. Nao assumir que frame e vblank sejam
identicos. `sample`, `transaction` e `callback` sao os IDs MAIS RECENTES de seus
inicios na janela, nao atribuicao causal automatica; zero significa que o inicio
nao foi observado. A janela pode cortar uma operacao no inicio/fim. Leituras e
escritas com o mesmo valor tambem sao registradas. O probe se desarma ao observar
netplay ativo; seus hooks nao escrevem no estado do guest.

| Evento | Interpretacao dos campos especificos |
| --- | --- |
| host_begin / host_end | aux=1 inicial, aux=2 tardio; inicio inicial inclui pump de eventos. No inicio inicial old=Fast Input efetivo, value=flags (1 present thread, 2 interpolacao, 4 render thread). |
| pad_delivery | old/value sao os botoes active-low anterior/entregue. O marcador v1 da primeira borda nao e reestampado e e registrado antes deste evento auxiliar. |
| pacer_begin / pacer_end | Entrada/retorno do limitador offline normal. Ausencia pode significar cadencia controlada pelo swap, nao espera zero. |
| host_present_begin / host_present_end | Chamada completa do callback do host, incluindo amostragem, limitador e apresentacao. Nao e somente o swap. |
| swap_begin / swap_end | Limites ja existentes do backend de apresentacao. Somente a thread de emulacao escreve na timeline; nao medem pixels no monitor. |
| vblank_edge | IRQ de VBlank levantada pelo agendador de ciclos. |
| irq_deliver | Entrega de IRQ a CPU: pc=ponto de retomada, old=I_STAT, value=I_MASK, aux=COP0 SR. Conferir bit 0: pode haver outras fontes pendentes. |
| callback_entry | Entrada observada em 0x801017F0. |
| buffer_read | Leitura byte efetiva em 0x1DCA48..0x1DCA4B, value=dado lido, pc=0, aux=ultimo bloco observado (fisico). Nao atribuir esse aux como PC exato da instrucao. O bloco 0x101850 contem a leitura conhecida 0x80101854. |
| buffer_write / game_write | Endereco, PC produtor, old/value e aux=largura. O hook de escrita existente observa imediatamente antes da gravacao; nao avanca ciclos. game_write inclui os dois campos do perfil, mesmo sem transicao. |
| sio_select / sio_deselect | Assercao/desasserção observada de SELECT na porta P1. Desasserção encerra ou aborta; nao prova sucesso. |
| sio_shift_begin / sio_rx_ready / sio_rx_read / sio_ack | old=TX, value=RX quando aplicavel, aux=contador de bytes do runtime, ctrl/stat/mode/baud=registradores observados. rx_ready ocorre depois do processamento do byte e de RX_RDY. RX_READ nao tem TX associado. |
| sio_snapshot | Estado escolhido pelo comando 0x42: old=ID, value=botoes active-low, aux=slot logico. O snapshot e registrado antes de montar os bytes da resposta. |

Para obter a conclusao, identificar uma transacao 0x01/0x42 que contem o botao,
separar RX_READY do ultimo byte necessario de SELECT desativado, encontrar a
escrita correspondente da BIOS e comparar com as leituras em callbacks adjacentes.
Relacionar com os pares pacer/swap e manter deltas QPC e ciclos lado a lado.
Nao converter a diferenca entre os dois relogios automaticamente em tempo de
espera. O baud observado nao implica que a implementacao derive o shifter dele:
o caminho atual usa constantes; esta etapa nao altera nem valida esse modelo.
As conclusoes seguem restritas a Ryu P1/soco fraco, offline, sem promessa de
reduzir abaixo de um frame. Preservar uma coleta sem -Timing na nova build e a
build estavel para avaliar a perturbacao introduzida pela observacao.


## Experimento A/B: limitador offline apos IRQ (opt-in)

Primeiro experimento de comportamento: apenas o limitador de frames e sua
reamostragem posterior mudam de lugar. A apresentacao, os comandos do frontend
(saves/diagnostico) e a amostragem inicial continuam no caminho existente.
Nao foi adiado o callback inteiro. O polling SIO e a ordem callback/BIOS do guest
permanecem intactos. O marco causal v1 continua na primeira borda entregue ao SIO.

O experimento vem DESLIGADO e so pode ser habilitado em builds com debug tools.
A variavel nao e salva no launcher/settings/game.toml. Netplay ativo impede o
adiamento, mesmo quando a variavel foi definida; uma sessao iniciada com netplay
configurado tambem desabilita a opcao. A build observacional anterior e a captura
200906 permanecem como referencia; nao recompilar por cima dela.

Compilacao MANUAL na raiz plusalpha-recomp (o agente nao executa build):

```powershell
.\PlusAlphaProject\tools\build_input_observation.ps1 -BuildDirName build-input-observation-pacer
```

O diretorio deve ser novo. Para retomar uma compilacao dessa mesma pasta:

```powershell
.\PlusAlphaProject\tools\build_online.ps1 -BuildDirName build-input-observation-pacer -StaticOverlayDir .\PlusAlphaProject\build-input-observation-pacer\static-overlays -Jobs 2
```

Primeiro rode a nova build com a ordem de referencia e faca uma coleta:

```powershell
$env:PSX_OFFLINE_POST_IRQ_PACER = '0'
.\PlusAlphaProject\build-input-observation-pacer\exPlusAlpha.exe
```

Feche o jogo e rode novamente, no mesmo PowerShell, com o experimento:

```powershell
$env:PSX_OFFLINE_POST_IRQ_PACER = '1'
.\PlusAlphaProject\build-input-observation-pacer\exPlusAlpha.exe
```

O log confirma que o experimento foi solicitado. Em AMBOS os casos, use outro
terminal para a coleta normal, com as mesmas configuracoes e cenario:

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Button square -CollectOnly -Timing
```

Depois dos testes, `$env:PSX_OFFLINE_POST_IRQ_PACER = '0'` retorna a referencia
nos proximos processos desse terminal. Nenhuma recompilacao e necessaria para A/B.

Quando elegivel: amostra inicial e apresentacao acontecem no VBlank; o limitador
fica pendente. O caminho de retorno do verificador de IRQ consome essa pendencia
somente fora do handler e sem troca de thread emulada pendente, depois da
restauracao arquitetural. Em seguida executa o mesmo frame_pacer_wait e uma
reamostragem do host. A pendencia e removida ANTES do callback, e limpa em resets
ja cobertos por gpu_vblank_clear_deferred_present; nao e estado de save/rollback.
Se a IRQ nao puder ser entregue, a saida do verificador permite uma espera de
fallback, sem deixar o jogo rodar sem limitador esperando uma IRQ mascarada.

O adiamento exige jogo iniciado, Fast Input ligado, janela normal, ausencia de
self-check/replay, render/present threads, interpolacao/frame generation,
resolucao dinamica, mouse local e menus de pause/rewind/save. Tambem nao arma
no handler, durante DMA/render pass ou com SIO de memory card em andamento.
Turbo e modos sem limitador continuam no fluxo existente. Configuracoes nao
elegiveis usam o comportamento original; nenhum setting e alterado para forcar
compatibilidade. Isso limita a abrangencia do experimento e nao prova seguranca
em todas as cenas: ainda e necessaria a validacao local de comandos e fluidez.

Eventos adicionais da timeline (timing_kinds inclui os nomes):

- 32 pacer_defer: espera transferida para uma saida segura do verificador de IRQ.
- 33 pacer_resume: value=1 se aquela chamada entregou VBlank; value=0 no fallback.
- pacer_begin/end: aux=1 no ponto adiado, aux=0 no ponto original.
- host_begin/end: aux=3 para amostragem apos a espera adiada; 1/2 mantem os
  significados anteriores. A fase 3 e posterior ao polling da BIOS daquele IRQ.

Zero eventos pacer_defer significa que o experimento nao foi aplicado naquela
janela. Nao interpretar isso como teste bem-sucedido da nova ordem. Confirmar
pacer_defer -> atendimento/retorno -> pacer_resume -> pacer_begin/end, e apenas
uma espera por frame elegivel, sem overflow, saltos de relogio ou perda de toques.
A janela pode cortar o primeiro/ultimo par, como na instrumentacao anterior.

A mudanca de fase da amostragem pode beneficiar certos toques e atrasar outros:
a amostra apos a espera ja nao participa do polling da BIOS que acabou. Comparar
origens 1/2/3 e ambos os relogios; nao apresentar uma reducao da media isolada
como melhoria ponta a ponta. Fazer primeiro os toques separados; depois conferir
toques curtos, direcoes, diagonais, comandos e fluidez. Tentativas sem resposta
precisam constar da analise. Nao ha promessa de remover o frame entre BIOS e jogo
nem de reduzir a latencia fisica ate pixels. Estatisticas do profiler de frontend
que encerram antes desse retorno nao incluem necessariamente a espera deslocada;
usar pacer_begin/end da timeline para esta comparacao.


## Segundo experimento: espera no fim do frame (modo 2)

O modo 1 NAO foi aprovado como otimizacao. A captura 205519 mostrou que ele
colocava a espera entre reconhecimento e animacao e que a amostra de origem 3,
posterior ao polling, podia adicionar um ciclo de leitura. Preservar essa build
e captura como evidencia; usar modo 0 para referencia e modo 2 no novo teste.

Nova compilacao manual em pasta separada:

```powershell
.\PlusAlphaProject\tools\build_input_observation.ps1 -BuildDirName build-input-observation-frame-end
```

Retomada incremental, se essa compilacao precisar continuar:

```powershell
.\PlusAlphaProject\tools\build_online.ps1 -BuildDirName build-input-observation-frame-end -StaticOverlayDir .\PlusAlphaProject\build-input-observation-frame-end\static-overlays -Jobs 2
```

Abrir com o novo modo (0=referencia, 1=experimento anterior, 2=fim do frame):

```powershell
$env:PSX_OFFLINE_POST_IRQ_PACER = '2'
.\PlusAlphaProject\build-input-observation-frame-end\exPlusAlpha.exe
```

Em outro terminal, manter o mesmo cenario Ryu P1/Square, VS offline:

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Button square -CollectOnly -Timing
```

Para comparar na MESMA build, fechar o jogo, definir a variavel como '0',
reabrir e coletar em nova pasta. Nao reutilizar o comando com valor '1' para
validar a nova politica. O log identifica explicitamente mode 2 (frame end).
Nenhuma build e executada pelo agente.

No modo 2, a pendencia continua armada apos o retorno da IRQ. Ela so pode ser
consumida numa saida segura do verificador quando faltar no maximo uma linha
emulada para o proximo VBlank (g_psx_hblank_cycles). A escolha e pela fase do
relogio emulado, nao por ler ou modificar a animacao do personagem. Nao se
saltam ciclos, nao se reordenam handlers e nao se alteram dados da BIOS.
No cenario ja observado, o reconhecimento e a selecao da animacao ocorrem bem
antes dessa janela; confirmar isso novamente pela captura, sem generalizar
para outros personagens/acoes.

O idle skip pode atravessar a janela inteira sem um novo retorno do verificador.
Nesse caso, a GPU consome a pendencia na entrada do proximo callback offline,
antes da apresentacao/amostragem inicial e antes do atendimento da nova IRQ.
Isso preserva o caminho de polling; nao esperar ate terminar o polling seguinte.
Se esse VBlank ocorrer em handler ou frontend reentrante, cancelar a pendencia
antiga e usar o caminho original da cena nao suportada. O cancelamento e
registrado, o coletor sinaliza a captura e ainda preserva os eventos exportados.
Nao acumular esperas antigas nem executar uma espera extra dentro do handler.
Os gates offline/self-check/threads/menus/DMA do experimento anterior continuam.

Amostras no novo modo:

- Origem 1: amostra inicial normal, preservada.
- Origem 5: nova observacao/entrega ANTES da espera de fim do frame. Se o botao
  ja mudou, o marco v1 comeca aqui e inclui a espera subsequente.
- Origem 4: reamostra depois da espera, antes do polling que ainda vai ocorrer.
  Um botao ja entregue na origem 5 nao reinicia o marco inicial.
- Origem 2: caminho original em frames nao elegiveis; origem 3 pertence ao modo 1.

Nao interpretar uma reducao de tempo medida apenas na origem 4 como ganho
fisico: a captura continua sem observar o contato do botao. Comparar todas as
origens, tentativas sem resposta e dispersao. A variacao de fase natural de um
poll periodico ainda existe; este experimento tenta remover a espera inserida
entre reconhecimento e animacao e o ciclo extra da origem 3, sem prometer
latencia fixa ou abaixo de um frame.

Metadados novos/estendidos:

- pacer_defer: value=2 identifica o novo modo; value=1 identifica o antigo.
- pacer_resume: aux=modo; old=ciclos restantes ate VBlank; value=0 saida comum,
  1 retorno de IRQ ou 2 entrada do proximo VBlank apos cruzar a janela.
- pacer_begin/end: aux=2 para a espera do novo modo, 1 para o antigo e 0 original.
- Evento 34 pacer_cancel: pendencia cancelada por contexto nao suportado.
  O resultado nao e classificado como captura limpa do experimento.

Verificar na nova coleta: ausencia de espera entre os marcadores revisados de
reconhecimento/animacao, amostras 4/5 antes do poll correspondente, uma espera
por frame elegivel, nenhuma origem 3 no modo 2, nenhum overflow/cancelamento e
nenhuma tentativa perdida. Conferir FPS, min/max/mediana e consistencia antes
de adotar qualquer mudanca. A nova politica ainda precisa de compilacao e
validacao local; testes Python nao executam os caminhos C/C++ nem comprovam
preservacao de comandos ou melhora visual.

## Experimento 3: espera em um quarto do frame emulado

Opt-in de diagnostico: `PSX_OFFLINE_POST_IRQ_PACER=3`. O modo 0 continua como
referencia; os modos 1 e 2 conservam suas politicas. Nao habilitado por padrao,
nao persistido no launcher e desabilitado quando a configuracao online esta
ativa. Os gates de threads, interpolacao, self-check, menus e contexto seguro
continuam os mesmos. O agente nao executa build.

O modo 3 adia somente a espera do limitador ate o primeiro retorno seguro do
verificador de interrupcoes em que tenham passado pelo menos 1/4 dos ciclos
do periodo de video corrente. Em NTSC: 141120 ciclos depois do VBlank, com
no maximo 423360 ciclos restantes ate a proxima borda. E uma fase emulada,
nao uma espera real fixa de 4,167 ms e nao um gatilho nos enderecos do Ryu.
A granularidade dos blocos/idle skip pode fazer o retorno ocorrer mais tarde.
O trace `pacer_resume.old` permite conferir a fase realmente atingida.

Se um idle skip atravessar essa fase sem retorno seguro, a pendencia pode ser
consumida antes do proximo callback offline (`pacer_resume.value=2`). Separar
esses casos da execucao na fase pretendida. Se nem essa borda for segura, a
pendencia e cancelada e o callback usa o caminho original; o evento 34 marca
que a coleta nao foi uma execucao limpa do experimento. Nao acumular esperas.

O experimento nao salta ciclos, nao muda o polling/baud/ACKs da SIO, nao
reordena os handlers e nao escreve no buffer da BIOS. A apresentacao permanece
no ponto existente; somente o limitador e suas amostragens experimentais mudam
de fase. Nao assumir que a animacao sempre termine antes da espera: isso e um
dos pontos a verificar, inicialmente apenas para Ryu P1/Square parado.

Origens das amostras no modo 3:

- 1: amostragem inicial normal, preservada.
- 6: amostragem/entrega antes da espera de quarto de frame.
- 7: amostragem/entrega depois dessa espera.
- 2: caminho original em frames nao elegiveis.

A primeira borda entregue ao SIO continua iniciando o evento v1. Uma borda
detectada na origem 6 inclui a espera seguinte; a origem 7 nao reinicia esse
timestamp. Nao ha mudanca no protocolo input_response v1 nem no schema da
timeline. `pacer_defer.value=3` e `pacer_resume.aux=3` identificam o modo;
`pacer_begin/end.aux=3` identifica sua espera. Origens 3/4/5 pertencem aos
experimentos anteriores, nao as amostras do modo 3.

### Compilar manualmente em outra pasta

Na raiz `F:\GitRevised\alphaplus\plusalpha-recomp`:

```powershell
.\PlusAlphaProject\tools\build_input_observation.ps1 -BuildDirName build-input-observation-quarter-frame -Jobs 2
```

Preservar a pasta/build frame-end e todos os checkpoints anteriores. O wrapper
recusa pasta ja existente. Se precisar recompilar incrementalmente a NOVA pasta:

```powershell
.\PlusAlphaProject\tools\build_online.ps1 -BuildDirName build-input-observation-quarter-frame -StaticOverlayDir .\PlusAlphaProject\build-input-observation-quarter-frame\static-overlays -Jobs 2
```

### Comparacao na mesma build: 0, 3, 3, 0

Usar quatro execucoes, fechando e reabrindo o jogo entre elas. A ordem evita
confundir uma mudanca progressiva de carga do PC com o modo experimental.
Manter a captura continua de VRAM desligada nos quatro casos; manter tambem
as mesmas configuracoes de video, resolucao e janela. Uma instancia por vez,
VS offline, Fast Input ativo, sem threads de render/present nem interpolacao.
O launcher pode nao expor esses controles; conferir os flags da timeline.

No terminal do jogo, preparar as variaveis (valem so para este terminal):

```powershell
$env:PSX_DISPLAY_RING = '0'
$exe = '.\PlusAlphaProject\build-input-observation-quarter-frame\exPlusAlpha.exe'
```

Executar CADA bloco abaixo separadamente. Com o jogo aberto, chegar ao mesmo
cenario Ryu P1 parado, Square/soco fraco. Em OUTRO terminal, executar o coletor
correspondente. Aguardar o fim da exportacao antes de fechar o jogo.

```powershell
# A1: referencia na nova build
$env:PSX_OFFLINE_POST_IRQ_PACER = '0'
& $exe
```

```powershell
# B1: experimento (fechar A1 antes)
$env:PSX_OFFLINE_POST_IRQ_PACER = '3'
& $exe
```

```powershell
# B2: repetir o experimento, em outra execucao
$env:PSX_OFFLINE_POST_IRQ_PACER = '3'
& $exe
```

```powershell
# A2: repetir a referencia, em outra execucao
$env:PSX_OFFLINE_POST_IRQ_PACER = '0'
& $exe
```

Coletor no outro terminal, uma vez por execucao; cada coleta cria sua pasta:

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Button square -CollectOnly -Timing
```

Sao 5 segundos de preparacao sem pressionar botoes, depois 5 segundos para
toques separados em Square por aproximadamente 1 segundo. Guardar a associacao
A1/B1/B2/A2 com as quatro pastas. Nao testar comandos extras durante a captura.
No modo 3, o log de abertura deve informar `mode 3 (quarter frame)`; confirmar
tambem os eventos de defer/resume, pois caminhos nao elegiveis usam modo 0.

Fora da janela de coleta, comparar tambem a sensacao dos comandos habituais
nos dois modos: movimentos, defesa, ataques e combinacoes ja conhecidas pelo
jogador. Observar atrasos, comandos perdidos e fluidez. Isso e uma verificacao
manual complementar: o perfil numerico continua restrito a Ryu P1/Square.

Na analise: conferir integridade, respostas completas, FPS, media/mediana,
min/max e dispersao; separar por origem da primeira entrega e contar esperas
ate processamento e entre processamento/animacao. Conferir a fase do resume
e quantos casos foram drenados somente no proximo VBlank. Uma media menor por
ter mais amostras tardias nao basta. Nao prometer resultado abaixo de um frame
nem tratar SIO->animacao como botao fisico->pixels.

Ao terminar, retornar `PSX_OFFLINE_POST_IRQ_PACER=0`. Para restaurar a captura
continua de VRAM em uma proxima execucao, usar `PSX_DISPLAY_RING=1` antes de
abrir o jogo. As variaveis sao lidas no processo; alterar com o jogo aberto
nao troca o modo daquela execucao.
