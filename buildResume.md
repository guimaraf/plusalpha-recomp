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
