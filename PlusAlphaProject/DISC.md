# Identidade do disco — Street Fighter EX Plus Alpha (USA)

## Fonte de verdade

O porte usa exclusivamente a imagem presente em `disc-a`, edição USA,
serial `SLUS-00548`. A imagem não deve ser convertida para ISO cooked, alterada
ou substituída silenciosamente por outra região/revisão.

Formato: CUE/BIN, um único track de dados `MODE2/2352` com 224.511 setores.
Música XA e vídeos STR permanecem dentro da faixa de dados; não há track CDDA.

| Arquivo | Tamanho | MD5 | SHA-1 | SHA-256 |
|---|---:|---|---|---|
| `Street Fighter EX Plus Alpha (USA).bin` | 528.049.872 | `2A57B43B0B2F3F094CE203D32E910E2A` | `4A25DAB2BDC11372AB8496C807C28D49A476137D` | `E1050B3B8A3D26E04D4BBE196A7DED17CD0FF1E7DE944D0FD7E161C48D60F9CA` |

## Identidade lógica

| Campo | Valor |
|---|---|
| Título | Street Fighter EX Plus Alpha |
| Região | USA / NTSC-U |
| Serial | `SLUS-00548` |
| Arquivo de boot | `SLUS_005.48` |
| Volume ID | `SFEXPLUSALPHA` |
| SYSTEM.CNF | `BOOT = cdrom:\\SLUS_005.48;1` |

## Executável principal

| Campo | Valor |
|---|---|
| Tamanho | 784.384 bytes |
| MD5 | `E2D965594249CBA514B0F914B745550E` |
| SHA-1 | `D8B81E036AA53C37EF983871C187CC9D00A27156` |
| SHA-256 | `4FFE98EB4F246B4D455392E537E8D9F029D34F2E95E301AEF2CB61F5E3E99820` |
| Entrada | `0x80101008` |
| Endereço de carga | `0x80101000` |
| Tamanho do texto | `0x000BF000` |
| Final do texto | `0x801C0000` |
| Stack inicial | `0x801FFFF0` |

## Inventário inicial

- 231 arquivos e 15 diretórios;
- 58 overlays `.OVL`, todos distintos por conteúdo;
- 97 arquivos `.PAC`;
- 4 fluxos de áudio `.XA`;
- 25 vídeos `.STR`;
- 41 imagens `.TIM`.
