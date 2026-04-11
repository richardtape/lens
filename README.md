# Lens

A native RSS/Atom/JSON Feed reader for iOS and macOS. Built with SwiftUI and SwiftData,
targeting iOS 26 and macOS 26.

## Opening the project

1. Open `Lens.xcodeproj` in **Xcode 26.3 or later**.
2. Select a scheme from the toolbar — **LensIOS** for iPhone/iPad, **LensMac** for Mac.
3. Choose a destination (Simulator or connected device).
4. Build with **⌘B**.

## Verification model

Building, running, and device testing are done by a **human driver in Xcode**.
Agents write and edit code; the human driver compiles and reports errors.

When an agent needs a build check it will ask:

> **In Xcode:** Select scheme `[name]`, destination `[Simulator / device]`, then ⌘B.
> Paste any errors here — full message + file:line.

## Project targets

| Target | Role |
|--------|------|
| **LensCore** | Framework — models, parsers, persistence, event bus, ThemeEngine, DeepLinkRouter. **No SwiftUI imports.** |
| **LensUI** | Framework — shared SwiftUI views with `#if os(macOS)` platform branches. |
| **LensIOS** | iOS app shell — entry point, scene lifecycle, tab bar. Thin; no business logic. |
| **LensMac** | macOS app shell — menus, windows, scene lifecycle. Thin; no business logic. |

## Key documents

| Document | Purpose |
|----------|---------|
| [`docs/superpowers/2026-04-10-lens-agent-orientation.md`](docs/superpowers/2026-04-10-lens-agent-orientation.md) | Project state, architecture decisions, agent/human split |
| [`docs/superpowers/specs/2026-04-09-lens-design.md`](docs/superpowers/specs/2026-04-09-lens-design.md) | Product spec — authoritative source of truth |
| [`docs/superpowers/specs/2026-04-10-lens-build-phases.md`](docs/superpowers/specs/2026-04-10-lens-build-phases.md) | Build roadmap — Phases 0–9 |
| [`docs/superpowers/specs/2026-04-10-lens-build-strategy.md`](docs/superpowers/specs/2026-04-10-lens-build-strategy.md) | Xcode workflow, signing, SPM — primarily for the human driver |

## App Group

SwiftData uses the shared App Group container **`group.com.richardtape.lens`** (wired in Phase 2).
All app targets and any future extensions (Share Extension, widgets) must belong to this group.
See [build strategy §7.2](docs/superpowers/specs/2026-04-10-lens-build-strategy.md) for setup steps.

## Minimum deployment

| Platform | Version |
|----------|---------|
| iOS | 26.0 |
| macOS | 26.0 |
