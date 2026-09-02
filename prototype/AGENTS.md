# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.

## Durable Crab design decisions

- Keep the main window understandable in under three seconds: one storage number, one safety sentence, and one primary action. Do not add dashboards, sidebars, charts, storage bars, technical paths, rule IDs, risk badges, or permanent-delete controls.
- Use the generated Protective Orbit logo at `public/assets/crab-protective-orbit.png`; do not redraw or approximate it with CSS, SVG, emoji, or text glyphs.
- Preserve the compact menu-bar-style quick panel as a secondary surface opened from the centered Crab brand. It shares the same result and routes into the same review flow without adding visible complexity to the main screen.
- Safety is part of the interaction model: every candidate starts unchecked, only regenerable caches appear, confirmation names the protected content, and every simulated clean moves items to Trash with an undo path and receipt.
- Visual language: macOS system fonts, misted off-white/lavender surfaces, coral `#F36B55` reserved for the Protective Orbit logo, ocean purple `#6558D3` for actions, deeper purple for confirmation, softer violet for verified safety, Phosphor icons, and critically damped interruptible motion with reduced-motion/transparency/contrast support.
