# Migração do online — validação local pendente

Esta integração usa o rollback e o lobby oficiais do PSXRecomp. O suporte está
conectado no código, mas este port ainda precisa ser compilado e qualificado
offline e entre dois pares. Nenhum build ou teste de partida foi executado pelo
agente. Não tratar esta branch como release validada.

## Revisões

- Baseline anterior do jogo: `abcac1c070652bd115d50a34659ffbe43b24c5c0`.
- Baseline anterior do framework: `1cfa7fe449dd94e911fcb9c5491e6806c11935b7`.
- Base original integrada: `RetroPortingToolKit/psxrecomp`,
  `53a057f548cd1f93f1b4d8300caaeded72f4160d` (17/10/2026).
- `recomp-net`: `e53059306824edf4f0aec4aae5ae65151b18535f`.
- `rbengine`: `2a03e73693acee0fb78076ea058642c931bef12e`.
- `recomp-ui`: `0546fbcb0126bb14bf88d2128b4fe8a4229570a3`.

Os gitlinks dos submódulos fixam as versões. O framework mantém o histórico do
fork e incorpora o histórico original; nenhuma atualização remota é automática.
O cache de toolchain que veio rastreado no original foi excluído do índice do
fork; dependências regeneráveis não fazem parte desta alteração.

## Build feito pelo usuário

Na raiz do repositório, com Python 3.11+, MSYS2 UCRT64 e suas ferramentas:

```powershell
git submodule update --init --recursive
.\PlusAlphaProject\tools\build_online.ps1 -Generate
```

`-Generate` chama a CLI oficial, recompila os emitters atuais, regenera OpenBIOS
e o jogo e depois compila o runtime. Pode baixar o toolchain e as dependências
fixadas pelo framework. Para também regenerar a BIOS de referência a partir do
seu próprio dump, acrescente `-BiosPath 'caminho\SCPH1001.BIN'`.

Saída: `PlusAlphaProject/build-online/exPlusAlpha.exe`. As fontes do jogo vão
para `generated-online/`; o disco preparado, para `prepared-online/`. Ambos são
locais e ignorados. As pastas `generated/`, `buildTele-*`, `build_s1_309_*`, saves
e caches existentes não são movidos nem apagados. Não copie seus caches de
overlays ou save states antigos para a versão nova. Memory cards são separados
dos snapshots; faça os primeiros testes com os saves novos da pasta de build.

Para builds seguintes, sem mudar o emitter ou a configuração de geração:

```powershell
.\PlusAlphaProject\tools\build_online.ps1
```

SDL3 é o padrão atual. `-SdlBackend SDL2` permite comparar o backend legado.
`-SetupHost` gera o setup host oficial com o wizard; ele substitui o fluxo TinyCC
antigo e não usa `game_core.dll`/`compileBuild`. Os scripts S1-309 e os antigos
`package_release.*` pertencem à baseline; não os use nesta branch.

## Overlays e desempenho

Os seeds existentes foram mantidos, mas as 2.219 DLLs/overlays S1-309 não são
compatíveis automaticamente com o emitter/ABI atual. A primeira versão não liga
essas fontes antigas: overlays ainda sem código nativo podem executar no caminho
de interpretação do framework. Isso precisa ser medido antes de prometer o mesmo
desempenho ou a mesma cobertura da baseline.

Quando regenerar um shard estático com as ferramentas atuais, forneça
`-StaticOverlayDir 'caminho\atual'`; o diretório deve conter
`overlays_static.c` e seus shards `overlays_static_NNNN.c`. Não renomeie uma pasta
S1-309 para contornar a incompatibilidade. Veja `psxrecomp/docs/AOT_SHARDING.md`.

## Launcher e recursos existentes

- Dois jogadores digitais, nome do jogo, ícone e configuração de baixa latência
  permanecem declarados no projeto.
- O launcher é agora o `recomp-ui`; o menu de configurações também é o oficial.
- `sfexp.png` continua sendo copiado. Para bezel, use Mods → Bezel Artwork e
  selecione essa imagem. O bezel oficial usa OpenGL; o botão `show_bezel` do
  RmlUi antigo e os seus caminhos Software/Vulkan não foram portados.
- A leitura de FPS é a do framework (`PSX_FPS_TELEMETRY=1` e hotkey do runtime).
  O botão persistente `Show FPS` do launcher antigo não integra a nova UI.
- O armazenamento criptografado de tempo de jogo foi preservado no fork. O
  total aparece em Credits e a gravação para antes de voltar ao lobby.
- UWP/Xbox não está qualificado nesta migração; o CMake recusa esse alvo.

## Roteiro de qualificação

1. Executar offline com o disco USA original e conferir boot, seleção de
   personagens, Arcade, Versus, áudio, controles P1/P2 e estabilidade dos frames.
2. Em dois PCs, usar exatamente esta versão do port, o mesmo perfil de execução,
   disco e BIOS negociada. Ambos usam a mesma edição USA `SLUS-00548`.
3. Abrir Netplay e testar LAN/Direct IP. Confirmar P1 e P2, comandos simultâneos,
   início/fim de round, troca de cenário e retorno ao lobby com revanche.
4. Testar o lobby online. O servidor padrão é
   `ws://netplay.retcomm.net:8765`; a disponibilidade não foi confirmada aqui.
   O runtime permite outro servidor por `PSX_NET_LOBBY_URL`.
5. Manter rollback habilitado (padrão), depois comparar com Disable Rollback.
   Conferir correções sob atraso/jitter, ausência de desync e perda de conexão.
6. Consultar `netplay_status` no debug server (porta 4531) em ambos os pares:
   verificar avanço dos ticks e da confirmação de estados. Guardar logs em
   caso de mismatch, timeout, travamento ou queda de desempenho.

Os gates verificam CRC/SHA-1 do disco e TOC exatos: um track MODE2/2352,
224.511 setores. Content negotiation está desabilitada para partidas vanilla.
Os pares também precisam concordar na BIOS e na identidade de execução; o
lobby comum não torna partidas PSX compatíveis com jogos SNES.

## Verificações feitas sem build

- 24 testes Python da CLI, incluindo o layout com framework irmão e os fluxos
  de geração/rebuild com processos substituídos por mocks.
- Sintaxe do script PowerShell, AST dos arquivos Python alterados, TOML e pins
  das três dependências.
- Contrato dos argumentos do CMake com o helper real, em modo script com
  criação de targets substituída; sem configurar compiladores ou compilar.
- SHA-256 e CRC32 do BIN local conferidos com a identidade USA; fingerprint
  calculado da TOC do CUE de um track.
- A CLI oficial `verify-disc` aceitou o track principal com os digests
  configurados. O status de subchannel foi `unknown`.

Essas verificações não validam compilação C/C++, desempenho ou sincronização
durante partidas. A comparação de whitespace com a base original é restrita às
adaptações locais; arquivos importados preservam a formatação do upstream.

Antes de distribuir, adaptar o empacotamento ao helper oficial
`psxrecomp/tools/package_game_release.sh`, incluindo assets, catálogo de mods,
OpenBIOS/licença, toolchain de overlays e sidecar de execução. Os pacotes antigos
baseados em `compileBuild` não contêm a estrutura atual.

## Recuperação da baseline

As branches `main` anteriores permanecem nos dois repositórios. Para comparar
com a versão validada, prefira outro checkout; não troque de branch com mudanças
pendentes e não use comandos de limpeza em builds, discos ou saves pessoais.
