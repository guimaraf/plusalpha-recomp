# Validation of CPU-Controlled Characters (Combat AI)

This document tracks native coverage and validation progress for all 26 characters (23 standard + 3 unlockable CPU boss variants) in *Street Fighter EX Plus Alpha* (`SLUS-005.48`) when controlled by CPU Artificial Intelligence.

---

## 1. CPU AI Architectural Overview

The game's combat artificial intelligence system consists of three layers:

1. **Decision and Strategy Core (Core AI Engine - `0x80155000..0x80158500`)**:
   - Distance assessment (neutral spacing).
   - Defensive reaction (high/low blocking, recovery after knockdown).
   - Chaining normal attacks, special moves, and *Super Cancels*.
   - Super-meter and aggression management according to difficulty level.
   - *Note*: Part of this layer was already validated in batch **S1-291** (Dummy/Training Cluster: 7 functions, 250 words at `0x801555A8..0x80156AD0`).
2. **Per-Character Move Data Tables (`0x801B0000..0x801B6000`)**:
   - Static data containing each move's priority weights and fighter-specific combo routes.
3. **Move-Specific Dispatches (`0x80126...`, `0x80129...`, `0x8014C...`, `0x80160...`)**:
   - Kinematic and physics functions triggered when the CPU selects an attack route.

---

## 2. Standardized Testing Methodology

To isolate CPU behavior without depending on Arcade/Survival randomness:

1. **Environment**: **Versus** mode with **Controller 2 disconnected** (automatic activation of P2 = COM / CPU).
2. **Difficulty Setting (Game Level)**:
   - Set **Game Level to MAXIMUM (Level 8 / Hardest)** in the *Options* menu.
   - **Technical Rationale**: Lower levels introduce artificial pauses (*idle frames*) and low reaction probabilities. At the maximum level, the CPU eliminates waiting windows, actively seeks *hit-confirms*, chains complex combos, executes *Super Cancels* as soon as the meter fills, and stresses the deepest reversal and rapid-approach routines.
3. **Player 1 Behavior**:
   - Do not attack.
   - Stay defensive (standing/crouching blocks, absorbing damage, allowing the CPU to fill its super meter).
   - Allow the CPU to exercise its entire action tree: approach (*footsies*), chained normals, specials, supers, and finishing combos.
4. **Telemetry Flow**:
   - Snapshot **before**: At the start of Round 1 (after the announcer says "Fight").
   - Gameplay: Defend and receive attacks until defeat / KO.
   - Snapshot **after**: Immediately after KO (during replay / victory pose).

---

## 3. Roster Tracking Table (CPU AI)

| # | Character | Status CPU | Telemetry Session | Main EXE Candidates | Notes |
|:---:|:---|:---:|:---:|:---:|:---|
| 1 | **Ryu** | Validated (Core AI) | `discovery-74` | **ZERO CANDIDATES** (100% native in the Main EXE) | Core AI Engine (`0x801550C8..0x80158500`) 100% native. Next target: fighter-specific dispatches for other characters. |
| 2 | **Ken** | Validated | `discovery-75` | **ZERO CANDIDATES** (100% native in the Main EXE) | 276.036 static hits, 0 misses in the Main EXE. Flaming Shoryuken, Shoryu Reppa, and Shinryuken fully covered in the static binary. |
| 3 | **Chun-Li** | Validated | `discovery-76` | **ZERO CANDIDATES** (100% native in the Main EXE) | 279.897 static hits, 0 misses in the Main EXE. Hyakuretsukyaku, Kikoken, Senretsukyaku and Hazanshou 100% native. Isolated micro-fluctuations in dynamic RAM (52,6M overlay insns cataloged for Track 2). |
| 4 | **Guile** | Validated | `discovery-78` | **ZERO CANDIDATES** (100% native in the Main EXE) | 1.134.699 static hits, 0 misses in the Main EXE over 4 fights. Both charge Supers (*Somersault Strike* and *Opening Gambit*) confirmed and 100% native. |
| 5 | **Zangief** | Validated | `discovery-79` | **ZERO CANDIDATES** (100% native in the Main EXE) | 778.583 static hits, 0 misses in the Main EXE over 3 fights. Spinning Piledriver, Double Lariat, Banishing Flat and Final Atomic Buster 100% native. |
| 6 | **Dhalsim** | Validated | `discovery-81` | **ZERO CANDIDATES** (100% native in the Main EXE) | 1.054.833 static hits, 0 misses in the Main EXE over 3 fights. Elastic limbs, Yoga Fire, and Yoga Inferno 100% native (Drill kinematics already covered in S1-287). |
| 7 | **Hokuto** | Validated | `discovery-85` | **ZERO CANDIDATES** (100% native in the Main EXE) | 993.384 static hits, 0 misses in the Main EXE over 3 fights. Weapon and prop pipeline (`0x80164D9C..0x80166170`) fully promoted through S1-301 and S1-302. |
| 8 | **Cracker Jack** | Validated | `discovery-86` | **ZERO CANDIDATES** (100% native in the Main EXE) | 360.153 static hits, 0 misses in the Main EXE. Boxing rushes, baseball swings, and supers 100% native (uppercut kinematics covered in S1-280). |
| 9 | **Doctrine Dark** | Validated | `discovery-87` | **ZERO CANDIDATES** (100% native in the Main EXE) | 376.111 static hits, 0 misses in the Main EXE. Kill Wire, cable/electric shock, knives (Kill Blade), land mines, and supers 100% native in the static binary. |
| 10 | **Pullum Purna** | Validated | `discovery-89` | **ZERO CANDIDATES** (100% native in the Main EXE) | 649.143 static hits, 0 misses in the Main EXE over 2 fights. Spins, Drill Purrus, and acrobatic dances 100% native (shared limb kinematics engine). |
| 11 | **Darun Mister** | Validated | `discovery-90` | **ZERO CANDIDATES** (100% native in the Main EXE) | 697.776 static hits, 0 misses in the Main EXE over 3 fights. Lariats, Ganges DDT, Indra Bridge, and throw supers 100% native (global table 0x801B33F0 and grappler physics). |
| 12 | **Kairi** | Validated | `discovery-92` | **ZERO CANDIDATES** (100% native in the Main EXE) | 481.577 static hits, 0 misses in the Main EXE over 2 fights. Shinki Hatsu Dou, Maryu Rekkou, and combat sub-cluster (`0x80162244..0x80162570`) 100% native through S1-303. |
| 13 | **Sakura** | Validated | `discovery-93` | **ZERO CANDIDATES** (100% native in the Main EXE) | 982.944 static hits, 0 misses in the Main EXE over 3 fights. Elimination of all 9 legacy candidates from `discovery-63` (Core AI promoted in S1-293..S1-300). Hadoken, Shouoken, Shunpukyaku and Haru Ichiban 100% native. Isolated micro-fluctuations in dynamic RAM (164,6M overlay insns cataloged for Track 2). |
| 14 | **Blair Dame** | Validated | `discovery-94` | **ZERO CANDIDATES** (100% native in the Main EXE) | 416.982 static hits, 0 misses in the Main EXE. Shoot Upper, Slider, Mirage Kick, Spinning Knee and Super Mirage Combination 100% native. 55,4M dynamic overlay insns archived for Track 2. |
| 15 | **Allen Snider** | Validated | `discovery-95` | **ZERO CANDIDATES** (100% native in the Main EXE) | 210.044 static hits, 0 misses in the Main EXE. Soul Force, Rising Dragon, Justice Fist, Vaulting Kick and Fire Force 100% native. 29,5M dynamic overlay insns archived for Track 2. |
| 16 | **Skullomania** | Validated | `discovery-96` | **ZERO CANDIDATES** (100% native in the Main EXE) | 306.039 static hits, 0 misses in the Main EXE. Skullo Crusher, Skullo Slider, Skullo Head, Skullo Dive, Skullo Dash and Super Skullo Slider 100% native. 35,3M dynamic overlay insns archived for Track 2. |
| 17 | **Akuma** | Validated | `discovery-97` | **ZERO CANDIDATES** (100% native in the Main EXE) | 455.919 static hits, 0 misses in the Main EXE. Gou Hadoken (ground/air), Shakunetsu, Gou Shoryuken and Tatsumaki 100% native. 82,4M dynamic overlay insns archived for Track 2. |
| 18 | **Garuda** | Validated | `discovery-98` | **ZERO CANDIDATES** (100% native in the Main EXE) | 289.224 static hits, 0 misses in the Main EXE. Shusui, Kizan, Raiga, Soukon Dan and Kienshou 100% native. 48,7M dynamic overlay insns archived for Track 2 (blade spin 0x80092294). |
| 19 | **M. Bison** | Validated | `discovery-99` | **ZERO CANDIDATES** (100% native in the Main EXE) | 564.441 static hits, 0 misses in the Main EXE over 2 fights. Psycho Crusher, Scissor Kick, Head Press and Knee Press Nightmare 100% native. 67,9M dynamic overlay insns archived for Track 2. |
| 20 | **Cycloid-β** | Validated | `discovery-100` | **ZERO CANDIDATES** (100% native in the Main EXE) | 376.839 static hits, 0 misses in the Main EXE. Hybrid moveset and knife/blade Super 100% native. 43,0M dynamic overlay insns archived for Track 2. |
| 21 | **Cycloid-γ** | Validated | `discovery-101` | **ZERO CANDIDATES** (100% native in the Main EXE) | 294.501 static hits, 0 misses in the Main EXE. Hybrid moveset, teleport, and aerial kick Super 100% native. 33,8M dynamic overlay insns archived for Track 2. |
| 22 | **Bloody Hokuto** | Validated | `discovery-102` | **ZERO CANDIDATES** (100% native in the Main EXE) | 235.842 static hits, 0 misses in the Main EXE. Dagger pipeline, fast slashes, and 2 Supers 100% native (S1-301/S1-302). 27,6M dynamic overlay insns archived for Track 2. |
| 23 | **Evil Ryu** | Validated | `discovery-103` | **ZERO CANDIDATES** (100% native in the Main EXE) | 360.870 static hits, 0 misses in the Main EXE. Dark Hadouken, Shoryuken, Ashura Senku and 2 Supers 100% native. 71,1M dynamic overlay insns archived for Track 2. |
| 24 | **Akuma (CPU / Boss)** | Validated | `discovery-104` / `discovery-109` | **ZERO CANDIDATES** (100% native in the Main EXE) | 415.845 static hits (CPU) and 3.584.080 static hits (P1), 0 misses in the Main EXE. Boss variant, double Zanku Hadoken, Shun Goku Satsu and supers 100% native and validated in `discovery-109`. 74,6M dynamic overlay insns archived for Track 2. |
| 25 | **Garuda (CPU / Boss)** | Validated | `discovery-105` / `discovery-108` | **ZERO CANDIDATES** (100% native in the Main EXE) | 356.634 static hits (CPU) and 3.484.378 static hits (P1), 0 misses in the Main EXE. Boss variant, super armor, blades, Super Kienshou, and exclusive defensive counterattack (Table 0x801B33F0 slot 12 promoted in S1-304) 100% native with ZERO candidates in `discovery-108`. 60,1M dynamic overlay insns archived for Track 2. |
| 26 | **M. Bison (CPU / Boss)** | Validated | `discovery-106` / `discovery-110` | **ZERO CANDIDATES** (100% native in the Main EXE) | 297.756 static hits (CPU) and 3.399.945 static hits (P1), 0 misses in the Main EXE. Final boss, continuous teleport, Psycho Crusher and Super 100% native and validated in `discovery-110`. 34,5M dynamic overlay insns archived for Track 2. |

---

## 4. CPU AI Promotion Strategy

Due to the engine's modular architecture:
- Promoting the functions of the **Core AI Engine (`0x80155000..0x80158500`)** will bring cumulative global gains for all fighters.
- For each tested character, we will first promote common AI engine functions, followed by any discovered move-specific dispatches.
