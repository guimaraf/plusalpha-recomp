# Street Fighter EX Plus Alpha Recomp

Independent static/hybrid port of **Street Fighter EX Plus Alpha** for PlayStation, dedicated exclusively to the North American edition `SLUS-00548`.

The repository contains only source code, configuration, and discovery data necessary to generate the port. It does not contain BIOS, game images, extracted executables, saves, or code generated from these files.

## Status

- gameplay validated in Software 1x at 60 FPS in baseline scenarios;
- launcher dedicated to `SLUS-00548`;
- execution with LLE BIOS SCPH-1001;
- CI-generated release built from statically recompiled sources;
- framework pinned as a submodule to keep the port reproducible.

## Structure

- `PlusAlphaProject/`: configuration, seeds, and game-specific tools;
- `psxrecomp/`: framework and runtime imported as a submodule;
- `PlusAlphaProject/disc-a/`: reserved folder for the user's image;
- `PlusAlphaProject/local/`: locally extracted executable;
- `PlusAlphaProject/generated/`: generated C code from the game's executable.

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

Complete instructions are in [`PlusAlphaProject/BUILD_LOCAL.md`](PlusAlphaProject/BUILD_LOCAL.md).

## Protected Files

You must provide your own SCPH-1001 BIOS and your own image of the USA edition `SLUS-00548`. Accepted hashes are documented in [`PlusAlphaProject/BIOS.md`](PlusAlphaProject/BIOS.md) and [`PlusAlphaProject/DISC.md`](PlusAlphaProject/DISC.md).

Do not open issues asking for BIOS, ROM, BIN/CUE, ISO, or extracted executables.

## Recording with OBS on Windows

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

---
## Project Overview

# Street Fighter EX Plus Alpha Recomp

Independent static/hybrid port of **Street Fighter EX Plus Alpha** for PlayStation, dedicated exclusively to the North American edition `SLUS-00548`.

The repository contains only source code, configuration, and discovery data necessary to generate the port. It does not contain BIOS, game images, extracted executables, saves, or code generated from these files.

## Status

- gameplay validated in Software 1x at 60 FPS in baseline scenarios;
- launcher dedicated to `SLUS-00548`;
- execution with LLE BIOS SCPH-1001;
- CI-generated release built from statically recompiled sources;
- framework pinned as a submodule to keep the port reproducible.

## Structure

- `PlusAlphaProject/`: configuration, seeds, and game-specific tools;
- `psxrecomp/`: framework and runtime imported as a submodule;
- `PlusAlphaProject/disc-a/`: reserved folder for the user's image;
- `PlusAlphaProject/local/`: locally extracted executable;
- `PlusAlphaProject/generated/`: generated C code from the game's executable.

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

Complete instructions are in [`PlusAlphaProject/BUILD_LOCAL.md`](PlusAlphaProject/BUILD_LOCAL.md).

## Protected Files

You must provide your own SCPH-1001 BIOS and your own image of the USA edition `SLUS-00548`. Accepted hashes are documented in [`PlusAlphaProject/BIOS.md`](PlusAlphaProject/BIOS.md) and [`PlusAlphaProject/DISC.md`](PlusAlphaProject/DISC.md).

Do not open issues asking for BIOS, ROM, BIN/CUE, ISO, or extracted executables.

## Recording with OBS on Windows

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
