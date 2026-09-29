# Projectile Collision and Interaction Catalog (Track 2 - RAM Overlay)

This document records the reverse engineering mapping of **projectile collision, absorption, reflection, mutual cancellation, and hit-stop** routines executed in the dynamic RAM combat subsystem (`0x80020000..0x800F2000`).

These routines will be compiled and promoted together after roster mapping.

---

### 1. Identified Global Projectile Structures and Offsets

| Register / Offset | Architectural Description |
|:---|:---|
| `offset 0x1354($s0)` | Array of the fighter's active projectile entities (`ProjectileEntity[]`). |
| `offset 0x1515($s0)` | Reaction state and projectile impact / block flags. |
| `offset 0x1F800008` | Scratchpad RAM (Fast DMA) for impact-particle transformation matrices. |

---

### 2. Cataloged Routine Table (Discovered in Combat)

| Address (PC) | Typical Instructions / Hits | MIPS Function / Diagnosis | Discovery Session | Matchup |
|:---|---:|:---|:---:|:---:|
| `0x8008E25C` | 278.449 insns (5.347 hits) | **Master projectile collision and mutual cancellation handler** (compares P1 and P2 `0x1354` structs). | `discovery-132` | Ryu x Guile |
| `0x8008FC6C` | 112.366 insns (5.914 hits) | **Projectile hit-stop processor** hitting guard or target. | `discovery-132` | Ryu x Guile |
| `0x80091F24` | 96.632 insns (376 hits) | **Impact-particle DMA** to Scratchpad RAM (`0x1F800008`). | `discovery-132` | Ryu x Guile |
| `0x80091C60` | 94.376 insns (376 hits) | Projectile-particle dissipation subroutine after collision. | `discovery-132` | Ryu x Guile |
| `0x80090BF0` | 79.734 insns (510 hits) | Frame-flag updater for projectiles in flight. | `discovery-132` | Ryu x Guile |
| `0x8008E714` | 13.680 insns (207 hits) | **Ballistic emitter and fire physics** (Yoga Fire / Yoga Flame). | `discovery-134` | Zangief x Dhalsim |
| `0x8008E99C` | 9.012 insns (277 hits) | **Fire-sprite renderer** and flame expansion. | `discovery-134` | Zangief x Dhalsim |
| `0x8008FA1C` | 5.867 insns (494 hits) | Loop for persistence and expiration of active onscreen fire. | `discovery-134` | Zangief x Dhalsim |
| `0x8008E6C0` | 2.100 insns (207 hits) | Fire-projectile activation and range-check handler. | `discovery-134` | Zangief x Dhalsim |
| `0x8008E398` | 1.830 insns (180 hits) | Fire-impact parameter initialization subroutine. | `discovery-134` | Zangief x Dhalsim |
| `0x80047EFC` | 904.415 insns (460 hits) | **Mine / trap detonation and area damage** (*Dark EX-Plo* / *Dark Shackle*). | `discovery-135` | D. Dark x Hokuto |
| `0x8008E798` | 594.897 insns (5.836 hits) | **RAM bomb-entity updater** (`struct Entity` type `0x13`). | `discovery-135` | D. Dark x Hokuto |
| `0x80047DE8` | 158.622 insns (6.070 hits) | Land-mine planting, arming, and countdown subroutine. | `discovery-135` | D. Dark x Hokuto |
| `0x8008E394` | 370.004 insns (5.208 hits) | **Projectile impact, contact, and reflection parameters** (*Soul Force* / *Batting Hero*). | `discovery-140` | Jack x Allen |

---

### 3. Matrix of Fighters with Special Projectile Mechanics

| Fighter | Exclusive Mechanic | Expected Interaction |
|:---|:---|:---|
| **Darun Mister** | Heavy punch / Brahma Lariat | Physical projectile destruction on impact. |
| **Doctrine Dark** | *Dark Wire* / *Kill Wire* (Whip) | Projectile interception and cancellation at mid-range. |
| **Cracker Jack** | *Batting Hero* (Baseball Bat) | Ballistic reflection of the projectile back toward the opponent. |
| **Dhalsim** | *Yoga Fire* / *Yoga Flame* | Short-arc projectile and persistent fire barrier. |
| **Chun-Li** | *Kikoken* | Rapidly dissipating projectile. |
| **Guile** | *Sonic Boom* | Cutting projectile with high cancellation priority. |
| **Ryu / Ken** | *Hadouken* / *Shinku Hadouken* | Standard projectile and piercing multi-hit beam. |
| **Akuma (Gouki)** | *Gou-Hadouken* / *Zanku Hadouken* | Aerial diagonal projectile and double fire projectile. |
| **Allen Snider** | *Soul Force* | Projectile with fast recovery. |
| **Kairi** | *Shinki Hatsu Dou* | Spiritual projectile with a straight trajectory. |
| **Garuda** | *Soukon Dan* | Multiple homing projectiles. |
| **M. Bison** | *Psycho Shot* | Charged spiral projectile. |

---

### 4. Final DLL Validation and Audit (100% Covered)

Exact geometric audit performed against the **1.943 `.ranges` manifests** in the native cache (`buildTele-s1-304\cache\SLUS-00548\gcc\win-x64\cg5_562d908f\`):

| PC | Architectural Role | Status | Covering DLLs (Sample) |
|:---|:---|:---:|:---|
| `0x8008E25C` | Master collision and mutual cancellation handler | **COVERED (100%)** | `00020000_1B719044.dll`, `00020000_2ED0DEE9.dll`, `00020000_341654DA.dll` (8 DLLs) |
| `0x8008FC6C` | Projectile hit-stop processor | **COVERED (100%)** | `00020000_012D1980.dll`, `00020000_14AFBCFA.dll` (43 DLLs) |
| `0x80091F24` | Particle DMA to Scratchpad (`0x1F800008`) | **COVERED (100%)** | `00020000_0475815F.dll`, `00020000_18CC20AA.dll` (17 DLLs) |
| `0x80091C60` | Particle dissipation after impact | **COVERED (100%)** | `00020000_02CAF9C0.dll`, `00020000_1AF11F1E.dll` (19 DLLs) |
| `0x80090BF0` | In-flight frame-flag updater | **COVERED (100%)** | `00020000_0094214B.dll`, `00020000_09FB3781.dll` (29 DLLs) |
| `0x8008E714` | Ballistic fire emitter (*Yoga Fire*) | **COVERED (100%)** | `00020000_13AE697C.dll`, `00020000_1B719044.dll` (9 DLLs) |
| `0x8008E99C` | Fire-sprite renderer (*Yoga Flame*) | **COVERED (100%)** | `00020000_09CB7DD2.dll`, `00020000_0FA5970F.dll` (25 DLLs) |
| `0x8008FA1C` | Fire persistence and expiration loop | **COVERED (100%)** | `00020000_0031F42F.dll`, `00020000_012D1980.dll` (57 DLLs) |
| `0x8008E6C0` | Fire range checker | **COVERED (100%)** | `00020000_1B719044.dll`, `00020000_270A1DC6.dll` (13 DLLs) |
| `0x8008E398` | Fire-impact parameters | **COVERED (100%)** | `00020000_1B719044.dll`, `00020000_2906ED7E.dll` (6 DLLs) |
| `0x80047EFC` | Mine/trap detonation (*D. Dark*) | **COVERED (100%)** | `00020000_7113C787.dll`, `00020000_8ADC0BC2.dll` (6 DLLs) |
| `0x8008E798` | RAM bomb updater | **COVERED (100%)** | `00020000_1B719044.dll`, `00020000_7113C787.dll` (8 DLLs) |
| `0x80047DE8` | Mine planting and countdown | **COVERED (100%)** | `00020000_0A559C58.dll`, `00020000_0FD5B73C.dll` (21 DLLs) |
| `0x8008E394` | Impact and reflection (*Soul Force* / *Batting Hero*) | **COVERED (100%)** | `00020000_1B719044.dll`, `00020000_2906ED7E.dll` (6 DLLs) |

**Audit Conclusion**: **14 of 14 routines (100%) APPROVED AND VALIDATED IN NATIVE DLLs.**
