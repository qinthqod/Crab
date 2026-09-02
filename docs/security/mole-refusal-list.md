# Mole refusal-list rules adopted by Crab

Source: [Mac 清理工具永远不该删什么](https://mole.fit/zh/blog/what-mac-cleaners-should-never-delete), published 2026-07-30 and updated 2026-08-22.

## Data classes

| Class | Crab behavior |
|---|---|
| Regenerable cache | May become a candidate only with an exact reviewed rule, known owner, stopped owner, risk A, execution-time revalidation, and Trash-only action. |
| Expensive to rebuild | Not part of automatic cleanup. The owning application's manager is preferred. |
| Irreplaceable user content | Never enters cache results, `CleanPlan`, or `CleanupExecutor`. |

Size, age, and names such as `Cache`, `tmp`, `Temp`, `.db`, and `.sqlite` are not safety evidence.

## Hard refusal categories

- AI chats, `sessions`, `file-history`, agent project trees, and conversation databases.
- Photos, Mail, Messages, Notes, Voice Memos, documents, Desktop, and project roots.
- iCloud `Mobile Documents`, `~/Library/CloudStorage`, and other sync trees.
- Keychains, browser login stores, tokens, TCC, profiles, MDM, and security-agent state.
- `Application Support`, `Containers`, `Group Containers`, shared vendor parents, and unknown-owner paths.
- Local model repositories for Ollama, LM Studio, Hugging Face, Jan, and similar tools.
- Install/update staging, active package-manager stores, and caches whose owning app is running.

The cache rule validator rejects protected path markers even below `Library/Caches`. Archive suggestions are read-only and structurally cannot become clean-plan entries.

## Execution gates

1. Refused categories never appear in cleanup results.
2. Every cache result starts unselected.
3. Plan creation checks exact rule, category, risk, and identity.
4. Execution rechecks rule, identity, symlink ancestry, and owner stopped state immediately before Trash movement.
5. Ordinary cleanup uses Trash only.
6. Receipts distinguish moved, skipped, and failed bytes. Missing paths never count as reclaimed.
7. Uncertainty fails closed: omission is acceptable; deleting unknown data is not.

## Effect on archive suggestions

The 180-day signal is useful for prioritization, not automatic deletion. Crab may label automatically associated local projects, reveal them in Finder, and move only an explicitly selected, revalidated project to Trash after a second confirmation. It will not permanently delete a project or accept an arbitrary user-entered cleanup path.
