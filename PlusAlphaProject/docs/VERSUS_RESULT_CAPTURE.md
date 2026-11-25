# Captura curta de resultado — 10 segundos

Use a build **de diagnóstico** já compilada, com o servidor TCP ativo. Não é
necessária nova build para esses scripts. Uma release com diagnóstico removido
não serve: nesse caso use a build de diagnóstico existente. O script não abre
o jogo, não executa build, não pausa e não envia controles. Você joga normalmente.

1. Entre no Versus offline. Deixe o adversário a um golpe de perder a **luta
   completa**, por exemplo no segundo round com uma vitória de round já obtida.
2. Inicie o comando abaixo e volte o foco para o jogo.
3. Ao aparecer `CAPTURA ATIVA: 10 segundos`, dê o último golpe.
4. Pule o replay normalmente dentro da janela. Se houver tempo, deixe chegar
   à próxima tela, onde o jogo mostra o acumulado. Não carregue save state,
   não use rewind nem volte à seleção de modos durante a coleta.
5. A coleta termina sozinha. A exportação e limpeza podem levar mais alguns
   segundos. O final imprime `ARQUIVO PARA ANALISE` com o caminho completo de
   um ZIP com jogador, data e hora. Copie esse caminho para o chat.
   Confira `status.json`: `complete: true`, `error: null`, sem avisos.

Na pasta `F:\GitRevised\alphaplus`:

```powershell
.\plusalpha-recomp\PlusAlphaProject\tools\capture_versus_result.ps1 -Winner P1
```

Use `-Winner P2` quando P2 vencer. Isso é sua anotação do resultado esperado,
não uma identificação automática do vencedor. Se o jogo usa outra porta:

```powershell
.\plusalpha-recomp\PlusAlphaProject\tools\capture_versus_result.ps1 -Winner P2 -Port 4533
```

Não é preciso reiniciar o jogo com variável de ambiente nem usar o observador
anterior. O script acrescenta uma faixa temporária ao histórico de escritas e
remove somente essa faixa ao terminar. Não limpa históricos nem troca as faixas
existentes. Não execute dois observadores ou altere faixas ao mesmo tempo.

Os dez segundos são medidos pelo relógio do computador. Preparação ocorre antes
do aviso; exportação ocorre depois. Uma resposta lenta do servidor pode deslocar
o encerramento: `observed_seconds` informa a duração efetivamente observada. A
coleta tem custo de diagnóstico; não serve para medir input lag/performance.

## Dados produzidos

Uma pasta nova em `PlusAlphaProject/captures/versus-result-...` contém:

- `versus-result-P1-AAAAMMDD-HHMMSS-microssegundos.zip`: pacote para análise,
  gerado também quando há lacunas. Não inclui outros ZIPs nem substitui capturas
  anteriores. Empacotar não torna completa uma coleta parcial.

- `before.bin` e `after.bin`: janela de RAM física `0x1D0000..0x1E0000`, cobrindo
  os estados conhecidos e estruturas próximas dos jogadores. Não é toda a RAM.
- `writes.jsonl`: mudanças de valor nessa janela, com endereço, largura, valor
  anterior/novo, PC escritor, frame, registradores e indicador de DMA, conforme
  o histórico disponível na build. Escritas sem mudança de valor são descartadas
  na exportação, mas contam no limite do histórico.
- `metadata.json`: frames inicial/final, resultado declarado e contexto de
  overlays. Leituras por requisições diferentes não são um snapshot atômico.
  `after.bin` é obtido depois do fechamento do histórico; pode conter avanços
  posteriores. O contexto dos overlays também é posterior, não prova a imagem
  carregada no instante de cada escrita.
- `increment_candidates.json`: agrupamentos aritméticos `valor novo = antigo + 1`.
  Também haverá timers e outros estados. Nenhuma entrada é automaticamente
  classificada como vitória de round, luta ou sequência.
- `status.json`: completude, duração e avisos de perda/truncamento.

O coletor divide intervalos de frames quando o lote chega ao máximo solicitado
de 2048 escritas. Se um único frame atingir esse limite ou o anel for
sobrescrito, marca a
captura como incompleta, preservando os dados. Nesse caso vamos estreitar as
faixas com base no que foi coletado, sem presumir que eventos ausentes não existem.
PCs de overlays exigem verificar o código/hash/geração correspondente antes de
atribuir significado. O campo `func` de uma escrita pode conter contexto auxiliar;
não deve ser tratado sozinho como identificação confiável da rotina.

O código de saída 0 indica coleta completa; 2 indica dados parciais com avisos;
1 indica erro. O wrapper mostra os motivos, sem esconder avisos em uma exceção
genérica, e termina exibindo o caminho absoluto do ZIP (ou do relatório, se não
foi possível empacotar). O intervalo entre consultas é de 50 ms para reduzir a
chance de sobrescrita, sem garantia de eliminar perdas sob carga elevada.

Para empacotar uma captura anterior sem consultar o jogo ou modificar seus dados:

```powershell
python -B .\plusalpha-recomp\PlusAlphaProject\tools\capture_versus_result.py `
  --package-only --winner P1 --output 'CAMINHO_COMPLETO_DA_PASTA_DA_CAPTURA'
```

## Sequência mínima útil

Primeiro envie uma captura de luta completa vencida por P1. Depois faça outra
vencida por P2. Para distinguir vitória de round de vitória da luta, uma terceira
captura `-Kind round -Winner P1` pode registrar apenas o primeiro round vencido.
Informe o placar original antes/depois e se conseguiu pular o replay dentro da
janela. Se o incremento acontecer depois dos dez segundos, repetir com o início
mais próximo desse momento; ausência de evento nessa janela não prova ausência
de contador nativo.

Esta etapa só coleta evidências. Não altera o filtro Versus, não implementa Wins
na HUD e não altera rollback, rede ou frame pacing.
