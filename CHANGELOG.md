# Changelog

All notable changes to Crab are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Runtime Optimization now reports local disk, memory-pressure, swap, uptime,
  thermal, sustained-process, and mounted-disk-image findings before showing
  maintenance results.
- Finder and Dock refreshes are explicit optional actions. Mounted disk images
  can be ejected only after confirmation and a fresh identity check.

### Changed

- Automatic Runtime Optimization is limited to reviewed Quick Look and app
  association maintenance; it never refreshes Finder or Dock automatically.

## [0.2.2] - 2026-09-04

### Fixed

- Closing the main window now removes Crab from the Dock while keeping its
  menu-bar icon and process available.
- Reopening Crab from the menu bar restores the main window and normal Dock
  presence; standard window minimization remains unchanged.

## [0.2.1] - 2026-09-04

### Fixed

- Update checks now use a versioned manifest attached to the latest official
  GitHub Release and fall back to it when the anonymous GitHub API is
  rate-limited.
- Release packaging verifies the manifest version, asset URL, size, and SHA-256
  digest before publication.

## [0.2.0] - 2026-09-04

### Changed

- Replaced the AI-app memory snapshot with an explicit whole-Mac Runtime
  Optimization workflow. It now refreshes Quick Look, app associations, and
  Finder only after the user clicks Start, shows animated task progress and
  per-task receipts, and never deletes files or closes third-party apps.

### Security

- Runtime Optimization uses one reviewed, timeout-bounded process boundary with
  fixed system executables and arguments; shells, administrator access, and
  user-provided commands remain unavailable.

## [0.1.2] - 2026-09-04

### Changed

- The primary manual installation artifact is now a macOS disk image with a
  drag-to-Applications flow.
- The architecture-specific ZIP remains available exclusively for compatible
  in-app updates, and release checksums now cover both artifacts.
- Added an on-demand, read-only Runtime Optimization page and menu-bar entry for
  reviewing supported AI desktop app process-tree memory without closing,
  pausing, or terminating applications and without modifying files.
- Added project search, inactive/large/recent filters, activity/size sorting,
  and select-all limited to the currently visible project results.
- Added last-scan details on the cache home page and separated immediately
  cleanable cache from cache blocked while its owning application is running.
- Reorganized repository documentation and removed the obsolete web prototype
  so the native macOS application, safety rules, and release tooling are easier
  to review.

## [0.1.1] - 2026-09-02

### Added

- User-confirmed in-app updates from Crab's official GitHub Releases.
- Download, size, SHA-256, bundle identity, version, file-structure, and code-signature validation before installation.
- Same-volume atomic app replacement with automatic relaunch and safe failure behavior.

### Security

- Update metadata, redirects, archives, and extracted applications are treated as untrusted input and fail closed.
- Only exact architecture-specific Crab release assets from allowlisted GitHub hosts are accepted.
- A failed verification or installation leaves the currently installed Crab application unchanged.

## [0.1.0] - 2026-09-02

### Added

- Native SwiftUI macOS application with Chinese and English localization.
- Safe cache discovery for installed AI desktop and command-line applications.
- Application inventory with recent-use, usage, open, and safe-uninstall actions.
- Automatic project discovery grouped by the associated AI application.
- Project cleanup with explicit selection, a second confirmation, fresh identity
  validation, and Trash-only execution.
- Labels for projects unused for six months and projects at least 1 GB in size.
- Menu bar presence, settings, launch-at-login support, and update checks.
- Dependency-free CLI commands for rule validation, scanning, and clean-plan creation.
- Apple Silicon public-beta application archive with a published SHA-256 checksum.

### Safety

- Nothing is selected automatically.
- Crab never permanently deletes files.
- Cache rules are exact reviewed leaves; unknown user data fails closed.
- Photos and Apple Music libraries are excluded from project inventory.
- Every selected target is revalidated immediately before it reaches the Trash boundary.
