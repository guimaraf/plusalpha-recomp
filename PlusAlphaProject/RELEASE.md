# Windows release build

Run the following from PowerShell on the build machine. The command builds a fresh Release directory and creates a portable folder, ZIP and SHA-256 checksum. It does not launch the game.

```powershell
Set-Location 'F:\GitRevised\alphaplus\plusalpha-recomp'
.\PlusAlphaProject\tools\build_release_0.2.51.ps1
```

Note: the 0.2.51 script requires `PlusAlphaProject/VERSION` to contain `0.2.51` (the current version is in that file); for other versions, see `tools/build_release.ps1`, which builds and packages whatever version `VERSION` holds but does not run the extra ZIP checks (version, RecompLauncher profile, excluded HD Texture Packs) done by the 0.2.51 script.

The version-specific script requires `PlusAlphaProject/VERSION` to contain `0.2.51`, builds in a fresh timestamped directory and verifies that the ZIP contains version 0.2.51 and excludes the HD Texture Packs mod. It calls `build_release.ps1` with two jobs and SDL3. It requires Python, the MSYS2 UCRT64 toolchain, initialized submodules, the locally prepared game sources, retained overlays, and the validated SCPH1001 BIOS. By default the BIOS is read from `gameFiles/bios/SCPH1001.BIN`; use `-BiosPath` to choose another path. The default retained overlays are under `PlusAlphaProject/buildTele-s1-309-bezeus/static_overlays`; use `-RetainedOverlayDir` if stored elsewhere.

For future versions, the underlying `build_release.ps1` names new packages `exPlusAlpha-v<version>-Windows-x64-<timestamp>.zip`, reading the version from `VERSION` or, in `-PackageOnly` mode, from the existing build.

The version-specific script uses already prepared game and BIOS sources and does not regenerate them. If they are not prepared, follow [ONLINE.md](ONLINE.md). The underlying `build_release.ps1` supports `-Generate`, which regenerates sources and requires the local game disc and BIOS.

## Windows release identification

The project metadata in `.recomp.json` declares Windows as its target. The ZIP filename uses the `exPlusAlpha-` prefix required by the current RecompLauncher catalog and includes `Windows-x64` to identify the target platform and architecture. Upload the generated ZIP and its matching `.sha256` file without renaming either file. GitHub may normalize asset names; if it does, verify that the checksum file names the uploaded ZIP. Automatic recognition depends on the launcher and its catalog settings.

## RecompLauncher integration

Every package includes `recomplauncher.json` beside `exPlusAlpha.exe`. RecompLauncher can request a USA `.cue`, validate the disc serial and pass the selected disc to the game launcher. It can also expose renderer, internal resolution, fullscreen and VSync settings, and back up the default `saves` directory. Custom memory-card paths need separate backup.

The PS1 BIOS must still be selected in the game launcher; the SDK does not manage PS1 BIOS files. The game launcher remains available for BIOS selection, netplay and its other settings. `settings.toml` is not included in cloud backups by this profile because it can contain machine-specific paths. Test the profile with RecompLauncher Developer tools before releasing; packaging the profile alone does not publish an update or force a catalog refresh.

## Output

- `PlusAlphaProject/build-release-online-<timestamp>/`: build directory.
- `PlusAlphaProject/dist/exPlusAlpha-v0.2.51-Windows-x64-<timestamp>/`: portable folder.
- `PlusAlphaProject/dist/exPlusAlpha-v0.2.51-Windows-x64-<timestamp>.zip`: distribution archive.
- `PlusAlphaProject/dist/exPlusAlpha-v0.2.51-Windows-x64-<timestamp>.zip.sha256`: archive checksum.

The package omits BIOS, game images, saves and personal settings. The player supplies the supported USA disc image and SCPH1001.BIN. Test an extracted copy before distribution; preserve the original ZIP and compare its SHA-256 with the checksum file. The underlying `build_release.ps1` supports `-NoZip` to create only the portable folder and `-PackageOnly -BuildDirName <existing-build-directory>` to package an existing compatible Release build without compiling. These switches are not accepted by the version-specific script.

Do not publish a `.partial` archive. The packaging script checks the ZIP against its manifest before completing it.

## Validation before publication

Extract the ZIP into two fresh writable folders and test each copy with your own disc and BIOS. Verify offline boot and gameplay first, then test online versus with matching releases. Test on separate machines and network conditions before drawing conclusions about online stability. Keep the ZIP unchanged and do not distribute the saves or personal settings created during testing.

For local two-window positioning, run `PlusAlphaProject/tools/position_netplay_windows.ps1` from the repository with `-FirstDir`, `-SecondDir`, and `-Fit`. The TCP capture scripts require a separate diagnostics build and do not inspect this release build.

To check a received archive, run `Get-FileHash '<path-to-zip>' -Algorithm SHA256` and compare it with the accompanying `.zip.sha256` file.
