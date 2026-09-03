# DMG Distribution

## Objective

Give macOS users the familiar drag-to-install flow while preserving Crab's
existing in-app update format.

## Distribution Contract

- `Crab-<version>-macOS-<architecture>.dmg` is the primary manual download.
- Opening the disk image presents exactly `Crab.app` and an `Applications`
  symbolic link whose target is `/Applications`.
- Users install Crab by dragging `Crab.app` onto `Applications`.
- `Crab-<version>-macOS-<architecture>.zip` remains available for the existing
  in-app updater and is not the preferred manual-install artifact.
- The application in both artifacts is the same verified, ad-hoc-signed bundle.
- `SHA256SUMS.txt` contains SHA-256 entries for both the DMG and ZIP.

## Safety Boundaries

- The DMG contains no installer package, shell script, privileged helper, or
  executable other than `Crab.app`.
- Creating or opening the DMG never modifies `/Applications`; installation only
  occurs when the user explicitly drags the app there.
- Crab remains ad-hoc signed and is not submitted for Apple notarization.
- Temporary staging and mount directories are narrowly scoped and cleaned up.

## Verification

Run:

```bash
bash scripts/package-release.sh
bash scripts/test-release-package.sh
```

The verification must mount the DMG read-only, validate its exact top-level
layout and link target, verify the embedded app signature, confirm the ZIP is
still present, and check both checksum entries.
