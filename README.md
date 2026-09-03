# Crab

**Stable Cleaning**

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="docs/images/crab-readme-hero.png" alt="Crab organizing AI application storage in a calm lavender ocean" width="100%">
</p>

Crab is an open-source macOS utility focused on one job: safely cleaning and
managing storage created by AI applications and coding harnesses.

> Crab prioritizes data safety over reclaimed space. Nothing is selected
> automatically, unknown data is protected, and cleanup only moves explicitly
> confirmed items to the macOS Trash.

## Download

[**Download Crab v0.1.1 for Apple Silicon →**](https://github.com/qinthqod/Crab/releases/download/v0.1.1/Crab-0.1.1-macOS-arm64.zip)

Crab requires Apple Silicon and macOS 14 or later. Before installing, you can
download the [SHA-256 checksum](https://github.com/qinthqod/Crab/releases/download/v0.1.1/SHA256SUMS.txt).
See [GitHub Releases](https://github.com/qinthqod/Crab/releases) for release notes
and all available versions.

## Features

- **Cache Cleanup** — scans reviewed, regenerable cache leaves for installed AI
  desktop and command-line applications.
- **Application Management** — shows installed and running AI tools, recent use,
  available local usage metrics, and safe app-only uninstall.
- **Project Cleanup** — automatically discovers projects, associates them with AI
  applications, and lets the user move any selected project to Trash after a
  second confirmation.
- **Useful Labels** — projects unused for six months and projects at least 1 GB
  are labelled for attention; labels never auto-select or restrict them.
- **Bilingual UI** — follows the macOS language by default and supports an explicit
  Chinese or English preference.
- **In-app Updates** — checks Crab's official GitHub Releases and, after explicit
  confirmation, verifies and installs a matching archive.

Current rules cover installed products such as ChatGPT, Claude and Claude Code,
Cursor, Codex, DeepSeek Harness, Windsurf, TRAE, Zed, Ollama, and Doubao variants.
Products without a reviewed cache leaf are shown as protected instead of being
silently omitted.

<table>
  <tr>
    <th>Cache Cleanup</th>
    <th>Application Management</th>
    <th>Project Cleanup</th>
  </tr>
  <tr>
    <td><img src="docs/images/crab-cache-cleanup.png" alt="Crab safely organizing regenerable cache blocks"></td>
    <td><img src="docs/images/crab-app-management.png" alt="Crab reviewing AI application activity and storage"></td>
    <td><img src="docs/images/crab-project-cleanup.png" alt="Crab organizing projects by age and size"></td>
  </tr>
</table>

## Safety Contract

- No permanent deletion. Selected items are moved to Trash and remain recoverable
  until the Trash is emptied.
- No automatic selection or cleanup.
- Cache rules are exact reviewed leaves. Crab does not clean broad Application
  Support, chat, credential, model-weight, or download directories.
- Project roots are automatically associated with installed AI applications. Every
  selected root is revalidated immediately before execution.
- Changed identities, symbolic-link path chains, stale plans, and paths outside the
  approved boundary fail closed.
- Photos and Apple Music libraries are excluded from project inventory.
- No account, telemetry, analytics, upload, or cloud service is required.

The detailed contracts live in [SPEC-safe-scan.md](SPEC-safe-scan.md),
[SPEC-project-inventory.md](SPEC-project-inventory.md), and
[SPEC-archive-trash-execution.md](SPEC-archive-trash-execution.md).

## Requirements

- macOS 14 or later
- Apple Silicon for the downloadable v0.1.1 beta
- Intel Macs can build Crab from source with a compatible Swift 6 toolchain
- Swift 6 toolchain for source builds

## Install the Public Beta

Download [`Crab-0.1.1-macOS-arm64.zip`](https://github.com/qinthqod/Crab/releases/download/v0.1.1/Crab-0.1.1-macOS-arm64.zip)
and [`SHA256SUMS.txt`](https://github.com/qinthqod/Crab/releases/download/v0.1.1/SHA256SUMS.txt),
verify the checksum, unzip the archive, and move `Crab.app` to Applications.

Version 0.1.1 adds user-confirmed updates inside Crab. Because 0.1.0 did not contain
the installer, upgrading from 0.1.0 to 0.1.1 is the final manual update. Later
compatible releases can be installed from Settings.

The beta is ad-hoc signed and is not notarized. macOS may require you to
Control-click Crab and choose **Open** the first time. Do not bypass security
warnings for a binary whose checksum does not match the published value.

## Build from Source

```bash
git clone https://github.com/qinthqod/Crab.git
cd Crab
swift run crab-core-tests
./scripts/build-app-bundle.sh
open build/Crab.app
```

Build a versioned zip and checksum file:

```bash
./scripts/package-release.sh
```

## CLI

The CLI is intentionally read-only: it validates rules, scans reviewed cache leaves,
and creates immutable plans. It has no clean command and accepts no arbitrary cleanup
path.

```bash
swift run crab --help
swift run crab rules validate Fixtures/Rules/example.json
swift run crab scan --rules Fixtures/Rules --home Fixtures/Home

# Empty selection is the safe default.
swift run crab plan \
  --rules Fixtures/Rules \
  --home Fixtures/Home \
  --output /tmp/crab-empty-plan.json
```

## Development

```bash
swift run crab-core-tests
swift build -c release
bash scripts/check-dangerous-apis.sh
```

The native application is implemented in SwiftUI. The web prototype under
`prototype/` is a design reference and is not production application code.

See [CONTRIBUTING.md](CONTRIBUTING.md) before proposing an application rule or a
change to cleanup behavior. Security issues should follow [SECURITY.md](SECURITY.md).

## License

Crab is available under the [MIT License](LICENSE).
