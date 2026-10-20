# Captura causal da resposta ao input

Objetivo: identificar e depois medir a passagem de parado para soco fraco.
Os PCs/endereÃƒÂ§os de animaÃƒÂ§ÃƒÂ£o e de reconhecimento do soco **ainda nÃƒÂ£o foram
confirmados**. O coletor separa descoberta de mediÃƒÂ§ÃƒÂ£o para nÃƒÂ£o confundir uma
escrita qualquer com o inÃƒÂ­cio de uma animaÃƒÂ§ÃƒÂ£o. FunÃƒÂ§ÃƒÂµes de animaÃƒÂ§ÃƒÂ£o podem ser
compartilhadas entre parado e golpe: endereÃƒÂ§o/valor de estado e contexto do
personagem sÃƒÂ£o necessÃƒÂ¡rios alÃƒÂ©m do PC.

## Build de diagnÃƒÂ³stico, feita pelo usuÃƒÂ¡rio

Na raiz `plusalpha-recomp`, crie um diretÃƒÂ³rio separado:

```powershell
.\PlusAlphaProject\tools\build_online.ps1 -BuildDirName build-input-response -Jobs 2
```

Essa build inclui a porta TCP local 4531 e o protocolo `input_response` v1.
NÃƒÂ£o use a release: os hooks e os comandos sÃƒÂ£o removidos com
`PSX_NO_DEBUG_TOOLS`. Os fontes jÃƒÂ¡ gerados podem ser reutilizados; se o CMake
indicar fingerprint de BIOS desatualizado, execute o mesmo comando com
`-Generate`. O agente nÃƒÂ£o executa build.

Abra `PlusAlphaProject/build-input-response/exPlusAlpha.exe`, configure sua BIOS
e disco, escolha OpenGL e entre em VS offline com tempo infinito. Feche outras
instÃƒÂ¢ncias antes da coleta para a porta nÃƒÂ£o apontar para outro processo.
As builds e pastas de teste existentes sÃƒÂ£o preservadas. Inicialmente mantenha
Ryu em P1 e o mesmo cenÃƒÂ¡rio, distÃƒÂ¢ncia, resoluÃƒÂ§ÃƒÂ£o e VSync entre repetiÃƒÂ§ÃƒÂµes.

## Primeira coleta: descobrir os marcadores

Confirme no jogo qual botÃƒÂ£o PS1 executa o soco fraco. O exemplo usa Square;
nÃƒÂ£o assume que a tecla fÃƒÂ­sica do teclado seja a mesma coisa. Um binding que
tambÃƒÂ©m ativa R3 ou outro botÃƒÂ£o contaminarÃƒÂ¡ a captura. Use um binding ÃƒÂºnico
ou o botÃƒÂ£o correspondente de um controle.

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Mode discovery -Button square
```

Roteiro:

1. Rode o script e volte imediatamente ÃƒÂ  janela do jogo.
2. Durante os **5 segundos de preparaÃƒÂ§ÃƒÂ£o**, deixe P1 parado, sem apertar nada.
3. Ao aviso `AGORA`/sinal do terminal, dÃƒÂª **um ÃƒÂºnico toque curto** no soco fraco.
4. Solte e nÃƒÂ£o faÃƒÂ§a mais nada atÃƒÂ© terminar a janela de **5 segundos**.

O script nÃƒÂ£o envia teclas, nÃƒÂ£o pausa e nÃƒÂ£o altera settings. O relÃƒÂ³gio da captura
ÃƒÂ© interno ao runtime, nÃƒÂ£o o tempo de resposta do TCP ou da automaÃƒÂ§ÃƒÂ£o. A mudanÃƒÂ§a
de fase ocorre no limite de frame; o aviso do terminal ÃƒÂ© somente uma orientaÃƒÂ§ÃƒÂ£o.
Se perder o inÃƒÂ­cio, repita em outra pasta; nunca sobrescreva a coleta anterior.

Na descoberta, mÃƒÂºltiplos toques do botÃƒÂ£o escolhido nÃƒÂ£o tornam a aquisiÃƒÂ§ÃƒÂ£o uma
falha: o script avisa e a revisÃƒÂ£o considera somente o primeiro ciclo antes do
segundo toque, inclusive exigindo o retorno ao idle nesse intervalo. A mediÃƒÂ§ÃƒÂ£o
definitiva continua exigindo exatamente um toque. `valid_capture=true` significa
aquisiÃƒÂ§ÃƒÂ£o aproveitÃƒÂ¡vel; `valid_measurement=false` ÃƒÂ© esperado enquanto os marcadores
nÃƒÂ£o forem confirmados, e nÃƒÂ£o causa erro de saÃƒÂ­da no modo discovery.

Para reanalisar uma captura jÃƒÂ¡ salva sem tocar no jogo ou nos arquivos originais:

```powershell
python -B .\PlusAlphaProject\tools\capture_input_response.py --review 'caminho\capture.json'
```

SaÃƒÂ­da em `PlusAlphaProject/captures/input-response-AAAAmmdd-HHmmss`:

- `capture.json`: input observado e primeiras mudanÃƒÂ§as por endereÃƒÂ§o de RAM,
  com frame, QPC, ciclo emulado, PC produtor, largura e valores anterior/novo.
- `candidates.csv`: prioriza campos estÃƒÂ¡veis antes do input. `return_pc` e
  `return_frame` indicam a primeira restauraÃƒÂ§ÃƒÂ£o do valor anterior observada.
- `capture.sha256`: identidade dos dados usados posteriormente pelo perfil.
- `arm.json`: configuraÃƒÂ§ÃƒÂ£o/estado inicial do protocolo.

Na descoberta o hook resume escritas em uma tabela limitada, usando memÃƒÂ³ria
somente enquanto armada e retendo os dados apÃƒÂ³s terminar para exportaÃƒÂ§ÃƒÂ£o. Ela
**perturba mais a execuÃƒÂ§ÃƒÂ£o e nÃƒÂ£o serve para calcular latÃƒÂªncia**. Overflow,
colisÃƒÂµes alÃƒÂ©m do limite, botÃƒÂ£o durante preparaÃƒÂ§ÃƒÂ£o e mÃƒÂºltiplos toques sÃƒÂ£o
declarados. Se houver overflow, estreitar a regiÃƒÂ£o `--lo/--hi` no script Python
apÃƒÂ³s uma anÃƒÂ¡lise dos primeiros dados, sem tratar a captura parcial como prova.

Depois precisamos revisar `capture.json` e os PCs no cÃƒÂ³digo gerado/disassembly
para distinguir: buffer de pad/BIOS, reconhecimento do soco pelo jogo, estado do
P1, renderizaÃƒÂ§ÃƒÂ£o e animaÃƒÂ§ÃƒÂ£o do oponente. Confirmar com outra coleta de parado,
uma repetiÃƒÂ§ÃƒÂ£o do soco fraco e outro ataque. Um campo estÃƒÂ¡vel que muda apÃƒÂ³s o
botÃƒÂ£o ÃƒÂ© apenas candidato; nÃƒÂ£o confirma sozinho uma animaÃƒÂ§ÃƒÂ£o.

## MediÃƒÂ§ÃƒÂ£o apÃƒÂ³s validar o perfil

`tools/input_response_profile.example.json` contÃƒÂ©m somente o esquema, sem
endereÃƒÂ§os inventados. ApÃƒÂ³s a anÃƒÂ¡lise, preencher uma cÃƒÂ³pia com os endereÃƒÂ§os,
valores e PCs confirmados, `verified=true`, o caminho relativo de `capture.json`
e seu SHA-256. Anotar personagem/aÃƒÂ§ÃƒÂ£o e os controles de validaÃƒÂ§ÃƒÂ£o em review_notes.

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Mode measure -Button square -Profile 'caminho\perfil-validado.json'
```

Esse modo observa sÃƒÂ³ o input e os dois marcadores revisados; nÃƒÂ£o varre RAM nem
faz IO de arquivo durante o intervalo medido. O resultado exige exatamente um
input, um reconhecimento e uma transiÃƒÂ§ÃƒÂ£o idleÃ¢â€ â€™ataque, em ordem, sem overflow,
sem botÃƒÂµes extras e com estado inicial idle. Perfis ausentes ou ambiguidade
produzem `valid_measurement=false`, nÃƒÂ£o um nÃƒÂºmero estimado.

A rÃƒÂ©gua comeÃƒÂ§a no input do host entregue ao SIO, nÃƒÂ£o no contato elÃƒÂ©trico do
controle. Termina na escrita validada de estado de animaÃƒÂ§ÃƒÂ£o, nÃƒÂ£o no primeiro
pixel exibido. Portanto nÃƒÂ£o mede dispositivo, compositor, scanout nem monitor.
A captura ÃƒÂ© **somente offline**: no online o SIO jÃƒÂ¡ recebe o input apÃƒÂ³s a fila
de delay; comparar esses marcadores como se incluÃƒÂ­ssem a fila seria incorreto.
Instrumentar a amostra do host antes dessa fila serÃƒÂ¡ uma etapa separada.

## Testes sem build

```powershell
python -B -m unittest discover -s PlusAlphaProject/tools/tests -p test_capture_input_response.py -v
```

Esses testes cobrem a anÃƒÂ¡lise dos eventos e a recusa de resultados incompletos,
ambÃƒÂ­guos ou de descoberta. NÃƒÂ£o executam o runtime C nem validam os PCs do jogo.

## MediÃ§Ã£o pronta com a build de diagnÃ³stico existente

NÃ£o precisa recompilar nem gerar novamente o jogo. O PowerShell agora usa
`measure` por padrÃ£o e carrega `tools/input_response_ryu_p1_square.json`.
Na raiz plusalpha-recomp:

```powershell
.\PlusAlphaProject\tools\capture_input_response.ps1 -Button square
```

Use uma Ãºnica instÃ¢ncia da build de diagnÃ³stico jÃ¡ utilizada, VS offline,
Ryu P1, parado no chÃ£o, sem levar golpes. Square deve executar soco fraco.
SÃ£o 5 segundos de preparaÃ§Ã£o sem input e 5 de coleta; dÃª apenas um toque
curto ao sinal e solte. NÃ£o use o perfil para outro personagem ou online.
Se precisar descobrir novos marcadores, informe `-Mode discovery` explicitamente.

O perfil verifica o SHA-256 da evidÃªncia original antes de armar. Preserve a
pasta da captura 151623 junto ao projeto. O arquivo original nÃ£o Ã© alterado.
A validaÃ§Ã£o Ã© restrita ao cenÃ¡rio descrito; controles com outro ataque ainda
nÃ£o foram coletados. Resultado vÃ¡lido significa correspondÃªncia com esse perfil.

`latency_ms` mede SIO atÃ© seleÃ§Ã£o interna da animaÃ§Ã£o. `latency_frames` Ã©
a diferenÃ§a entre Ã­ndices de frames, nÃ£o uma duraÃ§Ã£o exata.
`elapsed_frame_equivalents` converte o tempo medido usando o FPS da coleta;
nÃ£o representa quantos frames foram efetivamente exibidos. O modo measure
observa somente os marcadores, evitando a tabela ampla usada na descoberta.
Envie o novo capture.json para anÃ¡lise. Este procedimento nÃ£o mede o atraso
fÃ­sico do controle atÃ© o monitor nem o atraso adicional da fila do netplay.

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
