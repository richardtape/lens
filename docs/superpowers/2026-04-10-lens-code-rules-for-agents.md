# Lens — Code rules (for coding agents)

**Status:** Active  
**Last updated:** 2026-04-10  
**Read first:** [`lens-agent-orientation.md`](./2026-04-10-lens-agent-orientation.md) — module layout, locked decisions, event bus pattern, agent/human split, and verification protocol all live there.

---

## 1. Audience note

The repo owner is an experienced engineer **learning SwiftUI**. Comments and structure should support that learning: explain non-obvious SwiftUI/HIG choices, concurrency boundaries, and Apple-specific idioms — but don't narrate the obvious.

---

## 2. Scope of edits

- Change **only** what the task requires. No drive-by refactors or unrelated formatting sweeps.
- Preserve existing **comments** unless they are wrong or the behaviour they describe has moved.
- Prefer **small, reviewable** diffs over large rewrites.

---

## 3. Swift style

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) naming.
- Use `enum` for finite states, `struct` for value types, protocols where abstraction genuinely pays off — don't over-engineer.
- Avoid adding error handling, fallbacks, or validation for scenarios the spec doesn't describe. Trust internal invariants; validate only at real boundaries (user input, network responses).
- Avoid huge monolith files. Abstract code into helper/utility files where possible; prefer files which server a single purpose.

---

## 4. Comments

- **Do comment:** non-obvious *why*, HIG / platform choices, concurrency boundaries (`// runs off main actor`), invariants, Swift quirks that trip up beginners.
- **Don't comment:** the obvious.
- Use `// MARK: -` to section larger files.
- `///` DocC comments on all `public` APIs in `LensCore` — other targets and future extensions consume these.
- When adding a non-trivial SwiftUI view, a 2–4 line header explaining layout intent is welcome if it saves reverse-engineering the hierarchy.

---

## 5. UI & platform behaviour

- Respect platform HIG: `NavigationSplitView` on iPad/Mac, tab bar on iPhone, menus and keyboard shortcuts on macOS — per the product spec.
- Support Dynamic Type and reasonable VoiceOver labels on all interactive controls. Match patterns already present in the file or module.

---

## 6. Documentation files

- Do **not** create new documentation files unless the phase plan explicitly asks for them.
- Update existing docs when team conventions change, with the maintainer's agreement.

---

## 7. Security & privacy

- Treat all feed HTML as untrusted: sanitise before rendering; enforce `WKWebView` sandboxed navigation (per product spec §2.4 and §8).
- No hidden telemetry. Any network or analytics behaviour must be explicit and spec-aligned.
