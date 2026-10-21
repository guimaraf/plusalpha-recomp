# Release portátil para teste e envio

O usuário executa a build localmente. O agente apenas preparou os scripts.
Não houve mudança do algoritmo de sincronismo nesta preparação. Os testes
locais sem arrasto não garantem o comportamento pela internet nem corrigem
a recuperação após interrupções já observada.

## Um comando

```powershell
Set-Location F:\GitRevised\alphaplus\plusalpha-recomp
.\PlusAlphaProject\tools\build_release.ps1 -Generate -Jobs 2 -SdlBackend SDL3
```

Esse comando gera as fontes, compila **Release** em uma pasta nova, prepara
o pacote e compacta. Não executa o jogo. Requer o mesmo ambiente MSYS2/UCRT64,
disco e BIOS locais usados nas builds anteriores. Não use os antigos scripts
`package_release.ps1`/`.bat`: eles pertencem ao fluxo legado de launcher com
toolchain de compilação. O fluxo atual é `build_release.ps1` com o empacotador
Python chamado automaticamente.

## Saída

- `PlusAlphaProject/build-release-online-DATA-HORA`: build de desenvolvimento;
  preserve localmente, não é a pasta para enviar.
- `PlusAlphaProject/dist/exPlusAlpha-DATA-HORA`: pasta portátil para testar.
- `PlusAlphaProject/dist/exPlusAlpha-DATA-HORA.zip`: arquivo para enviar.
- `PlusAlphaProject/dist/exPlusAlpha-DATA-HORA.zip.sha256`: checksum do ZIP.

O ZIP é montado a partir da lista de arquivos do manifesto e verificado por
CRC e SHA-256 antes de ser publicado. Arquivos existentes não são substituídos;
um `.partial` indica compactação interrompida e não deve ser enviado.
O tamanho exato aparece no final. Como referência, a release anterior local
ocupava cerca de **81,5 MiB sem compactar**; a nova build e o ZIP podem diferir.

O pacote contém EXE sem símbolos de debug, DLLs não pertencentes ao Windows
quando necessárias, configuração base, assets do launcher, mods bundled
declarados pela build, manifesto de execução, versão, instruções e licenças.
Não inclui build/cache/fontes gerados, compiladores, Python, dumps, capturas,
saves, credenciais ou configurações pessoais da raiz da build. Não inclui
disco CUE/BIN nem BIOS para o destinatário. Cada jogador seleciona seus próprios
arquivos no launcher; o destinatário não precisa instalar ferramentas de build.

Launcher, lobby, rollback e ICE ficam habilitados. Debug TCP e wizard de
compilação ficam desligados. O empacotador recusa cache com flags incompatíveis.

## Testar a release em duas cópias

1. Extraia o ZIP em duas pastas novas, por exemplo `G:\sfPlus\release1` e
   `G:\sfPlus\release2`, de modo que cada uma contenha `exPlusAlpha.exe`.
2. Feche as instâncias antigas. Abra cada EXE com sua própria pasta como
   diretório de trabalho, configure seus arquivos no launcher e teste primeiro
   boot e luta offline. Depois entre no versus online por IP direto.
3. Posicione as janelas usando o script já existente, apontando para essas pastas:

```powershell
Start-Process 'G:\sfPlus\release1\exPlusAlpha.exe' -WorkingDirectory 'G:\sfPlus\release1'
Start-Process 'G:\sfPlus\release2\exPlusAlpha.exe' -WorkingDirectory 'G:\sfPlus\release2'

# Depois de entrar no versus:
.\PlusAlphaProject\tools\position_netplay_windows.ps1 -FirstDir G:\sfPlus\release1 -SecondDir G:\sfPlus\release2 -Fit
```

O script de posicionamento roda no PC de teste a partir do repositório;
não precisa acompanhar o ZIP. Ele funciona sem TCP de diagnóstico. Aguarde
cinco segundos depois de posicionar. Observe alguns rounds sem arrasto,
depois combos/especiais em cada lado. Repita invertendo quem cria a sala.
Não conclua estabilidade da release só pelo teste no mesmo PC: depois compare
com outro jogador em outra máquina, usando o mesmo ZIP.

Os scripts `capture_net_sync.ps1` e `test_net_sync_drag.ps1` dependem dos comandos
TCP e **não consultam esta release**. Para números detalhados de fase, use a
build de diagnóstico separada. A comparação inicial da release será funcional
e visual; preserve qualquer mensagem ou relatório gerado caso haja falha.

Teste uma cópia extraída do ZIP; preserve o ZIP original para envio. Os
arquivos de configuração e saves criados durante seu teste não precisam ser
enviados ao outro jogador. Para conferir o arquivo recebido:

```powershell
Get-FileHash 'CAMINHO\exPlusAlpha-DATA-HORA.zip' -Algorithm SHA256
```

Compare com o texto `.zip.sha256`. Para gerar somente a pasta sem ZIP,
adicione `-NoZip`. Para empacotar uma build Release já existente, sem compilar,
use `-PackageOnly -BuildDirName build-release-online-DATA-HORA`; ainda é
necessário apontar para um cache Release compatível. Não empacote a build de
diagnóstico como se fosse release.
