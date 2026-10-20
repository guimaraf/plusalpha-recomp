# BIOS de referência local

O port usa BIOS LLE com uma cópia legítima da BIOS norte-americana SCPH-1001.
A BIOS não acompanha este repositório.

Coloque o arquivo em:

```text
bios/SCPH1001.BIN
```

| Campo | Valor |
|---|---|
| Tamanho | 524.288 bytes |
| MD5 | `924E392ED05558FFDB115408C263DCCF` |
| SHA-1 | `10155D8D6E6E832D6EA66DB9BC098321FB5E8EBF` |
| SHA-256 | `71AF94D1E47A68C11E8FDB9F8368040601514A42A5A399CDA48C7D3BFF1E99D3` |

A ROM e os fontes derivados gerados localmente permanecem ignorados pelo Git.
`tools/build_online.ps1 -Generate` encontra esse arquivo na raiz do repositório,
confere o SHA-256 e o fornece à CLI para gerar o backend SCPH1001 no framework.
Outro caminho local pode ser informado com `-BiosPath`.

O port exige a BIOS SCPH-1001 do jogador. O CMake liga exclusivamente o backend
SCPH1001 e `[runtime] openbios = false` impede fallback para OpenBIOS, inclusive
se existirem preferências antigas. Nenhuma ROM de BIOS é copiada para a pasta
de distribuição pelo build do jogo.

Ao abrir o launcher, selecione sua própria `SCPH1001.BIN` no seletor de BIOS.
Também é possível passar `--bios caminho/para/SCPH1001.BIN` ao executável.
No online, os dois jogadores precisam fornecer a mesma imagem aceita pelo port.
