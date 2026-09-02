# Changelog

All notable changes to Crab are documented here. This project follows
[Semantic Versioning](https://semver.org/).

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
