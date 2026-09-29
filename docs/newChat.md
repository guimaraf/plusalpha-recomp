# Briefing and Instructions for Continuing in a New Chat

## 1. Mandatory Working Rules (User Rules & Constraints)
- **Tone and Communication**: Strictly technical, candid, and direct. No embellishment, praise, or unnecessary apologies. Get straight to the point.
- **Immediate Correction**: If the user proposes a technically flawed or unsafe approach, correct it immediately with a technical explanation.
- **Inviolable Host Ownership**: The assistant **NEVER** executes native C/C++ compilation commands, invokes the recompiler (`psxrecomp-game.exe`), runs telemetry scripts, or issues gameplay commands. All compilation, game execution, and telemetry are performed exclusively by the **Operator** through PowerShell scripts (`.ps1`). The assistant generates/edits scripts, analyzes logs, and guides the architecture.

---

## 2. Project and Repository Context
- **Project**: Native C11 recompilation of *Street Fighter EX Plus Alpha* (USA, `SLUS-005.48`).
- **Main Directory**: `f:\GitRevised\alphaplus\plusalpha-recomp`
- **Critical Subdirectories**:
  - `PlusAlphaProject/`: CMake project, generated C sources, binaries (`buildTele-s1-309/exPlusAlpha.exe`), and build scripts.
  - `PlusAlphaProject/tools/`: PowerShell automation scripts (`compile_track2_training_mode.ps1`, `compile_track2_expert_mode.ps1`, `run_gameplay_telemetry.ps1`, etc.).
  - `PlusAlphaProject/local/telemetry/`: Telemetry sessions (`gameplay-discovery-179/`, `gameplay-discovery-178/`, etc.).
  - `psxrecomp/`: Static/dynamic recompiler core and MIPS R3000A runtime.
  - `buildTele-s1-309/cache/`: Native DLL cache and `.ranges` manifest directory.

---

## 3. Current Project State (Test 179 Checkpoint)

### A. Track 1: Static Recompilation (Main EXE `SLUS-005.48`)
- **Status**: **100% VALIDATED** (Micro-batch S1-309, commit `d4c0bc8`).
- **Current Metrics**:
  - **1.358 native functions** compiled into the main executable.
  - **154.846 MIPS words** (619.384 bytes) — **79,1711%** of the base executable (`195.584` words). The remaining 20,83% consists of constants, *jump tables*, strings, and inaccessible arcade code.
  - **Static Runtime Misses**: **EXACTLY ZERO** across all tested paths (Boot, FMVs, Menus, Options, Mode Select, Character Select, 26/26 Combat, Pause, Command List, Barrel Bonus Stage, Replay, Records, Expert Mode, and Training Mode).
- **Reference Documents**: [`progress.md`](progress.md) and [`buildResume.md`](buildResume.md).

### B. Track 2: Dynamic Recompilation (Overlay .DLL Shards)
- **Current Cache Status**: **2.219 native DLLs** and **2.219 `.ranges` manifests** (3.843 dynamic functions).
- **Validated Campaigns**:
  1. **Complete Character Roster**: 26/26 fighters (23 playable + 3 CPU bosses), 100% native (1.943 base DLLs).
  2. **Projectile / Flame Engines**: 14/14 routines validated (100%).
  3. **Bonus Stage (Barrel), Replay & Records (Tests 168-171)**: 100% native (+4,09M native dispatches, 2.140 DLLs).
  4. **Expert Mode (Tests 172-175)**: 100% native with Ken and Skullomania (+590k native dispatches, 2.216 DLLs).
  5. **Training Mode (Tests 176-179)**: 100% native with Ken x Ryu (+675k native dispatches, 2.219 DLLs).
     - **Residual interpreted game code**: **EXACTLY ZERO**.
     - **Native handoffs (context breaks)**: **ZERO**.
     - **MIPS roots declared in `game.toml` under `[[overlays]]` (`load_addr = "0x80020000"`)**:
       - `0x80047E78` (physics/collision host function covering the internal alias `0x8004809C`).
       - `0x80046BC8`, `0x8004649C`, `0x80044818` (training HUD/pause routines).
     - **Automation Script**: [`PlusAlphaProject/tools/compile_track2_training_mode.ps1`](../PlusAlphaProject/tools/compile_track2_training_mode.ps1).

---

## 4. Guidelines for the Next Chat (Detailed Inspection Campaign)

The user is performing additional tests to check for residual code in specific modes or combinations.

When the user presents the results of a new test:
1. **Immediately Separate Sony BIOS from Game Code**:
   - The global `Fallback Interprete` line in the telemetry summary is dominated (> 99,5%) by the Sony BIOS (`0x80004498`, `0x80000C80`, `0x800000B0`, `0x8000641C`).
   - The Sony BIOS is deliberately kept interpreted for hardware synchronization without regressions. BIOS count variations reflect only elapsed execution time (wall-clock time).
   - The audit must focus strictly on **game code outside the `0x8000xxxx` range**.
2. **If interpreted game hotspots appear (range `0x8001xxxx` to `0x800Fxxxx`)**:
   - Check for captures in the session's `overlay_captures.json` file.
   - Detect keys with `detect_capture_keys.py`.
   - Inspect whether the hotspot is a legitimate MIPS function root (`addiu $sp, $sp, -imm` or immediately after `jr $ra`) or an internal continuation/alias.
   - If it is a root not automatically identified (indirect call), add it to `game.toml` under `[[overlays]]`.
   - If it is an internal continuation, identify its host function.
   - Generate/run a dedicated PowerShell script to compile the shards into the cache.
3. **If a static miss appears in the Main EXE (`0x80101000..0x801C0000`)**:
   - This is a rare event (Track 1 has had 0 misses for dozens of tests).
   - Strictly follow the isolation protocol: reachable closure preview, word-budget validation, and micro-batch generation without breaking the existing compilation.
