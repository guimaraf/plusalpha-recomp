# Build & Reverse Engineering Technical History (Build Resume)

This document serves as the historical deep-dive record for all static recompilation micro-batches, pre-audits, incident post-mortems, and dynamic overlay investigations for *Street Fighter EX Plus Alpha* (USA, `SLUS-005.48`).

For the current baseline status, active batches, and concise tracking table, see [`newWords.md`](newWords.md).

---

## 1. Governance & Maintenance Rules

- **Observed PC $\neq$ Function Root**: A runtime program counter hit can be an internal entry, a return site, a jump table destination, or an inline trampoline alias.
- **Promotion Lifecycle**: A candidate is only marked as `processed` after its boundary, callers, internal aliases, reachable closure, indirect control flow, telemetry verification, and regression tests are fully audited and clean.
- **Isolation Gates**: No new seed can be added to `seeds/entry_funcs.txt` without an isolated pre-audit measuring the full reachable closure and establishing a hard word budget. If the closure exceeds the budget, the candidate is quarantined or rejected.
- **SMC / Hardware I/O Isolation**: Self-modifying code (SMC) and direct hardware MMIO busy-wait loops (such as SIO/Joypad monkey-patches) must remain under interpreter execution (`psx_interpreter` / `dirty_ram_interp`) to prevent deadlocks and recursive crashes.

---

## 2. Static Micro-Batches Deep-Dive History

### S1-240 through S1-250 (Early Discovery Phase)
- **S1-240 (`0x8013CB08..0x8013CB8B`)**: 33 words promoted (cumulative: 106,352 words).
- **S1-241 (`0x801102A0..0x8011062F`)**: 228 words promoted (cumulative: 106,580 words).
- **S1-242 (`0x80137FE8`, `0x80138084`, `0x8013827C`)**: 245 words promoted (cumulative: 106,825 words).
- **S1-243 (`0x80162D68..0x8016313B`)**: 245 words promoted (cumulative: 107,070 words).
- **S1-244 (`0x80107A74..0x80107D7F`)**: 195 words promoted (cumulative: 107,265 words).
- **S1-245 (`0x8011D310..0x8011D9B3`)**: 425 words promoted (cumulative: 107,690 words).
- **S1-246 (`0x8011D030`, `0x8011D078`)**: 184 words promoted (cumulative: 107,874 words).
- **S1-247 (`0x801A92B8..0x801A939B`)**: 57 words promoted (cumulative: 107,931 words).
- **S1-248 (`0x801A9DC0..0x801A9FD3`)**: 133 words promoted (cumulative: 108,064 words).
- **S1-249 (`0x8019F6A8`, `0x8019FB64`)**: 125 words promoted (cumulative: 108,189 words).
- **S1-250 (`0x8019F5CC`, `0x8019FB4C`, `0x8019FB84`, `0x8019FB94`)**: 76 words promoted (cumulative: 108,265 words).

---

### Incident S1-252: Uncontrolled Closure Expansion (Post-Mortem)
- **Candidate**: Dispatcher `0x8016FC28` was initially estimated at only 39 words.
- **Root Cause**: The function contained two direct `JAL` instructions targeting uncompiled functions. Reachable discovery recursively expanded the closure to **12 functions and 2,805 words**, contaminating the work sources with 1,054 functions.
- **Corrective Action**: The candidate was immediately rejected and quarantined. Work sources were rolled back to S1-251 (`BB5EA43C...`). This incident established the mandatory rule of **isolated preview and hard word-budget validation** prior to touching main project files.

---

### S1-251 through S1-261 (Stabilization & Checkpoints)
- **S1-251 (`0x8014C708..0x8014C72F`)**: 10 words. Formal wrapper of 40 bytes. Telemetry confirmed 8,736 entries with zero misses.
- **S1-253 (`0x8017D860`, `0x8017DA08`, `0x80191000`)**: 184 words promoted.
- **S1-254 (`0x8017DA9C`, `0x80190EB8`, `0x80190FAC`)**: 155 words promoted.
- **S1-255 (`0x8018F10C..0x80190E6B`)**: 1,880 words promoted. Checkpoint reached 110,494 words.
- **S1-256 (`0x8016FC28`, `0x801910A4`, `0x801914C0`, `0x80191C84`, `0x80192D6C`, `0x801930BC`)**: 622 words promoted.
- **S1-257 (`0x8019FC6C..0x8019FCE3`)**: 30 words. Permanent title screen dispatcher.
- **S1-258 (`0x8017566C..0x801758C7`)**: 151 words. UI text rendering routines.
- **S1-259 (`0x801939A0..0x80193A17`)**: 30 words.
- **S1-260 (`0x80103BD8..0x80103CA7`)**: 52 words. Pause menu state handler.
- **S1-261 Checkpoint**: Cumulative release incorporating S1-251 through S1-260. Full regression verified 60 FPS across Expert Mode, Bonus Stage, Versus (Doctrine Dark vs Skullomania), Survival, Options, and Memory Card.

---

### S1-262 through S1-266 (Menu Eradication Campaign)
- **S1-262 (`0x80103384` + closure)**: 936 words. Reached 112,315 words.
- **S1-263 (`0x80164F00` + closure)**: 8,026 words (9 functions). 3D fight rendering pipeline and GTE math. Codegen audit: CLEAN.
- **S1-264 (`0x801912D8`, `0x80191588`, `0x801961BC`)**: 217 words. Direct targets from overlay `0x80020000` (Character Select & Menus).
- **S1-265 (`0x80192128`, `0x80192E58`, `0x80192F60`, `0x8019314C`, `0x80193174`, `0x8019319C`, `0x801931C4`, `0x8019328C`)**: 981 words. Options and Memory Card jump tables (`0x801B8538`).
- **S1-266 (`0x80124400`, `0x801932BC`, `0x80125594`, `0x801258D4`, `0x8016A84C`, `0x8018C880`)**: 3,896 words (22 native functions expanded). Eradicated 50 out of 52 residual uncompiled menu PCs. Baseline reached **125,435 words (64.1336%)**.
- **Residual Menu Candidates Audit**:
  - `0x801AB1F4` and `0x801AB2C0` were audited and confirmed as PSX BIOS kernel monkey-patches (SIO/Joypad hook and SMC delay swap). Quarantined under interpreter execution to protect entry timing.

---

### S1-267: Match State Machine / FSM (Promoted & Validated)
- **Root**: `0x80106BD4..0x80107A70` (3,744 bytes / **936 words**).
- **Architecture**: Core Round State Manager (Versus and Arcade match loop). Controls round initialization, Fight banner, active combat, KO, victory pose, replay, and post-match menu via jump table `0x801AB5BC` (9 cases).
- **Closure**: All 17 direct JAL calls resolve to pre-existing native functions. Zero closure expansion.
- **Coverage**: Advances static coverage to **126,371 words (64.6121%)** across 1,109 functions. Status: CLEAN.
- **Gameplay Validation (`gameplay-discovery-02`)**:
  - Telemetry verification across active Versus match (Doctrine Dark vs Ryu, 2 full rounds, special moves, combos, supers).
  - Native dispatches surged to **+152,919** (+40,355 additional native dispatches).
  - **100% of the 10 FSM uncompiled misses were completely eradicated** (`0x80106BD4`, `0x80106CB0`, `0x80106CB8`, `0x80106DB0`, `0x80106E8C`, `0x80106E94`, `0x80106E9C`, `0x80106F74`, `0x8010773C`, `0x80107744` dropped to zero).
  - Frametime confirmed rock-solid and ultra-smooth across entire combat session.
  - Remaining uncompiled Main EXE misses reduced to just 3 PCs (Entity update family `0x80117224`).

---

### S1-268: Entity & Frame Processing Cluster (Promoted & Validated)
- **Root**: `0x80117224` (Entity / Frame Processing Cluster).
- **Closure**: Directly resolves `0x80117224` (18 words / 72 bytes), `0x8011726C` (47 words / 188 bytes), `0x80117328` (143 words / 572 bytes), and `0x80117564` (251 words / 1,004 bytes). Total: 4 new native functions, 459 words (1,836 bytes).
- **Bridge**: Perfectly bridges the gap between `0x801171DC` and `0x80117950` in the Main EXE text segment.
- **External Calls**: Direct `JAL` calls to `0x801938B0`, `0x80194A58`, and `0x8010C72C` (all 100% native). All returns are standard `JR $ra` (`r31`); zero indirect branches, zero `JALR`.
- **Coverage**: Advances static coverage to **126,830 words (64.8468%)** across **1,113 functions** and **18,271 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Impact**: Eradicates the last 3 uncompiled Main EXE misses observed in active combat (`0x80117224`, `0x8011726C`, `0x80117328`). Main EXE static code in gameplay reaches 100% native dispatch (zero uncompiled misses), with only runtime-quarantined BIOS/SIO SMC patches remaining under interpreter execution.
- **Clean Gameplay Validation (`buildClean-ucrt-s1-268`)**:
  - Validated clean across a full Versus match (Doctrine Dark vs Ryu, 2 full rounds) followed by 4 consecutive Arcade mode fights with Doctrine Dark.
  - Frametime confirmed rock-solid and ultra-clean at fixed 60.0 FPS, with zero micro-stutter and zero regressions in hitboxes, physics, collision, special moves, supers, or audio. Full overlay cache (58 precompiled DLL shards) successfully integrated and operational.

---

### S1-269: 3D Projectile / Particle & Effect Entity Processor (Promoted & Validated)
- **Root**: `0x8014FE30..0x801502D4` (1,192 bytes / **298 words**).
- **Architecture**: 3D projection, transform, and physics handler for combat projectile entities, visual hitsparks, and special move particle systems (Hadoken, Shoryuken, and collision particles). Features an internal 5-case jump table at `0x801ABDD4` strictly bounded (`sltiu $v0, $fp, 5`) with all branches converging internally to `0x8014FEB8`, `0x8014FEC4`, and `0x8014FECC`.
- **Topological Bridge**: Perfectly bridges the physical gap in Main EXE between `0x8014FD54..0x8014FE30` and `0x801502D8..0x801502FC` (eliminating the 298-word hole).
- **Closure**: All 13 direct JAL calls point to pre-existing native functions (`0x80123910`, `0x801502D8`, `0x801502FC`, `0x80167D28`, `0x80194828`, `0x8019C0B8`, `0x8019C184`, `0x8019D740`, `0x8019D7D0`). Zero closure expansion.
- **Coverage**: Advances static coverage to **127,128 words (64.9991%)** across **1,114 functions** and **18,311 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Impact (`gameplay-discovery-05`)**:
  - Validated clean across full rematch of Ryu vs Ken on Ken's stage (Hadokens, Shoryukens, combos, supers, K.O.).
  - Completely eradicated all 3 misses observed in run 04 (`0x8014FE30`, `0x8014FF98`, `0x8014FFCC` dropped to 0).
  - Interpreter fallbacks plunged from +200,351 down to +92,498 (a reduction of -107,853 interpreted executions).
  - Confirmed frametime stabilization and a cleaner 60 FPS timeline due to elimination of dirty-RAM interpreter transitions during fireball and particle rendering.

---

### S1-270: 3D Trigonometry & Combat Reaction/Collision Cluster (Fronts 1 and 2)
 - **Front 1 (Trigonometry and 3D Matrix Rotation Leaf)**:
  - **Root**: `0x8019E6D0..0x8019E864` (408 bytes / **102 words**).
  - **Function**: Pure leaf without a stack frame (`sp`) or external calls (`jal`), ending with `jr $ra`. Executed dozens of times per frame in matrix rotation calculations for 3D fighter models.
  - **Validation (`gameplay-discovery-07`)**: Eliminated all 5.328 misses observed in Garuda vs Kairi. Native dispatches rose from +157.489 to +269.103 (+111.614 additional native dispatches). The operator reported noticeable frametime stabilization.
  - **F1 Coverage**: 127.230 words (65,0513%) across 1.115 native functions.
- **Front 2 (Cluster of reaction, damage and collision)**:
  - **Range**: `0x80160B54..0x80160F94` (1.088 bytes / **272 words**).
  - **functions (5 contiguous)**:
    - `0x80160B54`: 240 bytes / 60 words (reaction flag/offset calculation)
    - `0x80160C44`: 152 bytes / 38 words (impact and status update)
    - `0x80160CDC`: 168 bytes / 42 words (damage and stun-frame handling)
    - `0x80160D84`: 256 bytes / 64 words (Collision and state-transition processor)
    - `0x80160E84`: 272 bytes / 68 words (Hit-stop and body-reaction mechanics)
  - **Topology**: Completely fills the gap of 272 words between `0x80160AA4` and `0x80160F94`.
  - **Closure**: All 24 direct calls `JAL` point to functions already native or internal (`0x8015D3F0`, `0x8015E12C`, `0x8011618C`, `0x80115574`, `0x80160430`, `0x801157A4`, `0x8015A0E8`, `0x8015D040`, `0x8012C288`, `0x80160C44`, `0x80101D68`, `0x80160084`, `0x801690D4`, `0x8015CF38`, `0x80158194`, `0x80159E44`). Zero closure expansion.
  - **Final Coverage S1-270**: **127.502 words (65,1904%)** at **1.120 native functions** and **18.388 dispatch entries**. Codegen audit: **CLEAN**.
  - **Gameplay Validation (`gameplay-discovery-08`)**:
    - Eliminated 100% of the 294 misses in Block A (`0x80160C44`, `0x80160CC4`, `0x80160CDC`, `0x80160CFC`, `0x80160D14`, `0x80160D70` reduced to zero).
    - Large drop of -21.826 interpreted instructions in the framework.
    - The operator confirmed extreme stabilization and a very clean frametime graph at 60 FPS.
    - Only 5 residual combat PCs remained (`0x801288DC..0x801289D0`), mapped to micro-batch S1-271.

---

### S1-271: Physics & Special Move Vector Calculation Cluster (Staged)
- **Origin / Trigger**: 5 PCs observed with 364 hits during active combat (Garuda vs Kairi, `gameplay-discovery-08`): `0x801288DC` (120 hits), `0x80128988` (120 hits), `0x801289D0` (120 hits), `0x80128930` (2 hits), `0x80128968` (2 hits).
- **Invocation / Jump Table**: Root `0x801288DC` is referenced by entry `0x801B03CC` in the combat action dispatch table (`0x801B03BC..0x801B03F8`).
- **Cluster & Boundaries**:
  - `0x801288DC`: 84 bytes / 21 words (Formal root; calculates action-vector parameters and calls `0x80128930` and `0x80128988`).
  - `0x80128930`: 88 bytes / 22 words (auxiliary vector subroutine; calls `0x8012B8F4` native).
  - `0x80128988`: 184 bytes / 46 words (trajectory and impact calculator; calls the native functions `0x8012B8F4` and `0x8012C628`).
- **Call Closure**: All 5 direct calls `JAL` are native or internal to the cluster. Zero closure expansion. Zero internal jump tables, zero `jalr`, zero risky interactions with hardware/SMC.
- **Topology**: Occupies the contiguous range `0x801288DC..0x80128A40` within the physics gap `0x80128524..0x80128D74`.
- **Budget**: 3 new functions, 356 bytes / **89 words**.
- **Final Coverage S1-271**: **127.591 words (65,2359%)** at **1.123 native functions** and **18.405 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-09`)**:
  - Eliminated 100% of the 5 misses of physics of combat (`0x801288DC`, `0x80128930`, `0x80128968`, `0x80128988`, `0x801289D0` reduced to zero).
  - New static Main EXE promotion candidates: **EXACTLY 0**.
  - Native dispatch rose to **+184.536** and interpreter fallback fell to a historical minimum of **+87.485**.
  - The Main EXE Text segment during active combat reaches **100% native static coverage** (zero misses in complete Garuda vs Kairi rounds). Only BIOS/SIO monkey-patches at `0x801AB1F4` and `0x801AB2C0` remain interpreted.

---

### S1-272: Defender Hit-Stun, Recoil & Damage Physics Cluster (Promoted and Validated)
- **Origin / Trigger**: Test with reversed roles (Kairi P1 attacking, Garuda P2 defending/taking damage, `gameplay-discovery-10`), revealing **19.678 interpreted hits** distributed across 9 PCs of the Main EXE.
- **Topology**: Occupies the contiguous range `0x801202EC..0x80120E44` (2.904 bytes / **726 words**), seamlessly joining the end of `0x8011FE28` to native function `0x80120E44`.
- **Promoted Functions (8 contiguous)**:
  - `0x801202EC`: 104 bytes / 26 words (3.176 hits; dispatcher for impact event)
  - `0x80120354`: 516 bytes / 129 words (1 hit; updater of meter and combat status)
  - `0x80120558`: 696 bytes / 174 words (3.176 hits; reaction loop with `jalr` indirectly through table `0x801AFFA0`)
  - `0x80120810`: 36 bytes / 9 words (18 hits; recoil / knockback subroutine)
  - `0x80120834`: 20 bytes / 5 words (14 hits; cleanup of collision flags)
  - `0x80120848`: 1.088 bytes / 272 words (5.107 hits at entry, 3.061 at `0x80120A48`, 18 at `0x80120954`; main processor for animation and damage impact, target 0 of table `0x801AFFA0`)
  - `0x80120C88`: 40 bytes / 10 words (alternative handler; target 1 of table `0x801AFFA0`)
  - `0x80120CB0`: 404 bytes / 101 words (5.107 hits; finalizer for hit-stun / guard frame)
- **JALR Resolution at `0x801206AC`**: The indirect jump consults table `0x801AFFA0`, whose only two targets (`0x80120848` and `0x80120C88`) belong to this batch. Both are promoted to the native dispatch table, so `call_by_address` resolves to native execution at runtime without dirty-RAM fallback.
- **Call Closure**: All 13 direct external calls JAL point to functions already compiled (`0x801938B0`, `0x8019D740`, `0x8019E870`, `0x8019C0B8`, etc.). closure expansion: **ZERO**.
- **Budget**: 8 new functions, 2.904 bytes / **726 words**.
- **Final Coverage S1-272**: **128.317 words (65,6071%)** at **1.131 native functions** and **18.528 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-11`)**:
  - Eliminated 100% of the 19.678 misses observed in Kairi vs Garuda in the 8 PCs of the Cluster of defense/hit-stun (`0x801202EC`, `0x80120354`, `0x80120558`, `0x80120810`, `0x80120834`, `0x80120848`, `0x80120A48`, `0x80120CB0` all reduced to zero).
  - Interpreter fallback fell sharply from +2.512.419 to the absolute historical record of **+70.140**.
  - Native dispatches reached **+175.766** with stable, clean frametime at 60 FPS.
  - New Main EXE promotion candidates: **EXACTLY 0**. Combat coverage in the main binary remains 100% free of misses.

---

### S1-273: Action NOP Handler, Special/Effects & Model Rendering Clusters (Promoted and Validated)
- **Origin / Trigger**: Test with Akuma vs Bison on Bison's stage (`gameplay-discovery-12`), revealing 14 candidate PCs in the Main EXE Text with a total of **3.306 interpreted hits**.
- **Cluster A (Action Dispatch NOP Handler)**:
  - `0x8011721C`: 8 bytes / **2 words** (2.969 hits / 89,8% of the test; stub `jr $ra; nop` called by indices 0, 11, 13, and 15 of table `0x801AFC70`). Precisely fills the micro-gap between `0x801171DC` and `0x80117224`.
- **Cluster B (Special Move and Projectile/Effect Subsystem)**:
  - `0x801338B8`: 1.348 bytes / **337 words** (38 hits; formal root referenced by entry `0x801B1BFC` in the effect table; dispatches to `0x80133DFC` and `0x80134224`).
  - `0x80133DFC`: 1.064 bytes / **266 words** (1 hit; trajectory vector and state setup).
  - `0x80134224`: 1.880 bytes / **470 words** (36 hits at the root, internal hits at `0x80134348`, `0x801343B4`, `0x801344F0`, `0x801344FC`, `0x80134618`; effect collision and physics processor).
  - Closure: All 21 direct external calls target existing native routines (`0x80123BF4`, `0x8010C72C`, `0x80101D18`, `0x80194990`, `0x8015C000`, etc.). Zero indirect jumps; closure expansion ZERO.
- **Cluster C (Model and Stage Rendering Engine)**:
  - `0x8013FF34`: 152 bytes / **38 words** (127 hits; handler referenced by table `0x801B1B58`).
  - `0x8013FFCC`: 552 bytes / **138 words** (1 hit at the root, 2 hits at `0x80140058`; matrix/vertex setup).
  - `0x801401F4`: 1.448 bytes / **362 words** (126 hits; vertex and lighting transformer).
  - `0x8014079C`: 188 bytes / **47 words** (Handler referenced by `0x801B1B5C`; contains an internal switch with table `0x801ABC58`, whose targets are all local labels).
  - Topology: Seamlessly joins native block `0x8013F998..0x8013FF34` to native block `0x80140858..0x80140CEC`.
  - Closure: All external calls are native. closure expansion ZERO.
- **Total Budget S1-273**: 8 new functions, 6.640 bytes / **1.660 words**.
- **Final Coverage S1-273**: **129.977 words (66,4558%)** at **1.139 native functions** and **18.726 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-13`)**:
  - Eliminated 100% of the 14 candidates and 3.306 misses observed in Akuma vs Bison.
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native dispatches rose to a record **+209.855 hits**.
  - interpreted fallback plummeted from +176.952 to +119.782 (-57.170 interpreted instructions eliminated).
  - **Akuma Teleport Diagnosis (Ashura Senku)**: The slight frametime ripple during repeated teleports comes from the dynamic RAM overlay engine (`0x80045ACC`, +31.318 interpreted overlay instructions in session 13), which handles trail/shadow animation and move invulnerability flags, while the Main EXE remained 100% free of misses. Frametime throughout the rest of combat remained extremely stable.

---

### S1-274 (Front 1): Combat Action Subsystem - Cluster 1 (Promoted and Validated)
- **Origin / Trigger**: Test with reversed roles (Bison P1 attacking with inactive P2, `gameplay-discovery-14`), revealing 358 hits in Cluster 1.
- **Topology & Boundaries**:
  - `0x8014373C`: 156 bytes / **39 words** (179 hits; dispatcher that calls `0x801437D8` and `0x801439E4`).
  - `0x801437D8`: 524 bytes / **131 words** (4 hits at the root, 4 hits at `0x80143948`; vector and attack-coordinate calculation).
  - `0x801439E4`: 1.996 bytes / **499 words** (171 hits; impact physics and 3D move transforms).
- **Call Closure**: All 14 direct external calls JAL point to existing native routines (`0x8019D740`, `0x8019D7D0`, `0x8019CA30`, `0x8019EFD0`, `0x8019CE70`, `0x8010C72C`, etc.). Zero indirect jumps; closure expansion ZERO.
- **Front Budget 1**: 3 new functions, 2.676 bytes / **669 words**.
- **Final Coverage Front 1**: **130.646 words (66,7979%)** at **1.142 native functions** and **18.792 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-15`)**:
  - Eliminated 100% of the 358 hits of the Cluster 1 (`0x8014373C`, `0x801437D8`, `0x80143948`, `0x801439E4` all reduced to zero).
  - Massive reduction of -168.126 interpreted fallback instructions (from +547.324 to +379.198).
  - native dispatches reached **+108.921**.
  - Only the 4 Cluster 2 PCs remained in the Main EXE (`0x80146B74..0x80147624`, 1.455 hits), mapped to Front 2. Zero additional new candidates.

---

### S1-274 (Front 2): Combat Action & Reaction Subsystem - Cluster 2 (Promoted and Validated)
- **Origin / Trigger**: Test with reversed roles (Bison P1 attacking with inactive P2, `gameplay-discovery-14` and `15`), leaving 1.455 hits in Cluster 2.
- **Topology & Boundaries**:
  - `0x80146B74`: 156 bytes / **39 words** (721 hits; dispatcher for impact/reaction event that calls `0x80146C10` and `0x80146E18`).
  - `0x80146C10`: 520 bytes / **130 words** (13 hits at the root, 13 hits at `0x80146D80`; setup of defensive parameters).
  - `0x80146E18`: 2.060 bytes / **515 words** (708 hits; recoil physics, impact animation, and state transition).
- **Call Closure**: All 14 direct external calls JAL point to existing native routines (`0x8019D740`, `0x8019D7D0`, `0x8019CA30`, `0x8019EFD0`, `0x8019CE70`, `0x8010C72C`, etc.). Zero indirect jumps; closure expansion ZERO.
- **Front Budget 2**: 3 new functions, 2.736 bytes / **684 words**.
- **Final Coverage S1-274**: **131.330 words (67,1476%)** at **1.145 native functions** and **18.861 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-16`)**:
  - Eliminated 100% of the 1.455 hits of the Cluster 2 (`0x80146B74`, `0x80146C10`, `0x80146D80`, `0x80146E18` all reduced to zero).
  - **Zero Main EXE misses during active combat**. The only fallback records are the BIOS/SIO SMC quarantine (`0x801AB1F4` and `0x801AB2C0`).
  - Interpreted fallback fell sharply from +379.198 to **+75.594** (-303.604 interpreted instructions eliminated).
  - Frametime telemetry perfectly stable at 60 FPS with an entirely native action/reaction engine.
- **Edge-Case Validation: Bison Head Press / Skull Diver (`gameplay-discovery-17`)**:
  - Intensive testing of Bison's flaming stomp and dive (repeated hits and whiffs).
  - Main EXE result: **EXACTLY 0 MISSES** (0 new static candidates). Native dispatches: **+210.765**.
  - Architectural Diagnosis: The limb fire effect and move-specific state machine run entirely in Bison's dynamic RAM overlay (`0x8004485C..0x80044DE8`, ~40k hits) and overlay animation dispatcher (`0x80093588..0x80093D70`). The Main EXE static framework for the match is fully saturated and native.

---

### S1-275: Combat Action Subsystem (charge/Hold) & Overlay Support Leaf (Promoted and Validated)
- **Origin / Trigger**: Test Chun-Li vs Guile on the stage of Guile (`gameplay-discovery-18`), revealing 12 candidate PCs in the Main EXE Text with a total of **48.935 interpreted hits**.
- **Block 1 (Gap of charge/Hold `0x8011F5F0..0x801202EC`, 9 contiguous functions, 3.324 bytes / 831 words)**:
  - `0x8011F5F0`: 116 bytes / **29 words** (1 hit; register and charge-vector setup).
  - `0x8011F664`: 76 bytes / **19 words** (201 hits; state-flag updater).
  - `0x8011F6B0`: 52 bytes / **13 words** (185 hits; cleanup of attack buffers).
  - `0x8011F6E4`: 128 bytes / **32 words** (3.290 hits; dispatch loop with `jalr ra, v0` via table `0x801AFF08`).
  - `0x8011F764`: 72 bytes / **18 words** (3.290 hits; **Formal root** referenced by index 10 of the combat action table `0x801AFC70` at offset `0x801AFC98`).
  - `0x8011F7AC`: 52 bytes / **13 words** (1 hit; frame and animation transition).
  - `0x8011F7E0`: 444 bytes / **111 words** (3.290 hits; cancel and charge-timing manager).
  - `0x8011F99C`: 1.164 bytes / **291 words** (**34.426 hits**; active frame processor for rapid and charge moves, target 0 of table `0x801AFF08`; contains the sub-path `0x8011FA88` with 236 hits).
  - `0x8011FE28`: 1.220 bytes / **305 words** (**3.044 hits**; finalizer and post-attack transition, target 1 of table `0x801AFF08`; contains the sub-path `0x8011FF24` with 166 hits).
  - Topology: Joins native function `0x8011F084` contiguously and without gaps to the start of batch S1-272 (`0x801202EC`).
- **Block 2 (Micro-gap Leaf `0x80167ED4..0x80167EF8`, 1 leaf function, 36 bytes / 9 words)**:
  - `0x80167ED4`: 36 bytes / **9 words** (**1.092 hits**; pure leaf without a stack frame, called by 8 sites in the dynamic RAM overlay engine `0x8008FEF4..0x80090040`).
  - Topology: Seamlessly joins native function `0x80167E34` to `0x80167EF8`.
- **Call Closure**: All 16 direct calls `JAL` point to functions already compiled in the Main EXE (`0x801938B0`, `0x8019DF20`, `0x80194990`, `0x801945F8`, `0x801946C8`, `0x801948DC`, `0x8019CE70`, `0x8019D740`, `0x8019D7D0`, `0x8010C72C`). Zero external jumps; closure expansion ZERO.
- **JALR Resolution at `0x8011F734`**: The indirect jump consults table `0x801AFF08`, whose only two destinations (`0x8011F99C` and `0x8011FE28`) were promoted in this batch, ensuring direct native resolution through `call_by_address`.
- **Total Budget S1-275**: 10 new functions, 3.360 bytes / **840 words**.
- **Final Coverage S1-275**: **132.170 words (67,5771%)** at **1.155 native functions** and **20.129 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-20`)**:
  - Eliminated 100% of the 12 candidates and 48.935 misses observed in Chun-Li vs Guile.
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - native dispatches rose to **+168.827 hits**.
  - interpreted fallback plummeted from +9.149.650 to +111.159 (-9.038.491 interpreted instructions eliminated; drop of 98,8%).
  - Locked, highly stable frametime at 60 FPS confirmed throughout active combat. Transient variations at fight boundaries (round start and K.O./replay/victory pose) come from dynamic RAM overlay routines (Track 2: `0x80048960`, `0x80046EEC`, `0x800477D0`).

---

### S1-276: Guile Combat Action Subsystem (Sonic Boom & Flash Kick) (Promoted and Validated)
- **Origin / Trigger**: Test with reversed roles (Guile P1 attacking with Chun-Li inactive P2, `gameplay-discovery-21`), revealing 4 candidate PCs in the Main EXE Text with a total of **6.534 interpreted hits**.
- **Topology & Boundaries (2 new functions, 1.180 bytes / 295 words)**:
  - `0x8011E344`: 104 bytes / **26 words** (2.655 hits at entry, 1 hit at `0x8011E390`; **Formal root** referenced by index 9 of the combat action table `0x801AFC70` at offset `0x801AFC94`; dispatches to `0x8011E3AC` native and `0x8011E628`).
  - `0x8011E628`: 1.076 bytes / **269 words** (2.655 hits at the root, 1.223 hits in the internal sub-block `0x8011E900`; processor for Guile move physics, impact vectors, and collisions).
- **Call Closure**: All 14 direct calls `JAL` point to routines already native in the Main EXE (`0x801938B0`, `0x8011EA5C`, `0x8019D740`, `0x8019D7D0`, `0x8011EA80`, `0x8019E870`, `0x8019CE70`, `0x80167D28`, `0x8019EA10`). Zero external jumps, Zero indirect jumps, closure expansion: **ZERO**.
- **Main EXE Continuity**: Seamlessly fills the gap before `0x8011E3AC` and between `0x8011E628` and `0x8011EA5C`, establishing more than 15.000 uninterrupted bytes of native static code between `0x8011D030` and `0x80120E44`.
- **Total Budget S1-276**: 2 new functions, 1.180 bytes / **295 words**.
- **Final Coverage S1-276**: **132.465 words (67,7284%)** at **1.157 native functions** and **20.129 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-22`)**:
  - Eliminated 100% of the 4 candidates and 6.534 misses observed in Guile vs Chun-Li (`0x8011E344`, `0x8011E390`, `0x8011E628`, `0x8011E900` all reduced to zero).
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - native dispatches remained very high: **+309.787 hits**.
  - Interpreted fallback plummeted from +2.474.813 to only **+23.032** (99,1% reduction, the project's new absolute historical minimum).
  - Guile formally validated as the 8º character with 100% native execution in the Main EXE.

---

### S1-277: Sakura Combat Action Subsystem & Collision Vector Leaf (Promoted and Validated)
- **Origin / Trigger**: Test Sakura vs Pullum Purna on stage Plus (`gameplay-discovery-24`), revealing 16 candidate PCs in the Main EXE Text with a total of **39.516 interpreted hits**.
- **Architectural Diagnosis**: Previous Sakura optimization covered Track 2 (dynamic RAM overlays `0x8004xxxx`). In the static Main EXE, Sakura triggers **Index 6 of the Global Action Table** (`0x801AFC70` at offset `0x801AFC88` -> `0x8011BD94`), which had not yet been statically recompiled.
- **Block 1 (Cluster of Action of the Sakura `0x8011BD94..0x8011D030`, 8 contiguous functions, 4.764 bytes / 1.191 words)**:
  - `0x8011BD94`: 104 bytes / **26 words** (1 hit at the root, 1 hit at `0x8011BDE0`; **Formal root** referenced by index 6 of table `0x801AFC70` at offset `0x801AFC88`; dispatches to `0x8011BDFC` and `0x8011C01C`).
  - `0x8011BDFC`: 544 bytes / **136 words** (1 hit; setup of properties, attack buffers and physics flags).
  - `0x8011C01C`: 816 bytes / **204 words** (3.447 hits at entry, sub-blocks `0x8011C0C4` [1 hit], `0x8011C118` [1 hit], `0x8011C144` [1 hit], `0x8011C288` [1 hit]; dispatch loop with `jalr ra, v0` via table `0x801AFDF8`).
  - `0x8011C34C`: 36 bytes / **9 words** (1 hit; cleanup of buffers and combat-command resets).
  - `0x8011C370`: 20 bytes / **5 words** (1 hit; atomic state-transition handler).
  - `0x8011C384`: 1.368 bytes / **342 words** (**27.420 hits** at the root, sub-blocks `0x8011C470` [1 hit], `0x8011C4E4` [1 hit], `0x8011C54C` [1 hit], `0x8011C774` [1 hit]; primary processor for Sakura physics, combos, and projectiles; target 0 of table `0x801AFDF8`).
  - `0x8011C8DC`: 880 bytes / **220 words** (**8.636 hits**; body collision, impact timing, and cancel processor; target 1 of table `0x801AFDF8`).
  - `0x8011CC4C`: 996 bytes / **249 words** (1 hit; attack-frame finalizer, recoil, and transition to neutral pose).
  - Topology: Seamlessly joins native function `0x8011B5E4` (ending at `0x8011BD94`) to the start of batch S1-246 (`0x8011D030`), fully closing the gap and creating a contiguous native block of more than 23 KB between `0x8011B3B8` and `0x80120E44`.
- **Block 2 (Collision Vector Calculator Leaf `0x8015DDC4..0x8015DE60`, 1 formal function, 156 bytes / 39 words)**:
  - `0x8015DDC4`: 156 bytes / **39 words** (1 hit; 3D vector calculator for fighter distance and hitboxes, called by `0x8019EFD0`).
  - Topology: Precisely fills the gap between native function `0x8015DC78` (ending at `0x8015DDC4`) and `0x8015DE60`.
- **Call Closure**: All 51 direct calls `JAL` point to functions already native in the Main EXE (`0x801938B0`, `0x8019DF20`, `0x8019D740`, `0x8019D7D0`, `0x8019E870`, `0x8019E778`, `0x8019CE70`, `0x8010C72C`, etc.) or internal to the cluster. closure expansion: **ZERO**.
- **JALR Resolution at `0x8011C1DC`**: Dynamic dispatch reads table `0x801AFDF8`, whose only two pointers (`0x8011C384` and `0x8011C8DC`) belong to this micro-batch, ensuring immediate native resolution through `call_by_address`.
- **Total Budget S1-277**: 9 new functions, 4.920 bytes / **1.230 words**.
- **Final Coverage S1-277**: **133.695 words (68,3568%)** at **1.166 native functions** and **20.129 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-25`)**:
  - Eliminated 100% of the 16 candidates and 39.516 misses observed in session 24.
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - native dispatches: **+147.240 hits**.
  - Interpreted fallback plummeted from +1.370.296 to only **+116.517** (91,5% reduction, -1.253.779 interpreted instructions eliminated).
  - Sakura formally validated as the 9th fighter running 100% natively in the static Main EXE.
- **Reversed Gameplay Validation (`gameplay-discovery-26` - Pullum Purna P1 vs Sakura P2)**:
  - New Main EXE promotion candidates: **EXACTLY 0** (0 dispatch misses, 0 misses in the Main EXE).
  - native dispatches maintained a high volume: **+197.291 hits** (+285.820 cumulative delta).
  - Fallback is concentrated entirely in dynamic RAM overlay code (`0x80045xxx`, `0x8008Exxx`, `0x8009xxxx`).
  - Pullum Purna formally validated as the 10th fighter running 100% natively in the static Main EXE.

---

### S1-278: Gameplay Status Dispatcher & Combat Vector Transition Cluster (Promoted and Validated)
- **Origin / Trigger**: Doctrine Dark vs Darun Mister test on Darun's stage (`gameplay-discovery-27`), revealing an unstable, noisy frametime graph caused by **+1.002 Native Handoffs** and 5 Main EXE Text candidates with **160 interpreted hits**.
- **Architectural Diagnosis**:
  - Previous D.Dark work covered Track 2 (RAM overlays `0x8004xxxx`, OVL-002 bomb and explosive series).
  - In the static Main EXE, active D.Dark and Darun combat encountered a 268-byte gap between native routines `0x80140B6C` (ending at `0x80140CE8`) and `0x80140DF8` (starting at `0x80140DF8`). Each attack fell into interpretation in the gap and returned to the next native block, causing +1.002 handoffs per frame and frametime fluctuation.
  - Additionally, index 4 (`0x801AE884` -> `0x80102B10`) of the global game status table at `0x801AE874` was triggered with 83 interpreted hits.
- **Topology & Boundaries (3 new functions, 892 bytes / 223 words)**:
  - **Block 1 (Global Status Table Entry, 1 function, 624 bytes / 156 words)**:
    - `0x80102B10`: 624 bytes / **156 words** (83 hits; formal game-mode dispatcher referenced by index 4 of table `0x801AE874` at offset `0x801AE884`; joins `0x80102B10` to `0x80102D80`; calls `0x80101D18` native).
  - **Block 2 (Gap of combat D.Dark/Darun `0x80140CEC..0x80140DF8`, 2 contiguous functions, 268 bytes / 67 words)**:
    - `0x80140CEC`: 76 bytes / **19 words** (1 hit; setup of properties, attack buffers and collision matrices; calls `0x80123A94` native; closes the gap between `0x80140CE8` and `0x80140D38`).
    - `0x80140D38`: 192 bytes / **48 words** (39 hits at the root, 1 hit at `0x80140DA0` and 36 hits in the epilogue `0x80140DE4`; active processor for actions, recoil, and combat transitions; calls `0x80140DF8`, `0x80123AE0`, `0x80141454`, `0x801411D8` all native; joins with `0x80140DF8`).
- **Call Closure**: All 6 direct calls `JAL` point to functions already native in the Main EXE (`0x80101D18`, `0x80123A94`, `0x80140DF8`, `0x80123AE0`, `0x80141454`, `0x801411D8`). Zero external jumps; closure expansion: **ZERO**.
- **Total Budget S1-278**: 3 new functions, 892 bytes / **223 words**.
- **Final Coverage S1-278**: **133.918 words (68,4708%)** at **1.169 native functions** and **20.129 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-28`)**:
  - Eliminated 100% of the 5 candidates and 160 misses observed in session 27 (`0x80102B10`, `0x80140CEC`, `0x80140D38`, `0x80140DA0`, `0x80140DE4` all reduced to zero).
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: plummeted from +1.002 to **0**.
  - Frametime graph: Visually confirmed 100% clean, smooth, and locked, without the previous run's micro-stutters.
  - native dispatches: **+205.138 hits**.
  - Doctrine Dark formally validated as the 11th fighter running 100% natively in the static Main EXE.

---

### S1-279: Darun Mister Combat Subsystem (Lariats, Heavy Impact & Command Throw Dispatcher) (Promoted and Validated)
- **Origin / Trigger**: Test with reversed roles (Darun Mister P1 attacking versus D.Dark inactive P2 on stage Darun, `gameplay-discovery-29`), revealing 27 candidates in the Main EXE Text with a total of **2.348 interpreted hits**.
- **Architectural Diagnosis**:
  - Command grabs, throws (*Indra Bridge*, *Daisharin*), *Lariats*, and the 720 special (*Twilight Collar*) depend on shared Main EXE infrastructure: the **Global Throw Table (`0x801B33F0`)** and heavy-physics dispatchers at `0x80128xxx`.
  - Uncompiled execution of this infrastructure triggered 27 collision points in the Main EXE Text.
- **Topology & Boundaries (13 new functions, 2.712 bytes / 678 words)**:
  - **Block 1 (Gap of Lariat / Grab Linkage `0x80127FB8..0x80128014`, 1 function, 92 bytes / 23 words)**:
    - `0x80127FB8`: 92 bytes / **23 words** (96 hits at the root, 96 hits at `0x80127FF8`, 3 hits at `0x80127FF0`, 3 hits at `0x80128000`; joins seamlessly `0x80127D1C` a `0x80128014`).
  - **Block 2 (Heavy Impact Gap & Lariat Engine `0x80128A40..0x80128D74` + Helper `0x8012B86C`, 5 functions, 956 bytes / 239 words)**:
    - `0x80128A40`: 308 bytes / **77 words** (352 hits; primary Lariat impact processor).
    - `0x80128B74`: 84 bytes / **21 words** (352 hits at `0x80128B58`; spin and impulse setup).
    - `0x80128BC8`: 88 bytes / **22 words** (post-hit transition; calls `0x8012B86C`).
    - `0x80128C20`: 340 bytes / **85 words** (Lariat finalizer and recoil calculation; calls `0x8012B86C`).
    - `0x8012B86C`: 136 bytes / **34 words** (heavy collision vector helper; fills 100% of the gap `0x8012B86C..0x8012B8F4`).
    - closes 100% of the gap between `0x80128A40` and `0x80128D74`.
  - **Block 3 (Global Throw Table `0x801B33F0` at `0x80161584..0x80161C04`, 7 contiguous functions, 1.664 bytes / 416 words)**:
    - `0x80161584`: 88 bytes / **22 words** (transition handler referenced by `0x801B3470`).
    - `0x801615DC`: 164 bytes / **41 words** (2 hits; throw setup referenced by `0x801B33FC`).
    - `0x80161680`: 364 bytes / **91 words** (233 hits at the root, 135 hits at `0x801616CC`, etc.; throw body-collision processor referenced by `0x801B3448`).
    - `0x801617EC`: 68 bytes / **17 words** (4 hits; suplex lift vectors referenced by `0x801B3400`).
    - `0x80161830`: 456 bytes / **114 words** (250 hits at the root, 132 hits at `0x801618CC`, 84 hits at `0x801618F4`, 66 hits at `0x80161994`, etc.; throw and damage processor referenced by `0x801B344C`).
    - `0x801619F8`: 68 bytes / **17 words** (3 hits at `0x801619E0`; recoil and release referenced by `0x801B342C`).
    - `0x80161A3C`: 456 bytes / **114 words** (ground impact and recovery referenced by `0x801B3478`).
    - Closes 100% of the gap and eliminates all 21 candidates in the `0x80161xxx` region.
- **Call Closure**: All direct calls `JAL` point to functions internas or already native in the Main EXE (`0x80126614`, `0x801265C0`, `0x8012B730`, `0x8012C628`, `0x8015E12C`, `0x80159E44`, `0x80115574`, etc.). closure expansion: **ZERO** (1.169 -> 1.182 functions exactly).
- **Total Budget S1-279**: 13 new functions, 2.712 bytes / **678 words**.
- **Final Coverage S1-279**: **134.596 words (68,8175%)** at **1.182 native functions** and **20.129 dispatch entries**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-30`)**:
  - Eliminated 100% of the 27 candidates and 2.348 misses observed in session 29 (all reduced to zero in the interpreter).
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: **0** strictly maintained.
  - Frametime graph: visually confirmed clean and stable during throws and lariats.
  - native dispatches maintained a high rate: **+218.855 hits** in the window.
  - Darun Mister formally validated as the 12th fighter running 100% natively in the static Main EXE.

---

### S1-280: Cracker Jack Stage & Action Subsystem (Promoted & Validated)
- **Origin / Trigger**: Reversed combat test (Allen Snider vs Cracker Jack on Cracker Jack's stage, `gameplay-discovery-32`), revealing pointer `0x801AFC80` in the Action Dispatch Table targeting `0x8011ABD4`, and exposing routine `0x8011AFBC` with 153.072 interpreted calls per fight, causing noticeable frametime fluctuations.
- **Topology & Boundaries (8 new functions, 2.652 bytes / 663 words)**:
  - **Block 1 (Gap of vectors and animation of the stage `0x8011A8DC..0x8011AAFC`, 1 function contiguous, 544 bytes / 136 words)**:
    - `0x8011A8DC`: 544 bytes / **136 words** (stage/combat transform and geometry processor; ends with `jr $ra` at `0x8011AAF4`; seamlessly joins `0x8011AAFC`). Address `0x8011A9F8`, with 1 hit, was the return from `jal 0x801945F8`.
  - **Block 2 (Action Dispatcher Subsystem `0x8011AB7C..0x8011B3B8`, 7 contiguous functions, 2.108 bytes / 527 words)**:
    - `0x8011AB7C`: 88 bytes / **22 words** (3.445 hits; caller of `0x8011AFBC`).
    - `0x8011ABD4`: 72 bytes / **18 words** (3.445 hits; Formal root of the Action Dispatch Table at `0x801AFC80`).
    - `0x8011AC1C`: 52 bytes / **13 words** (1 hit; despachador to `0x8011A8DC`).
    - `0x8011AC50`: 876 bytes / **219 words** (3.445 hits; geometric transformations and frame updates).
    - `0x8011AFBC`: 452 bytes / **113 words** (**Workhorse central of combat/stage: 153.072 interpreted hits eliminated!**).
    - `0x8011B180`: 184 bytes / **46 words** (3.445 hits; vectors of camera and collision).
    - `0x8011B238`: 384 bytes / **96 words** (3.445 hits; buffer finalization; joins seamlessly with `0x8011B3B8`).
- **Call Closure**: All direct `JAL` calls and branches are strictly internal to the cluster or target already native static code. Closure expansion: **ZERO** (exactly 1.182 -> 1.190 functions).
- **Total Budget S1-280**: 8 new functions, 2.652 bytes / **663 words**.
- **Final Coverage S1-280**: **135.259 words (69,1565%)** at **1.190 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-33`)**:
  - Eliminated 100% of the 9 candidates and the 153.072 interpreted calls from session 32.
  - O volume of interpreted fallback fell from 14.701.282 to 1.303.848 instructions (**-91,1%**).
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: **0** strictly maintained.
  - Frametime graph: confirmed clean and stable in both orientations (direct and reversed).
  - Cracker Jack (13º) and Allen Snider (14º) formally validated as 100% native in the static Main EXE.

---

### S1-281: Action Dispatcher Subsystem - Blair Dame & Zangief (Promoted & Validated)
- **Origin / Trigger**: Reversed combat test (Blair Dame vs Zangief on Zangief's stage, `gameplay-discovery-35`), revealing pointer `0x801AFC90` in the Action Dispatch Table targeting `0x8011D9B4`, and exposing internal routine `0x8011E18C` with 47.970 interpreted calls per fight.
- **Topology & Boundaries (5 new functions, 2.448 bytes / 612 words)**:
  - Gap contiguous `0x8011D9B4..0x8011E344`:
    - `0x8011D9B4`: 104 bytes / **26 words** (3.846 hits; Formal root of the Action Table at `0x801AFC90`).
    - `0x8011DA1C`: 512 bytes / **128 words** (1 hit; setup of buffers and properties of attack).
    - `0x8011DC1C`: 1.776 bytes / **444 words** (3.846 hits at entry, **47.970 hits at `0x8011E18C`**; central processor for states of combat/reaction).
    - `0x8011E30C`: 36 bytes / **9 words** (734 hits; transition handler).
    - `0x8011E330`: 20 bytes / **5 words** (712 hits; conector terminal; ends with `jr $ra` at `0x8011E33C`; joins seamlessly a `0x8011E344`).
- **Layout and Continuity**: Joins `0x8011D310..0x8011D9B3` (S1-245) to `0x8011E344` (S1-276), unifying the entire range `0x8011BD94..0x8011F5F0` as a contiguous compiled Main EXE block.
- **Call Closure**: All direct calls `JAL` point to functions already native or internal to the block. closure expansion: **ZERO** (1.190 -> 1.195 functions exactly).
- **Total Budget S1-281**: 5 new functions, 2.448 bytes / **612 words**.
- **Final Coverage S1-281**: **135.871 words (69,4694%)** at **1.195 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-36`)**:
  - Eliminated 100% of the 7 candidates from session 35 and the 47.970 interpreted calls to `0x8011E18C`.
  - O volume of interpreted fallback fell from 8.624.913 to 1.621.746 instructions (**-81,2%**).
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: **0** strictly maintained.
  - Native dispatches maintained a high rate: **+201.339 calls** in native C.

---

### S1-282: Grappling Engine - Zangief Command Throws (Promoted & Validated)
- **Origin / Trigger**: Initial Zangief vs Blair Dame test (`gameplay-discovery-34`), which activated the second half of the Global Throw Table `0x801B33F0` at `0x80161C04..0x80161FE4`, revealing 14 candidates (270 hits at `0x80161CCC` and 90 hits at `0x80161E5C`).
- **Topology & Boundaries (7 new functions, 992 bytes / 248 words)**:
  - `0x80161C04`: 8 bytes / **2 words** (stub of transition referenced by `0x801B3410`).
  - `0x80161C0C`: 124 bytes / **31 words** (handler referenced by `0x801B345C`).
  - `0x80161C88`: 68 bytes / **17 words** (setup of arremesso referenced by `0x801B3414; 3 hits`).
  - `0x80161CCC`: 332 bytes / **83 words** (impact body and collision of *Spinning Piledriver* / *Powerbomb* at `0x801B3460`; **270 hits**).
  - `0x80161E18`: 68 bytes / **17 words** (transition referenced by `0x801B3418; 1 hit`).
  - `0x80161E5C`: 332 bytes / **83 words** (trajectory, lift, and impact of *Atomic Suplex* / *Final Atomic Buster* at `0x801B3464`; **90 hits**).
  - `0x80161FA8`: 60 bytes / **15 words** (recoil post-throw referenced by `0x801B3438`).
- **Layout and Continuity**: Connects directly to `0x80161A3C` (promoted in S1-279), extending the Global Throw Table to `0x80161FE4`.
- **Call Closure**: Zero indirect jumps, zero unresolved external calls. closure expansion: **ZERO** (1.195 -> 1.202 functions exactly).
- **Total Budget S1-282**: 7 new functions, 992 bytes / **248 words**.
- **Final Coverage S1-282**: **136.119 words (69,5962%)** at **1.202 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-37`)**:
  - Eliminated 100% of the 14 throw-table candidates from session 34.
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: **0** strictly maintained.
  - Native dispatches reached **+305.438 calls** in native C with maximum stability.
  - Frametime graph: visually confirmed to be extremely clean.

---

### S1-283: Core Combat & Action Engine - Blair Dame & Zangief (Promoted & Validated)
- **Origin / Trigger**: Initial Zangief vs Blair Dame test (`gameplay-discovery-34`), revealing the contiguous gap `0x8013E930..0x8013F7A0` responsible for attack chaining and collision processing (more than 1.000 combined hits).
- **Topology & Boundaries (3 new functions, 3.696 bytes / 924 words)**:
  - `0x8013E930`: 152 bytes / **38 words** (transitions and encadeamento of moves of attack; **527 hits**).
  - `0x8013E9C8`: 408 bytes / **102 words** (physical property and impulse vector setup; 6 hits).
  - `0x8013EB60`: 3.136 bytes / **784 words** (loop central of processing of animation and combat; **517 hits**).
- **Layout and Continuity**: Joins `0x8013E764..0x8013E92F` (promoted in S1-146) directly to `0x8013F7A0` (S1-177/210), eliminating the entire gap in this combat range.
- **Call Closure**: Zero indirect jumps, zero unresolved external calls. closure expansion: **ZERO** (1.202 -> 1.205 functions exactly).
- **Total Budget S1-283**: 3 new functions, 3.696 bytes / **924 words**.
- **Final Coverage S1-283**: **137.043 words (70,0686%)** across **1.205 native functions**. Codegen audit: **CLEAN**. **The 70% binary coverage milestone was officially reached**.
- **Gameplay Validation (`gameplay-discovery-38`)**:
  - Eliminated 100% of the candidates of attack of the session 34.
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: **0** strictly maintained.
  - native dispatches: **+168.833 calls** at C native.
  - Frametime graph: visually confirmed to be extremely clean.

---

### S1-284: Movement & Sliding Subroutines - Blair Dame (Promoted & Validated)
- **Origin / Trigger**: Initial Zangief vs Blair Dame test (`gameplay-discovery-34`), revealing the contiguous gap `0x8014901C..0x801495D4` responsible for ground sliding (*sliding*), post-attack forward movement, and ground recovery friction/recoil.
- **Topology & Boundaries (3 new functions, 1.464 bytes / 366 words)**:
  - `0x8014901C`: 152 bytes / **38 words** (ground acceleration vectors and sliding calculation; **32 hits**).
  - `0x801490B4`: 268 bytes / **67 words** (forward movement and post-attack stance transition; **1 hit**).
  - `0x801491C0`: 1.044 bytes / **261 words** (processing of atrito, recoil and recovery of solo; **31 hits**).
- **Layout and Continuity**: Connects directly to `0x80148B64..0x8014901C` (function compilada anteriormente), extending continuous block coverage to `0x801495D4`.
- **Call Closure**: Zero indirect jumps `jr $reg`, zero unresolved external calls (100% closed closure). closure expansion: **ZERO** (1.205 -> 1.208 functions exactly).
- **Total Budget S1-284**: 3 new functions, 1.464 bytes / **366 words**.
- **Final Coverage S1-284**: **137.409 words (70,2557%)** at **1.208 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-39`)**:
  - Eliminated 100% of the candidates of movimento and sliding of the session 34.
  - New Main EXE promotion candidates: **EXACTLY 0** (`candidates.txt` empty).
  - Native Handoffs: **0** strictly maintained.
  - Frametime graph: Confirmed extremely stable throughout combat, with transient jitter restricted to initial scene/overlay loading.
- **Cycle Conclusion**: **Zangief (15º)** and **Blair Dame (16º)** officially validated with **100% native execution** in the Main EXE.

---

### S1-285: Acrobatic Action, Trajectory & Combat States - Skullomania (Prepared & Audited)
- **Origin / Trigger**: Initial Skullomania vs Ryu test (`gameplay-discovery-40`), revealing 22 Main EXE candidates and isolating the *Skullo Dream* micro-ripple in dynamic RAM hotspot `0x80093E4C` (+13.966.308 interpreted insns).
- **Topology & Boundaries (6 new functions, 3.788 bytes / 947 words distributed across 3 contiguous gaps)**:
  - **Gap 1: calculation of trajectory and vectors Especiais (`0x8012A7E4..0x8012AA74`)**:
    - `0x8012A7E4`: 656 bytes / **164 words** (457 hits at entry and 457 hits at the return `0x8012AA54`; jump vector and sliding-position calculation; 5 native JAL calls).
  - **Gap 2: Acrobatic Action and 3D Transformation Engine (`0x801441B0..0x80144AD8`)**:
    - `0x801441B0`: 156 bytes / **39 words** (238 hits; initial handler for attack acrobatic).
    - `0x8014424C`: 332 bytes / **83 words** (14 hits at entry and hits at `0x80144358` and `0x8014436C`; transition of mergulho / *Skullo Dive*).
    - `0x80144398`: 1.856 bytes / **464 words** (210 hits; central processor for rotation of malhas, bones and hitboxes with 73 instructions COP2 GTE).
  - **Gap 3: Attack/Reaction State Machine (`0x80160790..0x80160AA4`)**:
    - `0x80160790`: 80 bytes / **20 words** (hits at `0x80160790`, `0x801607C0`, `0x801607CC`; dispatch of properties of attack).
    - `0x801607E0`: 708 bytes / **177 words** (50 hits at entry and multiple internal blocks `0x8016084C..0x80160A90`; central collision-state and guard-break loop).
- **Layout and Continuity**:
  - Gap 1 joins `0x8012A58C` a `0x8012AA74`.
  - Gap 2 joins `0x801439E4` (S1-274 F1) a `0x80144AD8`.
  - Gap 3 joins `0x80160480` a `0x80160AA4` (S1-270 F2).
- **Call Closure**: All 36 direct calls `JAL` point to functions already native or internal to the batch. closure expansion: **ZERO** (1.208 -> 1.214 functions exactly). Zero indirect jumps (`jr $ra` estrito).
- **Total Budget S1-285**: 6 new functions, 3.788 bytes / **947 words**.
- **Final Coverage S1-285**: **138.356 words (70,7400%)** at **1.214 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-41`)**:
  - Eliminated 100% of the 22 candidates of the session 40 (`candidates.txt` empty).
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: **0** strictly maintained.
  - Frametime graph: Confirmed extremely stable throughout combat, with micro-fluctuation restricted exclusively to the *Skullo Dream* loop in dynamic RAM (`0x80093E4C`).
- **Cycle Conclusion**: **Skullomania (17º)** officially validated with **100% native execution** in the Main EXE.

---

### S1-286: GTE Vector Math Subroutine Cluster - Hokuto (Prepared & Audited)
- **Origin / Trigger**: Initial Hokuto vs Ryu test (`gameplay-discovery-42`), revealing only 1 residual Main EXE candidate (`0x8019D9FC`, 308 hits).
- **Topology & Boundaries (10 contiguous leaf functions, 500 bytes / 125 words)**:
  - Gap contiguous `0x8019D860..0x8019DA54`:
    - `0x8019D860`: 40 bytes / **10 words** (Transformation of rotation GTE; frameless leaf; `jr $ra`).
    - `0x8019D888`: 40 bytes / **10 words** (Transformation of scale GTE; frameless leaf; `jr $ra`).
    - `0x8019D8B0`: 60 bytes / **15 words** (Transformation of composite matrix GTE; frameless leaf; `jr $ra`).
    - `0x8019D8EC`: 36 bytes / **9 words** (Vector multiplication GTE; frameless leaf; `jr $ra`).
    - `0x8019D910`: 40 bytes / **10 words** (Dot product GTE with clamp; frameless leaf; `jr $ra`).
    - `0x8019D938`: 40 bytes / **10 words** (Cross product GTE; frameless leaf; `jr $ra`).
    - `0x8019D960`: 32 bytes / **8 words** (Orthogonal projection GTE; frameless leaf; `jr $ra`).
    - `0x8019D980`: 36 bytes / **9 words** (Vector normalization GTE; frameless leaf; `jr $ra`).
    - `0x8019D9A4`: 88 bytes / **22 words** (Transformation of vertices and lighting GTE; frameless leaf; `jr $ra`).
    - `0x8019D9FC`: 88 bytes / **22 words** (Transformation vetorial MVMVA GTE; 308 hits; `jr $ra`).
- **Layout and Continuity**: Joins `0x8019D850..0x8019D85C` directly to `0x8019DA54..0x8019DA6C`, unifying the entire range `0x8019D740` to `0x8019DA6C` as a contiguous compiled super-block with 100% native execution.
- **Call Closure**: All 10 functions are pure frameless leaves without external `JAL` calls. Closure expansion: **EXACTLY ZERO** (1.214 -> 1.224 functions exactly). Zero indirect jumps (strict `jr $ra`).
- **Total Budget S1-286**: 10 new functions, 500 bytes / **125 words**.
- **Final Coverage S1-286**: **138.481 words (70,8038%)** at **1.224 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-43`)**:
  - Eliminated 100% of the residual candidate `0x8019D9FC` from session 42 (`candidates.txt` empty).
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: **0** strictly maintained.
  - Frametime graph: confirmed perfectly stable and clean throughout the fight.
- **Cycle Conclusion**: **Hokuto (18º)** officially validated with **100% native execution** in the Main EXE.

### S1-287: Dhalsim Mechanics & Bone Animation Pipeline (Prepared & Audited)
- **Origin / Trigger**: Initial Dhalsim vs Ryu test (`gameplay-discovery-45`), revealing exactly 8 residual Main EXE records (total: 2.002 hits):
  - `0x80194BB4` (1.728 hits), `0x8014B430` (72 hits), `0x8014B21C` (46 hits), `0x8014B6B0` (40 hits), `0x8014B524` (36 hits), `0x8014B580` (36 hits), `0x8015A530` (31 hits), `0x8014B2B4` (2 hits).
- **Clarification of Return Addresses**:
  - The MIPS disassembly audit revealed that `0x8014B430`, `0x8014B524`, and `0x8014B580` are return sites for `jal` calls (`0x801945F8` and `0x8019C0B8`) within function `0x8014B2B4`, rather than function roots. With an interpreted caller and native callee, the return triggered fallback at the next PC.
- **Topology & Boundaries (9 functions in 3 clusters, 3.120 bytes / 780 words)**:
  - **Cluster Dhalsim (`0x8014B21C..0x8014BA4C`, 2.096 bytes / 524 words)**:
    - `0x8014B21C`: 152 bytes / **38 words** (Dispatch Root of Dhalsim in table `0x801B1BA8`; calls `0x8014B2B4`, `0x8014B6B0` and `0x80123AE0`).
    - `0x8014B2B4`: 1.020 bytes / **255 words** (kinematic calculation of alcance and deformation elastic of the limbs).
    - `0x8014B6B0`: 924 bytes / **231 words** (Dhalsim stance and elastic hitbox updates).
  - **Cluster Yoga Fire (`0x8015A530..0x8015A600`, 208 bytes / 52 words)**:
    - `0x8015A530`: 208 bytes / **52 words** (fire-projectile physics and collision; pure leaf with `jr $ra` epilogue at `0x8015A5F8`).
  - **Cluster Pipeline of animation (`0x80194BB4..0x80194EE4`, 816 bytes / 204 words)**:
    - `0x80194BB4`: 96 bytes / **24 words** (calculation of bones of animation; Pure leaf; 1.728 hits).
    - `0x80194C14`: 108 bytes / **27 words** (bone orientation matrix; pure leaf).
    - `0x80194C80`: 56 bytes / **14 words** (joint indexing and bounds; pure leaf).
    - `0x80194CB8`: 384 bytes / **96 words** (transform application and calls to `0x8019528C`).
    - `0x80194E38`: 172 bytes / **43 words** (secondary transform application).
- **Call Closure**:
  - All 13 mapped `jal` targets are already native (`0x80123AE0`, `0x801938B0`, `0x80194990`, `0x801948DC`, `0x801946C8`, `0x801945F8`, `0x8019C184`, `0x8019C0B8`, `0x8019CE70`, `0x8019D740`, `0x8019D7D0`, `0x8010C72C`, `0x8019528C`) or included in the batch (`0x8014B2B4`, `0x8014B6B0`). Closure expansion: **ZERO**.
- **Total Budget S1-287**: 9 new functions, 3.120 bytes / **780 words**.
- **Final Coverage S1-287**: **139.261 words (71,2026%)** at **1.233 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-46`)**:
  - Eliminated 100% of the 8 residual candidates of the session 45 (`candidates.txt` empty).
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: **0** strictly maintained.
  - Diverged Pages: **0**.
  - Frametime graph: confirmed extremely clean and stable throughout the fight.
- **Cycle Conclusion**: **Dhalsim (19º)** officially validated with **100% native execution** in the Main EXE.
- **Immediate Validation: Cycloid-β (20º Character native)**:
  - Tested in session `gameplay-discovery-47` (Cycloid-β vs Ryu, stage Ryu).
  - Results: **EXACTLY 0 candidates in the Main EXE** (`candidates.txt` empty), 0 native handoffs, 0 Diverged Pages, stable, clean frametime.
  - Cycloid-β's moveset shares already promoted dispatches and kinematic mechanics, so it ran entirely natively on the first test.
- **Validation: Cycloid-γ (21º Character native)**:
  - Tested in session `gameplay-discovery-48` (Cycloid-γ vs Ryu, stage Ryu).
  - Main EXE results: **EXACTLY 0 static promotion candidates** (`candidates.txt` empty), 339.883 static hits (100% native static dispatches), 0 native handoffs, 0 diverged pages.
  - Technical Frametime Diagnosis: The frametime fluctuation came from the **Dynamic RAM Overlay (Track 2, `0x80040000..0x80090000`)**, while the Main EXE (Track 1) ran entirely natively. Total interpreted instructions rose to 40,85 million (+6,7M relative to Beta), with new heavy hotspots at `0x80048930` (462k insns) and `0x8004880C` (177k insns) due to the character's special moves and teleports.
- **Immediate Validation: Bloody Hokuto (22º Character native)**:
  - Tested in session `gameplay-discovery-49` (Bloody Hokuto vs Ryu, stage Ryu).
  - Results: **EXACTLY 0 Main EXE candidates** (`candidates.txt` empty), 195.889 static hits, 0 native handoffs, 0 diverged pages, stable, clean frametime (interpreted RAM volume fell to only 25,4M insns).
  - Bloody Hokuto fully shares standard Hokuto's matrix and kinematic subroutines (promoted in S1-286), so she executed entirely natively without misses.
- **Immediate Validation: Evil Ryu (23º Native Character - ROSTER 100% COMPLETE)**:
  - Tested in session `gameplay-discovery-50` (Evil Ryu vs Ryu, stage Ryu).
  - Results: **EXACTLY 0 Main EXE candidates** (`candidates.txt` empty), 219.488 static hits, 0 native handoffs, 0 diverged pages, perfectly clean and stable frametime.
  - Evil Ryu shares the kinematic foundation, projectile dispatches (Hadouken), and animation transforms with Ryu and Akuma, so he executed entirely natively without misses.
  - **HISTORICAL MILESTONE COMPLETED**: **100% of Street Fighter EX Plus Alpha's 23 characters are officially validated and execute natively in the Main EXE!**

### S1-288: Boot Sequence & Attract/Demo Presentation Pipeline (Prepared & Audited)
- **Origin / Trigger**: Detailed boot and attract-mode inspection (`gameplay-discovery-51`, route: Boot -> Capcom/Arika Logos -> Intro Video/3D Render -> Title Screen), revealing 14 residual Main EXE records:
  - `0x80136648` (1.134 hits), `0x80136824` (1.134 hits), `0x80136AC8` (478 hits), `0x80136D38` (450 hits), `0x80136F5C` (350 hits), `0x8013701C` (350 hits), `0x80102488` (85 hits), `0x80136B64` (16 hits), `0x80136DEC` (16 hits), `0x80136C44` (8 hits), `0x80136C8C` (8 hits), `0x8010250C` (3 hits), `0x80102520` (3 hits), `0x801366E4` (3 hits).
- **Clarification of Return Addresses**:
  - 6 of the 14 records are return sites for native `jal` calls inside functions running in the interpreter:
    - `0x8010250C` and `0x80102520` (returns from `jal 0x80194B00` inside `0x80102488`).
    - `0x80136C44` and `0x80136C8C` (returns from `jal 0x801945F8` inside `0x80136B64`).
    - `0x80136DEC` (return from `jal 0x8016864C` inside `0x80136D38`).
    - `0x8013701C` (return from `jal 0x8019C0B8` inside `0x80136F5C`).
- **Topology & Boundaries (8 functions in 2 clusters, 3.888 bytes / 972 words)**:
  - **Post-Boot Video / Display Setup Cluster (`0x80102488..0x80102838`, 944 bytes / 236 words)**:
    - `0x80102488`: 944 bytes / **236 words** (initial display-packet buffer setup and rendering-context initialization; precisely closes the gap between `0x801021B0` and `0x80102838`).
  - **Cluster Cadeia contiguous of Attract & Demo Play (`0x80136648..0x801371C8`, 2.944 bytes / 736 words)**:
    - `0x80136648`: 156 bytes / **39 words** (Attract / Demo mode main sequencer; 1.134 hits).
    - `0x801366E4`: 320 bytes / **80 words** (intro camera control, projection, and frustum; 3 hits).
    - `0x80136824`: 676 bytes / **169 words** (game-logo rendering and 3D matrices; 1.134 hits).
    - `0x80136AC8`: 156 bytes / **39 words** (automated demo combat dispatcher; 478 hits).
    - `0x80136B64`: 468 bytes / **117 words** (demo fight kinematics and collisions; 16 hits).
    - `0x80136D38`: 548 bytes / **137 words** (demo AI and action-selection routine; 450 hits).
    - `0x80136F5C`: 620 bytes / **155 words** (demo animation and matrix resolver; 350 hits).
- **Call Closure**:
  - All calls `jal` externas target existing native routines (`0x80194B00`, `0x80194A44`, `0x801948DC`, `0x80194828`, `0x80123BF4`, `0x8019DF20`, `0x8019CD60`, `0x8019CE70`, `0x8019D740`, `0x8019D7D0`, `0x8019D7A0`, `0x8019D770`, `0x8010D1E8`, `0x80194990`, `0x801946C8`, `0x801945F8`, `0x8016864C`, `0x8010C72C`, `0x8019C0B8`, `0x8019C184`).
  - Calls internal to the batch: `0x801366E4`, `0x80136824`, `0x80136B64`, `0x80136D38`, `0x80136F5C`. Closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-288**: 8 new functions, 3.888 bytes / **972 words**.
- **Final Coverage S1-288**: **140.233 words (71,6996%)** at **1.241 native functions**. Codegen audit: **CLEAN**.
- **Gameplay / Boot Validation (`gameplay-discovery-52`)**:
  - Eliminated 100% of the 14 residual candidates of the session 51 (`candidates.txt` empty).
  - New Main EXE promotion candidates: **EXACTLY 0**.
  - Native Handoffs: **0** strictly maintained.
  - Diverged Pages: **0**.
  - Frametime graph: Confirmed extremely stable and clean on all tested screens (logos, intro render, demo fight, and title screen).
- **Cycle Conclusion**: Boot and attract mode entirely native in the Main EXE. Static coverage exceeds the historical 140.000-word milestone (71,6996%).

---

### Micro-Batch S1-289: Training Mode HUD & Input Processing Pipeline (Cluster 1)

- **Discovery Origin**: Combat and training telemetry in `gameplay-discovery-57` (Evil Ryu x Ken on the Training Stage).
- **Preliminary Diagnosis**:
  - 25 Main EXE candidates were observed across 4 distinct clusters.
  - To maintain strict project safety and avoid nearly 2.000 words of expansion (especially the closure risk of Cluster 4 / Pause Menu), independent cluster isolation was adopted.
  - Micro-Batch S1-289 focuses exclusively on **Cluster 1** (command HUD, combo count, and damage).
- **Functions Promoted in S1-289 (3 functions, 812 bytes / 203 words)**:
  - `0x8013BFA8`: 164 bytes / **41 words** (Training mode main input and HUD loop; 7.510 hits).
  - `0x8013C04C`: 32 bytes / **8 words** (Limpeza and reset of the text buffers/frames of the HUD; 1 hit).
  - `0x8013C06C`: 616 bytes / **154 words** (Renderizador of damage acumulado, Counting of combo and inputs; 6.856 hits).
- **Clarification of Call Returns**:
  - Promoting `0x8013C06C` absorbs and eliminates 3 return records from `jal 0x80193A18` (onscreen font rendering):
    - `0x8013C108` (6.856 hits)
    - `0x8013C160` (6.856 hits)
    - `0x8013C188` (6.856 hits)
  - Perfect abutment: The end of `0x8013C06C` joins the existing compiled range at `0x8013C2D4` directly.
- **Call Closure**:
  - External calls from `0x8013C06C`: `0x80193A18` (font rendering, already native) and `0x80125154` (already native).
  - Calls internal to the cluster: `0x8013BFA8` calls `0x8013C04C` and `0x8013C06C`.
  - closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-289**: 3 new functions, 812 bytes / **203 words**.
- **Final Coverage S1-289**: **140.436 words (71,8034%)** at **1.244 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-58`)**:
  - Elimination of 100% of Cluster 1 candidates (`candidates.txt` without any record of `0x8013BFA8`, `0x8013C04C`, `0x8013C06C` or their returns).
  - More than 28.000 interpreted calls converted to native C execution.
  - 511.834 native static hits without any miss or handoff.

---

### Micro-Batch S1-290: Training Stage 3D Grid & camera Pipeline (Cluster 2)

- **Discovery Origin**: Combat and training telemetry in `gameplay-discovery-57` and `gameplay-discovery-58`.
- **Topology & Boundaries**:
  - Completely fills the contiguous gap `[0x80148678..0x8014901C]` (2.468 bytes / 617 words) between already native blocks `[0x80148184..0x80148678]` and `[0x8014901C..0x801491C0]`.
- **Functions Promoted in S1-290 (3 functions, 2.468 bytes / 617 words)**:
  - `0x80148678`: 152 bytes / **38 words** (Training Stage 3D environment root dispatcher; 102 hits).
  - `0x80148710`: 1.108 bytes / **277 words** (Stage camera projection, frustum, and perspective; 3 hits).
  - `0x80148B64`: 1.208 bytes / **302 words** (Floor-grid vertex lighting and transformation through GTE; 93 hits).
- **Clarification of Call Returns**:
  - Promoting `0x80148710` absorbs the returns from `jal 0x801945F8` (GTE) at `0x801487DC` and `0x801487F8`.
  - Promoting `0x80148B64` absorbs the return from `jal 0x8019C0B8` (GTE) at `0x80148C74`.
  - Eliminates 6 records observed in telemetry.
- **Call Closure**:
  - All calls `jal` (`0x80148710`, `0x80148B64`, `0x80123AE0`, `0x801938B0`, `0x80194990`, `0x801948DC`, `0x801945F8`, `0x801946C8`, `0x80194904`, `0x8019DF20`, `0x8019D270`, `0x8019D7D0`, `0x8019D740`, `0x8019C0B8`, `0x8019C184`, `0x8019DA70`, `0x8010C72C`) are already native.
  - closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-290**: 3 new functions, 2.468 bytes / **617 words**.
- **Final Coverage S1-290**: **141.053 words (72,1188%)** at **1.247 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-59`)**:
  - Elimination of all Cluster 2 candidates (`candidates.txt` has no records for `0x80148678`, `0x80148710`, `0x80148B64`, or their GTE returns).
  - Gap `[0x80148678..0x8014901C]` completely filled.
  - 497.503 native static hits without misses or handoffs.
  - Historical milestone of 141.000 statically compiled words exceeded.

---

### Micro-Batch S1-291: Training Mode Dummy AI, Recovery & Damage Tracking Pipeline (Cluster 3)

- **Discovery Origin**: Combat and training telemetry in `gameplay-discovery-57`, `58`, and `59` (Evil Ryu x Ken on the Training Stage).
- **Dispatch Mechanism**:
  - Dynamically dispatched through indirect table `0x801B2E64` (called through `jalr` at `0x801551BC` and `0x80158038`).
  - Controls the training dummy (Ken) AI cycle, stance detection, automatic blocking (guard), knockdown recovery, and cumulative combo damage.
- **Functions Promoted in S1-291 (7 functions, 1.000 bytes / 250 words)**:
  - `0x801555A8`: 20 bytes / **5 words** (Dummy AI timer and state incrementer; 1.047 hits).
  - `0x801555BC`: 76 bytes / **19 words** (Stance and action lookup in table `0x801B3088`; 1.933 hits).
  - `0x801556E4`: 104 bytes / **26 words** (Dummy secondary action-state handler; 26 hits).
  - `0x80156190`: 172 bytes / **43 words** (Knockdown recovery and get-up routine; 1.645 hits).
  - `0x80156458`: 164 bytes / **41 words** (Dummy automatic blocking / intelligent guard logic; 1.168 hits).
  - `0x801569B0`: 288 bytes / **72 words** (Cumulative damage and impact reaction; 1.334 hits).
  - `0x80156AD0`: 176 bytes / **44 words** (Dummy super-meter management; 267 hits).
- **Clarification of Call Returns (7 returns absorbed)**:
  - Promoting `0x80156190` absorbs the return from `jal 0x8015E12C` at `0x80156210`.
  - Promoting `0x80156458` absorbs the returns from `jal 0x8015E12C` at `0x801564AC` and `0x801564D8`.
  - Promoting `0x801569B0` absorbs the returns from `jal 0x8015D8E4` at `0x80156A1C` and `0x80156A6C`, and from `jal 0x8015E12C` at `0x80156A94`.
  - Promoting `0x80156AD0` absorbs the return from `jal 0x8015E12C` at `0x80156B70`.
  - Eliminates **14 candidates at once** in `candidates.txt`.
- **Call Closure**:
  - All called subroutines (`0x8015E12C`, `0x8015D474`, `0x8015D8E4`) are already native in the Main EXE.
  - Internal call: `0x801569B0` calls `0x80156AD0`.
  - closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-291**: 7 new functions, 1.000 bytes / **250 words**.
- **Final Coverage S1-291**: **141.303 words (72,2467%)** at **1.254 native functions**. Codegen audit: **CLEAN**.
- **Gameplay Validation (`gameplay-discovery-60`)**:
  - Elimination of all Cluster 3 candidates (14 fewer candidates in `candidates.txt`).
  - More than 610.000 native static hits (record: 610.907 hits) without misses or handoffs.

---

### Micro-Batch S1-292: Combat Callback Stub Pipeline

- **Discovery Origin**: Combat telemetry in `gameplay-discovery-60`.
- **Topology & Structure**:
  - `0x80162680`: 8 bytes / **2 words** (Leaf stub `jr ra; nop` in callback table `0x801B3408`; 2 hits).
  - Perfect abutment: Joins native range `[0x80162688..0x801627A4]`.
- **Pause Menu Architectural Decision**:
  - The Pause Menu subsystem (`0x80172DD0..0x8017566C`, ~2.599 words / 10 functions) was intentionally deferred at the operator's request for a dedicated test campaign exploring pause screens in every game mode.
- **Call Closure**:
  - Pure leaf function without children. Closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-292**: 1 new function, 8 bytes / **2 words**.
- **Coverage Target S1-292**: **141.305 words (72,2477%)** at **1.255 native functions**.

---

### Micro-Batch S1-293: CPU AI Core Engine Pipeline (Clusters 1 and 2)

- **Discovery Origin**: Level 8 CPU combat telemetry (Ryu vs Ryu, Suzaku Castle) in `gameplay-discovery-65`.
- **Topology & Structure**:
  - **Cluster 1 (Gap 2)**:
    - `0x80155608`: 220 bytes / **55 words** (Bridge between `0x801555BC` and `0x801556E4`; 40 hits; the only external call is `jal 0x80123910`, already 100% native).
  - **Cluster 2 (Gap 7)**:
    - `0x80158050`: 68 bytes / **17 words** (CPU attack central dispatcher and helper; 216 hits; invoked by 25 Cluster 6 attack routines; calls `0x80158094` internally).
    - `0x80158094`: 224 bytes / **56 words** (Leaf loop checking CPU move timers and frames; 57 hits; zero external calls).
    - `0x80158174`: 32 bytes / **8 words** (Leaf routine for incrementing and counting CPU action state; 74 hits; zero external calls).
- **Structural Abutment**:
  - `0x80155608` fits exactly between native ranges `0x801555BC..0x80155608` and `0x801556E4..0x8015574C`.
  - `0x80158050..0x80158194` directly joins native ranges `0x80157F2C..0x80158050` and `0x80158194..0x801582B8`.
- **Call Closure**:
  - All calls target already native functions or functions within the cluster. Closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-293**: 4 new functions, 544 bytes / **136 words**.
- **Coverage Target S1-293**: **141.441 words (72,3172%)** at **1.259 native functions**.
- **Gameplay Validation (`gameplay-discovery-66`)**:
  - Validated in direct combat against Ryu CPU Level 8.
  - Elimination of 100% of the 4 promoted targets (`0x80155608`, `0x80158050`, `0x80158094`, `0x80158174` dropped to ZERO hits).
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Batch S1-294: CPU AI Core Engine Pipeline (Cluster 3 / Gap 4)

- **Discovery Origin**: Telemetria of combat of the CPU Level 8 at `gameplay-discovery-66` (382 hits).
- **Topology & Structure**:
  - `0x8015623C`: 216 bytes / **54 words** (CPU guard and defensive timing leaf routine; 139 hits; zero external calls).
  - `0x80156314`: 324 bytes / **81 words** (Neutral spacing and projectile reaction calculation; 243 hits; the only external call is `jal 0x80123910`, already native).
- **Structural Abutment**:
  - Fills 100% of the gap between the native function `0x80156190..0x8015623C` and the native function `0x80156458..0x801564FC`.
- **Call Closure**:
  - No new external dependencies. Closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-294**: 2 new functions, 540 bytes / **135 words**.
- **Coverage Target S1-294**: **141.576 words (72,3862%)** at **1.261 native functions**.
- **Gameplay Validation (`gameplay-discovery-67`)**:
  - Validated in direct combat against Ryu CPU Level 8.
  - Elimination of 100% of the 2 promoted targets (`0x8015623C` and `0x80156314` dropped to ZERO hits).
  - Total of residual candidates in the Main EXE fell from 49 to 40 candidates.
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Batch S1-295: CPU AI Core Engine Pipeline (Cluster 4 / Gap 5)

- **Discovery Origin**: Telemetria of combat of the CPU Level 8 at `gameplay-discovery-67`.
- **Topology & Structure**:
  - `0x801564FC`: 152 bytes / **38 words** (Combat target lookup helper; no external calls).
  - `0x80156594`: 164 bytes / **41 words** (CPU approach dispatch; 10 hits; calls `0x801566E4` internally).
  - `0x80156638`: 172 bytes / **43 words** (CPU tactical retreat dispatch; calls `0x801566E4` internally).
  - `0x801566E4`: 296 bytes / **74 words** (Central horizontal tracking and movement routine; 60 hits; no external calls).
  - `0x8015680C`: 236 bytes / **59 words** (Collision and corner-pressure check; 50 hits; calls `0x801566E4` internally).
  - `0x801568F8`: 184 bytes / **46 words** (Jump timer and anti-air logic; 1 hit; no external calls).
- **Structural Abutment**:
  - Fills 100% of the gap between the native function `0x80156458..0x801564FC` and the native function `0x801569B0..0x80156AD0`.
- **Call Closure**:
  - All calls remain strictly internal to `0x801566E4`. closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-295**: 6 new functions, 1.204 bytes / **301 words**.
- **Coverage Target S1-295**: **141.877 words (72,5401%)** at **1.267 native functions**.
- **Gameplay Validation (`gameplay-discovery-68`)**:
  - Validated in direct combat against Ryu CPU Level 8.
  - Elimination of 100% of the 6 promoted targets (`0x801564FC..0x801568F8` dropped to ZERO hits), along with the associated internal offsets.
  - Contiguous connection of the entire segment `0x80156190..0x80156B80` (nearly 2,5 KB), 100% native.
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Batch S1-296: CPU AI Core Engine Pipeline (Gap 3 Part 1: Positioning and Evasion)

- **Discovery Origin**: Telemetria of combat of the CPU Level 8 at `gameplay-discovery-68` (371 hits).
- **Topology & Structure**:
  - `0x8015574C`: 88 bytes / **22 words** (Mid-range distance calculation leaf routine; 92 hits).
  - `0x801557A4`: 76 bytes / **19 words** (Cornering and wall-check leaf routine; 22 hits).
  - `0x801557F0`: 80 bytes / **20 words** (Quick evasion and dash-back leaf routine; 251 hits).
  - `0x80155840`: 140 bytes / **35 words** (High/low guard timing leaf routine; 6 hits).
  - `0x801558CC`: 184 bytes / **46 words** (Normal-move frame-data lookup helper; no external calls).
  - `0x80155984`: 212 bytes / **53 words** (Punch/kick button priority helper; no external calls).
  - `0x80155A58`: 196 bytes / **49 words** (Neutral timer and stance reset; no external calls).
- **Structural Abutment**:
  - Connects directly to native function `0x801556E4..0x8015574C`, advancing linearly from `0x8015574C` to `0x80155B1C`.
- **Call Closure**:
  - All 7 functions are pure leaves or self-contained helpers. Closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-296**: 7 new functions, 976 bytes / **244 words**.
- **Coverage Target S1-296**: **142.121 words (72,6649%)** at **1.274 native functions**.
- **Gameplay Validation (`gameplay-discovery-70`)**:
  - Validated in direct combat against Ryu CPU Level 8.
  - Elimination of 100% of the 7 promoted targets (`0x8015574C..0x80155A58` dropped to ZERO hits).
  - More than 370 positioning and evasion hits transferred to native execution.
  - Total residual Main EXE candidates reduced to 38.
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Batch S1-297: CPU AI Core Engine Pipeline (Gap 3 Part 2: Combos, Cancels & Input Simulation)

- **Discovery Origin**: Level 8 CPU combat telemetry in `gameplay-discovery-70` (1.135+ hits in the 3 primary targets).
- **Topology & Structure**:
  - `0x80155B1C`: 664 bytes / **166 words** (Hit-confirm and sequential chaining of normal and special combos; 399 hits).
  - `0x80155DB4`: 484 bytes / **121 words** (Super Cancel and reversal selection with a full meter; 50 hits).
  - `0x80155F98`: 504 bytes / **126 words** (Aggression loop, buffer reading, and P2 controller input simulation; 686 hits).
- **Structural Abutment**:
  - Connects directly to native function `0x80155A58` (S1-296) at `0x80155B1C` and closes precisely at `0x80156190`, joining the start of the cluster `0x80156190..0x80156B80`.
  - Closes 100% of **Gap 3 (`0x8015574C..0x80156190`)**, unifying a nearly 7 KB contiguous block (`0x801550C8..0x80156B80`), 100% native.
- **Call Closure**:
  - All internal calls (`0x80155608`, `0x8015574C`, `0x801558CC`, etc.) were already compiled natively in batches S1-291 to S1-296. Closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-297**: 3 new functions, 1.652 bytes / **413 words**.
- **Coverage Target S1-297**: **142.534 words (72,8761%)** at **1.277 native functions**.
- **Gameplay Validation (`gameplay-discovery-71`)**:
  - Validated in direct combat against Ryu CPU Level 8.
  - Elimination of 100% of the 3 promoted targets (`0x80155B1C`, `0x80155DB4`, `0x80155F98` dropped to ZERO hits).
  - More than 1.135 combo, cancel, and input-simulation hits transferred to native execution.
  - Residual Main EXE candidates reduced to 29 (all strictly within Gap 6: `0x80156B80..0x80157F2C`).
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Batch S1-298: CPU AI Core Engine Pipeline (Gap 6 Part 1: Close Range, Jump vs Run & Normal Moves)

- **Discovery Origin**: Level 8 CPU combat telemetry in `gameplay-discovery-71` (1.059 hits in batch targets).
- **Topology & Structure**:
  - `0x80156B80`: 292 bytes / **73 words** (Neutral $\rightarrow$ attack transition dispatcher; 39 hits).
  - `0x80156CA4`: 108 bytes / **27 words** (Frame-buffer timing leaf helper).
  - `0x80156D10`: 168 bytes / **42 words** (Close-range distance and projectile checking helper).
  - `0x80156DB8`: 168 bytes / **42 words** (Jump-vs-run approach selector; 27 hits).
  - `0x80156E60`: 220 bytes / **55 words** (Anti-air selector and vertical tracking).
  - `0x80156F3C`: 216 bytes / **54 words** (Main CPU close-range attack decision routine; 789 hits).
  - `0x80157014`: 376 bytes / **94 words** (Rapid normal-move chaining routine; 204 hits).
- **Structural Abutment**:
  - Joins linearly at `0x80156B80` at the end of the native cluster `0x801550C8..0x80156B80`, extending it continuously to `0x8015718C`.
- **Call Closure**:
  - All internal or external cluster calls converge on already native functions. Closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-298**: 7 new functions, 1.548 bytes / **387 words**.
- **Coverage Target S1-298**: **142.921 words (73,0740%)** at **1.284 native functions**.
- **Gameplay Validation (`gameplay-discovery-72`)**:
  - Validated in direct combat against Ryu CPU Level 8.
  - Elimination of 100% of the 7 promoted targets (`0x80156B80..0x80157014` dropped to ZERO hits).
  - More than 1.059 close-range attack, approach, and normal-move hits transferred to native execution.
  - Residual Main EXE candidates reduced to 23 (all strictly contained in `0x8015718C..0x80157F2C`).
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Batch S1-299: CPU AI Core Engine Pipeline (Gap 6 Part 2: Dash, Frame Advantage, Specials & Reversals)

- **Discovery Origin**: Level 8 CPU combat telemetry in `gameplay-discovery-72` (320+ hits in batch targets).
- **Topology & Structure**:
  - `0x8015718C`: 236 bytes / **59 words** (Dash approach selector and command buffer; 4 hits).
  - `0x80157278`: 188 bytes / **47 words** (Opponent frame-advantage and recovery evaluator; 39 hits).
  - `0x80157334`: 536 bytes / **134 words** (Special attack route dispatcher - Hadoken/Tatsu; 70 hits).
  - `0x8015754C`: 216 bytes / **54 words** (Fast-reaction reversal and anti-air decision routine; 187 hits).
  - `0x80157624`: 192 bytes / **48 words** (Cooldown control and AI reset helper; 17 hits).
  - `0x801576E4`: 212 bytes / **53 words** (Screen-edge proximity checking helper; 3 hits).
- **Structural Abutment**:
  - Joins linearly at `0x8015718C` at the end of the native cluster `0x801550C8..0x8015718C` (S1-298), extending it continuously to `0x801577B8`.
- **Call Closure**:
  - All calls converge on already native functions or functions belonging to this sub-batch. Closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-299**: 6 new functions, 1.580 bytes / **395 words**.
- **Coverage Target S1-299**: **143.316 words (73,2759%)** at **1.290 native functions**.
- **Gameplay Validation (`gameplay-discovery-73`)**:
  - Validated in direct combat against Ryu CPU Level 8.
  - Elimination of 100% of the 6 promoted targets (`0x8015718C..0x801576E4` dropped to ZERO hits), along with the internal offsets.
  - More than 320 special, reversal, and dash hits transferred to native execution.
  - Residual Main EXE candidates reduced to only 13 (all within the final stretch of Gap 6: `0x801577B8..0x80157F2C`).
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Batch S1-300: CPU AI Core Engine Pipeline (Gap 6 Part 3: Core AI Completion)

- **Discovery Origin**: Level 8 CPU combat telemetry in `gameplay-discovery-73` (167 residual hits).
- **Topology & Structure**:
  - `0x801577B8`: 244 bytes / **61 words** (Mid/long-range attack decision dispatcher; 70 hits).
  - `0x801578AC`: 624 bytes / **156 words** (Projectile/hadoken reaction probability matrix; 1 hit).
  - `0x80157B1C`: 304 bytes / **76 words** (Round finisher and punish selector; 31 hits + 32 off).
  - `0x80157C4C`: 320 bytes / **80 words** (Simulated-input buffer synchronization helper; 0 hits).
  - `0x80157D8C`: 192 bytes / **48 words** (Wake-up guard stance selector; 5 hits).
  - `0x80157E4C..0x80157F0C` (7 leaf functions): 224 bytes / **56 words** (Distance and bounds calculation vector leaves; 8 words each; 28 hits).
- **Structural Abutment**:
  - Precisely joins the end of the native cluster at `0x801577B8` and closes at `0x80157F2C`, directly joining block `0x80157F2C..0x80158500`.
  - Unifies the entire Core AI Engine (`0x801550C8..0x80158500`): **13.368 bytes / 3.342 contiguous words**, 100% native.
- **Call Closure**:
  - All calls converge exclusively on native functions. Closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-300**: 12 new functions, 1.908 bytes / **477 words**.
- **Coverage Target S1-300**: **143.793 words (73,5200%)** at **1.302 native functions**.
- **Gameplay Validation (`gameplay-discovery-74`)**:
  - Validated in direct combat against Ryu CPU Level 8.
  - Elimination of 100% of All 12 promoted targets (`0x801577B8..0x80157F0C` dropped to ZERO hits).
  - Residual Main EXE Text candidates reduced to **ZERO** (0 candidates, 0 hits).
  - Core AI Engine (`0x801550C8..0x80158500`) fully unified and contiguous (13.368 bytes / 3.342 native words).
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Batch S1-301: Weapon/Prop Kinematics Pipeline (Hokuto 3D Dagger Renderer)

- **Discovery Origin**: Combat telemetry against Hokuto CPU Level 8 in `gameplay-discovery-83` (7 residual candidates, 108 hits).
- **Reverse Engineering Discovery (Rule 1 - Observed PC $\neq$ Function Root)**:
  - Of the 7 observed candidates, 5 are strictly **return sites (post-JAL continuations)** of matrix calculation loops within root function `0x80165130`:
    - `0x80165190`: Return point from `jal 0x801945F8` (4 hits).
    - `0x80165280`, `0x80165304`, `0x80165368`, `0x801653C4`: Return points from `jal 0x8019C0B8` (24 hits each; loop executed 6 times per activation).
  - Only 2 addresses are canonical function roots with a MIPS prologue: `0x80164D9C` (89 words) and `0x80165130` (266 words).
- **Topology & Structure of S1-301**:
  - `0x80165130`: 1.064 bytes / **266 words** (Hokuto *Shirase Gatana* weapon/dagger 3D kinematic renderer).
- **Precise Structural Abutment**:
  - Starts exactly at `0x80165130`, adjacent to the end of compiled block `0x80164F00` (`+0x230`).
  - Ends exactly at `0x80165554` (`jr ra` + `nop` delay slot), adjoining compiled block `0x80165558` with byte precision.
- **Call Closure (Closure Audit)**:
  - Contains 12 `JAL` calls: `0x801945F8`, `0x801946C8`, `0x8019C184` (6x), `0x8019C0B8` (4x), `0x801948DC`.
  - **All 12 calls converge on already compiled native functions**.
  - Indirect jumps (`jr $reg` other than ra): **0**.
  - Branches outside the function: **0**.
  - Uncontrolled closure expansion: **ZERO**.
- **Total Budget S1-301**: 1 new function, 1.064 bytes / **266 words**.
- **Coverage Target S1-301**: **144.059 words (73,6558%)** at **1.303 native functions**.
- **Immediate Impact**: Resolves 6 of the 7 candidates and 104 of the 108 hits (96,3%) from the combat session. Dispatcher `0x80164D9C` (89 words) and its branch `0x80165DAC` (241 words) remain isolated for sequential batch S1-302 under the Hard Budget Gate.

---

### Micro-Batch S1-302: Weapon/Prop Kinematics Pipeline (Dispatcher and ID 25 Variant)

- **Origin & Purpose**: Completion of Hokuto weapon/prop subsystem validation (started in S1-301).
- **Topology & Structure of S1-302**:
  - `0x80164D9C`: 356 bytes / **89 words** (Weapon/prop dispatcher by Character ID: ID 1/19 Hokuto and ID 25).
  - `0x80165DAC`: 964 bytes / **241 words** (Weapon/prop 3D kinematic renderer for Character ID 25).
- **Precise Structural Abutment**:
  - `0x80164D9C`: fills precisely the gap between `0x80164CC8` (`+0xD4`) and `0x80164F00`.
  - `0x80165DAC`: fills precisely the gap between `0x80165558` (`+0x854`) and `0x80166170`.
  - Joins the entire range `0x80164CC8..0x80166170` into a contiguous block of 100% native static code.
- **Call Closure (Closure Audit)**:
  - `0x80164D9C`: Calls `0x80165130` (promoted in S1-301) and `0x80165DAC` (promoted in this batch). Zero pending calls.
  - `0x80165DAC`: Contains 11 `JAL` calls (`0x801945F8`, `0x801946C8`, `0x8019C184`, `0x8019C0B8`, `0x8019CB60`, `0x801948DC`), all 100% native.
  - Indirect jumps (`jr $reg` other than ra): **0**.
  - closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-302**: 2 new functions, 1.320 bytes / **330 words**.
- **Coverage Target S1-302**: **144.389 words (73,8245%)** at **1.305 native functions**.
- **Impact**: Final elimination of all combat weapon/prop candidates.
- **Gameplay Validation (`gameplay-discovery-85`)**:
  - Validated over 3 full fights against Hokuto CPU Level 8 in build `buildTele-s1-302`.
  - **993.384 native static hits**, **ZERO misses**, **ZERO new candidates**.
  - Complete elimination of `0x80164D9C`, `0x80165130`, and all Main EXE matrix return sites.
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### Micro-Batch S1-303: Kairi Action and Move Sub-Cluster (Table 0x801B3400)

- **Origin & Purpose**: Discovered in session `gameplay-discovery-91` (Kairi CPU Level 8, 5 fights; 344 residual hits). Resolves attack roots and closes the contiguous sub-cluster up to `0x80162680`.
- **Topology & Structure of S1-303**:
  - `0x80162244`: 224 bytes / **56 words** (Kinematic handler in table `0x801B3400`).
  - `0x80162324`: 300 bytes / **75 words** (Kinematic handler in table `0x801B3400`).
  - `0x80162450`: 8 bytes / **2 words** (Fast-return null stub; `jr $ra`).
  - `0x80162458`: 272 bytes / **68 words** (Symmetric attack variant of `0x80162570`).
  - `0x80162568`: 8 bytes / **2 words** (Fast-return null stub; triggered with 2 hits).
  - `0x80162570`: 272 bytes / **68 words** (Attack dispatcher triggered with 112 hits during the test).
- **Precise Structural Abutment**:
  - Forms a contiguous 1.084-byte block (271 words) from `0x80162244` to `0x80162680`, directly joining native block `0x80162680..0x80162688`.
- **Call Closure (Closure Audit)**:
  - All calls `JAL` point to functions 100% native already compiled (`0x80159F3C`, `0x8015A080`, `0x8011618C`, `0x8015D3F0`, `0x8015D040`, `0x8012C288`, `0x801154EC`, `0x8015E12C`).
  - Indirect jumps (`jr $reg` other than ra): **0**.
  - closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-303**: 6 new functions, 1.084 bytes / **271 words**.
- **Coverage Target S1-303**: **144.660 words (73,9631%)** at **1.311 native functions**.
- **Impact**: Eliminates all 344 hits and 9 candidates from session 91 (removing 7 false return sites).
- **Gameplay Validation (`gameplay-discovery-92`)**:
  - Validated over 2 full fights against Kairi CPU Level 8 in build `buildTele-s1-303`.
  - **481.577 native static hits**, **ZERO misses**, **ZERO new candidates**.
  - Complete elimination of all 9 residual candidates of the session 91.
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

### S1-304 (Global Table 0x801B33F0 - Garuda Counterattack & Gaps 1 and 18)
- **Origin / Trigger**:
  - Discovered in session `gameplay-discovery-107` with P1 = Garuda Boss CPU vs P2 = Ryu COM, exercising the exclusive defensive counterattack mechanic.
  - Telemetry reported 5 candidates (`0x80161450`, `0x80161474`, `0x8016147C`, `0x80161494`, `0x80161540`) with 76 hits.
- **Architectural Diagnosis and MIPS Disassembly**:
  - The MIPS audit revealed that all 5 addresses belong strictly to **one contiguous function**: `0x80161450` (264 bytes / 66 words), the action handler for Garuda's exclusive counterattack (Slot 12 of Global Table `0x801B33F0`, referenced at `0x801B346C`).
  - `0x80161450`: Root of the function (37 dispatches).
  - `0x80161474` and `0x8016147C`: Internal call `jal 0x8011618C` and interception test `lh $v1, 474($s0)`.
  - `0x80161494`: Counterattack call `jal 0x80123BA8` (1 hit when the move connected).
  - `0x80161540`: Register restoration epilogue (`lw $ra, 24($sp)`).
- **Promoted Cohesive Table 0x801B33F0 Cluster**:
  - `0x801613B8`: 8 bytes / **2 words** (Fast-return leaf stub; Slot 1 Setup).
  - `0x801613C0`: 104 bytes / **26 words** (Action handler; Slot 1 Action).
  - `0x80161450`: 264 bytes / **66 words** (Garuda counterattack; Slot 12 Action).
  - `0x80161FE4`: 608 bytes / **152 words** (Throw/kinematic handler; Slot 18 Action, closing the connection between S1-282 and S1-303).
- **Contiguous Structural Abutment**:
  - Fully closes the contiguous range `0x80160FB4..0x80161A3C` (zero static gaps).
  - Fully closes the contiguous range `0x80161C04..0x801627A4` (zero static gaps).
- **Call Closure (Closure Audit)**:
  - All `JAL` calls (20 external calls) were already fully resolved in native code.
  - Indirect jumps (`jr $reg` other than ra): **0**.
  - closure expansion: **EXACTLY ZERO**.
- **Total Budget S1-304**: 4 new functions, 984 bytes / **246 words**.
- **Coverage Target S1-304**: **144.906 words (74,0889%)** at **1.315 native functions**.
- **Gameplay Validation (`gameplay-discovery-108`)**:
  - Validated in P1 = Garuda Boss CPU vs P2 = Ryu COM combat in build `buildTele-s1-304`.
  - **3.484.378 native static hits**, **ZERO misses**, **ZERO new candidates**.
  - Complete elimination of all 5 candidates of `gameplay-discovery-107`.
  - Codegen audit: **CLEAN**. Status: **PROCESSED & VALIDATED**.

---

## 3. Dynamic Overlay Track History

Overlays are dynamically loaded into RAM (`0x80020000..0x800F2000`) during fights and character-specific modes.

### OVL-001 Series (Core Battle Engine)
- **OVL-001A (`0x00020000:0xAC1FF1A4`)**:
  - 64 entries (22 roots, 42 internal entries), 4,563 reachable MIPS words.
  - Dominant PCs: `0x8004A44C`, `0x80091878`, `0x8004922C`, `0x80049500`.
  - Telemetry soak: 1,232,009 native dispatches over 3 complete matches with zero fallback and average 59.93 FPS. Approved as isolated dynamic checkpoint.
- **OVL-001B (`0x00020000:0x94E6122F`)**:
  - 122 entries (32 roots, 90 internal entries), 5,313 reachable words. Validated under S1-261 clean baseline.

### OVL-002 Series (Character Action Engine - Doctrine Dark & Ryu)
- **OVL-002A (`0x80092C2C` & `0x80092F00`)**: Core frame update routines for player 1 and player 2.
- **OVL-002B**: Closure resolution for `0x80092C2C`.
- **OVL-002C through OVL-002G (D.Dark Bomb Subsystem)**:
  - Addressed bomb placement, timing, guard checks, and detonation handlers (`0x80045E30`, `0x80045F00`, `0x80045F80`, `0x80045F94`, `0x80045FF8`).
  - Total 2,563 words verified clean across 4 test phases (unhit, hit, blocked, and special).
- **OVL-002H (`0x800465A8`)**: Super explosive bomb throw handler (239 words, jump table `0x8004A610` with 6 targets). Telemetry verified CLEAN with zero fallback.

---

## 4. Track 2 - Dynamic Overlays Promotion (DLL Cache System)

Transition from static text recompiler (Track 1 closed at S1-304 with 100% clean baseline) to dynamic isolated shard compilation in RAM via `compile_overlays.py`.

### Target A: Video Streaming Overlay (`MOV.OVL` - `0x000D6000:0xF06249FB`)
- **Objective**: Eliminate hotspot `0x800E78DC` (~226M interpreted instructions during FMV streaming).
- **Compilation**: 30 native shards (.dll) and 30 manifests (.ranges) generated in `cache/SLUS-00548/gcc/win-x64/cg5_562d908f/`.
- **Telemetry Validation (Session 119)**:
  - Hotspot `0x800E78DC` fell from 226M to **exactly 0 in the interpreter**.
  - **+13.974.887 native dispatches** successfully executed through DLLs.
  - Frametime graph stabilized at a locked 60 FPS during video playback.

### Target B: Game Menus (`OVL3/OPTS.OVL` - `0x00020000:0xD955BA78`)
- **First Iteration (Session 120)**:
  - Main options loop (`0x80021FB0`) ran natively with 0 fallbacks.
  - Deep submenu navigation (sound, controls, etc.) revealed 15 previously unexplored routines in range `0x80024xxx` (`0x800246E8`, `0x80024248`, `0x80024638`, etc.), producing 1.266.643 interpreted instructions.
- **Recompilation with Interior Fragments**:
  - `overlay_captures.json` expanded from 910 to 1.637 executed PCs.
  - Compilation of 24 `DISPATCH_INTERIOR` points directly into shard `00020000_D955BA78.dll`.
  - Manifest `00020000_D955BA78.ranges` expanded to **81 mapped native functions**.
- **Telemetry Validation (Sessions 121 and 122)**:
  - **Session 122 (Options Only)**: Full navigation through every option (Button Config, Sound Test, Ranking, Memory Card, Difficulty, Volume). **100% elimination** of all `0x8002xxxx` interpreter hotspots (0 fallbacks in the options range).
  - Frametime graph remained perfectly smooth and locked at 60 FPS. Target B successfully validated.

### Target C: Title Screen & Attract Mode (`0x00020000:0xCD5EAEA6`)
- **Origin / Discovery (Session 123)**:
  - Complete cold boot: Capcom and Arika Logos -> Entire Opening/Intro FMV played without cuts (+5.682.976 native dispatches through `MOV.OVL`, 0 misses) -> Transition to Title Screen ("Press Start").
  - Identified a concentrated hotspot of ~8,7 million interpreted instructions in title-screen rendering and state control.
- **Top Discovered Hotspots**:
  - `0x8004A44C`: 4.253.319 insns, 11.742 hits (Title Screen / Attract Master Loop).
  - `0x8004922C`: 2.178.743 insns, 1.957 hits (Frame / Animation Dispatcher).
  - `0x80091878`: 1.115.060 insns, 1.957 hits (Render / Vertex Transformation).
  - `0x8004AF94`: 974.649 insns, 1.957 hits (Menu State Control / Input).
  - `0x80049500`: 207.477 insns, 1.957 hits (UI Update Subroutine).
- **Captured Module Specifications (`buildTele-s1-304/overlay_captures.json`)**:
  - Base Address: `0x80020000` (Physical: `0x00020000`)
  - Size: 872.448 bytes (852 KB), CRC32: `0xCD5EAEA6`
  - Coverage: 4.601 executed PCs, 25 Root Seeds, 89 Interior Seeds.
  - C11 Pre-Audit: 0 unknown bad, 0 unsupported todo. 100% CLEAN.
- **Telemetry Validation (Sessions 124, 125, and 126)**:
  - **Session 124**: Title Screen validation. Native dispatches rose to **+5.924.377** (+241k additional native dispatches). All 5 top hotspots (`0x8004A44C`, `0x8004922C`, `0x80091878`, etc.) were **100% eliminated** from interpretation. Locked, clean frametime at 60 FPS.
  - **Session 125**: Full navigation: Title Screen -> Mode Select (Arcade, Versus, Survival, Team, Practice) -> Character Select Screen (Char Select) -> Return to Title. **ZERO** overlay hotspots fell into the interpreter. Module `0xCD5EAEA6` (872 KB) confirmed as the integrated engine for the entire game selection UI.
  - **Session 126**: Validation of secret-code execution in Mode Select to unlock characters/bosses. **ZERO** new candidates, **ZERO** overlay fallbacks. Unmasking logic, global bitmasks, and sound confirmation executed entirely natively.

### Target D: Bonus Stage (Barrel Break) and Replay (Track 2 - Batch 1 Validated in Test 168)
- **Origin / Mapped Gaps (Session 167)**:
  - Bonus Stage execution telemetry reported ~312 million interpreted instructions in routines residing in overlays loaded at `0x80018000` (and variant `0x80016000`).
  - Mapped critical hotspots:
    - `0x8001D4B4`: 260.029.498 insns, 15.517 hits (Master barrel physics and falling loop).
    - `0x80047E78`: 26.434.505 insns, 15.517 hits (LZSS decompressor / barrel graphics).
    - `0x8001BF44`: 14.094.651 insns, 131.944 hits (Collision and breaking routine).
    - `0x8001BD70`: 6.094.709 insns, 16.493 hits (Score / impact handler).
    - `0x8001C530`: 1.306.324 insns, 50.114 hits (Debris animation subroutine).
    - `0x8001B90C`: 1.271.911 insns, 19.120 hits (Bonus timer and counters).
    - `0x8004495C`: 316.000 insns, 3.678 hits (Auxiliary dispatcher).
- **Dynamic Compilation (Script `compile_track2_bonus_barrel_overlay.ps1`)**:
  - Dynamic shard compilation for variants `0x00018000:0x19B8E508` (Session 167) and `0x00016000:0x21A4041B` (Session 166).
  - Emitted **155 new shards (.dll)** and 155 manifests (.ranges) in the GCC UCRT64 cache. Total cached DLLs rose to **2.098 DLLs** (3.678 unique functions).
- **Runtime Validation (Test 168)**:
  - Execution validated over the full route: `Option Mode > before > Menu Bonus > Bonus Barril > Ken > Jogo completo > Replay > Tela de resultado (Iniciais) > Option Mode > after`.
  - **Full Elimination of All 7 Hotspots**: The 7 compiled hotspots fell from 309,5M to **exactly ZERO** in the interpreter (`0x8001D4B4`, `0x80047E78`, `0x8001BF44`, `0x8001BD70`, `0x8001C530`, `0x8001B90C`, `0x8004495C` 100% native).
  - **Native Dispatches**: Massive increase to **+1.641.932** native dispatches through DLLs, **+2.838.699** generation fastpaths, and 15 new loaded DLL modules.
  - **Static Misses (Main EXE)**: **EXACTLY ZERO** (1.157.625 static hits).
  - **Technical Diagnosis of `0x8001910C` (252M)**: Telemetry recorded `0x8001910C` (15.154 hits) in the interpreter because the `after` snapshot was captured after the game had returned to Option Mode, when GPU graphics buffers overwrote the bonus MIPS RAM. The audit safely rejected the corrupted data (`_is_valid_mips_word` false). Compiling Batch 2 and eliminating the residual 252M requires a capture triggered during bonus gameplay (Test 169).

---

## 5. Consolidated Project Statistics (Track 1 + Track 2)

### A. Track 1: Static Recompilation of the Main Executable (`SLUS_005.48`)
- **Status**: **100% VALIDATED AND COMPLETED (S1-308)**.
- **Total Native Functions**: **1.357 functions**.
- **Compiled MIPS Words**: **154.836 words** (79,1660% of the base binary's 195.584 words).
- **Static Runtime Misses**: **EXACTLY ZERO** across all modes, menus, pause, command list, bonus stage, replay, records/initials screen, and Expert Mode.

### B. Track 2: Promoted Dynamic Overlays (DLL Cache System)
- **Menus, Videos, 26/26 Roster, Bonus Stage & Expert Mode Status**: **100% VALIDATED AND ACTIVE IN CACHE**.
- **Total Native Shards (.dll)**: **2.216 DLLs** (+76 new Expert Mode DLLs).
- **Total Manifests (.ranges)**: **2.216 manifests**.
- **Total Unique Native Functions in DLLs**: **3.840 functions**.
- **Distribution by RAM Module**:
  - `00020000` (Title, Menus, Options, CharSelect, Cheats, 26/26 fighters & Expert Mode): 1.977 DLLs.
  - `00016000` / `00018000` (Barrel Bonus Stage, Replay and Records - Dual Base): 197 DLLs (71 synchronized pairs + adjacent variants).
  - `0008C000` (System Submenus): 12 DLLs, 12 functions, **1.950 words**.
  - `000D6000` (Video Streaming `MOV.OVL`): 30 DLLs, 56 functions, **1.298 words**.

### C. Consolidated Global Metric
- **Total Native Functions in the Game**: **5.198 compiled native functions** (1.358 static + 3.840 dynamic).
- **Runtime Coverage**: **100% native execution** in Boot, Logos, Opening FMV, Title Screen, Options Menu, Mode Select, Character Select Screen, Combat (26/26), Pause, Command List, Bonus Stage, and Expert Mode (Track 1 + Track 2 with zero static misses and +590k additional native dispatches in Test 174).
- **Interpreted Gameplay Overlay Instructions in Expert Mode**: Plummeted to **21.828 instructions** (99,833% elimination).

---

## 6. Architectural Guidelines and Future Tasks

### A. PSX Kernel / BIOS (`0x80000000..0x8000FFFF`)
- **Validated Architectural Decision**: Retained under the CPU / HLE interpreter.
- **Rationale**: The BIOS kernel directly handles hardware interrupt vectors (`0x80000080` / `0x800000B0`), COP0 Status/Cause/EPC, and the TCB scheduler (`syscall 3 / RFE`). Runtime cost is negligible (< 0,001% of a 16,6 ms frame) and does not affect frametime (locked 60 FPS), eliminating asynchronous desynchronization risks with SDL/host.

### B. Gameplay Overlay Campaign Status (Track 2 - 26/26 Fighters Validated)
The dynamic combat-module compilation campaign (`0x80020000..0x800F2000`, 840 KB) achieved **100% roster coverage (26/26 fighters)** and **1.943 DLLs** active in cache:
- **Batch 1 (Ryu & Ken)**: VALIDATED (Sessions 127/128).
- **Batch 2A (Guile & Chun-Li)**: VALIDATED (Sessions 129/131).
- **Batch 2B (Zangief & Dhalsim)**: VALIDATED (Sessions 133/134).
- **Batch 3 (Doctrine Dark & Hokuto)**: VALIDATED (Sessions 135/136).
- **Batch 4 (Skullomania & Blair Dame)**: VALIDATED (Sessions 137/138/139, accompanied by Main EXE promotion S1-305).
- **Batch 5 (Cracker Jack & Allen Snider)**: VALIDATED (Sessions 140/141, elimination of 23M interpreted instructions, cache at 979 DLLs).
- **Batch 6 (Kairi & Darun Mister)**: VALIDATED (Sessions 142/143, elimination of 7,86M instructions at `0x80048190`, +159 DLLs, cache at 1.138 DLLs).
- **Batch 7 (Sakura & Pullum Purna)**: VALIDATED (Sessions 144/145, elimination of 29M instructions, +121 new DLLs, cache at 1.259 DLLs).
- **Batch 8 (Garuda & Akuma)**: VALIDATED (Sessions 146/147, elimination of 50M combat and teleport instructions, milestone of >1M native dispatches, +173 new DLLs, cache at 1.432 DLLs).
- **Batch 9 (M. Bison & Evil Ryu)**: VALIDATED (Sessions 148/149, elimination of 32M instructions, native teleports and Psycho Power, cache at 1.544 DLLs).
- **Batch 10A (Bloody Hokuto & Cycloid-β)**: VALIDATED (Sessions 150/151, elimination of residual dagger and polygonal-model hotspots, cache at 1.688 DLLs).
- **Batch 10B (Cycloid-γ)**: VALIDATED (Sessions 152/153, native gold moveset and teleport, cache at 1.742 DLLs — 23/23 playable fighters completed).
- **Batch 11A (Garuda Boss & Akuma Boss CPU)**: VALIDATED (Sessions 154/155, super armor and boss variants completed, cache at 1.743 DLLs).
- **Batch 11B (M. Bison Boss CPU)**: VALIDATED (Sessions 156/157, elimination of 20M final-boss instructions, new record of 1,42M native dispatches, cache at 1.888 DLLs — 26/26 fighters completed).
- **Batch 12 (Dhalsim Projectile & Fire Engine)**: VALIDATED (Sessions 158/159/160/161, elimination of spell collisions and 18M flame/Yoga Inferno instructions, record of 2,88M native dispatches, cache at 1.943 DLLs — 14/14 `projecteisHit.md` routines fully covered in DLLs).

### C. UI Subsystems and Special Modes
1. **Main Pause Menu (`0x80172DD0..0x8017566C`)**: **VALIDATED** (Micro-batch S1-306, Session 164, 10 functions, 2.599 words, 76,0047% ROM coverage).
2. **Command List & 3D Submenus (`0x80183734..0x80185CC0` and GTE `0x8019`)**: **VALIDATED** (Micro-batch S1-307, Session 165, 14 functions, 2.598 words, 77,3330% ROM coverage).
3. **Bonus Stage Barrel Break, Option→Bonus Transition, and Records/Initials Screen (`0x801495D4..0x8014B21C`, `0x8016F668..0x8016FB64`, `0x80181F7C..0x80183734`)**: **VALIDATED IN TRACK 1 AND TRACK 2** (Micro-batch S1-308 + Batch 1 & Batch 2 Dual-Base Shards, Tests 168-171, elimination of >300M instructions, 0 static misses, and +4,09M native overlay dispatches).
4. **Expert Mode (Challenges 1 to 8, Combo Evaluator, and Goal HUD) (`0x8014C6E0`, `0x80047E78`, `0x800E64D8`..`0x800E724C`)**: **VALIDATED IN TRACK 1 AND TRACK 2** (Micro-batch S1-309 + Expert Mode Shards, Tests 172-174, elimination of 99,833% of overlay instructions, 0 static misses, and +590k additional native dispatches).
5. **Training Mode (Ken x Ryu, Combos, Training Arena, and Extended Pause Menu) (`0x80047E78`, `0x8004809C`, `0x80046BC8`, `0x8004649C`, `0x80044818`)**: **VALIDATED IN TRACK 1 AND TRACK 2** (Tests 176-179, elimination of all game overlay instructions, 0 native handoffs, 0 static misses, and cache consolidated at 2.219 DLLs).
