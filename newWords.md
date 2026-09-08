# New Words Inventory (Static & Dynamic Promotion Tracker)

This document is the official tracking registry for newly discovered functions, static promotion micro-batches, and coverage baselines in the *Street Fighter EX Plus Alpha* (`SLUS-005.48`) static recompilation project.

For full reverse engineering notes, pre-audit breakdowns, incident reports, and deep historical logs, refer to [`buildResume.md`](buildResume.md).

---

## 1. Governance & Maintenance Rules

1. **Observed PC $\neq$ Function Root**: Runtime hits may point to internal blocks, return sites, jump table targets, or trampolines. Only audited function entry points qualify as seeds.
2. **Promotion Requirement**: A micro-batch is only marked as `processed` after its boundaries, callers, internal aliases, reachable closure, indirect jumps, telemetry validation, and regressions pass with zero defects.
3. **Hard Budget Gate**: No seed may be added to `seeds/entry_funcs.txt` without an isolated pre-audit measuring the full reachable closure. If the expanded closure exceeds the budget, the candidate is rejected or quarantined.
4. **Interpreter Quarantine for SMC/Hardware**: Self-modifying code and direct hardware MMIO busy-wait loops (such as the PSX BIOS Joypad/SIO hook at `0x801AB1F4` and `0x801AB2C0`) must remain interpreted to guarantee input timing and prevent execution deadlocks.

---

## 2. Current Baseline Status

- **Validated Checkpoint**: **S1-267** (Round State Manager verified clean in gameplay-discovery-02; eliminated 10 FSM misses, +40k native dispatches).
- **Current Active Batch**: None (S1-267 promoted and verified).
- **Current Main Binary Coverage**: **126,371 / 195,584 words (64.6121%)**.
- **Total Compiled Native Functions**: **1,109 functions**.
- **Codegen Audit Status**: **CLEAN** (0 unresolved direct calls, 0 call_by_address misses, 0 tail-call misses, 0 unresolved gotos).
- **Residual Menu Misses**: 0 actionable misses (the remaining 2 hits are quarantined SMC hooks).

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


- **Total words promoted since S1-239**: **+20,052 words** (+10.25% absolute gain).

---

## 4. Dynamic Overlay Track Summary

Dynamic battle overlays (`0x80020000..0x800F2000`) are compiled on-demand via the overlay cache framework:
- **OVL-001A (`0xAC1FF1A4`)**: 4,563 words compiled (64 entries). Validated clean at 60 FPS over 3 complete matches.
- **OVL-001B (`0x94E6122F`)**: 5,313 words compiled (122 entries). Integrated under S1-261 clean baseline.
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
| `0x8019E6D0` | Non-reproducible historical candidate (`deferred_watchlist.txt`) | Quarantine (no seed) |
| `0x80103384..0x801038B4` | Global root previously quarantined under S1-261 | Resolved via S1-262 |
