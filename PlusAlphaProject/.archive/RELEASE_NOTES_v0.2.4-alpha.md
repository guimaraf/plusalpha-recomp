# Ex Plus Alpha v0.2.4-alpha — Online Play and Versus Scoreboard

This Windows x64 release enables online play with lobby support and rollback netcode, and adds player nameplates and a cumulative match scoreboard to Versus gameplay.

## Highlights

- **Online multiplayer:** play Versus matches through the online lobby with rollback synchronization.
- **Online player names:** each player's online display name appears on the correct side of the HUD.
- **Versus-only nameplates:** the player bars and score boxes appear during Versus gameplay and stay hidden in other game modes and selection screens.
- **Compact player bars:** names use up to eight display characters, with longer names truncated for presentation.
- **Separate win boxes:** each player's total appears in its own box beside the nameplate.
- **Cumulative match scores:** each completed match adds one point to its winner. A P1 win followed by a P2 win displays **1–1**, rather than replacing the previous player's streak.
- **Session continuity:** rematches and character changes preserve the accumulated score.
- **Score resets:** returning to mode selection, starting a new session, successfully loading a manual save state, or disconnecting clears the scores.
- **Result protection:** held result flags and replay transitions do not repeatedly award the same match. The counters and result latch participate in rollback snapshots so a restored result can be recalculated.
- **Non-scoring results:** results excluded by the game's native scoring rules do not award a point.

## Package contents

The portable package contains the game launcher/runtime, online lobby support, required non-system DLLs, interface assets and fonts, bundled mod resources, third-party license notices, and a file integrity manifest. It includes bundled resources for the 8 MB RAM, CD speed, fast loading, HD textures, PGXP, and bezel options; inclusion does not mean every option is enabled by default.

This is a Release build with diagnostic tools disabled. Build directories, compilers, development tools, personal saves, and personal settings are not included. Python, CMake, and MSYS2 are not required to run the package.

## Installation

1. Download and extract `exPlusAlpha-20261021-193923.zip` into a writable folder.
2. Run `exPlusAlpha.exe`.
3. Select your own supported **Street Fighter EX Plus Alpha (USA), SLUS-00548** disc image and **SCPH1001.BIN** BIOS in the launcher. The disc image and BIOS are not included.
4. For online play, both players should use this same release and matching supported game content.

## Validation and status

The maintainer built and tested the supplied package. Reported tests confirmed Versus-only HUD visibility, cumulative counters, reset on return to mode selection, online player names, and successful synchronized online gameplay. This remains an alpha release for further testing; these reports do not constitute exhaustive validation of all network conditions, draw outcomes, disconnect paths, or rollback scenarios.

The published ZIP is the exact existing package tested by the maintainer; it was not rebuilt or repackaged during publication. The packaged runtime version string remains `0.2.0-online-dev`; `v0.2.4-alpha` identifies this GitHub release. Source commits created for publication record the tested working-tree implementation and submodule revisions after the binary was built.

## Downloads and integrity

- Windows x64 portable package: `exPlusAlpha-20261021-193923.zip`
- SHA-256 checksum: `exPlusAlpha-20261021-193923.zip.sha256`

```text
27e612f5053a1917dca04e4aaebd923fc63ad1ba04a49efa847c0c865fb2660a  exPlusAlpha-20261021-193923.zip
```
