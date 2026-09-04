# Mole 技术调研：Crab 可以借鉴什么

> 调研对象：[tw93/Mole](https://github.com/tw93/Mole)
> 基准分支：`main`
> 基准提交：[`650ec4202343542e86b09c451a75bd6c171b5b6e`](https://github.com/tw93/Mole/tree/650ec4202343542e86b09c451a75bd6c171b5b6e)
> 调研日期：2026-09-01
> 结论：参考安全工程和 macOS 文件操作经验，不复制 Mole 的通用清理范围与 Shell 架构

## 1. 一句话结论

Mole 是一个功能很广的 Mac 维护工具，覆盖清理、卸载、优化、磁盘分析和系统监控。Crab 与它不应在产品范围上竞争。Crab 应只解决一个问题：**识别并安全处理主流 AI 工具产生的可再生缓存、更新残留、旧运行时，以及由用户显式管理的生成文件。**

Mole 最有参考价值的是经过大量真实问题磨出来的文件安全机制；最不适合照搬的是以 Shell 脚本和硬编码路径为主的通用清理实现。

## 2. Mole 当前技术构成

从仓库可见：

- 通用清理、卸载和优化核心主要使用 Bash；
- 磁盘分析和系统状态 TUI 使用 Go；
- Go TUI 使用 Bubble Tea/Lip Gloss；
- 测试包含 Bats、Go 单元测试和 fuzz test；
- CLI 开源，原生商业 Mac App 的源码不在该仓库；
- 仓库许可证是 GPL-3.0。

参考：

- [README：产品范围和 CLI/App 关系](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/README.md)
- [go.mod：Go 与 Bubble Tea 等依赖](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/go.mod)
- [Makefile：Go 组件构建方式](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/Makefile)
- [GPL-3.0 License](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/LICENSE)

## 3. 强烈建议借鉴的技术

### 3.1 所有写操作必须经过唯一安全出口

Mole 将 Shell 删除集中到 `safe_remove`/`safe_sudo_remove` 等封装，并通过 CI 检查直接 `rm -rf`。这类“删除汇聚点”值得 Crab 采用，但 Crab 应做得更彻底：Core 对外只暴露 `scan → plan → execute(plan)`，任何调用方都不能提交任意路径执行删除。

Crab 建议：

- Core 内部只存在一个 `TrashExecutor` 写入出口；
- CLI/App 不得直接调用 `FileManager.removeItem`、`rm` 或 AppleScript；
- CI 禁止 Core 之外出现删除、rename-to-trash 等危险 API；
- 执行器只接受签名/哈希固定的 `CleanPlan`，不接受路径列表；
- 每个动作都有规则 ID、原始文件身份、执行前复验和审计结果。

参考：[Mole Security Design：删除汇聚与 CI `# SAFE:` 契约](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/docs/SECURITY_DESIGN.md)

### 3.2 Fail Closed：不知道就跳过

Mole 对应用进程状态使用三态判断：运行、未运行、无法判断。无法判断不会被当成“安全”。Codex 相关测试还覆盖了 `pgrep` 缺失、检测失败、应用在扫描后突然启动等情况。

Crab 建议把所有安全证据统一建模为：

```text
verified-safe | verified-unsafe | unknown
```

以下任意状态为 `unknown` 都使计划项失效：

- 应用是否运行无法确认；
- 目标是否被打开无法确认；
- 应用版本无法确认；
- 路径或文件身份发生变化；
- 规则版本不匹配；
- 权限不足；
- 超时或系统 API 返回不完整结果。

参考：

- [AI 缓存测试：进程探测失败即跳过](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/tests/clean_ai_cli_caches.bats#L204-L277)
- [Mole Security Audit：live cache、lsof 与 fail-closed 说明](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/SECURITY_AUDIT.md)

### 3.3 只清理固定叶子，不清理整个应用目录

Mole 对 Codex Desktop 的处理非常值得参考：只处理经过测量和验证的 `Cache`/`Code Cache` 固定叶子，明确保留邻近的 `Local Storage` 和 `Application Support` 数据。它也明确让整个 `~/.codex` 默认保持不动，因为其中可能包含 session、credential、index 和本地 thread state。

这与 Crab 的单一定位完全一致。

Crab 规则应使用：

```text
应用根目录（只读识别）
  ├── 固定可再生叶子（允许进入 A 级候选）
  ├── 固定诊断叶子（允许进入 B 级候选）
  ├── 可下载资产（只读展示）
  ├── 用户状态（硬保护）
  └── 未知子目录（硬保护）
```

规则不得表达“清理此根目录下除排除项之外的所有内容”。只能表达“允许处理这些精确叶子”。

参考：

- [Codex CLI 状态默认全部保留](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/tests/clean_ai_cli_caches.bats#L60-L122)
- [Codex Desktop 只删除固定缓存叶子的测试](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/tests/clean_ai_cli_caches.bats#L124-L171)
- [Claude/Codex 状态保护说明](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/lib/clean/dev.sh#L5055-L5075)

### 3.4 在删除边界重新验证，而不是相信扫描结果

Mole 针对 Claude/Codex 的新版代码反复强调：测量大小、生成保留集合后，应用可能启动、更新器可能切换版本、旧目录可能变成活动目录。因此它在真正删除前重新规划和检查目标。

Crab 应将这一思路升级为正式的不可变计划：

```text
ScanSnapshot
    ↓
Candidate + Evidence
    ↓ 用户选择
CleanPlan(plan_id, rule_version, app_version, file_identity, expiry)
    ↓ 执行前逐项复验
TrashExecutor
```

每个目标至少固定：

- 卷 ID；
- device/inode 或 macOS 等价持久文件身份；
- 规范物理父路径；
- 文件类型；
- 规则 ID 与规则版本；
- 扫描时大小和修改时间；
- 应用版本及运行状态证据；
- 计划生成时间和过期时间。

只要有一项改变，目标变为 `stale-plan`，必须重新扫描，不能“尽力执行”。

参考：[旧 AI agent 版本清理：删除边界重新规划与保留活动版本](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/lib/clean/dev.sh#L3142-L3560)

### 3.5 符号链接和祖先链接必须专项防御

仅检查目标自身是不是 symlink 不够，任意祖先目录都可能被链接到用户文档或系统目录。Mole 同时测试了：

- `Library` 是 symlink；
- `Caches` 是 symlink；
- 应用缓存根是 symlink；
- profile 是 symlink；
- 最终 cache leaf 是 symlink。

Crab 建议：

- 扫描时用 `lstat`/`fstatat(..., AT_SYMLINK_NOFOLLOW)`；
- 逐级打开目录，禁止路径解析过程中跟随链接；
- 通过父目录 file descriptor + 相对叶子执行，不在最后重新解析完整字符串路径；
- Finder alias、APFS mount point、网络挂载和外部卷也作为边界处理；
- 测试规则目录的每个祖先都可被恶意替换为链接。

参考：

- [Codex 缓存祖先/根/profile/leaf 链接测试](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/tests/clean_ai_cli_caches.bats#L279-L360)
- [磁盘扫描器不跟随 symlink](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/cmd/analyze/scanner.go#L308-L340)

### 3.6 使用系统废纸篓，并保证不覆盖同名项目

Mole 的 Go 分析器在 macOS 15+ 优先调用绝对路径 `/usr/bin/trash`；旧系统回退到每卷废纸篓，并使用 `renameatx_np(RENAME_EXCL)` 防止同名覆盖；再无法处理时才回退 Finder。它还验证废纸篓目录不是 symlink、属于当前用户、没有其他用户写权限。

Crab 可以直接借鉴这个设计思想，但应自行实现：

1. 优先使用 macOS 官方可恢复删除能力；
2. 每次移动必须 no-overwrite；
3. 目标卷废纸篓不可验证时直接失败；
4. Finder/AppleScript 只能是兼容回退，并设置超时；
5. 移动失败不能退化为永久删除；
6. 历史记录保存原路径与废纸篓路径，恢复时同样 no-overwrite。

参考：[Mole 的多层废纸篓路由与 `RENAME_EXCL`](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/cmd/analyze/delete.go#L127-L275)

### 3.7 正确计算物理空间，处理硬链接和 APFS 语义

Mole 的 Go 扫描器以 `stat.Blocks * 512` 估算实际占用，并用 device/inode 对硬链接去重；扫描缓存还带 schema version，空间语义变化后拒绝复用旧缓存。

Crab 值得采用：

- 同时展示逻辑大小、物理占用和预计可释放空间；
- 对硬链接按 `(device, inode)` 去重；
- 不把 symlink 目标大小计入；
- 对 APFS clone、压缩文件、稀疏文件标记估算不确定性；
- 大小缓存包含 schema、规则版本和文件系统语义版本；
- 任何涉及硬链接去重的缓存必须考虑扫描顺序与失效问题。

参考：

- [硬链接去重与实际 block 大小](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/cmd/analyze/scanner.go#L1234-L1265)
- [扫描缓存 schema version](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/cmd/analyze/cache.go#L25-L35)

### 3.8 真实世界安全回归测试比 happy path 更重要

Mole 的 AI 缓存测试并非只测试“能删掉缓存”，还测试：

- 临近状态目录必须保留；
- 应用在测量后启动；
- 进程检测失败或工具缺失；
- 路径含 `|` 等特殊字符；
- 各层祖先 symlink；
- 活动版本在清理期间改变；
- 更新器和 open file 状态变化；
- dangerous path corpus 和 Go fuzz。

Crab 每条正式规则应强制提供以下测试夹具：

- positive fixture：只命中预期缓存；
- negative fixture：相邻用户状态全部保留；
- unknown-version fixture；
- every-ancestor-symlink fixture；
- target-replaced-after-plan fixture；
- app-started-after-plan fixture；
- permission/probe-timeout fixture；
- unusual-name fixture：空格、换行、控制字符、Unicode、`..`、前导 `-`；
- hardlink/clone fixture；
- interrupted-execution/recovery fixture。

参考：[危险路径 corpus 测试](https://github.com/tw93/Mole/blob/650ec4202343542e86b09c451a75bd6c171b5b6e/tests/path_validation_fuzz.bats)

## 4. 有条件借鉴的技术

### 4.1 并发扫描、Top-N 和渐进结果

Mole 用 Go 并发扫描、有限容量 channel、Top-N heap、取消 context 和磁盘缓存优化大盘扫描。Crab 不做全盘分析，所以无需复制整套复杂度。

Crab 可保留的部分：

- 按应用根并发，单应用内部受控串行或低并发；
- 最多 2–4 个 I/O worker；
- 支持取消和渐进展示；
- 大目录只维护聚合值和有限候选，避免内存随文件数无限增长；
- 第一次只扫已知根，不启动 Spotlight 全盘查询。

不需要：

- `/` 全盘视图；
- 通用 Top Files；
- 任意路径钻取和删除；
- Time Machine/外部卷总览；
- 通用 Spotlight 大文件搜索。

### 4.2 旧版本保留算法

Mole 对 Claude Code/Cursor Agent 等版本目录使用“保留活动版本 + 最近 N 个版本”，而不是只按 mtime 删除。这个思路适合 Crab 的“旧运行时/旧版本资产”类别，但应先作为 B/C 级手动项。

Crab 必须额外要求：

- 能证明当前活动版本；
- 能证明被删版本完整且非活动；
- 计划和执行时都重新检查；
- 至少保留活动版本和一个可回退版本；
- 不能证明时只展示占用，不给删除按钮。

### 4.3 本地操作日志和白名单

Mole 提供 dry-run、operation log 和用户 whitelist。Crab 也需要，但表达应升级：

- `ProtectedPaths`：用户永久保护的路径/规则项；
- `CleanPlan`：一次性不可变执行计划；
- `ExecutionReceipt`：逐项执行结果；
- `RulePin`：用户固定的规则版本；
- `LocalOnlyDiagnostics`：默认不上传的诊断信息。

简单的 whitelist 不能替代规则边界和文件身份复验。

## 5. 明确不要照搬的部分

### 5.1 不采用 Shell 作为 Crab 的安全核心

Mole 为兼容系统 Bash 3.2 做了大量复杂防御，但 Crab 是新项目，没有必要继承 Shell 在数组、路径、并发、类型、错误传播和 TOCTOU 方面的负担。

建议：

- Crab Core 使用 Swift Package 实现；
- CLI 也使用 Swift，并直接依赖同一个 `CrabCore`；
- App 使用 SwiftUI/AppKit，同样依赖 `CrabCore`；
- 需要原子文件操作时通过 Darwin API 封装 `openat`、`fstatat`、`renameatx_np`；
- 不通过 shell 拼接和执行路径。

备选是 Rust Core + SwiftUI，但对 Mac-only MVP 会增加 FFI、打包和调试成本。除非团队已有成熟 Rust 能力，否则 Swift 共享核心更简单。

### 5.2 不采用宽泛 glob 和“清理整个缓存根”

Mole 的通用清理中存在大量 `safe_clean path/*` 一类策略。这适合它的广域清理定位，但不适合 Crab 的“AI 数据零误判优先”目标。

Crab 规则只能命中：

- 精确叶子；或
- 有严格 `allowed_children`、结构 marker、版本边界和负向测试的有限集合。

未知新增子目录自动落入 Protected/Unknown，不能自动继承父目录的可清理资格。

### 5.3 不提供 root/sudo 清理

主流 AI 客户端和 CLI 的主要缓存都在用户空间。Crab MVP 不应为了少量系统级残留引入 root helper、Touch ID sudo 或系统目录清理能力。

收益：

- 大幅缩小攻击面；
- 避免系统完整性风险；
- 更容易沙箱化、签名和审计；
- 产品边界更容易向用户解释。

### 5.4 不提供永久删除和自动清空废纸篓

Mole 部分 clean 路径会直接永久删除。Crab 的安全承诺更强，MVP 只能移入废纸篓。任何失败都不能 fallback 到 `removeItem`。

### 5.5 不提供任意路径磁盘浏览和删除

Mole 的 `mo analyze` 是通用磁盘浏览器，可以选择任意文件移动到废纸篓。Crab 不应提供这个能力，否则产品会从“AI 文件安全管理”扩张成另一个磁盘工具，安全边界也随之失焦。

### 5.6 不以目录年龄作为唯一清理证据

旧文件不等于垃圾，尤其是聊天 checkpoint、模型、插件、历史日志和生成物。mtime 只能作为辅助证据，不能独立授予清理资格。

### 5.7 不直接复制 Mole 代码

Mole 使用 GPL-3.0。可以研究设计、行为和公开经验，但直接复制或改写其实现可能使 Crab 形成 GPL 派生作品。若 Crab 计划采用 MIT、Apache-2.0 或其他许可证，应采用 clean-room 式独立实现，并保留技术调研记录。

本节不是法律意见；正式发布前应由项目负责人或法律顾问确认许可证策略。

## 6. 推荐的 Crab 技术架构

```text
Crab.app (SwiftUI/AppKit) ─┐
                           ├── CrabCore (Swift Package, no UI, no network)
crab CLI (Swift ArgumentParser) ─┘ │
                                   ├── AppDetector
                                   ├── RuleEngine
                                   ├── SafeScanner
                                   ├── EvidenceEvaluator
                                   ├── PlanBuilder
                                   ├── TrashExecutor
                                   ├── RestoreEngine
                                   └── AuditStore

Signed declarative rule bundles
  ├── chatgpt
  ├── claude-desktop
  ├── cursor
  ├── codex
  ├── claude-code
  └── doubao
```

### 6.1 模块职责

| 模块 | 职责 | 关键限制 |
|---|---|---|
| `AppDetector` | 识别安装路径、bundle ID、版本、运行进程 | 识别失败返回 unknown |
| `RuleEngine` | 加载和验证声明式规则 | 规则不能执行代码或命令 |
| `SafeScanner` | 扫描固定规则根和叶子 | 不跟随 link，不全盘搜索 |
| `EvidenceEvaluator` | 汇总路径、结构、版本、运行态证据 | 所有授权条件必须 verified-safe |
| `PlanBuilder` | 生成不可变计划 | 固定文件身份、规则版本和期限 |
| `TrashExecutor` | 执行 no-overwrite 废纸篓移动 | 只接受 CleanPlan，不接受任意路径 |
| `RestoreEngine` | 从执行回执恢复 | 永不覆盖现有文件 |
| `AuditStore` | 保存本地扫描/执行记录 | 不存正文，默认不联网 |

### 6.2 规则不是“路径列表”，而是证据契约

建议规则结构：

```yaml
schema: 1
rule_id: ai.openai.codex.desktop.chromium-cache.v1
app:
  bundle_ids: ["verified.bundle.id"]
  versions: ">=x.y <z.0"
scope:
  root: "~/Library/Caches/VerifiedAppRoot"
  root_must_be_physical: true
candidates:
  - relative_path: "Default/Cache"
    type: directory
  - relative_path: "Default/Code Cache"
    type: directory
protected_siblings:
  - "Default/Local Storage"
  - "Default/IndexedDB"
requirements:
  app_stopped: true
  no_open_handles: true
  revalidate_at_execution: true
risk: A
action: trash
```

真实 bundle ID、路径和版本范围必须由数据地图与实机测试产生，不能从示例猜测。

## 7. 对 Crab 产品范围的进一步收敛

参考 Mole 后，建议把 Crab v1 的“一个问题”定义得更精确：

> Crab 只负责审计和安全处理已支持 AI 工具在用户空间产生的、具有明确所有权和再生语义的本地数据。

包含：

- Electron/Chromium 网络缓存、Code Cache、GPU Cache 等固定叶子；
- 已验证的诊断日志和崩溃报告；
- 已中断的安装/更新 staging；
- 能证明非活动的旧 CLI/agent 版本；
- 能证明不完整且非活动的临时运行时；
- 用户显式加入 Crab 管理目录的生成文件整理与手动移入废纸篓。

不包含：

- 通用系统缓存；
- 浏览器缓存；
- 编程语言包管理器缓存；
- 普通大文件和 Downloads 扫描；
- App 卸载与残留清理；
- 通用系统缓存删除、监控和健康分；Crab 的运行优化只执行单独审核的系统维护白名单。

### 7.1 Runtime Optimizer 补充调研（2026-09-04）

重新核对 Mole Optimizer 页面与仓库提交
`867270e93c42378b57f9706406845c7fd5a1fe91` 后确认：Mole 的内存部分使用
`sysctl vm.swapusage`、`memory_pressure` 和进程 RSS 做只读诊断；源码明确说明诊断
不会终止进程。Mole 的 Optimize 主体是按名称执行的 Finder、DNS、Spotlight、
LaunchServices 和数据库维护任务，而不是通过 `purge` 或强杀进程制造“已释放内存”。

2026-09-04 的后续产品决策将 Runtime Optimization 调整为面向整台 Mac 的主动维护
流程，而不是 AI 应用内存列表。Crab 仍不复制 Mole 的完整任务集，只采纳其“任务
目录、逐项结果、不确定时跳过”的结构。首版白名单仅包含 `qlmanage -r`、固定系统
路径下的 `lsregister -gc`，以及明确告知影响后的 Finder HUP 重启；不包含 DNS 全量
刷新、Spotlight 重建、数据库 vacuum、权限修复、启动项处理、系统服务批量终止或
任何文件删除。所有任务使用固定绝对路径和固定参数，不使用 shell、sudo、永久
helper、`kill -9` 或用户输入。参考来源：<https://mole.fit/zh/mac-optimizer>、
<https://github.com/tw93/mole/blob/867270e93c42378b57f9706406845c7fd5a1fe91/lib/optimize/catalog.sh>、
<https://github.com/tw93/mole/blob/867270e93c42378b57f9706406845c7fd5a1fe91/lib/optimize/tasks.sh>。
- 任意项目构建产物；
- 聊天、Memory、凭据、workspace state、项目源码和模型权重的自动清理。

## 8. 建议的首个纵向原型

不要从“支持六个应用”开始。先做一个只有两个规则的安全纵向切片：

1. 一个 Electron/Chromium 类 AI Desktop 的固定 `Cache`/`Code Cache` 叶子；
2. 一个 AI CLI 的明确中断 staging 目录。

原型必须打通：

- 应用/版本识别；
- 声明式规则；
- 只读扫描；
- 证据解释；
- 不可变计划；
- 执行前复验；
- 废纸篓 no-overwrite 移动；
- 执行回执与恢复；
- symlink/TOCTOU/fuzz 测试。

通过安全评审后，再为 ChatGPT、Claude、Cursor、Codex、Claude Code、豆包逐一建立数据地图。这样可以验证架构，而不会把未经验证的真实路径过早写死进产品。

## 9. 最终判断

Mole 证明了两个事实：

1. Mac 清理真正困难的不是找到目录，而是在应用更新、文件链接、进程竞争和文件系统差异下证明“此刻仍然可以安全处理”。
2. AI 工具目录尤其不能看名字行事：`cache` 目录中也可能有索引和状态，`.tmp` 中也可能有恢复数据，版本目录中也可能包含活动运行时。

因此，Crab 的护城河不应是更多路径，而应是：

- AI 工具数据地图；
- 声明式证据规则；
- 删除边界复验；
- 可解释计划；
- 可恢复执行；
- 每个应用持续维护的负向安全测试。

这会让 Crab 比通用清理器清得更少，但在目标问题上更专业、更可信。
