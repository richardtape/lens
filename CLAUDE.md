# Lens — Claude Code instructions

## Read before doing anything else

1. **[Agent orientation](docs/superpowers/2026-04-10-lens-agent-orientation.md)** — current project state, module layout, locked decisions, event bus pattern, agent/human split. Start here.
2. **[Product spec](docs/superpowers/specs/2026-04-09-lens-design.md)** — authoritative source of truth for all product decisions and data models.
3. **[Build phases](docs/superpowers/specs/2026-04-10-lens-build-phases.md)** — canonical implementation order (Phases 0–9). Your per-session phase plan names the current slice against this roadmap.
4. **[Code rules](docs/superpowers/2026-04-10-lens-code-rules-for-agents.md)** — style, comments, platform behaviour.

The build phases doc tells you **when** each capability lands; the product spec tells you **how** it should behave.

---

## End-of-phase requirement

Every phase plan must end with a step to update [`agent-orientation.md`](docs/superpowers/2026-04-10-lens-agent-orientation.md) to reflect what was built. At minimum, update the **Current state** section. Also update the **Module layout** if new directories were added, and the **Agent / human driver split** table if scheme names are now known.

The next agent will read this document cold. Leave it accurate.
