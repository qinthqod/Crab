# Spec: Crab System-Language Localization

## Objective

Crab provides complete Simplified Chinese and English application interfaces. The active language follows the first macOS preferred language: `zh-Hans` and Chinese regional variants use Simplified Chinese; every other language uses English.

## Commands

- Build: `swift build -c debug --product CrabApp`
- Test: `swift run crab-core-tests`
- Package: `./scripts/build-app-bundle.sh`
- Verify: `codesign --verify --deep --strict build/Crab.app`

## Project Structure

- `Sources/CrabApp/Localization.swift`: locale resolution and typed dynamic copy.
- `Sources/CrabApp/Resources/*.lproj/Localizable.strings`: static SwiftUI copy.
- `Sources/CrabApp/*.swift`: dynamic strings routed through the localization layer.
- `Packaging/Info.plist`: declares supported localizations.

## Code Style

```swift
Text(CrabL10n.projectCount(total: total, inactive: inactive))
```

Static SwiftUI literals use localization resources. Copy containing runtime values uses named `CrabL10n` functions rather than assembling translated fragments.

## Testing Strategy

- Unit-test preferred-language resolution independently of the host locale.
- Unit-test representative pluralized/dynamic Chinese and English output.
- Validate both packaged locales using `AppleLanguages` overrides and the accessibility tree.
- Run the complete core suite and launch smoke test.

## Boundaries

- Always: localize visible controls, states, dialogs, errors, menu items, help and accessibility copy.
- Always: preserve product names, versions, sizes and filesystem paths.
- Never: infer language from region alone or send locale information off device.
- Never: localize stable app IDs, rule IDs or cleanup evidence.

## Success Criteria

- Chinese-preferred macOS displays the existing Simplified Chinese interface.
- English or any non-Chinese preferred language displays English throughout the main workflows.
- Menu bar, settings, cache cleanup, application management, residue review and project cleanup all switch consistently.
- Layout remains usable at Crab's minimum window size in both languages.
- Changing the system preferred language takes effect on the next application launch.

## Open Questions

- None. An in-app language override and additional locales remain out of scope.
