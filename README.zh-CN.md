# Crab

**断舍离 · Stable Cleaning**

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="docs/images/crab-readme-hero.png" alt="Crab 在淡紫色海洋中整理 AI 应用存储" width="100%">
</p>

Crab 是一款开源 macOS 工具，只专注于一件事：安全清理并管理 AI 应用与
Coding Harness 产生的本地存储。

> Crab 把数据安全置于释放空间之前：不会自动勾选项目，未知数据默认受保护，
> 只有用户明确选择并确认的内容才会被移入 macOS 废纸篓。

## 下载

[**下载 Crab v0.2.0 Apple Silicon 版 →**](https://github.com/qinthqod/Crab/releases/download/v0.2.0/Crab-0.2.0-macOS-arm64.dmg)

Crab 需要 Apple Silicon 与 macOS 14 或更高版本。安装前可下载
[SHA-256 校验文件](https://github.com/qinthqod/Crab/releases/download/v0.2.0/SHA256SUMS.txt)。
全部版本和发布说明请前往 [GitHub Releases](https://github.com/qinthqod/Crab/releases)。

> **macOS 首次打开说明：**当前公开测试版采用 ad-hoc 签名，尚未经过 Apple 公证。
> 即使安装包完整，macOS 也可能拦截首次启动。请先核对官方 SHA-256 校验值，再按照
> 下方的[首次打开步骤](#macos-首次打开说明)操作。

## 功能

- **缓存清理** — 扫描已安装 AI 桌面应用与命令行工具中经过审核、可重新生成的精确缓存目录。
- **应用管理** — 显示已安装和运行中的 AI 工具、最近使用时间、可获取的本地用量指标，并支持仅卸载应用本体。
- **运行优化** — 用户主动点击后，为整台 Mac 刷新文件预览、应用关联和 Finder；不删除文件，也不关闭第三方应用。
- **项目清理** — 自动发现项目并关联到 AI 应用；用户明确选择并二次确认后，才可将项目移入废纸篓。
- **风险提示** — 为超过 6 个月未使用和不小于 1 GB 的项目添加标签；标签不会自动选择或限制项目。
- **双语界面** — 默认跟随 macOS 系统语言，也可以明确选择中文或英文。
- **应用内更新** — 检查 Crab 官方 GitHub Releases；用户确认后验证并安装匹配的更新包。

当前规则覆盖 ChatGPT、Claude、Claude Code、Cursor、Codex、DeepSeek Harness、
Windsurf、TRAE、Zed、Ollama 和豆包系列等已安装产品。缺少已审核缓存规则的产品
会显示为受保护状态，而不会被静默省略。

<table>
  <tr>
    <th>缓存清理</th>
    <th>应用管理</th>
    <th>项目清理</th>
  </tr>
  <tr>
    <td><img src="docs/images/crab-cache-cleanup.png" alt="Crab 安全整理可重新生成的缓存块"></td>
    <td><img src="docs/images/crab-app-management.png" alt="Crab 查看 AI 应用活动与本地占用"></td>
    <td><img src="docs/images/crab-project-cleanup.png" alt="Crab 根据时间和大小整理项目"></td>
  </tr>
</table>

## 仓库结构

```text
Sources/          SwiftUI 应用、安全核心、CLI 和测试工具
Rules/            按产品审核的缓存规则
Assets/Brand/     macOS 应用打包使用的品牌源文件
Fixtures/         非生产环境的文件系统与规则测试样例
Packaging/        macOS 应用元数据
scripts/          构建、验证、冒烟测试和发布脚本
docs/             产品、工程、安全、研究和技术规格
.github/workflows 持续集成
```

## 安全边界

- 不永久删除。已选择内容只会移入废纸篓，清空废纸篓前仍可恢复。
- 不自动选择，也不自动清理。
- 缓存规则只允许经过审核的精确目录。Crab 不会清理宽泛的 Application Support、对话、凭据、模型权重或下载目录。
- 项目根目录会自动关联到已安装的 AI 应用；每个已选项目在执行前都会再次校验。
- 文件身份变化、符号链接路径、过期计划和安全边界外路径都会触发停止处理。
- 项目扫描明确排除照片和 Apple Music 资料库。
- 不需要账户、遥测、分析、上传或云服务。

详细约束统一收录在[文档索引](docs/README.md)，包括
[安全扫描](docs/specs/safe-scan.md)、[项目盘点](docs/specs/project-inventory.md)和
[项目废纸篓执行](docs/specs/archive-trash-execution.md)规格。

## 系统要求

- macOS 14 或更高版本
- 可下载的 v0.2.0 测试版适用于 Apple Silicon
- Intel Mac 可使用兼容的 Swift 6 工具链从源码构建
- 从源码构建需要 Swift 6 工具链

## 安装公开测试版

下载 [`Crab-0.2.0-macOS-arm64.dmg`](https://github.com/qinthqod/Crab/releases/download/v0.2.0/Crab-0.2.0-macOS-arm64.dmg)
和 [`SHA256SUMS.txt`](https://github.com/qinthqod/Crab/releases/download/v0.2.0/SHA256SUMS.txt)，
验证校验值并打开磁盘映像，然后把 `Crab.app` 拖到“Applications（应用程序）”快捷方式。
复制完成后推出 Crab 磁盘映像。

v0.1.1 增加了用户确认后的 Crab 应用内更新。由于 v0.1.0 尚未包含安装器，
从 v0.1.0 升级到 v0.1.1 是最后一次手动更新；之后的兼容版本可从设置页面安装。

### macOS 首次打开说明

测试版采用 ad-hoc 签名，尚未经过 Apple 公证。首次启动时，Gatekeeper 可能提示
“Apple 无法验证 Crab 是否包含可能危害 Mac 安全或泄漏隐私的恶意软件”。这是 macOS
的来源验证提示，并不表示 Crab 已经启动后崩溃。

确认下载文件与官方发布的 SHA-256 校验值一致后：

1. 将磁盘映像中的 `Crab.app` 拖入“应用程序”。
2. 尝试打开一次；若 macOS 阻止打开，请点击“完成”。
3. 打开“系统设置 → 隐私与安全”。
4. 在“安全性”区域找到 Crab 被阻止的提示，点击“仍要打开”。
5. 再次确认“打开”。之后通常可以直接启动 Crab。

部分 macOS 版本也可以在“应用程序”中按住 Control 点击 Crab，选择“打开”，再确认
“打开”。如果校验值与 Crab 官方 Release 公布的值不一致，请勿继续打开。

## 从源码构建

```bash
git clone https://github.com/qinthqod/Crab.git
cd Crab
swift run crab-core-tests
./scripts/build-app-bundle.sh
open build/Crab.app
```

构建拖拽安装用 DMG、应用内更新使用的 ZIP，以及两者的校验文件：

```bash
./scripts/package-release.sh
```

## CLI

CLI 有意保持只读：它负责验证规则、扫描经过审核的缓存目录，并创建不可变计划。
它没有清理命令，也不接受任意清理路径。

```bash
swift run crab --help
swift run crab rules validate Fixtures/Rules/example.json
swift run crab scan --rules Fixtures/Rules --home Fixtures/Home

# 空选择是安全默认值。
swift run crab plan \
  --rules Fixtures/Rules \
  --home Fixtures/Home \
  --output /tmp/crab-empty-plan.json
```

## 开发

```bash
swift run crab-core-tests
swift build -c release
bash scripts/check-dangerous-apis.sh
```

原生应用使用 SwiftUI 实现。架构、产品、安全和研究资料统一整理在
[`docs/`](docs/README.md) 下。

提交应用规则或修改清理行为前，请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
安全问题请遵循 [SECURITY.md](SECURITY.md)。

## 许可证

Crab 使用 [MIT License](LICENSE) 开源。
