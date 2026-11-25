# New Words Inventory (Static & Dynamic Promotion Tracker)

This document is the official tracking registry for newly discovered functions, static promotion micro-batches, and coverage baselines in the *Street Fighter EX Plus Alpha* (`SLUS-005.48`) static recompilation project.

For full reverse engineering notes, pre-audit breakdowns, incident reports, and deep historical logs, refer to [`buildResume.md`](archive/buildResume.md).

---

## 1. Governance & Maintenance Rules

1. **Observed PC $\neq$ Function Root**: Runtime hits may point to internal blocks, return sites, jump table targets, or trampolines. Only audited function entry points qualify as seeds.
2. **Promotion Requirement**: A micro-batch is only marked as `processed` after its boundaries, callers, internal aliases, reachable closure, indirect jumps, telemetry validation, and regressions pass with zero defects.
3. **Hard Budget Gate**: No seed may be added to `seeds/entry_funcs.txt` without an isolated pre-audit measuring the full reachable closure. If the expanded closure exceeds the budget, the candidate is rejected or quarantined.
4. **Interpreter Quarantine for SMC/Hardware**: Self-modifying code and direct hardware MMIO busy-wait loops (such as the PSX BIOS Joypad/SIO hook at `0x801AB1F4` and `0x801AB2C0`) must remain interpreted to guarantee input timing and prevent execution deadlocks.

---

## 2. Current Baseline Status

> **Official metric (Phase 0, 2026-11-24).** From now on, coverage is measured by `python PlusAlphaProject/tools/coverage_metric.py`, which counts **unique** words, and guarded by `--check` against `PlusAlphaProject/coverage/baseline.json`. Value at Phase 0: **154.639 / 174.276 code words (88,7322%)**, 1.359 functions and 21.908 dispatcher entries (`generated-online`); the current Fase 2 value is in section 6. Cumulative figures below that came from summing manifest `R` lines may double-count alias ranges: the S1-309 figure of 154.846 contained 202 duplicated words. The quarantines are exactly `0x801AB1F4..0x801AB237` (SIO) and `0x801AB2C0..0x801AB2EF` (SMC). The entries below are kept as a historical record. Atualizado em F2-L16 (secao 6): 168.654 / 174.246 (96,7907%), 1.476 funcoes, 23.938 entradas (denominador corrigido de 174.276 para 174.246 no F2-L16, ver secao 6); o baseline.json so sera promovido no fim da Fase 2.

- **Validated Checkpoint**: **S1-305** (Skullo Dream cinematics and 3D camera setup - `0x8013B070..0x8013BFA8`: `0x8013B070`, `0x8013B078`, `0x8013B10C`, `0x8013B114`, `0x8013B328`, 5 functions, 1.148 words / 4.592 bytes; successfully validated in `gameplay-discovery-139`, eliminating 100% of Main EXE candidates; 1.320 native functions, 146.054 words, 74,6758%).
- **Active Batch (S1-305, historical)**: None (S1-305 validation complete); the Fase 2 micro-lots are tracked in section 6.
- **Main Binary Coverage at S1-305 (historical)**: **146,054 / 195,584 words (74.6758%)** (Validated S1-305). Current Fase 2 metric after F2-L16: **168.654 / 174.246 code words (96,7907%)**, section 6.
- **Total Compiled Native Functions (S1-305, historical)**: **1,320 functions**; 1.476 functions after F2-L16, section 6.
- **Codegen Audit Status**: **CLEAN** (0 unresolved direct calls, 0 call_by_address misses, 0 tail-call misses, 0 unresolved gotos).
- **Residual Main EXE Misses**: **ZERO misses during boot, introduction, and active combat** (S1-305). In the F2-L8, F2-L9, F2-L10, F2-L11, F2-L12, F2-L13, F2-L14, F2-L15 and F2-L16 routes, the only Main EXE PCs in fallback are the six quarantined ones, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` and `0x801AB2E8` (BIOS/SIO SMC monkey-patches, inside the metric quarantine ranges `0x801AB1F4..0x801AB237` and `0x801AB2C0..0x801AB2EF`).

---

## 3. Processed Micro-Batches Table

| Batch | Promoted Functions / Ranges | New Words | Cumulative Words | Status / Checkpoint |
|---|---|---:|---:|---|
| **S1-240** | `0x8013CB08..0x8013CB8B` | 33 | 106,352 | Processed; Checkpoint S1-242 |
| **S1-241** | `0x801102A0..0x8011062F` | 228 | 106,580 | Processed; Checkpoint S1-242 |
| **S1-242** | `0x80137FE8`, `0x80138084`, `0x8013827C` | 245 | 106,825 | Processed; Checkpoint S1-242 |
| **S1-243** | `0x80162D68..0x8016313B` | 245 | 107,070 | Processed; Checkpoint S1-245 |
| **S1-244** | `0x80107A74..0x80107D7F` | 195 | 107,265 | Processed; Checkpoint S1-245 |
| **S1-245** | `0x8011D310..0x8011D9B3` | 425 | 107,690 | Processed; Checkpoint S1-245 |
| **S1-246** | `0x8011D030`, `0x8011D078` | 184 | 107,874 | Processed; Checkpoint S1-248 |
| **S1-247** | `0x801A92B8..0x801A939B` | 57 | 107,931 | Processed; Checkpoint S1-248 |
| **S1-248** | `0x801A9DC0..0x801A9FD3` | 133 | 108,064 | Processed; Checkpoint S1-248 |
| **S1-249** | `0x8019F6A8`, `0x8019FB64` | 125 | 108,189 | Processed; Checkpoint S1-250 |
| **S1-250** | `0x8019F5CC`, `0x8019FB4C`, `0x8019FB84`, `0x8019FB94` | 76 | 108,265 | Processed; Checkpoint S1-250 |
| **S1-251** | `0x8014C708..0x8014C72F` | 10 | 108,275 | Processed; Checkpoint S1-255 |
| **S1-253** | `0x8017D860`, `0x8017DA08`, `0x80191000` | 184 | 108,459 | Processed; Checkpoint S1-255 |
| **S1-254** | `0x8017DA9C`, `0x80190EB8`, `0x80190FAC` | 155 | 108,614 | Processed; Checkpoint S1-255 |
| **S1-255** | `0x8018F10C..0x80190E6B` | 1,880 | 110,494 | Processed; Checkpoint S1-255 |
| **S1-256** | `0x8016FC28`, `0x801910A4`, `0x801914C0`, `0x80191C84`, `0x80192D6C`, `0x801930BC` | 622 | 111,116 | Processed; Checkpoint S1-261 |
| **S1-257** | `0x8019FC6C..0x8019FCE3` | 30 | 111,146 | Processed; Checkpoint S1-261 |
| **S1-258** | `0x8017566C..0x801758C7` | 151 | 111,297 | Processed; Checkpoint S1-261 |
| **S1-259** | `0x801939A0..0x80193A17` | 30 | 111,327 | Processed; Checkpoint S1-261 |
| **S1-260** | `0x80103BD8..0x80103CA7` | 52 | 111,379 | Processed; Checkpoint S1-261 |
| **S1-262** | `0x80103384` + closure | 936 | 112,315 | Processed; Checkpoint S1-262 |
| **S1-263** | `0x80164F00` + closure (9 functions) | 8,026 | 120,341 | Processed; Checkpoint S1-263 |
| **S1-264** | `0x801912D8`, `0x80191588`, `0x801961BC` | 217 | 120,558 | Processed; Checkpoint S1-264 |
| **S1-265** | `0x80192128` + Options/Memory Card helpers (8 functions) | 981 | 121,539 | Processed; Checkpoint S1-265 |
| **S1-266** | `0x80124400`, `0x801932BC`, `0x80125594`, `0x801258D4`, `0x8016A84C`, `0x8018C880` + closure | 3,896 | 125,435 | Processed; Checkpoint S1-266 |
| **S1-267** | `0x80106BD4` (Round State Manager FSM; jump table `0x801AB5BC`) | 936 | 126,371 | Processed; Checkpoint S1-267 |
| **S1-268** | `0x80117224`, `0x8011726C`, `0x80117328`, `0x80117564` (Entity / Frame Processing Cluster) | 459 | 126,830 | Processed & Validated; Checkpoint S1-268 |
| **S1-269** | `0x8014FE30..0x801502D4` (3D Projectile/Particle Entity Processor; jump table `0x801ABDD4`) | 298 | 127,128 | Processed & Validated; Telemetry 05 CLEAN |
| **S1-270** | `0x8019E6D0` (F1) + `0x80160B54..0x80160F94` (F2, 5 funcs) | 374 | 127,502 | Processed & Validated; Telemetry 08 CLEAN |
| **S1-271** | `0x801288DC`, `0x80128930`, `0x80128988` (Physics & Special Move Vector Cluster) | 89 | 127,591 | Processed & Validated; Telemetry 09 CLEAN |
| **S1-272** | `0x801202EC..0x80120E44` (Defender Hit-Stun, Recoil & Damage Physics Cluster, 8 funcs) | 726 | 128,317 | Processed & Validated; Telemetry 11 CLEAN |
| **S1-273** | `0x8011721C` (A) + `0x801338B8..0x8013497C` (B) + `0x8013FF34..0x80140858` (C, 8 funcs) | 1,660 | 129,977 | Processed & Validated; Telemetry 13 CLEAN |
| **S1-274 (F1)** | `0x8014373C..0x801441B0` (Combat Action Subsystem, 3 funcs) | 669 | 130,646 | Processed & Validated; Telemetry 15 CLEAN |
| **S1-274 (F2)** | `0x80146B74..0x80147624` (Action/Reaction Subsystem, 3 funcs) | 684 | 131,330 | Processed & Validated; Telemetry 16 CLEAN |
| **S1-275** | `0x8011F5F0..0x801202EC` (9 funcs) + `0x80167ED4` (Leaf) | 840 | 132,170 | Processed & Validated; Telemetry 20 CLEAN |
| **S1-276** | `0x8011E344`, `0x8011E628` (Guile Action Subsystem) | 295 | 132,465 | Processed & Validated; Telemetry 22 CLEAN |
| **S1-277** | `0x8011BD94..0x8011D030` (8 funcs) + `0x8015DDC4` (Leaf) | 1,230 | 133,695 | Processed & Validated; Telemetry 25 CLEAN |
| **S1-278** | `0x80102B10` + `0x80140CEC`, `0x80140D38` | 223 | 133,918 | Processed & Validated; Telemetry 28 CLEAN |
| **S1-279** | `0x80127FB8`, `0x80128A40..D74`, `0x8012B86C`, `0x80161584..1A3C` (13 funcs) | 678 | 134,596 | Processed & Validated; Telemetry 30 CLEAN |
| **S1-280** | `0x8011A8DC`, `0x8011AB7C..B238` (8 funcs) | 663 | 135,259 | Processed & Validated; Telemetry 33 CLEAN |
| **S1-281** | `0x8011D9B4..0x8011E330` (5 funcs) | 612 | 135,871 | Processed & Validated; Telemetry 36 CLEAN |
| **S1-282** | `0x80161C04..0x80161FA8` (7 funcs) | 248 | 136,119 | Processed & Validated; Telemetry 37 CLEAN |
| **S1-283** | `0x8013E930..0x8013EB60` (3 funcs) | 924 | 137,043 | Processed & Validated; Telemetry 38 CLEAN |
| **S1-284** | `0x8014901C..0x801491C0` (3 funcs) | 366 | 137,409 | Processed & Validated; Telemetry 39 CLEAN |
| **S1-285** | `0x8012A7E4`, `0x801441B0..AD8`, `0x80160790..AA4` (6 funcs) | 947 | 138,356 | Processed & Validated; Telemetry 41 CLEAN |
| **S1-286** | `0x8019D860..0x8019D9FC` (10 funcs) | 125 | 138,481 | Processed & Validated; Telemetry 43 CLEAN |
| **S1-287** | `0x8014B21C..BA4C` (3 funcs), `0x8015A530` (1 func), `0x80194BB4..EE4` (5 funcs) | 780 | 139,261 | Processed & Validated; Telemetry 46 CLEAN |
| **S1-288** | `0x80102488` (1 func), `0x80136648..71C8` (7 funcs) | 972 | 140,233 | Processed & Validated; Telemetry 52 CLEAN |
| **S1-289** | `0x8013BFA8`, `0x8013C04C`, `0x8013C06C` (3 funcs) | 203 | 140,436 | Processed & Validated; Telemetry 58 CLEAN |
| **S1-290** | `0x80148678`, `0x80148710`, `0x80148B64` (3 funcs) | 617 | 141,053 | Processed & Validated; Telemetry 59 CLEAN |
| **S1-291** | `0x801555A8..6AD0` (7 funcs) | 250 | 141,303 | Processed & Validated; Telemetry 60 CLEAN |
| **S1-292** | `0x80162680` (1 func) | 2 | 141,305 | Processed & Validated; Telemetry 61 CLEAN |
| **S1-293** | `0x80155608`, `0x80158050`, `0x80158094`, `0x80158174` (4 funcs) | 136 | 141,441 | Processed & Validated; Telemetry 66 CLEAN |
| **S1-294** | `0x8015623C`, `0x80156314` (2 funcs) | 135 | 141,576 | Processed & Validated; Telemetry 67 CLEAN |
| **S1-295** | `0x801564FC..68F8` (6 funcs) | 301 | 141,877 | Processed & Validated; Telemetry 68 CLEAN |
| **S1-296** | `0x8015574C..5A58` (7 funcs) | 244 | 142,121 | Processed & Validated; Telemetry 70 CLEAN |
| **S1-297** | `0x80155B1C`, `0x80155DB4`, `0x80155F98` (3 funcs) | 413 | 142,534 | Processed & Validated; Telemetry 71 CLEAN |
| **S1-298** | `0x80156B80..7014` (7 funcs) | 387 | 142,921 | Processed & Validated; Telemetry 72 CLEAN |
| **S1-299** | `0x8015718C..76E4` (6 funcs) | 395 | 143,316 | Processed & Validated; Telemetry 73 CLEAN |
| **S1-300** | `0x801577B8..7F0C` (12 funcs) | 477 | 143,793 | Processed & Validated; Telemetry 74 CLEAN (0 residual) |
| **S1-301** | `0x80165130` (1 func) | 266 | 144,059 | Processed & Validated; Checkpoint S1-301 (discovery-84) |
| **S1-302** | `0x80164D9C`, `0x80165DAC` (2 funcs) | 330 | 144,389 | Processed & Validated; Telemetry 85 CLEAN (0 residual) |
| **S1-303** | `0x80162244..2570` (6 funcs) | 271 | 144,660 | Processed & Validated; Telemetry 92 CLEAN (0 residual) |
| **S1-304** | `0x801613B8..C0`, `0x80161450`, `0x80161FE4` (4 funcs) | 246 | 144,906 | Processed & Validated; Telemetry 108 CLEAN (0 residual) |
| **S1-305** | `0x8013B070..B328` (5 funcs) | 1,148 | 146,054 | Processed & Validated; Telemetry 139 CLEAN (0 residual) |

- **Total words promoted since S1-239**: **+39,735 words** (+20.32% absolute gain).

---

## 4. Dynamic Overlay Track Summary

Dynamic battle overlays (`0x80020000..0x800F2000`) are compiled on-demand via the overlay cache framework:
- **OVL-001A (`0xAC1FF1A4`)**: 4,563 words compiled (64 entries). Validated clean at 60 FPS over 3 complete matches.
- **OVL-001B (`0x94E6122F`)**: 5,313 words compiled (122 entries). Integrated under S1-261 clean baseline.
- **OVL-MOV (`0x000D6000:0xF06249FB` / `OVL3/MOV.OVL`)**: 30 native DLL shards (80 KB) compiled through GCC. Validated clean in session 119 (+13,97M native dispatches, elimination of all 226,5M interpreted instructions at `0x800E78DC`, perfectly flat frametime at 60 FPS during videos).
- **OVL-OPTS (`0x00020000:0xD955BA78` / `OVL3/OPTS.OVL`)**: 46 native functions compiled through GCC (28 KB). Covers the options-menu update loop `0x80021FB0` and option-navigation subsystems.
- **OVL-MENUS (`0x0008C000:0xD67A9445`)**: 12 native shards (388 KB) compiled through GCC. Covers system-screen control and game-mode selection.
- **OVL-002 Series (Character Fight Logic)**:
  - `OVL-002A` / `OVL-002B`: Player frame update roots (`0x80092C2C`, `0x80092F00`).
  - `OVL-002C` .. `OVL-002G`: Doctrine Dark bomb weapon family (2,563 words).
  - `OVL-002H`: Explosive throw special move (`0x800465A8`, 239 words).

---

## 5. Active Quarantine & Exclusions

| Target / Range | Reason | Policy |
|---|---|---|
| `0x801AB1F4` | SIO/Joypad status polling loop (`0x1F801044` bit `0x80`) | Retained under interpreter |
| `0x801AB2C0` | Self-modifying code (swaps 5 instructions with BIOS in runtime) | Retained under interpreter |
| `0x8019E6D0` | Historical candidate (reproduced with 5,328 hits in Garuda vs Kairi) | Resolved via S1-270 |
| `0x80103384..0x801038B4` | Global root previously quarantined under S1-261 | Resolved via S1-262 |

---

## 6. Fase 2

| Lote | Seeds / Faixas | Novas palavras | Palavras cumulativas | Estado |
|---|---|---:|---:|---|
| **F2-L1** | `0x80169B78`, `0x8010ADE8` (fechamento inclui `0x8016A3A4` via `jal`; 8 funcoes, 213 entradas) | 1.375 | 156.014 (89,5212%) | Validado em execucao autonoma; pendente validacao de sensacao do usuario |
| **F2-L2** | `0x8013009C` (fechamento: `0x80130138`, `0x80130294`; 3 funcoes, 40 entradas) | 288 | 156.302 (89,6865%) | Validado em execucao autonoma; pendente validacao de sensacao do usuario |
| **F2-L3** | `0x8010A5FC`, `0x8010ABC8`, `0x8010ACD8`, `0x8010AFDC`, `0x80107D80`, `0x80107EF0`, `0x8010809C`, `0x801085E0`, `0x8019CB8C` (9 funcoes, 199 entradas) | 1.131 | 157.433 (90,3354%) | Sem regressao nas rotas; so `0x801085E0` com execucao observada; demais pendentes de rota; pendente validacao de sensacao do usuario |
| **F2-L4** | `0x8017FEC0` (fechamento: `0x80180010`, `0x8018097C`; 3 funcoes, 135 entradas) | 1.072 | 158.505 (90,9506%) | Validado em execucao autonoma; pendente validacao de sensacao do usuario |
| **F2-L5** | `0x80129E0C` (fechamento: palavras entre `0x80126DC4` e `0x8012A588`; 6 funcoes, 95 entradas) | 749 | 159.254 (91,3803%) | Validado em execucao autonoma (execucao inferida pelos PCs que sairam do interpretador, sem hits de fntrace); pendente validacao de sensacao do usuario |
| **F2-L6** | `0x80102D80`, `0x80102FAC`, `0x80126878`, `0x80129148`, `0x80162848`, `0x8016321C` (6 raizes estaticas de tabelas de handlers; 10 funcoes, 144 entradas) | 895 | 160.149 (91,8939%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L7** | `0x8012F484` e `0x8013497C` (2 raizes estaticas da tabela contigua `0x801B1BC0..0x801B1C1C`; ponteiros `0x801B1BD8` e `0x801B1C00`; 6 funcoes, 215 entradas) | 1.195 | 161.344 (92,5796%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L8** | `0x80141A30`, `0x80135E50` e `0x80129384` (3 raizes estaticas: ponteiros `0x801B1B64`, `0x801B1C0C` e `0x801B03F4`; 7 funcoes, 116 entradas) | 1.174 | 162.518 (93,2532%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L9** | `0x80132ED4` e `0x8012E858` (2 raizes estaticas, borda em prologo; 6 funcoes, 119 entradas) | 1.093 | 163.611 (93,8804%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L10** | `0x801371C8` e `0x80135010` (2 raizes estaticas da tabela de ponteiros `0x801B1BC0..0x801B1C1C`, ponteiros `0x801B1C18` e `0x801B1C04`, borda em prologo; 10 funcoes, 165 entradas) | 1.135 | 164.746 (94,5317%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L11** | `0x801453A8`, `0x8018D298` e `0x80127320` (3 raizes estaticas: ponteiros `0x801B1B7C`, `0x801B7EF0` e `0x801B039C`, borda em prologo; 5 funcoes, 148 entradas) | 1.104 | 165.850 (95,1651%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L12** | `0x8012EF88`, `0x801236EC`, `0x80198BE4` e `0x8019B168` (4 raizes estaticas: ponteiro `0x801B1BD4` para `0x8012EF88`, borda em prologo; os tres `jal` com alvo unico, sem referencia no EXE; 9 funcoes, 149 entradas) | 721 | 166.571 (95,5789%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L13** | `0x80128524`, `0x80129BE0`, `0x801356A4`, `0x80162B18` e `0x801627AC` (4 ponteiros de tabelas: `0x801B03C4` para `0x80128524`, `0x801B0400` para `0x80129BE0`, `0x801B3468` para `0x80162B18` e `0x801B3450` para `0x801627AC`; `0x801356A4` e alvo de `jal` em `0x8013565C`, origem mais fraca; borda em prologo; 10 funcoes, 75 entradas) | 488 | 167.059 (95,8589%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L14** | `0x801287CC`, `0x80131A3C`, `0x8019735C`, `0x80197370`, `0x8019743C`, `0x8019FA90`, `0x8019FCE4` e `0x801A74F8` (8 raizes: ponteiros `0x801B03C8`, `0x801ABAA8`, `0x801B85C8`, `0x801B85B4`, `0x801B85A4` e `0x801BEEA8`; `0x8019FCE4` e `0x801A74F8` por `lui/addiu` em codigo coberto (callback); `0x80131A3C` tem origem mais fraca; bordas em prologo ou `jr ra`+delay; 10 funcoes, 46 entradas) | 369 | 167.428 (96,0706%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L15** | `0x8012DB4C`, `0x80118010`, `0x80118018`, `0x801627A4`, `0x8016280C`, `0x80162AA8`, `0x8016313C` e `0x80196B18` (8 raizes de tabelas de ponteiros: `0x801B1BC4` (tabela `0x801B1BC0..`), `0x801AFCC4`, `0x801AFCC8`, `0x801B3404`, `0x801B340C`, `0x801B341C`, `0x801B3428` (tabela `0x801B33F0..`) e `0x801B85D8` (tabela `0x801B85A4..`); bordas em prologo ou `jr ra`+delay; 10 funcoes, 46 entradas; ultimo lote de raizes auditaveis da varredura `scan_L15`) | 196 | 167.624 (96,1831%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |
| **F2-L16** | `0x80135608` e `0x80147624` (2 raizes com jump table, adiadas no F2-L10 por `jr` nao-`$ra`: ponteiros `0x801B1C08` e `0x801B1B8C`; `jr v0` em `0x80135898` (tabela `0x801ABBEC`, 5 alvos, switch em `func_80135848`) e em `0x80147CD8` (tabela `0x801ABC6C`, 6 alvos, switch em `func_801477F8`); borda em prologo; 5 funcoes, 125 entradas) | 1.030 | 168.654 (96,7907%) | Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario |

Nota: os percentuais de F2-L1 a F2-L15 usam o denominador 174.276; a partir do F2-L16 o denominador e 174.246 (correcao de exclusoes de padding, ver F2-L16).

Pendencias da Fase 2:

- **[RESOLVIDA em F2-R1]** PCs interpretados restantes no EXE (fora da quarentena): `0x801548BC` e `0x80198350`, alvos de jump table (`0x801ABF24` e `0x801AEE94`) interiores de funcoes ja compiladas; o resolvedor nao reconhece `sltiu; beqz; sll (delay); lui; addiu; addu; lw; nop; jr`, entao nao viram leader nem entrada de dispatcher; nao ha correcao por seed (seed_preview: +0 palavras, borda NAO). Mesma causa para `0x801980B0`, `0x801981E4`, `0x80198268`, `0x80198310`.
- **[RESOLVIDA em F2-R1]** Resolvedor de jump table nao reconhecia `sltiu; beq; sll (delay); lui [; addiu]; addu; lw; nop; jr` (`function_analysis.cpp` ~890-1010; espelho em `tools/compile_overlays.py`). Corrigido; ver F2-R1 abaixo.
- Apos F2-R1 restavam 41 `jr` nao-`$ra` indiretos no EXE (13 em `$v0`, 27 em `$t2`, 1 em `$t1`; 42 apos F2-L3, ver abaixo): outras formas, ainda nao investigadas; as de `$v0` examinadas tem o delay slot do `beq` de limite ocupado por outra instrucao (`0x80106C28`, `0x8010F4B0`, `0x8014F590`). Follow-up; nao ha PC novo interpretado por isso na rota.
- Fechamento do emitter (palavras emitidas e nao visitadas) muda o hash de codegen (`1b6950cb` -> `d3d005b3`) e o stamp do BIOS SCPH1001.

**F2-R1 (correcao do resolvedor):** `resolve_exact_bounded_jump_table` (C++) e `_find_jump_table_targets` (Python) reconhecem `sltiu; beq(z); sll (delay do beq); lui [; addiu]; addu; lw; nop; jr`, com `guard_pc = sll_pc - 4`, `bound_pc = sll_pc - 8`, LW dois words antes do JR e todas as provas anteriores (indice, `sltiu` no mesmo registrador, guarda levando ao default, base exata `lui`/`addiu`/offset do `lw`, alvos validos). Hash de codegen `d3d005b3` -> `e13692f6`. BIOS SCPH1001/OpenBIOS: C gerado identico (so os stamps mudam). Base (EXE): palavras, funcoes e entradas inalteradas (156.302 / 1.370 / 22.161; 0 palavras perdidas); 37 `jr` resolvidos (78 -> 41 `jr` indiretos), incluindo `0x80169BF4`, `0x801548A0` e `0x80198074`; `codegen_audit_game.py` CLEAN. AOT: 280 switches (226 pares overlay/`jr`), 0 antes; palavras de overlay cobertas iguais (328.019), entradas 61.189 -> 61.226; recibo `all_pairs_valid` e `all_guards_match_known_input_bytes` true. Rotas: PCs EXE interpretados 8 -> 6 (`0x801548BC` e `0x80198350` saem; nenhum novo), `miss_total` = 0, instrucoes interpretadas na luta 1.179.616 -> 1.174.456. Evidencias em `relatorios/fase2/R1/`.

**F2-L3 (lote 1A, 2026-11-24):** oito raizes da tabela de cenas `0x801AF960` (indices 2, 4, 5, 12, 22, 23, 24, 26) e o alias `0x8019CB8C`. Base: +1.131 palavras, 1.379 funcoes, 22.360 entradas; 0 perdas; 0 em quarentena; `codegen_audit_game.py` CLEAN; build incremental 187 s. Rotas `boot_to_fight` e `survey_post_fight`: so os 6 PCs de quarentena interpretados e `miss_total` = 0 (a primeira execucao da `survey_post_fight` parou num screenshot com `display disabled`; a repeticao completou os 332 passos). Rotas novas: `survey_modes` (Team Battle ate a selecao, Survival, Watch, Versus, Time Attack, Practice so em Training Mode, Option com Game Option e a tela de Memory Card sem load nem save) e `survey_options` (submenus de Option e derrota/continue/game over), ambas com `miss_total` = 0. Execucao observada: `0x801085E0` (1 hit, frame 26.549, entre as leituras de cena 3 e 1 do continue do Time Attack). Nao alcancados: `0x8010A5FC`, `0x8010ABC8`, `0x8010ACD8`, `0x8010AFDC`, `0x80107D80`, `0x80107EF0`, `0x8010809C`, `0x8019CB8C`. Evidencias em `relatorios/fase2/L3/`.

Pendencias abertas por F2-L3:

- `jr` em `0x8010B030` (tabela `0x801AB6CC`) nao resolvido: forma `sltiu; beq; sw (delay); sll; lui; addiu; addu; lw; nop; jr`. Os alvos `0x8010B1BC` e `0x8010B230` ficam sem entrada no dispatcher (os outros quatro tem). Os `jr` indiretos do EXE passam de 41 para 42. Nao ha correcao por seed.
- Candidatos com execucao observada levantados em F2-L3 (so pre-auditados na epoca; `0x8017FEC0` foi promovido em F2-L4): `0x8017FEC0` (resultado do Survival; +1.072 palavras, 3 funcoes, 135 entradas; 99 PCs interpretados) e `0x80129E0C` (modo Watch; +749 palavras, 6 funcoes, 95 entradas; 46 PCs interpretados; promovido em F2-L5). `0x80129E0C` tem ponteiro em `0x801B0404`, portanto o cluster `0x80129E1C` deixa de ser "sem referencia estatica".

**F2-L4 (lote 1B2, 2026-11-24):** seed `0x8017FEC0`, indice 8 da tabela `0x801AF960` (resultado do Survival), com `0x80180010` e `0x8018097C` no fechamento; faixa continua `0x8017FEC0..0x80180F7F`. Base: +1.072 palavras, 1.382 funcoes, 22.495 entradas; 0 perdas; 0 em quarentena; 0 `jalr` e 0 `jr` nao-`$ra` no lote (42 `jr` indiretos no EXE, sem mudanca); `codegen_audit_game.py` CLEAN; build incremental 125 s. Quatro rotas completas, `miss_total` = 0. PCs do EXE interpretados contra as rotas de F2-L3: `boot_to_fight` e `survey_post_fight` 6 -> 6 (quarentena); `survey_modes` 151 -> 52 (saem os 99 desta faixa; restam 46 do modo Watch e a quarentena; os 46 saem em F2-L5); `survey_options` 105 -> 6; nenhum PC novo. Instrucoes interpretadas (rotas nao deterministicas): `survey_modes` 2.633.837 -> 2.497.521; `survey_options` 2.768.293 -> 2.579.874. `0x8017FEC0`: 838 e 1.684 hits no fntrace. A tela de resultado do Survival mantem o mesmo layout nos screenshots; nao ha comparacao pixel a pixel no mesmo frame. Proximo candidato: `0x80129E0C` (modo Watch; promovido em F2-L5, ver abaixo). Evidencias em `relatorios/fase2/L4/`.

**F2-L5 (lote 1B3, 2026-11-25):** seed `0x80129E0C`, modo Watch, ponteiro em `0x801B0404` (raiz de funcao; borda `jr ra`+delay); fechamento com palavras entre `0x80126DC4` e `0x8012A588` (inclui `0x80126DC4`). Base: +749 palavras, 1.388 funcoes, 22.590 entradas; 0 perdas; 0 em quarentena; 0 `jalr`, 0 `jr` nao-`$ra` e 0 SMC no lote (42 `jr` indiretos no EXE, sem mudanca; mesma forma de escrita de F2-L4); `codegen_audit_game.py` CLEAN; build incremental 151 s. Metrica observada igual a prevista. Rotas `boot_to_fight` (48 passos), `survey_post_fight` (332) e `survey_modes` (446), todas completas, `miss_total` = 0; `survey_options` nao foi refeita neste lote. PCs do EXE interpretados contra as rotas de F2-L4: `boot_to_fight` e `survey_post_fight` 6 -> 6 (quarentena); `survey_modes` 52 -> 6 (saem os 46 do modo Watch; restam so os 6 da quarentena `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC`, `0x801AB2E8`); nenhum PC novo. O modo Watch foi alcancado (snapshots `misses_m_watch_*`). `0x80129E0C` nao tem hits de fntrace porque o fntrace da rota so arma os alvos da tabela `0x801AF960`; a execucao compilada e inferida pela saida dos PCs interpretados, nao medida por contagem. Candidatos restantes: todas as raizes de origem auditada restantes sao estaticas (ponteiros unicos em tabelas de handlers `0x801B0380..0x801B0404`, `0x801B3450..0x801B3474` e de estados `0x801AF888/0x801AF88C`), sem execucao observada; com F2-L5 nao resta PC do EXE interpretado fora da quarentena nas rotas atuais. Desfecho (F2-L6): seis dessas raizes foram promovidas (`0x80102D80`, `0x80102FAC`, `0x80126878`, `0x80129148`, `0x80162848`, `0x8016321C`), tambem sem execucao observada. Fila em `relatorios/fase2/fila.json`. Evidencias em `relatorios/fase2/L5/`.

**F2-L6 (2026-11-25):** seis raizes estaticas de tabelas de handlers, cada uma com ponteiro unico, `jr ra`+nop antes e prologo: `0x80102D80` (ponteiro `0x801AF888`) e `0x80102FAC` (`0x801AF88C`), da tabela de estados; `0x80126878` (`0x801B0380`) e `0x80129148` (`0x801B03EC`), da tabela de handlers do modo (mesma de `0x80129E0C`); `0x80162848` (`0x801B3458`) e `0x8016321C` (`0x801B3474`). Sem execucao observada (nenhum fntrace/rota com hit; nao ha PC interpretado associado). `0x80131A3C` foi excluido pelo coordenador (origem fraca: ponteiro no meio de strings). Base: +895 palavras, +10 funcoes (1.398 no total), +144 entradas (22.734 no total); 0 perdas; 0 em quarentena; 0 `jalr`, 0 `jr` nao-`$ra` e 0 SMC no lote (42 `jr` indiretos no EXE, sem mudanca); `codegen_audit_game.py` CLEAN; build incremental 144 s. Metrica observada igual a prevista: 160.149 de 174.276 (91,8939%), 1.398 funcoes, 22.734 entradas. Rotas `boot_to_fight` (48 passos) e `survey_post_fight` (332), ambas com `miss_total` = 0 e so os 6 PCs da quarentena interpretados, como em F2-L5; nenhum PC novo. `survey_modes` (446 passos) completa, `miss_total` = 0 em 99 snapshots, so os mesmos 6 PCs da quarentena, nenhum PC novo e 0 esperas de display. Incidente: a `survey_post_fight` falhou duas vezes com o script antigo (`survey_try1/` passo 248, `survey_try2/` passo 280), ambas com `screenshot_file` respondendo `display disabled` logo apos ler o byte de cena 7 na saida do Game Over; a triagem nao achou nada contra as seeds (miss_total 0 em todos os snapshots, mesmos 6 PCs da quarentena). Correcao aplicada no `auto_session.py` (commit `6673184`; validada por teste unitario; nao recorreu na 3a execucao): o screenshot espera 15 frames e tenta de novo, ate 8 vezes, registrando `display_retries`. A 3a execucao, com o script corrigido, completou os 332 passos com `display_retries` = 0 em todos os 58 screenshots; `survey_options` nao refeita desde F2-L4. Uma tentativa anterior de `survey_modes` foi interrompida por desligamento do PC (`modes_interrompida/`), sem contar como falha. Proximo (registrado em F2-L6; promovido em F2-L7, abaixo): `0x8012F484` (ponteiro `0x801B1BD8`) e `0x8013497C` (`0x801B1C00`), tabela de funcoes `0x801B1BC0..0x801B1C1C`, +1.195 palavras previstas; fila em `relatorios/fase2/fila.json`. Evidencias em `relatorios/fase2/L6/`.

**F2-L7 (2026-11-25):** duas raizes estaticas, cada uma com ponteiro unico em tabela contigua de funcoes `0x801B1BC0..0x801B1C1C`, `jr ra`+nop antes e prologo, sem `jal`/`j` nem `lui`+`addiu` apontando para elas: `0x8012F484` (ponteiro `0x801B1BD8`; fecha 3 funcoes, +774 palavras, +140 entradas) e `0x8013497C` (ponteiro `0x801B1C00`; fecha 3 funcoes, +421 palavras, +75 entradas). Pre-auditoria (`seed_preview.py`, base F2-L6 de 160.149 palavras, 1.398 funcoes, 22.734 entradas; `relatorios/fase2/L7/preview.txt`): +1.195 palavras, +6 funcoes, +215 entradas; 0 perdas; 0 em quarentena; 0 `jalr`; 0 `jr` nao-`$ra`; 0 SMC; orcamento OK (1.195 <= 1.200 palavras; 6 <= 10 funcoes). Reconferencia em `relatorios/fase2/L7/r2/preview.txt`, com as seeds aplicadas: base 161.344, +0.

Metrica observada igual a prevista (`relatorios/fase2/L7/r2/metric.json`): 161.344 de 174.276 (92,5796%), 1.404 funcoes, 22.949 entradas, `entries_not_covered` 0. `codegen_audit_game.py` CLEAN (`relatorios/fase2/L7/r2/audit.txt`): 0 sites de `call_by_address` indireto. Build incremental `build-auto-p2infra` com `exit_code` 0 em 28,4 s.

Rotas (checkpoint de 3 lotes, L5, L6 e L7; as quatro rotas): `boot_to_fight` completou (48 passos; `miss_total` = 0); `survey_post_fight` completou (332 passos, 58 checkpoints, `display_retries` = 0 em todos); `survey_modes` completou (446 passos, 99 checkpoints). `miss_total` = 0 nas tres. Os unicos PCs do EXE interpretados estao nas quarentenas: `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`; nenhum PC novo.

Rota `survey_options`: completou (417 passos, 90 checkpoints, 0 falhas), miss_total 0, apenas os seis PCs da quarentena interpretados; nenhum PC novo do EXE. Comparado com F2-L6: mesmo conjunto de PCs interpretados e miss_total 0 nas rotas comparaveis (F2-L6 nao rodou `survey_options`).

`0x8012F484` e `0x8013497C` nao estao na lista de alvos do fntrace de nenhuma rota (verificado nos arquivos de `r2/`): nao ha execucao observada, e a instrumentacao atual nao permite afirmar que nao sao chamadas. Incidente de ambiente: a primeira tentativa do L7 (sessao anterior) parou nas rotas por maquina ocupada (timeouts de `wait_frames`/`starvation_watchdog`); o patch foi salvo e reaplicado, e a reexecucao r2 passou.

Proximo (registrado em F2-L7; promovido em F2-L8, abaixo): `0x80141A30` + `0x80135E50` + `0x80129384`. Evidencias em `relatorios/fase2/L7/r2/`.

**F2-L8 (2026-11-25):** tres raizes estaticas, cada uma com ponteiro unico em tabela, palavra anterior `jr ra`+delay e borda em prologo: `0x80141A30` (ponteiro `0x801B1B64`, achado pela varredura `scan_L7`; fecha 3 funcoes, +644 palavras, +65 entradas), `0x80135E50` (ponteiro `0x801B1C0C`, na mesma tabela `0x801B1BC0..0x801B1C1C` do F2-L7; fecha 3 funcoes, +510 palavras, +44 entradas) e `0x80129384` (ponteiro unico `0x801B03F4`, tabela de handlers; fecha 1 funcao, +20 palavras, +7 entradas). Pre-auditoria (`seed_preview.py` contra a base F2-L7, 161.344 palavras, 1.404 funcoes, 22.949 entradas; `relatorios/fase2/L8/preview.txt`): +1.174 palavras, +7 funcoes, +116 entradas; 0 perdas; 0 em quarentena; 0 `jalr`; 0 `jr` nao-`$ra`; 0 SMC; orcamento OK (1.174 <= 1.200 palavras; 7 <= 10 funcoes).

Metrica observada igual a prevista (`relatorios/fase2/L8/metric.json`): 162.518 de 174.276 (93,2532%), 1.411 funcoes, 23.065 entradas, `entries_not_covered` 0. `codegen_audit_game.py` STATUS CLEAN (`relatorios/fase2/L8/audit.txt`): 0 sites de `call_by_address` indireto. Build incremental `build-auto-p2infra` com `exit_code` 0 em 159,9 s (`relatorios/fase2/L8/build/build.json`).

Rotas (as tres completas): `boot_to_fight` completou (48 passos; `miss_total` 0 na telemetria final); `survey_post_fight` completou (332 passos, 58 snapshots de misses, `miss_total` 0); `survey_modes` completou (446 passos, 99 snapshots de misses, `miss_total` 0). Os unicos PCs do EXE interpretados sao os seis da quarentena, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`, o mesmo conjunto do F2-L7; nenhum PC novo. `survey_options` nao foi rodada (nao e lote de checkpoint).

As tres raizes nao estavam nos alvos do fntrace (nenhum arquivo de `relatorios/fase2/L8/`, incluindo `survey_modes/fntrace_alvos.json`, cita os seus enderecos): sem execucao observada, o que nao prova que nao sao chamadas. Proximo candidato: F2-L9 (promovido). Evidencias em `relatorios/fase2/L8/`.

**F2-L9 (2026-11-25):** duas raizes estaticas, com borda em prologo: `0x80132ED4` (fecha 3 funcoes, +633 palavras, +53 entradas) e `0x8012E858` (fecha 3 funcoes, +460 palavras, +66 entradas). Pre-auditoria (`seed_preview.py` contra a base F2-L8, 162.518 palavras, 1.411 funcoes, 23.065 entradas; `relatorios/fase2/L9/preview.txt`): +1.093 palavras, +6 funcoes, +119 entradas; 0 perdas; 0 em quarentena; 0 `jalr`; 0 `jr` nao-`$ra`; 0 SMC; orcamento OK (1.093 <= 1.200 palavras; 6 <= 10 funcoes).

Metrica observada igual a prevista (`relatorios/fase2/L9/metric.json`): 163.611 de 174.276 (93,8804%), 1.417 funcoes, 23.184 entradas, `entries_not_covered` 0. `codegen_audit_game.py` STATUS CLEAN (`relatorios/fase2/L9/audit.txt`): 0 sites de `call_by_address` indireto. Build incremental `build-auto-p2infra` (`reused_build` true) com `exit_code` 0 em 134,5 s (`relatorios/fase2/L9/build/build.json`).

Rotas (as tres completas): `boot_to_fight` completou (48 passos; `miss_total` 0 na telemetria final); `survey_post_fight` completou (332 passos, 58 snapshots de misses, `miss_total` 0); `survey_modes` completou (446 passos, 99 snapshots de misses, `miss_total` 0). Os unicos PCs do EXE interpretados sao os seis da quarentena, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`, o mesmo conjunto do F2-L8; nenhum PC novo. `survey_options` nao foi rodada (o checkpoint de quatro rotas foi feito no F2-L10).

As duas raizes nao estavam nos alvos do fntrace (`survey_modes/fntrace_alvos.json` e `survey_post_fight/fntrace_alvos.json` nao citam os seus enderecos; `boot_to_fight` nao tem arquivo de fntrace): sem execucao observada, o que nao prova que nao sao chamadas. Proximo candidato: F2-L10 (promovido); checkpoint de quatro rotas feito no F2-L10. Evidencias em `relatorios/fase2/L9/`.

**F2-L10 (2026-11-25, checkpoint de quatro rotas):** duas raizes estaticas da tabela de ponteiros `0x801B1BC0..0x801B1C1C` (varredura `scan_L7`), com borda em prologo e palavra anterior `jr ra`+delay: `0x801371C8` (ponteiro `0x801B1C18`; fecha 7 funcoes, +753 palavras, +118 entradas) e `0x80135010` (ponteiro `0x801B1C04`; fecha 3 funcoes, +382 palavras, +47 entradas).

Pre-auditoria (`seed_preview.py` contra a base F2-L9, 163.611 palavras, 1.417 funcoes, 23.184 entradas; `relatorios/fase2/L10/preview.txt`): +1.135 palavras, +10 funcoes, +165 entradas; 0 perdas; 0 em quarentena; 0 `jalr`; 0 `jr` nao-`$ra`; 0 SMC; orcamento OK (1.135 <= 1.200 palavras; 10 <= 10 funcoes).

Metrica observada igual a prevista (`relatorios/fase2/L10/metric.json`): 164.746 de 174.276 (94,5317%), 1.427 funcoes, 23.349 entradas, `entries_not_covered` 0. `codegen_audit_game.py` STATUS CLEAN (`relatorios/fase2/L10/audit.txt`): 0 sites de `call_by_address` indireto. Build incremental `build-auto-p2infra` (`reused_build` true) com `exit_code` 0 em 139,3 s (`relatorios/fase2/L10/build/build.json`).

Rotas (checkpoint, as quatro completas): `boot_to_fight` completou (48 passos; `miss_total` 0 na telemetria final); `survey_post_fight` completou (332 passos, 58 snapshots de misses, `miss_total` 0); `survey_modes` completou (446 passos, 99 snapshots de misses, `miss_total` 0); `survey_options` completou (417 passos, 90 snapshots de misses, `miss_total` 0). Os unicos PCs do EXE interpretados sao os seis da quarentena, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`, o mesmo conjunto do F2-L9; em `survey_options`, tambem o mesmo conjunto do F2-L7 (`relatorios/fase2/L7/r2/survey_options/`). Nenhum PC novo.

As duas raizes nao estavam nos alvos do fntrace (`survey_modes/fntrace_alvos.json`, `survey_post_fight/fntrace_alvos.json` e `survey_options/fntrace_alvos.json` nao citam os seus enderecos; `boot_to_fight` nao tem arquivo de fntrace): sem execucao observada, o que nao prova que nao sao chamadas.

Candidatos adiados (nao promovidos): `0x80135608` (pre-auditoria em pares: 530 palavras, 3 funcoes, 85 entradas) e `0x80147624` (605 palavras, 3 funcoes, 54 entradas) tem `jr` nao-`$ra` = 1 no fechamento (jump table), segundo `relatorios/fase2/L10pre/combos.txt` e `relatorios/fase2/fila.json`; ficam para investigacao/resolvedor antes de promover.

Proximo candidato: F2-L11 (promovido). Evidencias em `relatorios/fase2/L10/`.

**F2-L11 (2026-11-25):** tres raizes estaticas de tabelas de ponteiros, com borda em prologo: `0x801453A8` (ponteiro `0x801B1B7C`, varredura `scan_L7`, palavra anterior `jr ra`+delay; fecha 3 funcoes, +610 palavras, +72 entradas), `0x8018D298` (ponteiro `0x801B7EF0`, `scan_L7`, `jr ra`+delay; fecha 1 funcao, +439 palavras, +72 entradas) e `0x80127320` (ponteiro unico `0x801B039C`, tabela de handlers, `jr ra`+nop; fecha 1 funcao, +55 palavras, +4 entradas).

Pre-auditoria (`seed_preview.py` contra a base F2-L10, 164.746 palavras, 1.427 funcoes, 23.349 entradas; `relatorios/fase2/L11/preview.txt`): +1.104 palavras, +5 funcoes, +148 entradas; 0 perdas; 0 em quarentena; 0 `jalr`; 0 `jr` nao-`$ra`; 0 SMC; orcamento OK (1.104 <= 1.200 palavras; 5 <= 10 funcoes).

Metrica observada igual a prevista (`relatorios/fase2/L11/metric.json`): 165.850 de 174.276 (95,1651%), 1.432 funcoes, 23.497 entradas, `entries_not_covered` 0. `codegen_audit_game.py` STATUS CLEAN (`relatorios/fase2/L11/audit.txt`): 0 sites de `call_by_address` indireto. Build incremental `build-auto-p2infra` (`reused_build` true) com `exit_code` 0 em 170,9 s (`relatorios/fase2/L11/build/build.json`).

Rotas: `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses) e `survey_modes` (446 passos, 99 snapshots de misses) completas, `miss_total` = 0; so os seis PCs da quarentena interpretados, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`, o mesmo conjunto do F2-L10; nenhum PC novo. `survey_options` nao foi rodada (checkpoint de quatro rotas feito no F2-L13).

As tres raizes nao estavam nos alvos do fntrace (`survey_post_fight/fntrace_alvos.json` e `survey_modes/fntrace_alvos.json` nao citam os seus enderecos; `boot_to_fight` nao tem arquivo de fntrace): sem execucao observada, o que nao prova que nao sao chamadas.

Proximo candidato: F2-L12 (promovido). Evidencias em `relatorios/fase2/L11/`.

**F2-L12 (2026-11-25):** quatro raizes estaticas, com borda em prologo: `0x8012EF88` (ponteiro `0x801B1BD4`, tabela `0x801B1BC0..0x801B1C1C`; fecha 4 funcoes, +365 palavras, +72 entradas; o callee `0x8012F090` (jal em `0x8012EFE4`) fica no fechamento e por isso nao entra como seed, por ser redundante), `0x801236EC` (alvo unico de `jal` em `0x801248E0`, dentro da funcao `0x80124728`, sem referencia no EXE; fecha 1 funcao, +137 palavras, +28 entradas), `0x80198BE4` (alvo unico de `jal` em `0x801987F8`, funcao `0x801987D8`, sem referencia; fecha 1 funcao, +102 palavras, +17 entradas) e `0x8019B168` (alvo unico de `jal` em `0x8019AE1C`, funcao `0x8019AD94`, sem referencia; fecha 3 funcoes, +117 palavras, +32 entradas). Os tres alvos de `jal` tem origem mais fraca (chamador ainda nao coberto, sem raiz maior auditavel) e foram aceitos so por evidencia estatica (`relatorios/fase2/L12/origem.txt`); neles a palavra anterior e `jr ra`+nop (`origem.txt`).

Pre-auditoria (`seed_preview.py` contra a base F2-L11, 165.850 palavras, 1.432 funcoes, 23.497 entradas; `relatorios/fase2/L12/preview.txt`): +721 palavras, +9 funcoes, +149 entradas; 0 perdas; 0 em quarentena; 0 `jalr`; 0 `jr` nao-`$ra`; 0 SMC; orcamento OK (721 <= 1.200 palavras; 9 <= 10 funcoes).

Metrica observada igual a prevista (`relatorios/fase2/L12/metric.json`): 166.571 de 174.276 (95,5789%), 1.441 funcoes, 23.646 entradas, `entries_not_covered` 0. `codegen_audit_game.py` STATUS CLEAN (`relatorios/fase2/L12/audit.txt`): 0 sites de `call_by_address` indireto. Build incremental `build-auto-p2infra` (`reused_build` true) com `exit_code` 0 em 360,9 s (`relatorios/fase2/L12/build/build.json`).

Rotas: `boot_to_fight` (48 passos), `survey_post_fight` (332 passos, 58 snapshots de misses) e `survey_modes` (446 passos, 99 snapshots de misses) completas, `miss_total` = 0 nas telemetrias finais; so os seis PCs da quarentena interpretados, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`, o mesmo conjunto do F2-L11; nenhum PC novo. `survey_options` nao foi rodada (checkpoint de quatro rotas feito no F2-L13).

As quatro raizes nao estavam nos alvos do fntrace (`survey_modes/fntrace_alvos.json` e `survey_post_fight/fntrace_alvos.json` nao citam os seus enderecos; `boot_to_fight` nao tem arquivo de fntrace): sem execucao observada, o que nao prova que nao sao chamadas.

Proximo candidato: F2-L13 (promovido). Evidencias em `relatorios/fase2/L12/`.

**F2-L13 (2026-11-25, checkpoint de quatro rotas):** cinco raizes estaticas, todas com borda em prologo: `0x80128524` (ponteiro unico `0x801B03C4`, tabela de handlers; fecha 4 funcoes, +170 palavras, +28 entradas), `0x80129BE0` (ponteiro `0x801B0400`; fecha 3 funcoes, +139 palavras, +13 entradas), `0x80162B18` (ponteiro `0x801B3468`; fecha 1 funcao, +50 palavras, +14 entradas), `0x801627AC` (ponteiro `0x801B3450`; fecha 1 funcao, +24 palavras, +6 entradas) e `0x801356A4` (alvo de `jal` 0x0C04D5A9 em `0x8013565C`, dentro da funcao `0x80135608`, que segue bloqueada por jump table; palavra `jr ra` em `0x8013569C` antes do alvo; origem mais fraca; +105 palavras, 1 funcao, +14 entradas).

Pre-auditoria (`seed_preview.py` contra a base F2-L12, 166.571 palavras, 1.441 funcoes, 23.646 entradas; `relatorios/fase2/L13/preview.txt`): +488 palavras, +10 funcoes, +75 entradas; 0 perdas; 0 em quarentena; 0 `jalr`; 0 `jr` nao-`$ra`; 0 SMC; orcamento OK (488 <= 1.200 palavras; 10 <= 10 funcoes).

Metrica observada igual a prevista (`relatorios/fase2/L13/metric.json`): 167.059 de 174.276 (95,8589%), 1.451 funcoes, 23.721 entradas, `entries_not_covered` 0. `codegen_audit_game.py` STATUS CLEAN (`relatorios/fase2/L13/audit.txt`): 0 sites de `call_by_address` indireto. Build incremental `build-auto-p2infra` (`reused_build` true) com `exit_code` 0 em 146,2 s (`relatorios/fase2/L13/build/build.json`).

Rotas (checkpoint, as quatro completas): `boot_to_fight` (48 passos; `miss_total` 0 em `telemetry_luta_final.json`), `survey_post_fight` (332 passos, 58 snapshots de misses), `survey_modes` (446 passos, 99 snapshots de misses) e `survey_options` (417 passos, 90 snapshots de misses), `miss_total` 0 nas telemetrias finais; so os seis PCs da quarentena interpretados, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`, o mesmo conjunto do F2-L12; em `survey_options`, tambem o mesmo conjunto do F2-L10. Nenhum PC novo.

As cinco raizes nao estavam nos alvos do fntrace (`survey_post_fight/fntrace_alvos.json`, `survey_modes/fntrace_alvos.json` e `survey_options/fntrace_alvos.json` nao citam os seus enderecos; `boot_to_fight` nao tem arquivo de fntrace): sem execucao observada, o que nao prova que nao sao chamadas.

Proximo candidato: F2-L14 (promovido). Evidencias em `relatorios/fase2/L13/`.

**F2-L14 (2026-11-25, sem checkpoint de quatro rotas):** oito raizes estaticas, todas sem execucao observada: `0x801287CC` (ponteiro unico `0x801B03C8`, tabela de handlers; fecha 3 funcoes, +68 palavras, +12 entradas), `0x80131A3C` (ponteiro `0x801ABAA8`, par de callbacks logo apos a string "HIT", ao lado de `0x801317E4` (`0x801ABAA4`, seed desde S1-160, que termina em `0x80131A3B`); a descricao anterior `{"HIT", funcao, 0x20, 0x21}` foi corrigida na revisao do checkpoint F2-L15; origem estatica, ja excluida em F2-L6 e reavaliada na decodificacao do EXE; fecha 1 funcao, +212 palavras, +16 entradas), `0x8019735C` (ponteiro `0x801B85C8`; +5 palavras, 1 funcao, +1 entrada), `0x80197370` (ponteiro `0x801B85B4`; +20 palavras, 1 funcao, +4 entradas), `0x8019743C` (ponteiro `0x801B85A4`, tabela `0x801B85A4..`; +9 palavras, 1 funcao, +2 entradas), `0x8019FA90` (ponteiro `0x801BEEA8`, tabela `0x801BEE90..`; +34 palavras, 1 funcao, +6 entradas), `0x8019FCE4` (`lui/addiu` em `0x8019FC54`, codigo coberto, callback; +11 palavras, 1 funcao, +3 entradas) e `0x801A74F8` (`lui/addiu` em `0x801A7474`, codigo coberto, registro de callback; +10 palavras, 1 funcao, +2 entradas). Origens em `PlusAlphaProject/seeds/entry_funcs.txt` (comentario do lote) e em `relatorios/fase2/scan_L15/candidatos.json`.

Pre-auditoria (`seed_preview.py` contra a base F2-L13, 167.059 palavras, 1.451 funcoes, 23.721 entradas; `relatorios/fase2/L14/preview.txt`): +369 palavras, +10 funcoes, +46 entradas; 0 perdas; 0 em quarentena; 0 `jalr`; 0 `jr` nao-`$ra`; 0 SMC; orcamento OK.

Metrica observada igual a prevista (`relatorios/fase2/L14/metric.json`): 167.428 de 174.276 (96,0706%), 1.461 funcoes, 23.767 entradas, `entries_not_covered` 0. `codegen_audit_game.py` STATUS CLEAN (`relatorios/fase2/L14/audit.txt`): 0 chamadas diretas nao resolvidas, 0 misses de `call_by_address` (in-code e RAM), 0 tail-call misses, 0 gotos nao resolvidos. Build incremental `build-auto-p2infra` (`reused_build` true) com `exit_code` 0 em 133,8 s (`relatorios/fase2/L14/build/build.json`).

Rotas: `boot_to_fight` (48 passos; `miss_total` 0 em `telemetry_luta_final.json`), `survey_post_fight` (332 passos, 58 snapshots de misses) e `survey_modes` (446 passos, 99 snapshots de misses), `miss_total` 0 nas telemetrias finais; so os seis PCs da quarentena interpretados, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`, o mesmo conjunto do F2-L13; nenhum PC novo. `survey_options` nao foi rodada (checkpoint de quatro rotas feito no F2-L15).

As oito raizes nao aparecem nos alvos do fntrace de `survey_modes/fntrace_alvos.json` e `survey_post_fight/fntrace_alvos.json`, e `boot_to_fight` nao tem arquivo de fntrace: sem execucao observada, o que nao prova que nao sao chamadas.

Status: sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario.

Varredura `scan_L15` (`relatorios/fase2/scan_L15/classificacao_faixas.json`, 152 faixas, soma 7.217 palavras sem cobertura antes do L14 = 174.276 - 167.059): 4.016 palavras em 72 faixas sem referencia estatica no EXE nem nos 59 overlays (classe "orfao sem referencia (codigo plausivel)"; exigem evidencia de execucao, a hipotese de SDK sem uso ainda nao e provada); 2.119 em 17 faixas alcancaveis so por jump table ou `jalr` (investigacao F2-Rx); 348 em 13 faixas com raiz auditavel; 327 encadeadas a orfao; 280 nas duas raizes `0x801287CC` e `0x80131A3C` (fila L14); 96 em fragmentos sem borda; 31 de zeros (padding). Os numeros de `scan_L15/categorias.json` (585, 2.169, 3.714) somam 7.317 e nao batem com a classificacao por faixa; por isso nao sao usados aqui.

Bloqueados por jump table na epoca do F2-L14 (aguardavam F2-Rx, `relatorios/fase2/fila.json`): `0x80147624`, `0x80135608`, `0x801477F8` e `0x80135848`. **Superado no F2-L16:** `0x80147624` e `0x80135608` foram promovidos; `0x801477F8` e `0x80135848` fecham com eles.

Proximo candidato: F2-L15 (promovido). Evidencias em `relatorios/fase2/L14/`.

**F2-L15 (2026-11-25, checkpoint de quatro rotas; ultimo lote de raizes auditaveis da varredura `scan_L15`):** oito raizes estaticas, todas sem execucao observada: `0x8012DB4C` (ponteiro `0x801B1BC4`, tabela `0x801B1BC0..`; +85 palavras, 3 funcoes, +24 entradas), `0x80118010` (ponteiro `0x801AFCC4`; +2 palavras, 1 funcao, +1 entrada; borda `jr ra`+delay), `0x80118018` (ponteiro `0x801AFCC8`; +2, 1, +1; borda em prologo), `0x801627A4` (ponteiro `0x801B3404`, tabela `0x801B33F0..`; +2, 1, +1), `0x8016280C` (ponteiro `0x801B340C`; +15, 1, +3), `0x80162AA8` (ponteiro `0x801B341C`; +28, 1, +7), `0x8016313C` (ponteiro `0x801B3428`; +56, 1, +8) e `0x80196B18` (ponteiro `0x801B85D8`, tabela `0x801B85A4..`; +6, 1, +1; borda `jr ra`+delay). Todas tem origem de tier T1 (ponteiro em tabela de dados com vizinhos cobertos; `relatorios/fase2/scan_L15/candidatos.json`).

Pre-auditoria (`seed_preview.py` contra a base F2-L14, 167.428 palavras, 1.461 funcoes, 23.767 entradas; `relatorios/fase2/L15/preview.txt`): +196 palavras, +10 funcoes, +46 entradas; 0 perdas; 0 em quarentena; 0 `jalr`; 0 `jr` nao-`$ra`; 0 SMC; orcamento OK.

Metrica observada igual a prevista (`relatorios/fase2/L15/metric.json`): 167.624 de 174.276 (96,1831%), 1.471 funcoes, 23.813 entradas, `entries_not_covered` 0. `codegen_audit_game.py` STATUS CLEAN (`relatorios/fase2/L15/audit.txt`): 0 chamadas diretas nao resolvidas, 0 misses de `call_by_address` (in-code e RAM), 0 tail-call misses, 0 gotos nao resolvidos. Build incremental `build-auto-p2infra` (`reused_build` true) com `exit_code` 0 em 126,0 s (`relatorios/fase2/L15/build/build.json`).

Rotas (checkpoint, as quatro completas): `boot_to_fight` (48 passos; `miss_total` 0 em `telemetry_luta_final.json`), `survey_post_fight` (332 passos, 58 snapshots de misses), `survey_modes` (446 passos, 99 snapshots de misses) e `survey_options` (417 passos, 90 snapshots de misses), `miss_total` 0 nas telemetrias finais; so os seis PCs da quarentena interpretados, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`, o mesmo conjunto do F2-L14 (e, em `survey_options`, tambem o do F2-L13); nenhum PC novo.

As oito raizes nao aparecem nos alvos do fntrace de `survey_modes/fntrace_alvos.json`, `survey_post_fight/fntrace_alvos.json` e `survey_options/fntrace_alvos.json` (nenhuma com hit), e `boot_to_fight` nao tem arquivo de fntrace: sem execucao observada, o que nao prova que nao sao chamadas.

Status: sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario.

Fronteira da Fase 2: com o F2-L15 esgotam-se as raizes estaticas auditaveis encontradas pelas varreduras `scan_L7` e `scan_L15`. Restam 6.652 palavras sem cobertura no fechamento do L15 (174.276 - 167.624; com o denominador corrigido e o F2-L16, restam 5.592, ver F2-L16). Pela classificacao por faixa de `relatorios/fase2/scan_L15/classificacao_faixas.json` (152 faixas; 7.217 palavras medidas antes do L14, das quais 565 foram promovidas em L14 e L15): ~2.119 palavras so alcancaveis por jump table ou `jalr` (17 faixas; candidatos citados `0x80135608`, `0x80135848`, `0x80147624`, `0x801477F8`, `0x8010F290`, `0x8018D974`, `0x8019F9E4`, `0x80193474`, `0x801935BC`, `0x801A15A8`, `0x801AB180`), que exigem investigacao F2-Rx (resolvedor de jump table); ~4.016 palavras orfas, sem referencia estatica no EXE nem nos overlays (hipotese: SDK sem uso), que so viram seed com evidencia de execucao ou decisao explicita do usuario; ~327 encadeadas a orfaos; ~96 em fragmentos sem borda de funcao e ~31 em zeros soltos (possivel ajuste de exclusoes). As 63 palavras restantes (6.652 = 6.589 + 63) estao na classe "raiz auditavel" da varredura, sem candidato atribuido no arquivo; `candidatos.json` marca `0x8019F9E4` como JT e `0x801A15A8` como jalr, o que sugere, mas nao prova, que sejam essas. O proximo passo deixa de ser micro-lote de seeds e passa a ser: (1) investigacao F2-Rx das jump tables (feita, sem mudanca no recompilador; ver F2-L16); (2) decidir a politica para orfaos (armar fntrace em rotas novas, ou aceitar raizes estaticas sem referencia); (3) revisar exclusoes de padding (feito no F2-L16).

**F2-L16 (2026-11-25, checkpoint de quatro rotas; primeiro lote com jump table promovida):** duas raizes adiadas no F2-L10 por `jr` nao-`$ra` no fechamento: `0x80135608` (ponteiro `0x801B1C08`; `jr v0` em `0x80135898`, jump table `0x801ABBEC` com 5 alvos, switch em `func_80135848`, que fecha no lote) e `0x80147624` (ponteiro `0x801B1B8C`; `jr v0` em `0x80147CD8`, jump table `0x801ABC6C` com 6 alvos, switch em `func_801477F8`, que fecha no lote). Os dois `jr` nao-`$ra` do fechamento sao essas tabelas. O resolvedor da F2-R1 (`psxrecomp/recompiler/src/function_analysis.cpp:764`, `resolve_exact_bounded_jump_table`) as resolve: o C gerado no build do lote traz `/* jump table 0x801ABBEC, 5 entries */` (`build-auto-p2infra/generated/SLUS_005.48_full_15.c:5490`) e `/* jump table 0x801ABC6C, 6 entries */` (`SLUS_005.48_full_20.c:10998`). Esses dois `jr` nao aparecem nos JSON de `relatorios/fase2/R1/` (`exe_jr_resolvidos.json` e `aot_jr_resolvidos.json`), que foram gerados antes deste lote, quando essas funcoes nao estavam no fechamento. Os ponteiros ficam contiguos as tabelas `0x801B1B64` e `0x801B1C0C`, promovidas no F2-L8. Origem: `PlusAlphaProject/seeds/entry_funcs.txt` (comentario do lote) e `relatorios/fase2/fila.json`.

Pre-auditoria (`seed_preview.py` contra a base F2-L15, 167.624 palavras, 1.471 funcoes, 23.813 entradas; `relatorios/fase2/L16/preview.txt`): +1.030 palavras, +5 funcoes, +125 entradas (`0x80135608`: +425 palavras, 2 funcoes, 71 entradas; `0x80147624`: +605 palavras, 3 funcoes, 54 entradas); 0 perdas; 0 em quarentena; 0 `jalr`; 0 SMC; 2 `jr` nao-`$ra` no fechamento (`0x80135898` e `0x80147CD8`, as duas tabelas); orcamento OK (1.030 <= 1.200 palavras; 5 <= 10 funcoes). O percentual previsto pelo preview (96,7741%) usa o denominador antigo de 174.276.

Metrica observada igual a prevista (`relatorios/fase2/L16/metric.json`): 168.654 de 174.246 (96,7907%), 1.476 funcoes, 23.938 entradas, `entries_not_covered` 0. Build incremental `build-auto-p2infra` ok em 203,8 s (`relatorios/fase2/L16/build_stdout.txt`). `codegen_audit_game.py` STATUS CLEAN sobre o C gerado do build do lote (`relatorios/fase2/L16/audit_build.txt`): 1.476 funcoes, 23.938 entradas no despachante (iguais a `metric.json`), 0 chamadas diretas nao resolvidas, 0 `call_by_address` em codigo, 0 misses de cauda e 0 gotos sem rotulo. Atencao: `--config PlusAlphaProject/build-auto-p2infra/game.toml` resolve `out_dir = "generated-online"` a partir da raiz do projeto, isto e, audita `PlusAlphaProject/generated-online` (a ultima geracao de release) e nao `build-auto-p2infra/generated`; por isso `relatorios/fase2/L16/audit.txt` mostra 1.471 funcoes e 23.813 entradas. Para o L16 a auditoria foi refeita com um toml temporario apontando `out_dir` para `build-auto-p2infra/generated`. Auditorias de lotes anteriores feitas com o comando da skill podem ter lido `generated-online`.

Correcao do denominador (`PlusAlphaProject/coverage/exclusions.json`, ver `git diff`): a faixa `0x801AB370..0x801AB380` saiu do padding porque `0x801AB370` e delay slot do `jr ra` em `0x801AB36C` (codigo); a faixa passa a ser `0x801AB374..0x801AB380`. Foram acrescentadas 31 faixas de 1 palavra de padding de alinhamento (zero apos delay slot de `j`/`jr`, seguido de inicio de funcao, sem referencia). Liquido: denominador do EXE 174.276 -> 174.246 (-30). Com o denominador corrigido, o estado do F2-L15 seria 167.624 / 174.246 = 96,1996%. Os percentuais anteriores (F2-L1 a F2-L15 e secao 2) usavam 174.276.

Rotas (checkpoint, as quatro completas): `boot_to_fight` (48 passos; `miss_total` 0 em `telemetry_luta_final.json`), `survey_post_fight` (332 passos, 58 snapshots de misses, `miss_total_max` 0), `survey_modes` (446 passos, 99 snapshots, `miss_total_max` 0) e `survey_options` (417 passos, 90 snapshots, `miss_total_max` 0); `passos_falha` vazio nas quatro (`relatorios/fase2/L16/agregado_rotas.json`). Os PCs do EXE interpretados sao os seis da quarentena, `0x801AB1F4`, `0x801AB208`, `0x801AB21C`, `0x801AB2C0`, `0x801AB2DC` e `0x801AB2E8`, sem PC novo. Divergencia nao resolvida: `agregado_rotas.json` lista so cinco PCs em `boot_to_fight` (sem `0x801AB2E8`), mas `telemetry_luta_final.json` lista os seis (`0x801AB2E8`, 956 hits). `survey_post_fight` teve `display_retries` 2, sem falha de passo.

Execucao observada dos alvos novos: nenhuma. `0x80135608`, `0x80147624`, `0x80135848` e `0x801477F8` nao aparecem nas listas de fntrace de `PlusAlphaProject/tools/auto_routes/*.json` e nao tem hit em `agregado_rotas.json` (`boot_to_fight` nao tem fntrace). Isso nao prova que nao sao chamadas.

Contador da quarentena (suspeita de contador congelado, resolvida como execucao so no boot; `relatorios/fase2/L16/quarentena_contador_resumo.json` e `quarentena_contador.json`): no mesmo processo de `survey_modes`, `insns_run` do interpretador cresceu de 1.000.427 (frame 2013) para 2.238.724 (frame 38067), enquanto os seis PCs ficaram fixos (`0x801AB2DC` 190.244 hits, `0x801AB208` 28.200, `0x801AB1F4` 9.400, `0x801AB21C` 9.400, `0x801AB2C0` 956, `0x801AB2E8` 956) em 99, 90 e 58 leituras de `survey_modes`, `survey_options` e `survey_post_fight`. O contador incrementa so em despacho nao forcado (`psxrecomp/runtime/src/dirty_ram_interp.c:3157-3159`). Conclusao registrada: esses PCs executam numa fase deterministica do boot, e nao depois; as contagens deles nao servem como evidencia de execucao por rota. O amostrador tem bug reconhecido em `dirty_pcs_6` (sem contagem por PC); as contagens por PC vem das series `misses_*.json`.

F2-Rx (investigacao da fronteira jump table/jalr, sem mudanca no recompilador; `git status` mostra alteracoes so em `PlusAlphaProject/coverage/exclusions.json` e `PlusAlphaProject/seeds/entry_funcs.txt`): dos 11 sitios de `relatorios/fase2/fila.json` (9 jump tables e 2 `jalr`), 4 ficam cobertos com o L16 (`0x80135608` e `0x80147624` como seeds; `0x80135848` e `0x801477F8` pelo fechamento) e 7 seguem `pendente` sem pre-auditoria individual: `0x801A15A8` (+20, `jalr`), `0x8019F9E4` (+46, ponteiro `0x801BEEA0`), `0x8010F290` (+100, so borda), `0x8018D974` (+424, so borda), `0x80193474` (+38), `0x801935BC` (+34) e `0x801AB180` (+41, `jalr`). Os tres ultimos nao tem referencia estatica e ficam perto de SDK, BIOS e quarentena. Assim, a afirmacao de que os 11 sitios se resolvem por seeds ainda nao vale para os 7 pendentes.

Faixas com `jalr` em `relatorios/fase2/scan_L15/classificacao_faixas.json`: 9 faixas com `jalr` > 0 e classe "so por jump table/jalr (investigador)" somam 498 palavras e 16 destinos entre `0x801946E0` e `0x8019F558`. Elas nao estao na classe "orfao sem referencia", que soma 4.016 palavras em 72 faixas; por isso nao sao contadas como orfas. A nota de `relatorios/fase2/fila.json` (~2.169 palavras e ~3.714 orfas) esta desatualizada frente a classificacao (2.119 e 4.016). Melhoria de ferramenta sugerida, sem implementacao: `PlusAlphaProject/tools/seed_preview.py`, funcao `scan_words` (linhas 63-73), contar separadamente o `jr` nao-`$ra` resolvido por jump table, para que as duas tabelas do L16 nao aparecam como pendencia.

Proximo candidato: nenhum promovido neste checkpoint; os 7 pendentes estao em `relatorios/fase2/fila.json`. Evidencias em `relatorios/fase2/L16/`.

Status: Sem regressao nas rotas (miss_total 0); raizes sem execucao observada; pendente validacao de sensacao do usuario.
