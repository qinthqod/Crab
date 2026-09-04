# Capability Map: Runtime Optimization

| Module id | Responsibility | Depends on |
|---|---|---|
| `runtime-diagnostics` | Collect a bounded, local snapshot of disk, memory pressure, swap, uptime, thermal state, sustained process load, and mounted disk images. | — |
| `smart-maintenance` | Run only the reviewed, non-destructive automatic refresh tasks after diagnosis and produce one receipt per attempted task. | `runtime-diagnostics` |
| `optional-system-refresh` | Let the user explicitly refresh Finder or Dock; never include either action in automatic execution. | `smart-maintenance` |
| `mounted-image-review` | Show mounted disk images and eject only the exact, freshly revalidated mount after a second confirmation. | `runtime-diagnostics` |

Build order: `runtime-diagnostics` → `smart-maintenance` → `optional-system-refresh`, `mounted-image-review`.
