# Planejamento Arquitetural: Subsistema de Menu de Pause e Command List

Este documento consolida o mapeamento estático, o fechamento de dependências e o plano de ação futuro para a recompilação nativa dos menus de pausa e listas de comandos de *Street Fighter EX Plus Alpha* (`SLUS-005.48`).

---

## 1. Visão Geral do Subsistema

O subsistema de pausa é dividido em **dois componentes principais** no Main EXE:
1. **Menu de Pause Principal (`0x80172DD0..0x8017566C`)**: Despachante da interface quando o botão START é pressionado durante o combate, exibindo opções de controle, retorno e reset.
2. **Command List & Submenus (`0x80183734..0x80185860`)**: Visualizador gráfico tridimensional de golpes dos lutadores e configurações secundárias.

---

## 2. Componente 1: Menu de Pause Principal (`0x80172DD0..0x8017566C`)

### Métricas
- **Orçamento**: 10 funções contíguas.
- **Palavras**: 2.599 palavras (10.396 bytes).
- **Ponto de Entrada (Semente)**: `0x80172DD0`.
- **Despacho Mestre**: Registrado no índice 0 da tabela mestre de estados do jogo em `0x801AF994` (chamado dinamicamente via `jalr` em `0x80104128`).

### Funções do Bloco
| Função | Bytes | Palavras | Hits Observados | Papel Arquitetural |
|:---|:---:|:---:|:---:|:---|
| `0x80172DD0` | 3.264 | 816 | 62 | Despachante raiz do menu de pause; possui jump table de 5 casos em `0x801AC91C`. |
| `0x80173A90` | 260 | 65 | 1 | Setup de viewports e display lists do menu. |
| `0x80173B94` | 684 | 171 | 1 | Alocação de buffers de texto e listas de renderização. |
| `0x80173E40` | 600 | 150 | 2 | Seleção e navegação dos itens do menu (Exit, Reset, Button Config). |
| `0x80174098` | 152 | 38 | 16 | Disparo de áudio e efeitos de cursor. |
| `0x80174130` | 1.540 | 385 | 2 | Processamento de transições e estados de botões. |
| `0x80174734` | 2.104 | 526 | 122 | Renderizador gráfico de caixas, fontes e textos na tela. |
| `0x80174F6C` | 268 | 67 | 22 | Limpeza e teardown de buffers ao fechar a interface. |
| `0x80175078` | 648 | 162 | — | Handler de transição de retorno ao combate. |
| `0x80175300` | 876 | 219 | 1 | Confirmação de Reset de partida ("YES / NO"). |

### Encaixe e Abutment
- **Limite Inferior**: Conecta-se contiguamente a `0x80172DD0` com o bloco compilado `[0x801727E4..0x80172DD0]`.
- **Limite Superior**: Conecta-se contiguamente a `0x8017566C` com o bloco compilado `[0x8017566C..0x801758C8]` (promovido no lote S1-258).
- **Resultado do Abutment**: Ao ser compilado, preenche 100% da lacuna entre os dois blocos, gerando uma região nativa única contígua `[0x801727E4..0x801758C8]`.

### Auditoria de Codegen & Closure
- **Chamadas Externas Pendentes**: **EXATAMENTE ZERO**. Todas as sub-rotinas invocadas via `jal` já estão compiladas nativamente.
- **Jump Table Interna (`0x801AC91C`)**: 5 casos (`0x80172E3C`, `0x801734FC`, `0x80173550`, `0x8017359C`, `0x80173638`), todos estritamente contidos dentro de `0x80172DD0`.
- **Expansão de Closure**: **RIGOROSAMENTE ZERO**.

---

## 3. Componente 2: Command List & Submenus (`0x80183734..0x80185860`)

### Métricas
- **Orçamento Estimado**: ~30 funções.
- **Ponto de Entrada (Semente)**: `0x80183734` (índice 12 da tabela `0x801AF994`).
- **Hits Observados na Telemetria 62**: 1.100 hits no interpretador.

### Funções Chave do Bloco
- `0x80183734`: Despachante principal da Command List.
- `0x8018404C` e `0x80184138`: Gestão de inputs e seleção de abas de golpes.
- `0x80185304`: Decodificador de strings e sequências de golpes (setas direcionais e botões).
- `0x80185618`: Formatador de buffers de primitivas de texto.
- `0x80185860` (`0x80185898`, `0x80185970`): Renderizador 3D de caixas e polígonos da interface.

### Pipeline GTE Associado
- A Command List aciona as seguintes rotinas vetoriais para renderizar ícones tridimensionais de golpes:
  - `0x8019C224`, `0x8019C278`, `0x8019C284`, `0x8019C290`, `0x8019C3F4`
  - `0x8019DAD0`

---

## 4. Plano de Execução Futura

Quando o subsistema for atacado:
1. **Passo 1: Menu de Pause Principal**
   - Adicionar semente `0x80172DD0` em `entry_funcs.txt`.
   - Gerar fontes e validar compilação sem expansão de closure (+2.599 palavras).
   - Validar em Versus Mode abrindo e fechando o pause sem navegar para Command List.
2. **Passo 2: Command List**
   - Adicionar semente `0x80183734` e rotinas vetoriais auxiliares (`0x8019C224`, `0x8019DAD0`).
   - Validar folheando todas as páginas de golpes de ambos os jogadores.
3. **Passo 3: Telas Especializadas**
   - Validar no Training Mode (opções de Dummy) e Expert Mode (Mission Select).
