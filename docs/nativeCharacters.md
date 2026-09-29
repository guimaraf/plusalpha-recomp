# Record of 100% Native Characters (Main EXE SLUS-005.48)

This document records characters tested and validated with **100% native execution** in the static executable (`Main EXE`), detailing validation sessions, covered subsystems, and special dynamic-overlay cases (Track 2) to be addressed later.

---

## 1. Character Validation Table (Track 1 - Main EXE)

| Character | Status Main EXE | Validation Session | Checkpoint | Static Move / Action Coverage |
|---|:---:|---|:---:|---|
| **Ryu** | **100% Native** (0 misses) | Initial Baselines | S1-266 | Hadouken, Shoryuken, Tatsumaki Senpuukyaku, Shinku Hadouken, normal collisions and supers. |
| **Ken** | **100% Native** (0 misses) | Initial Baselines | S1-266 | Flaming Shoryuken, Hadouken, Tatsumaki, Shoryu Reppa, Shinryuken, combo transitions. |
| **Garuda** | **100% Native** (0 misses) | `gameplay-discovery-08` | S1-270 | Soukon Dan, Kizan, Raiga, multiple projectiles, spikes, and mesh transformations. |
| **Kairi** | **100% Native** (0 misses) | `gameplay-discovery-08` | S1-270 | Shinki Hatsu Dou, Maryu Rekkou, Shoushuu Renbu, recoil and attack cancels. |
| **Akuma (Gouki)** | **100% Native** (0 misses) | `gameplay-discovery-13` & `16` | S1-273 / S1-274 | Gou-Hadouken, Shakunetsu, Gou-Shoryuken, Tatsumaki air/ground, Messatsu Gou Shoryu. |
| **M. Bison (Vega)** | **100% Native** (0 misses) | `gameplay-discovery-15`, `16`, `17` | S1-274 | Psycho Shot, Double Knee Press, Head Press, Somersault Skull Diver, Knee Press Nightmare. |
| **Chun-Li** | **100% Native** (0 misses) | `gameplay-discovery-20` | S1-275 | Hyakuretsu Kyaku, Kikoken, Spinning Bird Kick, Hazan Tenshou Kyaku, Senretsu Kyaku, cancels and charge moves. |
| **Guile** | **100% Native** (0 misses) | `gameplay-discovery-22` | S1-276 | Sonic Boom, Flash Kick (Somersault), normal charge attacks, Opening Gambit, Double Somersault. |
| **Sakura** | **100% Native** (0 misses) | `gameplay-discovery-25` | S1-277 | Hadoken, Shouoken (anti-air), Shunpukyaku, Midare Zakura, Haru Ichiban, cancels and vector collisions. |
| **Pullum Purna** | **100% Native** (0 misses) | `gameplay-discovery-26` | S1-277 | Drill Purrus, Tenresuu, Prim Rose, Prapera Dance, Resall Dance, Gradus Pearl, transitions and spins. |
| **Doctrine Dark** | **100% Native** (0 misses) | `gameplay-discovery-28` | S1-278 | Kill Wire, Dark Wire, stabs, Dark EX-Plo (bombs), Dark Shackle, Kill Sword, combat transitions. |
| **Darun Mister** | **100% Native** (0 misses) | `gameplay-discovery-30` | S1-279 | Lariat, Ganga Lariat, Brahma Lariat, Indra Bridge, Daisharin, Twilight Collar, Hasin Shake. |
| **Cracker Jack** | **100% Native** (0 misses) | `gameplay-discovery-31` & `33` | S1-280 | Dash Straight, Dash Upper, Batting Hero, Soccer Ball Kick, Crazy Jack, Raging Buffalo, Home Run Hero, stage and props. |
| **Allen Snider** | **100% Native** (0 misses) | `gameplay-discovery-31` & `33` | S1-280 | Soul Force, Justice Fist, Vaulting Kick, Rising Dragon, Fire Force, Triple Break, move and stage transitions. |
| **Zangief** | **100% Native** (0 misses) | `gameplay-discovery-36` & `37` | S1-281 / S1-282 | Spinning Piledriver, Atomic Suplex, Final Atomic Buster, Double Lariat, Banishing Flat, global throw table `0x801B33F0`. |
| **Blair Dame** | **100% Native** (0 misses) | `gameplay-discovery-38` & `39` | S1-283 / S1-284 | Shoot Kick, Lightning Knee, Sliding D-Kick, Spin Kick, Mirage Kick, action/combat `0x8013E930`, sliding vectors `0x8014901C`. |
| **Skullomania** | **100% Native** (0 misses) | `gameplay-discovery-40` & `41` | S1-285 | Skullo Crusher, Skullo Slider, Skullo Head, Skullo Dive, Skullo Dash, Super Skullo Crusher/Slider, trajectory `0x8012A7E4`, 3D acrobatic action `0x801441B0..AD8`, combat engine `0x80160790..AA4`. |
| **Hokuto** | **100% Native** (0 misses) | `gameplay-discovery-42`, `43` & `85` | S1-286 / S1-302 | Chuuhou, Kaishuu, Shingetsu, Kyaku Houugi, Kiren'eki, Shirase Gatana, collisions, defense, GTE family `0x8019D860..0x8019DA54` and 3D weapon/dagger pipeline (`0x80164D9C..0x80165DAC`). |
| **Dhalsim** | **100% Native** (0 misses) | `gameplay-discovery-46` | S1-287 | Yoga Fire (`0x8015A530`), Yoga Flame, Yoga Blast, elastic limb deformation (`0x8014B2B4`), elastic hitboxes (`0x8014B6B0`) and animation bones (`0x80194BB4..EE4`). |
| **Cycloid-β** | **100% Native** (0 misses) | `gameplay-discovery-47` | S1-287 | Blue polygonal model; hybrid SF roster moveset fully shared with pre-existing native routines. |
| **Cycloid-γ** | **100% Native** (0 misses) | `gameplay-discovery-48` | S1-287 | Gold polygonal model; hybrid EX roster moveset and teleports (100% native static dispatches in the Main EXE; variations restricted to the dynamic RAM overlay). |
| **Bloody Hokuto** | **100% Native** (0 misses) | `gameplay-discovery-49` & `85` | S1-287 / S1-302 | Corrupted Hokuto variant, permanent dagger and fast blood attacks; shares 100% of the kinematic subroutines, matrices, and prop pipeline (S1-286 / S1-302). |
| **Evil Ryu** | **100% Native** (0 misses) | `gameplay-discovery-50` | S1-287 | Ashura Senku, Messatsu Gou Shoryu, Shun Goku Satsu, Dark Hadouken; shares kinematic matrices, transforms, and projectile dispatches with Ryu and Akuma. |
| **Akuma (CPU / Boss)** | **100% Native** (0 misses) | `gameplay-discovery-104` | S1-303 | Variant unlocked through Expert Mode / Save 100%. Ultra-aggressive boss AI, double Zanku Hadoken, Messatsu Gou Hado/Shoryu 100% native in the Main EXE. |
| **Garuda (CPU / Boss)** | **100% Native** (0 misses) | `gameplay-discovery-105` | S1-303 | Variant unlocked through Expert Mode / Save 100%. Boss AI, native super armor, blades, and Kienshou 100% native in the Main EXE. |
| **M. Bison (CPU / Boss)** | **100% Native** (0 misses) | `gameplay-discovery-106` | S1-303 | Variant unlocked through Expert Mode / Save 100%. Ultra-aggressive final-boss AI, continuous teleport, and static dispatches 100% native in the Main EXE. |

---

### Roster Summary (23 Base Characters + 3 Unlockable CPU Bosses)
- **Top Row (8)**: Zangief [OK], Cracker Jack [OK], Hokuto [OK], Ryu [OK], Ken [OK], Chun-Li [OK], Doctrine Dark [OK], Guile [OK]
- **Middle Row (8)**: Pullum Purna [OK], Darun Mister [OK], Kairi [OK], Sakura [OK], Dhalsim [OK], Allen Snider [OK], Blair Dame [OK], Skullomania [OK]
- **Bottom Row / Bosses & Secret Characters (7)**: Akuma [OK], M. Bison [OK], Garuda [OK], Evil Ryu [OK], Bloody Hokuto [OK], Cycloid-β [OK], Cycloid-γ [OK]
- **Special CPU Boss Variants (3)**: Akuma (CPU) [OK], Garuda (CPU) [OK], M. Bison (CPU) [OK]
- **Validation Progress**:
  - **Base Versus Roster**: **23 / 23 characters (100,00%)** with 100% native execution in the Main EXE!
  - **CPU Boss Variants**: **3 / 3 (100,00%)** with 100% native execution in the Main EXE!
  - **Overall Roster Total**: **26 / 26 characters (100,00%)** with **100% native static execution (0 misses)**!

---

## 2. Special-Case Report & Overlay Architecture (Track 2)

During high-density combat tests, telemetry isolation revealed the exact division between static ROM code (`SLUS-005.48`) and dynamic modules loaded into RAM (`0x80020000..0x800F2000`).

### Case 1: Akuma Teleport (*Ashura Senku*)
- **Observed Behavior**: Repeated Akuma teleports produced a slight variation (micro-ripple) in the frametime graph, while the rest of combat remained stable at a locked 60 FPS.
- **Technical Diagnosis**:
  - The Main EXE maintained **EXACTLY 0 MISSES**.
  - The variation comes from dynamic RAM routine **`0x80045ACC`** (region `0x80045000..0x80046000`, Capture 1 in `overlay_captures.json`), which triggered a spike of **+31.318 interpreted instructions** in fallback.
  - This routine handles the translucent shadow/trail calculation loop and teleport invulnerability-frame control.
- **Planned Treatment (Track 2)**:
  - It must not be added to `seeds/entry_funcs.txt` (it does not exist in the physical `SLUS_005.48` file).
  - It will be compiled natively through the **Overlay Cache / TCC JIT** framework during the stage dedicated to dynamic RAM modules.

---

### Case 2: Bison Stomp and Flame Effect (*Head Press & Somersault Skull Diver*)
- **Observed Behavior**: Intensive stomp hit and *whiff* testing with flaming hands and feet (`gameplay-discovery-17`).
- **Technical Diagnosis**:
  - The Main EXE recorded a new high of **+210.765 native dispatches** and **ZERO misses** (0 new static candidates).
  - All high-level collision physics, action dispatch, and round management ran entirely in native C.
  - Move-specific logic, flame anchor points (*VFX particle emitters*), and *Skull Diver* descent vectors ran in the dynamic RAM overlay block:
    - **`0x8004485C` to `0x80044DE8`**: Routine block with ~40.000 executions each.
    - **`0x80093588` and `0x80093D70`**: Dynamic RAM sprite/effect renderer (~16,4 million instructions).
- **Planned Treatment (Track 2)**:
  - The `0x80044xxx` group forms Bison's exclusive ability module in RAM and will be addressed in the character-overlay batch.

---

### Case 3: Chun-Li Intro, Celebration, and Replay Poses
- **Observed Behavior**: Slight transient variation in the frametime graph at fight boundaries (round start and K.O./victory screen), with locked, highly stable frametime at 60 FPS throughout active combat (`gameplay-discovery-20`).
- **Technical Diagnosis**:
  - The Main EXE recorded **EXACTLY 0 MISSES** and interpreted fallback fell from 9,15M to only 111k instructions (-98,8%).
  - The transient variation comes from dynamic RAM routines:
    - **`0x80048960`**: Skeleton/intro animation initialization (~8,9 million interpreted RAM instructions).
    - **`0x80046EEC` and `0x800477D0`**: Victory pose ("Yatta!") and post-K.O. processing (~4 million instructions).
- **Planned Treatment (Track 2)**:
  - RAM routines handled through dynamic caching / TCC sharding to eliminate any ripple at round boundaries.

---

### Case 4: Cracker Jack & Allen Snider Stage and Action Subsystem (Micro-batch S1-280)
- **Observed Behavior**: Continuous micro-fluctuations in the frametime graph during the match with Cracker Jack on his stage (`gameplay-discovery-32`), while the first test (`gameplay-discovery-31`) recorded zero misses but high RAM overlay cost.
- **Technical Diagnosis**:
  - Cracker Jack's stage path and P2 stance triggered entry `0x801AFC80` in the Action Dispatch Table, dispatching into a static Main EXE gap (`0x8011A8DC..0x8011B3B8`).
  - One internal routine, **`0x8011AFBC`**, was called **153.072 times** by the fallback interpreter (averaging ~64 calls/frame), causing extensive switching between x64 and MIPS.
- **Implemented Resolution (S1-280)**:
  - Promotion of 8 native functions (`0x8011A8DC`, `0x8011AB7C`, `0x8011ABD4`, `0x8011AC1C`, `0x8011AC50`, `0x8011AFBC`, `0x8011B180`, `0x8011B238`), totaling +663 words.
  - Validation in `gameplay-discovery-33`: **0 misses in the Main EXE**, complete elimination of the 153k fallback calls, a **-91,1%** reduction in interpreted instructions, and fully clean frametime in both combat orientations (normal and reversed).

---

### Case 5: Transient Startup Jitter and Full Frametime Stabilization (Micro-batch S1-284)
- **Observed Behavior**: During session `gameplay-discovery-39` (Blair Dame vs Zangief), an initial frametime transient appeared during the transition from the loading/intro screen to the start of Round 1. Immediately afterward, frametime remained completely clean and locked at 60 FPS throughout the rest of combat.
- **Technical Diagnosis**:
  - **Main EXE 100% Free of Misses**: Telemetry recorded `static_text_misses: []` (0 new candidates and 0 context breaks in static ROM code).
  - **Initial Jitter Source**: It comes from PlayStation resource staging and dynamic RAM loading:
    1. *CD-ROM / ISO9660 Streaming*: Reading XA/CDDA audio blocks and character SPU/VAG samples into sound memory.
    2. *Dynamic Module Loading (Track 2)*: Allocation of RAM overlay blocks (`0x80020000..0x800F2000`) containing character-specific move tables and introduction scripts.
    3. *VRAM Setup*: Uploading 3D textures/2D sprites and color palettes (CLUTs) into PS1 GPU buffers.
  - **Active Combat Behavior**: Once the RAM and VRAM buffers are established, the action dispatcher (`0x801AFC70`), throw engine (`0x801B33F0`), combat engine (`0x8013E930..0x8013EB60`), and movement/sliding subroutines (`0x8014901C..0x801495D4`) execute entirely as native x64 machine code, eliminating frametime drops caused by interpreter fallback.
- **Planned Treatment (Track 2)**:
  - The initial streaming transient will be mitigated later through OVL Caching/JIT and disk I/O optimization.

---

### Case 6: Skullomania's Theatrical Super Combo (*Skullo Dream*) - Resolved (S1-285, S1-305 & Track 2)
- **Observed Behavior**: During sessions `gameplay-discovery-40`, `41`, `137`, `138`, and `139`, the frametime graph stayed locked at 60 FPS throughout active combat. Triggering the theatrical cinematic special (*Skullo Dream*) revealed the exact division between static ROM and RAM overlay.
- **Technical Diagnosis**:
  - **Main EXE Text (S1-305)**: *Skullo Dream* triggered Action Table entry 0 (`0x801B1B48 -> 0x8013B070`), with internal JALs for 3D camera matrix and GTE setup (`0x8013B070..0x8013B328`).
  - **Implemented Resolution (S1-305)**: Promotion of 5 native functions (+1.148 words: `0x8013B070`, `0x8013B078`, `0x8013B10C`, `0x8013B114`, `0x8013B328`), closing the gap up to Training Mode (`0x8013BFA8`).
  - **Validation in `gameplay-discovery-139`**: **0 CANDIDATES IN THE MAIN EXE**, elimination of all static misses, +380.190 native dispatches, and full absorption of the cinematic's processing cost.
  - **Track 2 (RAM Overlay)**: The RAM combat module (`0x00020000:0x2906ED7E`) was compiled into 263 shard DLLs, eliminating 10,3M instructions from Skullomania's acrobatic movement and Blair Dame's kicks.

---

### Case 7: Dhalsim Elastic-Limb Kinematics and Bone Animation Pipeline (Micro-batch S1-287)
- **Observed Behavior**: During session `gameplay-discovery-45` (Dhalsim vs Ryu), 8 residual candidates (2.002 hits) were detected when triggering extended-limb attacks.
- **Technical Diagnosis**:
  - Dhalsim's unique arm and leg stretching mechanics invoke specific kinematic subroutines for deformation and moving contact boxes:
    - `0x8014B21C` (Combat root dispatch in table `0x801B1BA8`).
    - `0x8014B2B4` (Kinematic calculation of limb reach and elastic deformation).
    - `0x8014B6B0` (Stance and moving hitbox updates).
    - `0x8015A530` (Yoga Fire projectile).
    - `0x80194BB4..0x80194EE4` (Matrix orientation and 3D animation bone interpolation pipeline).
- **Implemented Resolution (S1-287)**:
  - Promotion of 9 native functions (+780 words).
  - Validation in `gameplay-discovery-46`: **0 candidates in the Main EXE**, locked frametime, and official validation of Dhalsim as the 19º fighter with 100% native execution.

---

### Case 8: Structural Moveset Sharing in Bosses and Bonus Characters (Cycloids, Bloody Hokuto, Evil Ryu)
- **Observed Behavior**: Combat tests with Cycloid-β (`gameplay-discovery-47`), Cycloid-γ (`gameplay-discovery-48`), Bloody Hokuto (`gameplay-discovery-49`) and Evil Ryu (`gameplay-discovery-50`).
- **Technical Diagnosis**:
  - All sessions recorded **EXACTLY 0 CANDIDATES IN THE MAIN EXE** (empty `candidates.txt`) on the first test.
  - **Kinematic Inheritance**:
    - **Cycloid-β**: Fully reuses the Street Fighter roster's already compiled normal/special move tables and routines.
    - **Cycloid-γ**: Reuses the EX fighters' combat foundation. Observed frametime fluctuations are concentrated in the dynamic RAM overlay (`0x80048930` and `0x8004880C`), with no static ROM misses.
    - **Bloody Hokuto**: Inherits all standard Hokuto kinematic subroutines, rotation matrices, and vectors (promoted in S1-286).
    - **Evil Ryu**: Shares kinematic dispatches, Hadouken paths, and collisions with Ryu and Akuma.
- **Cycle Conclusion**: All 23 fighters in the game were validated with **100% native execution** in the Main EXE.

---

### Case 9: Hokuto Weapon/Prop Pipeline and 3D Dagger Renderer (Micro-batches S1-301 and S1-302)
- **Observed Behavior**: During the CPU AI campaign (`gameplay-discovery-83` and `84`), candidates were discovered around Hokuto's prop pipeline (`0x80164D9C..0x80165DAC`).
- **Technical Diagnosis**:
  - Hokuto (and variants such as Bloody Hokuto) uses a global weapon accessory/prop dispatcher that checks the Character ID (`0x80164D9C`, 89 words).
  - The 3D polygon renderer for daggers and fan operates in subroutines `0x80165130` (266 words) and `0x80165DAC` (241 words), with native GTE calls.
- **Implemented Resolution (S1-301 and S1-302)**:
  - **S1-301**: Promotion of `0x80165130` (266 words).
  - **S1-302**: Promotion of `0x80164D9C` and `0x80165DAC` (330 words).
  - Validated in `gameplay-discovery-85` with **zero candidates and 993.384 static hits** in the Main EXE.

---

### Case 10: Dynamic RAM Loop Churn During CPU Combat (Sakura #13 - Session `gameplay-discovery-93`)
- **Observed Behavior**: During 3 fights against Level 8 Sakura (`gameplay-discovery-93`), frequent frametime micro-fluctuations were observed, with zero new Main EXE candidates.
- **Technical Diagnosis**:
  - **Main EXE 100% Free of Misses**: 982.944 native static hits and 0 misses.
  - **Dynamic RAM Jitter Source**: Fallback interpreter saturation in dynamic code with **+164.611.395 interpreted instructions** and **+7.318.116 hits** in overlays:
    - **`0x80092280`**: 42.114.686 instructions (88.170 hits) — frame update / dynamic combat loop.
    - **`0x8004A44C`**: 39.595.929 instructions (88.170 hits) — shared battle engine (`OVL-001A`), operating in direct synchronization with `0x80092280`.
    - **`0x8004922C`**: 23.867.322 instructions (15.499 hits) — RAM move kinematics and renderer.
    - **`0x80049500`**: 10.625.735 instructions (15.499 hits) — particles and special-effect emitters.
    - **`0x80091334`**: 10.067.308 instructions (15.499 hits) — dynamic collision dispatcher.
- **Planned Treatment (Track 2)**:
  - Cataloged in the Overlay pipeline for shard DLL generation through TCC/JIT, eliminating handoffs between x64 and MIPS.

---

## 3. Core AI Engine Validation (Batches S1-291 to S1-300)

After full validation of the 23 characters under human control (P1), the validation campaign for CPU-controlled characters (Level 8 / Hardest) began.

- **The Core AI Engine Challenge (`0x80155000..0x80158500`)**:
  - When controlled by AI at maximum aggression, fighters invoke deep trees for neutral assessment, *hit-confirms*, sequential cancels, input simulation, and reversals.
- **Micro-Batch Promotion Campaign (S1-291 to S1-300)**:
  - **S1-291 / S1-292**: Training dummy configuration and neutral-transition flags.
  - **S1-293**: Gap 2 and Gap 7 (Recovery and block-transition helpers).
  - **S1-294**: Gap 4 (Approach and jump timing).
  - **S1-295**: Gap 5 (Super selection and cancels).
  - **S1-296 / S1-297**: Gap 3 Part 1 and Part 2 (Positioning, evasion, hit-confirms, and combos; elimination of 1.500+ hits).
  - **S1-298 / S1-299 / S1-300**: Gap 6 Parts 1, 2, and 3 (Close range, dashes, frame advantage, reversals, projectile matrix, and finishers; elimination of 1.540+ hits).
- **Result in Session `gameplay-discovery-74`**:
  - **0 CANDIDATES IN THE MAIN EXE TEXT**.
  - The Core AI Engine now forms a **contiguous block of 13.368 bytes (3.342 words)** of native C11 code from `0x801550C8` to `0x80158500`.
  - Ensures the entire roster, whether controlled by humans or high-difficulty AI, executes with **zero fallbacks in the Main EXE**.

---

## 4. Mandatory Main EXE Quarantine (Safe Interpretation)

The only addresses in the main executable address space (`0x80100000..0x801BF000`) intentionally kept under interpretation are:

1. **`0x801AB1F4`**: Busy-wait read loop for the SIO/Joypad hardware register (`0x1F801044` bit `0x80`). Static recompilation breaks controller input polling timing.
2. **`0x801AB2C0`**: Self-modifying code (SMC) monkey-patch that replaces 5 instructions at runtime for BIOS synchronization.

Any hit at these two addresses is ignored by telemetry filters as normal, expected hardware emulation behavior.
