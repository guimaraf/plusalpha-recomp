# Source Generation, Build, and Testing Methodology

This document defines the mandatory protocol for promoting native code, generating sources, creating builds, and performing telemetry verification in the *Street Fighter EX Plus Alpha* (`SLUS-005.48`) static recompilation project.

Its purpose is to guarantee execution stability, prevent uncontrolled closure expansion, eliminate frametime jitter, and ensure any developer or AI assistant can resume work without relying on conversational context.

For candidate tracking and historical micro-batch logs, refer to [`newWords.md`](newWords.md) and [`buildResume.md`](buildResume.md).

---

## 1. Non-Negotiable Rules

1. **Host Execution Ownership**: The automated assistant never runs source generation, compilation, or the game binary directly. The local operator executes all commands and submits the logs/results.
2. **Generated C Immutability**: Manual edits to `PlusAlphaProject/generated/` are strictly forbidden. The C code in `generated/` is exclusively produced by `psxrecomp-game.exe`.
3. **Three-Script Decoupling**: Every micro-batch must feature independent scripts with isolated responsibilities: source generation, compilation, and telemetry. A script must never combine multiple stages.
4. **Collector Independence**: The telemetry collector must never build, launch, or terminate the game.
5. **Two-Stage Promotion**: Telemetry approval provides provisional acceptance only. Permanent promotion requires an independent clean Release checkpoint (`buildClean-ucrt-*`).
6. **Single Source of Truth**: [`newWords.md`](newWords.md) is the sole authoritative registry for candidates, boundaries, closures, measured budgets, evidence, and promotion decisions.

---

## 2. When Each Step Is Required

| Scenario | Regenerate BIOS | Generate Game Sources | Compile Binary | Collect Telemetry |
|---|---:|---:|---:|---:|
| Telemetry run on existing build | No | No | No | **Yes** |
| New seed or change in `entry_funcs.txt` | No | **Yes** | **Yes** | **Yes** |
| Changes to BIOS emitter or stale BIOS warning | **Yes** | No (unless game logic changes) | **Yes** | Risk-dependent |
| Runtime/CMake modification without new seeds | No | No | **Yes** | Smoke / Regression |
| Clean checkpoint after approved batches | No | No | **Yes** (Release, no debug) | Optional |

> **Note on BIOS Regeneration**: Only modifications directly impacting the BIOS compiler justify regenerating it (e.g., `full_function_emitter.cpp`, `strict_translator.cpp`, BIOS function discovery, cycle model, or BIOS seeds). Game seeds in `SLUS_005.48_*` never require regenerating the BIOS.

---

## 3. Mandatory Candidate Pre-Audit

No observed program counter is ever promoted directly as a seed. Before preparing micro-batch scripts, the following must be documented in [`newWords.md`](newWords.md):

1. **Formal Boundary**: Entry address, epilogue address, exact byte length, word count, and body SHA-256 hash.
2. **Callers and Aliases**: Distinguish function entry points from internal basic blocks, return sites, jump table targets, and trampolines.
3. **Control Flow**: Audit all branch targets, direct `JAL` calls, indirect `JALR`/`JR` jumps, jump tables, callbacks, and dynamic RAM references.
4. **Reachable Closure**: Every direct `JAL` call must be recursively mapped until reaching either an already native function or an interpreted leaf.
5. **Hard Budget**: The real cost of a micro-batch is the root size **plus all newly expanded closure functions**. Candidates exceeding the agreed budget are rejected.
6. **Risk Factors**: COP2/GTE math, scratchpad usage, DIV/MULT latency, BREAK/SYSCALL, self-modifying code (SMC), and BIOS kernel hooks must be treated with maximum isolation.

### Reference Incident: S1-252 (Uncontrolled Closure Expansion)
Dispatcher `0x8016FC28` was initially estimated at 39 words. Reachable call analysis recursively pulled in 12 uncompiled functions totaling 2,805 words. The batch contaminated work sources with 1,054 functions and was rolled back to S1-251. This incident mandates that **all candidate closures must be pre-audited in an isolated environment prior to touching production files**.

---

## 4. Micro-Batch Script Contracts

For any micro-batch (e.g., `S1-XYZ`), the following scripts reside in `PlusAlphaProject/tools/`:

| Script | Exclusive Responsibility |
|---|---|
| `generate_s1_XYZ_sources.sh` / `.ps1` | Validate baseline seeds, generate game C sources, run `codegen_audit_game.py`. Must not compile or touch BIOS. |
| `compile-run_s1_XYZ_telemetry.sh` / `.ps1` | Validate symbols and ranges, configure and compile isolated telemetry build (`RelWithDebInfo`, `PSX_DEBUG_TOOLS=ON`). |
| `telemetry_before_after_s1_XYZ.sh` / `.ps1` | Capture BEFORE and AFTER telemetry snapshots across the target scenario. Must not build or close the game. |
| `compile-run_s1_XYZ_checkpoint.sh` / `.ps1` | (When requested) Compile standalone clean Release checkpoint (`PSX_DEBUG_TOOLS=OFF`). |

### Source Generator Contract
- Ensures the new seed appears exactly once; existing approved seeds remain untouched; quarantined seeds are absent.
- Enforces baseline function and word counts.
- Verifies that no previously compiled ranges disappear.
- Executes `python tools/codegen_audit_game.py --config game.toml` and requires `STATUS: CLEAN`.
- Fails immediately if any function outside the approved closure is introduced.

### Compilation Script Contract
- Validates the environment: MSYS2 UCRT64 toolchain, `cmake`, `ninja`, `gcc`, `objdump`.
- Enforces `CMAKE_BUILD_TYPE=RelWithDebInfo`, `PSX_DEBUG_TOOLS=ON`, and `PSX_STATIC_RUNTIME=ON`.
- Verifies output binary creation and static linkage of required libraries.

---

## 5. Clean Delivery / Gameplay Build Contract (`buildClean-*`)

All clean builds destined for gameplay verification, frametime audits, and distribution must strictly follow the `RelWithDebInfo` profile:

### 1. Mandatory Compilation Flags
- `CMAKE_BUILD_TYPE="RelWithDebInfo"` (`-O2 -g -DNDEBUG`).
- `PSX_STATIC_RUNTIME=ON` (statically embeds C/C++ runtimes and SDL2).
- `PSX_DEBUG_TOOLS=OFF` (disables debug TCP server and heavy cycle profiling).
- `PSX_LAUNCHER=ON` (enables launcher UI).

### 2. Technical Justification (`-O2` vs `-O3`)
- The generated C source (`SLUS_005.48_full.c`) exceeds **36 MB and 1.2 million lines of C**, with tens of thousands of basic blocks and jump switches.
- GCC's `-O3` triggers aggressive function inlining, auto-vectorization, and extensive loop unrolling. In massive codebases, this inflates binary code size in the L1/L2 Instruction Caches (I-cache bloat) and causes branch target buffer (BTB) thrashing.
- Under `-O3`, transitions between native compiled code and the dynamic dirty-RAM interpreter (`dirty_ram_interp.c`) produce severe I-cache miss spikes, resulting in perceptible micro-stutter and unstable frametimes.
- `RelWithDebInfo` compiles under `-O2`, producing dense, linear machine code that minimizes I-cache misses and delivers a solid, jitter-free 60.0 FPS timeline.

### 3. Required Directory Assets
Every clean build folder must include the full overlay cache hierarchy:
`cache/SLUS-00548/gcc/win-x64/cg5_<hash>/` with all compiled shard DLLs and `.ranges` sidecars, along with `launcher.rml`, `settings.toml`, `keybinds.ini`, `input.ini`, `fonts/`, and `img/`.

---

## 6. Telemetry Collector Contract

The telemetry collector implements a clean three-phase lifecycle:
1. **`prepare`**: Validates target build, creates unique timestamped run directory, records metadata, arms trace filters.
2. **`before`**: Verifies prepared state, captures initial baseline snapshot at target scenario (e.g., Round 1 Fight banner), clears noise.
3. **`after`**: Captures final snapshot at scenario completion (e.g., KO / Replay / Victory), executes delta analysis, outputs `candidates.txt` and `summary.md`. Leaves the game running.

---

## 7. In-Game Testing & Manual Regression Guide

Telemetry scenarios must be chosen based on target code evidence rather than routine. Character, stage, and snapshot trigger sites must be documented in `metadata.txt`.

### Standard Bonus Barrel Scenario
1. Launch telemetry build manually.
2. Highlight Bonus Barrel in menu; run `prepare`.
3. Select Guile. When stage loads and control is active, run `before` with zero inputs.
4. Complete the round normally, breaking barrels.
5. On the `Replay/Exit` screen, run `after` with zero inputs.

### Mandatory Manual Regression Routes

| Mode | Matchup & Stage | Observation Focus |
|---|---|---|
| **Versus** | Doctrine Dark vs Skullomania (Skullomania Stage) | Sprites, particle effects, audio, 60 FPS lock, frametime linearity |
| **Versus** | Guile vs Hokuto (Hokuto Stage) | Stage-specific geometry and special animations |
| **Bonus** | Barrel Bonus Stage | Hitboxes, multi-object collision, replay transitions |
| **Trial** | Complete Expert Trial Session | Input responsiveness, combo cancel timing, timer accuracy |
| **Arcade** | 3+ Consecutive Arcade Fights | Long-term memory stability, sound effects, clean transitions |

---

## 8. Post-Test Decision Matrix

| Test Result | Decision |
|---|---|
| Clean technical gate, zero misses/aborts, clean manual regression | **Provisionally Approved** |
| Target execution path not observed | Retain candidate; design targeted scenario; do not promote |
| Unexpected miss, abort, handoff, crash, or regression | **Rejected / Suspended**; preserve logs; create minimal reproduction |
| 3 to 5 micro-batches approved or high-risk milestone reached | Request clean checkpoint build (`buildClean-*`) |
| Clean checkpoint build validated across full regression | **Permanent Promotion**; commit to main branch |

---

## 9. Error Recovery Protocol

- **Closure Exceeds Budget**: Do not build. Roll back sources to last approved baseline seed list. Document the expansion in [`newWords.md`](newWords.md).
- **Abnormal Game Exit During Test**: Discard state. Remove collector state token and restart test from `prepare`.
- **Telemetry Disconnection**: Retain run folder. Do not overwrite logs. Report error trace.
- **Safety Restriction**: Never execute destructive commands (`git clean -fdX`, `git reset --hard`) on work directories without explicit authorization and verified file targets.
