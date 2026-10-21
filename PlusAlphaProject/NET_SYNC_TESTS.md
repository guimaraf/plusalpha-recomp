# Testes de repetibilidade do sincronismo

## Posicionar as duas janelas sem arrastar — sem nova build

Depois de entrar no versus, execute uma vez, antes de iniciar a coleta:

```powershell
Set-Location F:\GitRevised\alphaplus\plusalpha-recomp
.\PlusAlphaProject\tools\position_netplay_windows.ps1
```

O script localiza as janelas pelas pastas dos EXEs. Diag1 fica à esquerda,
Diag2 à direita, independentemente de qual criou a sala. As bordas visíveis
encostam no centro horizontal da área útil do monitor principal; cada janela
fica centralizada verticalmente. Não há movimento manual nem mudança de
configuração. Por padrão, mantém o tamanho atual e não muda foco/ordem das
janelas. A posição é aplicada às janelas existentes, não salva para a próxima
abertura. Execute novamente após criar outra janela de jogo ou reabrir os EXEs.

Se as janelas forem grandes demais para caber, o script informa isso antes
de mover qualquer uma. Para permitir redução proporcional somente se preciso:

```powershell
.\PlusAlphaProject\tools\position_netplay_windows.ps1 -Fit
```

`-Swap` inverte os lados. `-Monitor 1` usa outro monitor (0 é o principal).
`-DryRun` apenas mostra o plano. Pastas diferentes podem ser indicadas com
`-FirstDir` e `-SecondDir`. O script requer uma janela normal visível por EXE;
não alterna fullscreen, não restaura janelas minimizadas/maximizadas, não
encerra processos, não inicia build nem altera arquivos do jogo. Se houver
instâncias duplicadas ou janelas auxiliares sem identificação única, recusa
o posicionamento. As bordas invisíveis do Windows são compensadas pelo DWM.

Aguarde cinco segundos após o posicionamento antes da captura. Isso permite
separar o ajuste inicial de qualquer interrupção deliberada durante o teste.
Use o script após entrar no jogo: posicionar apenas o launcher não garante a
posição da janela de jogo criada depois dele. O teste real das chamadas Win32
nas janelas do jogo fica para execução do usuário; os cálculos são testados
sem movimentar janelas durante a preparação.

## Teste curto automático de arrasto — sem nova build

Para testar somente a interrupção e a recuperação, use a build atual. Se os
jogos já estiverem abertos pelo script com histórico ativo, vá direto ao
comando do teste. Caso contrário, feche as instâncias antigas e abra assim:

```powershell
Set-Location F:\GitRevised\alphaplus\plusalpha-recomp
.\PlusAlphaProject\tools\capture_net_sync.ps1 -Launch -LaunchOnly
```

Crie a sala por IP direto, entre no versus com tempo infinito e coloque as
janelas lado a lado. Faça isso antes do trecho medido. O script curto não
inicia nem muda salas, configurações ou janelas. Encerre outro coletor que
estiver usando as mesmas portas antes de começar, mantendo os jogos abertos.

```powershell
.\PlusAlphaProject\tools\test_net_sync_drag.ps1 -Target Both
```

Ele verifica os papéis reais pelas duas portas, mostra qual é host/cliente,
monitora ambos continuamente e grava marcadores automáticos com avisos sonoros.
Volte ao jogo ao iniciar; não precisa voltar ao PowerShell entre etapas.
Deixe o console visível para acompanhar o texto; o som apenas sinaliza a troca.

| Etapa | Duração | Ação |
| --- | ---: | --- |
| Referência host | 10 s | Não arrastar nem jogar; voltar ao jogo e estabilizar. |
| Arrasto host | 15 s | Arrastar somente a janela identificada como host. |
| Recuperação host | 20 s | Soltar e deixar ambas paradas. |
| Referência cliente | 10 s | Ambas paradas. |
| Arrasto cliente | 15 s | Arrastar somente a janela identificada como cliente. |
| Recuperação cliente | 20 s | Soltar e deixar ambas paradas. |

Total das etapas: **90 segundos**, mais a preparação/finalização da coleta.
Mova pela barra de título, sem redimensionar ou minimizar. Pode segurar e
movimentar durante o intervalo ou fazer vários arrastos, mas apenas na janela
indicada. Ao sinal de recuperação, solte mesmo se as imagens estiverem atrasadas.
Os avisos definem os intervalos solicitados; não detectam fisicamente o mouse
ou o instante exato em que você começou a movimentar. Não execute o menu de
marcadores durante esse teste: as marcas já são automáticas.

Para inverter a ordem: `-Target Both -Order ClientFirst`. Para arrastar por
10 segundos: `-DragSeconds 10`. Para testar só um lado (45 segundos):

```powershell
.\PlusAlphaProject\tools\test_net_sync_drag.ps1 -Target Host
.\PlusAlphaProject\tools\test_net_sync_drag.ps1 -Target Client
```

Execute esses dois comandos em momentos separados. No modo Both, o cliente
pode herdar atraso do teste do host; o trecho de referência registra isso.
Para comparação independente, use sessões recém-abertas e confirme o mesmo
estado inicial antes de cada comando. Não tente remover atraso mudando delay.

O teste curto descarta intencionalmente o histórico anterior ao seu início
e registra essa posição em `trace_start`; não apaga o ring do jogo. As perdas
anteriores do ring não invalidam esse teste, mas qualquer perda ocorrida
durante a nova coleta precisa ser investigada. As portas são lidas por dois
workers; respostas podem atrasar se o processo ficar preso durante o arrasto,
e o ring permite buscar os eventos após a retomada.

Saída: uma nova pasta `captures/net-sync-drag-both-DATA-HORA` (ou host/client),
com papéis verificados no manifesto, os dois históricos, marcas e resumo.
Preserve a pasta e mantenha os jogos abertos para análise. Verificaremos a fase
antes/depois, delay, dívida de correção e hashes reportados. Um pico durante o
arrasto é esperado como hipótese de interrupção; atraso persistente depois de
soltar é o resultado principal a investigar. Mesmo PC e arrasto são testes de
recuperação local e não substituem validação em dois PCs pela internet.

Use a build de diagnóstico já compilada e copiada para `onlineDiag1`/`onlineDiag2`.
Estas mudanças são scripts e documentação: **não exigem nova build**.
Não altere delay, previsão, VSync, resolução, áudio, personagens ou dispositivos
entre as repetições iniciais. Mantenha o ajuste automático habitual. Nenhum
script injeta comandos, altera configurações, pausa ou encerra o jogo.

## Como abrir a captura

Feche manualmente as duas instâncias anteriores. Em um PowerShell:

```powershell
Set-Location F:\GitRevised\alphaplus\plusalpha-recomp
.\PlusAlphaProject\tools\capture_net_sync.ps1 -Launch -Label T01-A -Seconds 600
```

Espere a mensagem de captura ativa **nas duas portas** antes de criar a sala.
A porta 4531 continua ligada à pasta `onlineDiag1`; a 4532, à `onlineDiag2`.
O papel de host depende de quem cria a sala, não da porta. Abra por IP direto,
versus, tempo infinito. Anote os personagens e o controle usado em cada lado.
Quando terminar as etapas, encerre a coleta com Ctrl+C, sem fechar os jogos,
ou aguarde o limite de tempo. Avise que os testes estão prontos para análise.

Em **outro PowerShell**, durante a coleta:

```powershell
Set-Location F:\GitRevised\alphaplus\plusalpha-recomp
.\PlusAlphaProject\tools\mark_net_sync.ps1
```

O marcador encontra a captura em andamento mais recente e mostra sua pasta.
Confira a pasta; se houver mais de uma captura, indique `-CaptureDir` explicitamente.
Escolha uma opção, escreva uma observação e volte ao jogo. Ao terminar a etapa,
volte ao PowerShell e pressione ENTER para registrar o fim. A opção 9 marca
um sintoma com texto livre: quem atrasou, áudio, golpe, duração aproximada.

A troca para o PowerShell muda o foco; deixe cinco segundos de margem ao voltar
ao jogo antes de executar a ação. Não atribua um pico exatamente na marca ao
combo ou ao arrasto sem considerar essa troca. As marcas delimitam uma janela
humana; não são o instante exato em que um botão ou arrasto foi detectado.

Também é possível marcar um ponto sem usar o menu, por exemplo:

```powershell
.\PlusAlphaProject\tools\mark_net_sync.ps1 -Label symptom -Note 'Cliente parece dois frames atrasado'
```

## Ordem dos testes

Faça os blocos em capturas separadas. Se ocorrer KO, transição de round ou
mudança de personagem, registre na observação. Não tente compensar um problema
mudando o delay; preserve o comportamento para investigação.

| Teste | Como executar | O que verifica |
| --- | --- | --- |
| T01 — partida após abrir processos | Crie a sala em `onlineDiag1`. Marque sessão e, na luta, marque parado por 60 s, depois P1 por 30 s e P2 por 30 s. Não arraste janelas. | Se a sessão já nasce defasada, sem estado de outra partida. |
| T02 — inverter o host | Feche ambos manualmente. Nova captura com `-Label T02-A`; `onlineDiag2` cria a sala. Repita o T01. | Se o problema acompanha o papel de host ou a pasta/processo. |
| T03 — inverter abertura | Feche ambos. Nova captura com `-Label T03-A -OpenOrder SecondThenFirst`; `onlineDiag1` cria a sala. Repita o T01. | Se a ordem de inicialização influencia o resultado. |
| T04 — salas consecutivas | Abra processos novos com `-Label T04-A -Seconds 600`. Faça três salas sem fechar os EXEs nem reiniciar a coleta. Sala 1: host em Diag1; sala 2: host em Diag2; sala 3: host em Diag1. Em cada luta: 45 s parado, 30 s de combate. Saia de ambos ao lobby antes de criar a próxima. | Estado residual do controlador, delay e pacer entre sessões. |
| T05 — combate | Processos novos, `-Label T05-A -Seconds 900`. Marque e faça as etapas de combate descritas abaixo, sem arrastar janelas. | Sincronismo com entradas variadas, animações, acertos, defesa e transições. |
| T06 — interrupções | Processos novos, `-Label T06-A -Seconds 600`. Use o procedimento de arrasto abaixo, sem misturar combos. | Resposta e recuperação de uma pausa local controlada. |

T01/T02/T03 precisam de **três repetições cada**, com processos novos em cada
repetição: use rótulos `T01-A`, `T01-B`, `T01-C`, e assim por diante. Isso é
uma investigação inicial de repetibilidade, não uma garantia estatística de
release. Execute primeiro T01-A; podemos analisar essa primeira captura antes
de você investir tempo em toda a matriz. Não é necessário realizar tudo de uma vez.

Exemplo de abertura invertida:

```powershell
.\PlusAlphaProject\tools\capture_net_sync.ps1 -Launch -Label T03-A -OpenOrder SecondThenFirst -Seconds 600
```

O script muda apenas a ordem em que abre as duas cópias. Não cria a sala nem
escolhe o host automaticamente. Não reinicie EXEs durante a mesma captura:
isso reinicia a sequência do histórico e exige uma captura nova. Recriar
salas mantendo os mesmos EXEs é permitido e é justamente o objetivo de T04.

## T05 — combos, especiais e efeitos

Sim, jogue. Faça cada etapa marcada separadamente, sem macros ou input injetado:

1. **Parado — 60 s:** observe se as telas já estão alinhadas e se a música
   mantém o mesmo andamento. Isso fornece a referência antes do combate.
2. **Combos P1 — 90 s:** normais fracos/fortes, sequências rápidas, pulos,
   agachamento, defesa e agarrões. Misture golpes acertando e errando.
3. **Combos P2 — 90 s:** repita pelo outro lado. Isso distingue problemas
   associados à origem da entrada. Use o mapeamento/dispositivo já configurado.
4. **Especiais e supers — 120 s:** use projéteis, vários efeitos e supers
   quando disponíveis pelas regras normais do jogo. Marque com o lado usado
   e os golpes. Não mude opções para obter barra infinita durante a rodada.
5. **Ambos — 90 s, se possível:** ataques e defesa simultâneos com os dois
   jogadores. Se estiver sozinho e não conseguir controlar ambos, pule esta
   etapa e anote; não é necessário um segundo jogador para os outros testes.
6. **Parado — 60 s:** pare as entradas e observe se a eventual diferença
   desaparece ou permanece. Registre rounds/KO ocorridos durante o teste.

No menu do marcador, use `combat-p1` ou `combat-p2` e a observação para
distinguir especiais/supers. Não existe exigência de executar um combo
específico. Compare o mesmo acontecimento nas duas telas: começo do golpe,
acerto, defesa, queda e recuperação. Animações diferentes entre P1 e P2 são
esperadas; o que deve coincidir é o estado da mesma luta nos dois processos.

## T06 — arrasto e foco

Prepare as janelas lado a lado **antes** de marcar o trecho parado. Se for
necessário sair de fullscreen, faça isso antes do trecho medido e anote o modo
de janela. Não compare essa rodada diretamente com fullscreen sem registrar.

1. Marque parado e observe por 60 s.
2. Escolha `arrastar host`, anote qual pasta é host e volte ao jogo.
   Após a margem de 5 s, segure o arrasto pela barra de título por cerca de
   3 s e solte. Faça **um** arrasto por janela marcada; não redimensione junto.
3. Espere 30 s sem input. Observe quanto tempo leva para voltar ao alinhamento.
   Termine a marca; registre se a defasagem ficou persistente.
4. Repita mais duas vezes no host, com observações `arrasto 2` e `arrasto 3`.
5. Faça três arrastos equivalentes no cliente, em marcas separadas.
6. Em uma marca `foco`, troque de janela e volte uma vez, **sem arrastar**;
   espere 30 s. Isso separa troca de foco de movimentação da janela.

O script não força congelamento, perda de pacotes nem pausa remota. Uma pausa
local durante arrasto é uma hipótese a medir, não uma falha de rede presumida.

## Como vamos avaliar

- Confirmar captura ativa em ambos, mesmos EXEs, zero perda de eventos e
  sessões pareadas. Erros de conexão antes do TCP abrir podem ser transitórios;
  arquivos incompletos ou sessões sem par precisam ser investigados.
- Conferir rollback, VSync real e hashes reportados. Música em uníssono é uma
  observação útil, mas não substitui a comparação de ticks/hashes existentes.
- Comparar fase, delay e correções por sessão e por etapa marcada. As gerações
  são locais a cada processo e não precisam ter o mesmo número. O resumo recusa
  pareamentos ambíguos em vez de tratar salas diferentes como uma só.
- Como alvo inicial de investigação: fase típica abaixo de um frame em trechos
  estáveis; sinalizar diferença acima de dois frames por mais de dois segundos.
  Depois de arrasto, verificar retorno à fase anterior em até dois segundos;
  exceder isso exige análise, não significa automaticamente desync determinístico.
  Esses alvos não constituem aprovação automática de release.
- Qualquer divergência de hash reportada, desconexão inesperada ou atraso
  persistente deve ser preservado e marcado. Não é necessário reiniciar
  imediatamente a sessão ruim: deixe-a aberta e avise para inspeção.

Os tempos são alvos práticos para esta investigação local. Input delay não
é a mesma coisa que diferença entre telas; 3 frames configurados não provam
50 ms de latência física. O relatório mede fronteiras de admissão, não o
instante em que cada monitor exibe a imagem. Testes no mesmo PC também não
substituem depois o teste real entre máquinas com latência/jitter/perda.

## Arquivos e espaço

Cada execução usa uma pasta nova em `PlusAlphaProject/captures/net-sync-ROTULO-DATA`.
Ela contém manifesto, dois JSONL, `markers.jsonl` e o resumo ao terminar.
O volume observado foi aproximadamente 25 MB/min para os dois processos
somados. Use Ctrl+C para encerrar a coleta após concluir as etapas; preserve
a pasta inteira para análise. Evite excluir capturas de falhas antes de comparar.

Os testes Python do coletor e a sintaxe PowerShell são verificáveis sem build.
O roteiro manual ainda precisa ser executado pelo usuário. Nenhuma build,
sessão de jogo ou entrada de combate foi executada pelo agente nesta preparação.
