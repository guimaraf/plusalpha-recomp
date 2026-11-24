# Project Progress Status: Street Fighter EX Plus Alpha (SLUS-005.48)

## 1. Track 1: Static Recompilation (Main EXE)
- **Official metric (Phase 0, 2026-11-24)**: `python PlusAlphaProject/tools/coverage_metric.py` (guard: `--check` against `PlusAlphaProject/coverage/baseline.json`; exclusions in `PlusAlphaProject/coverage/exclusions.json`).
- **Native Functions**: 1.359 (`generated-online`; S1-309 `generated/` had 1.358)
- **Recompiled Words (unique)**: 154.639 of 174.276 code words — **88,7322%** of real code; 79,07% of the full 195.584-word text segment, which includes 21.254 words of trailing data.
- **Dispatcher entries**: 21.908 (all inside compiled ranges).
- **Correction**: the previous figure of 154.846 words (79,1711%) summed `R` lines of the manifest, and three alias entries repeat the same range (`0x8013B070`, `0x8013B10C`, `0x8019CB4C`, 202 words counted twice). The unique S1-309 count was 154.644. The current online generation lost a further 5 words (`0x8019CB8C..0x8019CB9F`) and the entry `0x8019CB8C`.
- **Misses in Gameplay, Menus, Pause, Command List, Bonus Stage, and Expert Mode**: 0 (100% native across all execution paths)
- **Main Pause Menu (`0x80172DD0..0x8017566C`)**: VALIDATED (S1-306, Test 164)
- **Command List & 3D Submenus (`0x80183734..0x80185CC0` and GTE `0x8019`)**: VALIDATED (S1-307, Test 165)
- **Bonus Stage (Barrel), Option→Bonus Transition, and Records/Initials Screen (`0x801495D4..0x8014B21C`, `0x8016F668..0x8016FB64`, `0x80181F7C..0x80183734`)**: VALIDATED (S1-308, Test 167 — 0 misses)
- **Expert Mode Dispatcher (`0x8014C6E0`)**: VALIDATED (S1-309, Tests 173-174 — 0 misses)

## 2. Track 2: Dynamic Recompilation (Combat Overlays and Special Modes)
- **Native DLLs in Cache**: 2.216 DLLs (+76 new Expert Mode DLLs: Tests 172-174)
- **Unique Functions in DLLs**: 3.840 unique functions
- **Roster Coverage**: 26/26 fighters (100% validated: 23 playable + 3 CPU bosses)
- **Projectile / Fire Engines**: 14/14 routines validated (100%)
- **Bonus Stage (Barrel) & Replay (Track 2)**: 100% VALIDATED (Test 171 — +4,09M native dispatches, 0 static misses, elimination of 288M overlay instructions).
- **Expert Mode (Ken Challenges & Combo Logic - Track 2)**: 100% VALIDATED (Test 174 — +590k native dispatches, elimination of 99,83% of overlay instructions, 0x80047E78 and 0x800E64D8 reduced to zero).
- **Training Mode (Ken x Ryu & Combos & Pause - Track 2)**: 100% VALIDATED (Test 179 — +675k native dispatches, 0 native handoffs, 0 static misses, 0 interpreted game-code instructions, 4 roots in game.toml: 0x80047E78, 0x80046BC8, 0x8004649C, 0x80044818).

## 3. Consolidated Native Total (Track 1 + Track 2)
- **Total Native Functions**: 5.201 (1.358 static + 3.843 dynamic)
- **Total Native Code**: 1.358 static functions + 2.219 active cached DLLs
- **Overall Project Status**: Track 1 100% validated; Track 2 (26/26 Roster + Projectiles + Bonus Stage + Expert Mode + Training Mode) 100% validated. Solid 60.0 FPS in all modes.
