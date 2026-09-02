# Spec: brand-assets

## Objective

Replace the macOS application icon with the approved coral crab mascot centered on a pale-lavender background while retaining the Protective Orbit logo inside the Results UI.

## Tech Stack and Commands

- Existing transparent PNG mascot and macOS `iconutil` packaging.
- `./scripts/build-app-bundle.sh`
- `iconutil`, `sips`, `plutil`, and `codesign --verify --deep --strict build/Crab.app`.

## Project Structure and Style

- Source mascot: `prototype/public/assets/crab-loading-mascot.png`.
- New square icon source: `prototype/public/assets/crab-app-icon.png`.
- Generated `.icns` remains build output.
- Background: pale lavender matching `Color.crabLavender`; mascot remains coral and optically centered with safe margins.

## Testing Strategy

- Source must be square, opaque, and at least 1024 × 1024.
- Verify every iconset size, final `Crab.icns`, bundle metadata, and code signature.
- Inspect Finder/Dock rendering at small and large sizes.

## Boundaries

- Always: use the real mascot asset and preserve its silhouette.
- Never: use emoji, text glyphs, handcrafted SVG replacements, or a transparent app-icon background.

## Success Criteria

- Finder and Dock display the coral crab on a pale-lavender background.
- Loading continues to show only the animated mascot; Results may show the Protective Orbit logo.
