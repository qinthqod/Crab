# Spec: Crab Safe Scan Foundation

## Objective

Build the first production-quality vertical slice of Crab: load and validate exact-leaf AI cache rules, scan only file metadata without following symbolic links, classify candidates, generate an immutable short-lived plan from explicit selections, and expose the result through a local CLI. This slice proves that Crab can identify safe candidates without reading file contents or mutating the filesystem.

Target users are Mac users with several AI tools and developers validating Crab rules. Success means the same `CrabCore` behavior is available to later CLI and SwiftUI consumers, with fail-closed results for every uncertain boundary.

## Assumptions

1. MVP deployment target is macOS 14 or newer on Apple Silicon; Intel remains source-compatible but is not a release gate yet.
2. Swift 6 and Swift Package Manager are the authoritative build system.
3. The first rule format is strict JSON using `Codable`; YAML and remote rule downloads are out of scope until a dependency and signing review.
4. The first slice operates only on test fixtures and user-supplied rule files. No unverified real AI application path ships as a stable cleaning rule.
5. No file-moving or deletion API is implemented in this slice.

## Native application

- The macOS application loads reviewed exact-leaf rules and scans the current user's real `~/Library/Caches` metadata.
- Missing optional tools are skipped; uncertain, linked, or unreadable targets fail closed and never appear as eligible.
- Results begin unselected. Recommended selection requires an explicit user action and excludes running applications.
- The user-facing action is “Move to Trash.” An immutable plan is an internal execution detail only.
- Immediately before any move, every selected target is rescanned and its rule, identity, action, and expiry are revalidated.
- The owning application is checked again immediately before the Trash boundary; launching during review invalidates the action.
- Every target must pass revalidation before the first move occurs. Permanent deletion is not implemented.

## Tech Stack

- Swift 6.3 language mode
- Foundation and Darwin system APIs only
- Dependency-free executable test harness in `Sources/CrabCoreTests` because the installed Command Line Tools toolchain does not ship `XCTest` or `Testing`
- macOS 14 minimum deployment target
- JSON schema version `1` for rule, scan report, and plan serialization

## Commands

```bash
swift build
swift run crab-core-tests
swift run crab scan --rules Fixtures/Rules --home /path/to/test-home
swift run crab plan --rules Fixtures/Rules --home /path/to/test-home --output crab-plan.json
swift run crab rules validate Fixtures/Rules/example.json
```

## Project Structure

```text
Package.swift                 Swift package manifest
Sources/CrabCore/             Shared models, rule validation, scanner, plan builder
Sources/crab/                 Dependency-free CLI executable
Sources/CrabCoreTests/        Unit and filesystem boundary test harness
Fixtures/Rules/               Non-production example rule fixtures
tasks/                        Implementation plan and durable task list
docs/security/                Threat model and security decisions
prototype/                    Existing web interaction prototype; not production code
```

## Code Style

Use value types, explicit dependencies, typed errors, and safe defaults. Paths are accepted only through validated rules; public write APIs must never accept arbitrary paths.

```swift
public struct ScanCandidate: Codable, Equatable, Sendable {
    public let ruleID: RuleID
    public let path: URL
    public let logicalBytes: UInt64
    public let physicalBytes: UInt64
    public let safety: SafetyVerdict
}
```

- Types: `UpperCamelCase`; members and functions: `lowerCamelCase`.
- Prefer `struct`, `enum`, immutable `let`, and `Sendable` models.
- Errors must explain which invariant failed without leaking file contents.
- Production code never uses `try?` at a safety boundary.

## Testing Strategy

- Unit tests for schema validation, risk/action constraints, exact-leaf rules, plan expiry, and explicit selection.
- Filesystem integration tests use a unique temporary directory and real files.
- Abuse cases are first-class tests: target symlink, ancestor symlink, path escape, missing target, unknown schema, and target replacement after scan.
- Tests assert outcomes and safety verdicts, not internal call order.
- Full gate: `swift run crab-core-tests` followed by `swift build`. Migrating the same cases to Swift Testing is planned when a full Xcode toolchain is available.

## Threat Model

| Boundary | Asset | Abuse case | Required control |
|---|---|---|---|
| Rule JSON → Core | User files outside cache leaves | Malicious `..`, absolute escape, broad root, unsupported action | Strict schema, relative leaf validation, exact application root, trash-only action |
| Filesystem → Scanner | User content and identity state | Target or any ancestor is a symlink | `lstat` every component, fail closed, never follow links |
| Scan result → Plan | Files changed after review | Target replaced after scan | Bind device/inode/type/size/mtime and expire plans |
| Rule name/path → Eligibility | A path named Cache contains chats, models, clipboard history, or credentials | Name-based false positive | Reject protected path markers and require reviewed category/risk/owner evidence |
| Running app → Trash | App relaunches after confirmation and writes into its cache | Race with owner process | Recheck owner stopped state immediately before each move |
| CLI arguments → Core | Arbitrary local paths | CLI attempts to clean a user-provided path | CLI accepts rule files and plan files only; no arbitrary clean path |
| Diagnostics → stdout/files | User identity in paths | Full home path leaks by default | Redacted paths by default; explicit opt-in planned later |

## Boundaries

### Always do

- Treat rules, paths, directory entries, and CLI input as untrusted.
- Treat size, age, and names such as `Cache`, `tmp`, `Temp`, `.db`, and `.sqlite` as non-evidence.
- Resolve all paths under an injected home directory and validate each path component.
- Use metadata only; never open candidate files for content reads.
- Fail closed on unsupported schema, symbolic links, permissions, or identity uncertainty.
- Generate a new plan ID whenever the selection changes.
- Run focused tests after every behavior change and the full suite before handoff.

### Ask first

- Add third-party dependencies or remote networking.
- Add entitlements, Full Disk Access guidance, helper tools, or elevated privileges.
- Add any real-world stable rule before its data map and negative fixtures exist.
- Add a file-moving implementation or system Trash integration.

### Never do

- Call `FileManager.removeItem`, `rm`, permanent deletion, or recursive deletion.
- Follow symbolic links while scanning or planning.
- Accept a user-provided arbitrary path as a clean target.
- Read chat, project, prompt, generated-file, credential, or database contents.
- Admit sessions, file history, local model stores, cloud-sync trees, containers, group containers, or shared vendor parents into a clean plan.
- Default-select a candidate.

## Success Criteria

- A valid exact-leaf rule can scan a fixture and report logical/physical bytes using metadata only.
- Invalid schema, path traversal, absolute leaves, non-trash action, target symlink, and ancestor symlink all fail closed.
- Hard-linked files are not double-counted within one candidate.
- A plan contains only explicitly selected `verifiedSafe` candidates and binds their identities.
- Empty selection produces an empty plan; no API defaults to selecting candidates.
- CLI can validate rules, scan, and write a JSON plan without mutating fixture files.
- `swift run crab-core-tests` and `swift build` pass with no third-party packages.

## Open Questions

- Which two real applications will become the first Stable rules after data-map research?
- Should the production App target macOS 13 as well as macOS 14?
- Which open-source license will be selected before the first public commit?
