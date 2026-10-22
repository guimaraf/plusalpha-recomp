# Street Fighter EX Plus Alpha Recomp

[![Listed on PlayPorted](https://playported.com/badge.svg)](https://playported.com/ports/227-street-fighter-ex-plus-alpha/)

**[Download v0.2.4-alpha for Windows x64](https://github.com/guimaraf/plusalpha-recomp/releases/tag/v0.2.4-alpha)** — online play, player nameplates, and a cumulative Versus scoreboard.

Independent static/hybrid port of **Street Fighter EX Plus Alpha** for PlayStation, dedicated exclusively to the North American edition `SLUS-00548`.

The repository contains only source code, configuration, and discovery data necessary to generate the port. It does not contain BIOS, game images, extracted executables, saves, or code generated from these files.

## Current features

- **Offline gameplay and online Versus:** a dedicated launcher for the USA edition `SLUS-00548`, with online lobby support and rollback synchronization.
- **Player names on the HUD:** online display names appear on the appropriate player side; offline player names can also be configured.
- **Optional player bars:** show or hide the nameplates and score boxes using the launcher option. They appear only during Versus gameplay, staying hidden in other modes and selection screens.
- **Compact nameplates:** up to eight display characters per name, with separate yellow win counters beside the bars.
- **Cumulative match scoreboard:** each completed match adds one point to its winner. If P1 wins and then P2 wins, the score becomes **1–1**. Rematches and character changes preserve the totals.
- **Session score resets:** returning to mode selection, starting a new session, successfully loading a manual save state, or disconnecting clears the counters. The scoreboard state participates in rollback snapshots to prevent duplicate awards during resimulation.
- **Software and OpenGL rendering**, with an SDL3-based Windows release.
- **Bundled enhancement and presentation resources:** 8 MB RAM, CD speed, fast loading, HD textures, PGXP, and bezel options. Included options are not necessarily enabled by default.
- **Pinned framework and UI submodules** to record the source revisions used by the port.

The maintainer has tested offline gameplay and online matches, including online names, counters, Versus-only HUD visibility, reset on return to mode selection, and synchronized play. This is an alpha release; testing continues across network conditions and gameplay scenarios.

## Download and play

The **[v0.2.4-alpha release](https://github.com/guimaraf/plusalpha-recomp/releases/tag/v0.2.4-alpha)** provides a portable Windows x64 package:

1. Download and extract `exPlusAlpha-20261021-193923.zip` into a writable folder.
2. Run `exPlusAlpha.exe` and select your own supported USA disc image and **SCPH1001.BIN** BIOS in the launcher.
3. For online play, both players should use the same release and matching supported game content.

The package includes the runtime/launcher, required non-system DLLs, UI assets and fonts, bundled mod resources, license notices, and an integrity manifest. Diagnostic tools, build tools, personal settings, and saves are excluded. **Python, CMake, and MSYS2 are not required to play.** Game images and BIOS files are not included.

A SHA-256 checksum is provided beside the ZIP. See the **[full release notes](PlusAlphaProject/RELEASE_NOTES_v0.2.4-alpha.md)** for scoreboard behavior, package contents, and validation details. The packaged runtime version string remains `0.2.0-online-dev`; the GitHub release is identified as `v0.2.4-alpha`.

The project is also [listed on PlayPorted](https://playported.com/ports/227-street-fighter-ex-plus-alpha/).

## Structure

- `PlusAlphaProject/`: configuration, seeds, and game-specific tools;
- `psxrecomp/`: framework, runtime, and networking dependencies imported as submodules;
- `recomp-ui/`: launcher and in-game interface imported as a submodule;
- `PlusAlphaProject/disc-a/`: reserved folder for the user's image;
- `PlusAlphaProject/local/`: locally extracted executable;
- `PlusAlphaProject/generated-online/`: locally generated C code for the current online build;
- `PlusAlphaProject/dist/`: locally packaged releases (not source files).

## Cloning

Clone including all submodules:

```bash
git clone --recurse-submodules https://github.com/guimaraf/plusalpha-recomp.git
cd plusalpha-recomp
```

If the repository was already cloned without recursion:

```bash
git submodule update --init --recursive
```

Local setup instructions are in [`PlusAlphaProject/BUILD_LOCAL.md`](PlusAlphaProject/BUILD_LOCAL.md). For the current online/SDL3 build workflow, see [`PlusAlphaProject/ONLINE.md`](PlusAlphaProject/ONLINE.md) and `PlusAlphaProject/tools/build_online.ps1`. To build and package a fresh release locally, use `PlusAlphaProject/tools/build_release.ps1`. Older S1-309 scripts belong to the previous workflow.

## Protected Files

You must provide your own SCPH-1001 BIOS and your own image of the USA edition `SLUS-00548`. Accepted hashes are documented in [`PlusAlphaProject/BIOS.md`](PlusAlphaProject/BIOS.md) and [`PlusAlphaProject/DISC.md`](PlusAlphaProject/DISC.md).

Do not open issues asking for BIOS, ROM, BIN/CUE, ISO, or extracted executables.

## Recording with OBS on Windows

The observations below come from earlier local builds; the current Windows release uses SDL3.

For stable video capture, use **Window Capture** in OBS and select the game
window. The game may be displayed fullscreen; capturing its window is still the
recommended method. Avoid **Display Capture** when frame-perfect recording is
important: in local tests, it occasionally produced apparent skipped frames in
the recorded video even though the game itself continued reporting stable FPS
and frame time.

During my tests, I recorded two complete Arcade matches in each of the
following configurations:

- OpenGL renderer, without video encoding or resolution scaling;
- OpenGL renderer, with video encoding and scaling from 1080p to 1440p;
- Software renderer, with video encoding and scaling from 1080p to 1440p.

Window Capture showed no FPS drops in any of my runs. The Display Capture
behavior may involve the OBS capture path, the Windows compositor, SDL2, and the
selected rendering backend; my tests did not isolate it as an SDL2 defect.

### Interpreting CPU clock readings

The CPU clock normally shown directly by MSI Afterburner/RTSS is an
instantaneous clock and should not be treated as the processor's effective
workload. For more representative readings, use HWiNFO's **Effective Clock**,
exported to MSI Afterburner/RTSS through HWiNFO Shared Memory and `HwInfo.dll`.

On my test machine, the clean build `buildClean-ucrt-s1-261-clean-ddark-bomb`
typically measured about 200-400 MHz of effective CPU clock, staying near
300 MHz during Ryu versus Ken gameplay. Running OBS increased it by roughly
100 MHz, remaining near or below 500 MHz. These values are specific to my
machine and test environment and are not performance requirements.

Consequently, a displayed instantaneous clock near the processor's maximum is
not, by itself, evidence that interpreted game instructions are saturating the
CPU. Interpreted code can still have a performance cost, but it must be assessed
with frame-time data, effective clocks, and controlled comparisons.

## Framework and Attributions

The framework is located at [`guimaraf/psxrecomp-plusalpha`](https://github.com/guimaraf/psxrecomp-plusalpha) and maintains its PolyForm Noncommercial 1.0.0 license and third-party attributions in the submodule itself.
