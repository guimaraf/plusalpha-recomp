# Project Build Architecture (Street Fighter EX Plus Alpha)

This document defines the project's build categories, their technical roles, the launcher lifecycle, and the versions retained for comparison and historical audits.

---

## 1. Release Build for Publication (`buildNoCopyright-s1-*`)

- **Directory**: `PlusAlphaProject/buildNoCopyright-s1-268/`
- **Main Executable**: `exPlusAlpha.exe` (~12.29 MB, *stripped*)
- **Window Title**: `Ex Plus Alpha`
- **Purpose**: Public distribution completely free of copyrighted content (*Clean-Room Pipeline*), containing **0 bytes** of proprietary Sony/Capcom assets or code.

### Portable Internal Compilation Toolchain (`compileBuild/`)
The release build includes a portable, self-contained compilation ecosystem:
- **TinyCC 0.9.27** (ultrafast C compiler).
- **Python 3.11.9 embeddable** + `psxrecomp-game.exe`.
- Native ISO9660 parser (`disc_extractor.cpp`) for extracting `SLUS_005.48`.
- Runtime headers and local compilation scripts (`compile_game_core.bat`, `compile_tcc_overlays.bat`).

### Release Launcher Behavior
The frontend checks for the presence of precompiled game files:
1. **First Run (Missing Files)**:
   - Because `game_core.dll` and `cache/` **are absent** from the distribution, the launcher automatically detects their absence and displays the **initial screen / setup wizard**.
   - On this screen, the user selects the original disc image (.cue/.bin/.iso), the BIOS, and clicks the **Compile** button.
   - The process extracts `SLUS_005.48`, recompiles the functions into C, and generates `game_core.dll` and dynamic shards in `cache/` within a few seconds.
2. **After Installation**:
   - A **"Remove Compilers"** UI button allows deletion of the `compileBuild/` folder (~65 MB), leaving a lean, fully independent folder.
3. **Subsequent Runs**:
   - Once `game_core.dll` is present, the initial setup/build screen **no longer appears** — the launcher proceeds directly to game initialization.

---

## 2. Telemetry and Instrumentation Build (`buildTele-s1-*`)

- **Directory**: `PlusAlphaProject/buildTele-s1-269/`
- **Main Executable**: `exPlusAlpha.exe` (~218.05 MB, with telemetry and integrated static code)
- **Compilation Profile**: `RelWithDebInfo` (`-O2 -g -DNDEBUG`) with `PSX_DEBUG_TOOLS=ON` and `PSX_STATIC_RUNTIME=ON`.
- **Purpose**: Test, debug, and instrument combat paths, menus, and game modes to identify interpreted instructions (*misses*) and overlay *hotspots*, guiding future micro-batches (e.g., **S1-270**).

### Fully Prepared for Immediate Testing
The telemetry build is prepared for maximum development productivity:
- **Everything Precompiled**:
  - Statically integrated game C code (`SLUS_005.48_full.c` and `SLUS_005.48_dispatch.c`, with the 1.114 native functions through S1-269, totaling 127.128 words).
  - Dynamic DLLs (`game_core.dll`) and the full overlay cache (`cache/SLUS-00548/gcc` and `cache/SLUS-00548/tcc`) already copied and synchronized.
- **Zero Manual Compilation Steps**: No disc extraction or compilation is required; the developer runs tests immediately.
- **Skips Setup Screen**: Because all game files and modules have already been generated and are present, the launcher skips the build wizard and starts the game directly, with the telemetry server listening on TCP port **`4531`**.

### Running Telemetry
- **Start the instrumented game**:
  ```cmd
  PlusAlphaProject\buildTele-s1-269\run_telemetry.bat
  ```
  *(or through `tools/run_gameplay_telemetry.ps1`)*
- **Capture real-time data (in a separate terminal)**:
  ```powershell
  python tools/observe_gameplay.py
  python tools/observe_menus_navigation.py
  python tools/observe_boot_to_charselect.py
  ```

---

## 3. Historical Comparison Record (Validation Checkpoints)

To prevent regressions in frametime, stability, collisions, hitboxes, or audio, the project preserves two reference versions as clean release checkpoints (`PSX_DEBUG_TOOLS=OFF`, monolithic `RelWithDebInfo`):

### A. `buildClean-ucrt-s1-266`
- **Milestone**: Completion of the major menu elimination campaign.
- **Metrics**: 125.435 words of static coverage (64,13%), 1.108 functions.
- **Purpose**: Stable reference for menus, navigation, option screens, and initial combat.

### B. `buildClean-ucrt-s1-268`
- **Milestone**: Integration of the Match State Machine (FSM - S1-267) and Entity/Frame Processing Cluster (S1-268).
- **Metrics**: 126.830 words of static coverage (64,84%), 1.113 promoted native functions, 18.271 dispatch entries.
- **Purpose**: Official reference for active combat at a fixed 60.0 FPS with **100% native dispatch in the Main EXE** (zero misses in complete fight rounds).

> **Testing Guideline**: Any future build or promoted micro-batch must be compared directly against `buildClean-ucrt-s1-268` to verify that no behavior has regressed.


## 4. Validation of build `build_s1_309_dll_complete` — 29/09/2026

Experimental build based on S1-309, with the code corresponding to the 2.219 DLLs from the validated cache compiled statically into the EXE. Dynamic overlay loading is disabled in this version.

### User-Reported Result

- **8 fights** were played.
- Gameplay remained stable throughout the test in both **FPS** and **frametime**.
- The game opened **much faster** than the previous version with DLL preloading.

The result confirms the stability observed in this test and a noticeable improvement in startup time. No timed startup measurements or numerical frametime collection were reported; this record documents the user's manual assessment without extending the conclusion to untested scenarios.

The previously validated installation was preserved for comparison. This test promotes no new Track 2 code: it evaluates static integration of the code already present in the S1-309 cache.
