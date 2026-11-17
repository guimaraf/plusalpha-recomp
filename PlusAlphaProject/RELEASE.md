# Windows release build

Run the following from PowerShell on the build machine. The command builds a fresh Release directory and creates a portable folder, ZIP and SHA-256 checksum. It does not launch the game.

```powershell
Set-Location 'F:\GitRevised\alphaplus\plusalpha-recomp'
.\PlusAlphaProject\tools\build_release.ps1 -Jobs 2 -SdlBackend SDL3
```

The script reads the version from `PlusAlphaProject/VERSION`. It requires Python, the MSYS2 UCRT64 toolchain, initialized submodules, the locally prepared game sources, retained overlays, and the validated SCPH1001 BIOS. By default the BIOS is read from `bios/SCPH1001.BIN`; use `-BiosPath` to choose another path. The default retained overlays are under `PlusAlphaProject/buildTele-s1-309-bezeus/static_overlays`; use `-RetainedOverlayDir` if stored elsewhere.

Without `-Generate`, the script uses already prepared game and BIOS sources. If they are not prepared, follow [ONLINE.md](ONLINE.md) before building. `-Generate` regenerates sources and requires the local game disc and BIOS; use it only when regeneration is intended.

## Output

- `PlusAlphaProject/build-release-online-<timestamp>/`: build directory.
- `PlusAlphaProject/dist/exPlusAlpha-<timestamp>/`: portable folder.
- `PlusAlphaProject/dist/exPlusAlpha-<timestamp>.zip`: distribution archive.
- `PlusAlphaProject/dist/exPlusAlpha-<timestamp>.zip.sha256`: archive checksum.

The package omits BIOS, game images, saves and personal settings. The player supplies the supported USA disc image and SCPH1001.BIN. Test an extracted copy before distribution; preserve the original ZIP and compare its SHA-256 with the checksum file. `-NoZip` creates only the portable folder. `-PackageOnly -BuildDirName <existing-build-directory>` packages a compatible existing Release build without compiling.

Do not publish a `.partial` archive. The packaging script checks the ZIP against its manifest before completing it.

## Validation before publication

Extract the ZIP into two fresh writable folders and test each copy with your own disc and BIOS. Verify offline boot and gameplay first, then test online versus with matching releases. Test on separate machines and network conditions before drawing conclusions about online stability. Keep the ZIP unchanged and do not distribute the saves or personal settings created during testing.

For local two-window positioning, run `PlusAlphaProject/tools/position_netplay_windows.ps1` from the repository with `-FirstDir`, `-SecondDir`, and `-Fit`. The TCP capture scripts require a separate diagnostics build and do not inspect this release build.

To check a received archive, run `Get-FileHash '<path-to-zip>' -Algorithm SHA256` and compare it with the accompanying `.zip.sha256` file.
