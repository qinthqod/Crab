# Crab

**断舍离 · Stable Cleaning**

Crab is an open-source macOS utility focused on one job: safely cleaning and
managing storage created by AI applications and coding harnesses.

Crab 是一款开源 macOS 工具，只专注于一件事：安全清理并管理 AI 应用与
Coding Harness 产生的本地存储。

> Crab prioritizes data safety over reclaimed space. Nothing is selected
> automatically, unknown data is protected, and cleanup only moves explicitly
> confirmed items to the macOS Trash.

> Crab 把数据安全置于释放空间之前：不会自动勾选项目，未知数据默认受保护，
> 只有用户明确选择并确认的内容才会被移入 macOS 废纸篓。

## Features / 功能

- **Cache Cleanup / 缓存清理** — scans reviewed, regenerable cache leaves for
  installed AI desktop and command-line applications.
- **Application Management / 应用管理** — shows installed and running AI tools,
  recent use, available local usage metrics, and safe app-only uninstall.
- **Project Cleanup / 项目清理** — automatically discovers projects, associates
  them with AI applications, and lets the user move any selected project to Trash
  after a second confirmation.
- **Useful labels / 风险提示** — projects unused for six months and projects at
  least 1 GB are labelled for attention; labels never auto-select or restrict them.
- **Bilingual UI / 双语界面** — follows the macOS language by default and supports
  an explicit Chinese or English preference.

Current rules cover installed products such as ChatGPT, Claude/Claude Code,
Cursor, Codex, DeepSeek Harness, Windsurf, TRAE, Zed, Ollama, and 豆包 variants.
Products without a reviewed cache leaf are shown as protected rather than silently
omitted.

## Safety contract / 安全边界

- No permanent deletion. Selected items are moved to Trash and remain recoverable
  until the Trash is emptied.
- No automatic selection or cleanup.
- Cache rules are exact reviewed leaves; Crab does not clean broad Application
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
- Apple Silicon for the downloadable v0.1.0 beta
- Intel Macs can build Crab from source with a compatible Swift 6 toolchain
- Swift 6 toolchain for source builds

## Install the public beta

Download `Crab-0.1.0-macOS-arm64.zip` and `SHA256SUMS.txt` from the latest GitHub Release,
verify the checksum, unzip it, and move `Crab.app` to Applications.

The first beta is ad-hoc signed because the project does not yet have an Apple
Developer ID certificate. It is not notarized. macOS may require you to Control-click
Crab and choose **Open** the first time. Do not bypass security warnings for a binary
whose checksum does not match the published value.

首次公开测试版采用 ad-hoc 签名，尚未经过 Apple 公证。首次启动时 macOS 可能
要求按住 Control 点击 Crab 并选择“打开”。若校验值与 Release 公布内容不一致，
请勿运行。

## Build from source

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
