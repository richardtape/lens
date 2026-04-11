# Lens Phase 1 — Hello World & Build Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the full human verification loop — clean build and successful launch on iOS Simulator, a physical iOS device, and macOS — and leave the codebase in a stable, committed state ready for Phase 2.

**Architecture:** The agent replaces Xcode's generic "Hello, world!" boilerplate with minimal, platform-labelled placeholder views so the human driver can confirm the correct target launched on each destination. Framework stubs (`LensCore`, `LensUI`) are cleaned up to be intention-revealing rather than auto-generated noise. No business logic is written; this phase is entirely about proving the toolchain.

**Tech Stack:** Swift 6, SwiftUI, Xcode 26.3. No third-party packages.

---

> **Note on TDD in Phase 1:** This phase has no logic to test — it is toolchain verification. The "tests" are manual: human builds and sees a labelled screen on each destination. `LensCoreTests` is set up as an empty test target here so Phase 2 can write its first tests immediately without extra scaffolding.

---

## Files created / modified

| File | Action | Responsibility |
|------|--------|----------------|
| `LensIOS/ContentView.swift` | **Modify** | iOS placeholder root view with platform label |
| `LensMac/ContentView.swift` | **Modify** | macOS placeholder root view with platform label and minimum window size |
| `LensCore/LensCore.swift` | **Modify** | Clean framework entry comment; removes Xcode generated struct |
| `LensUI/LensUI.swift` | **Modify** | Clean framework entry comment; removes Xcode generated struct |
| `LensCoreTests/LensCoreTests.swift` | **Modify** | Empty Swift Testing file; no test functions until Phase 2 |
| `docs/superpowers/2026-04-10-lens-agent-orientation.md` | **Modify** | Update Current state to reflect Phase 1 completion |

The App entry point files (`LensIOS/LensApp.swift`, `LensMac/LensMacApp.swift`) are left as Xcode generated them — `WindowGroup { ContentView() }` is correct for both targets.

---

## Task 1: Write the iOS placeholder view

**(Agent)**

**Files:**
- Modify: `LensIOS/ContentView.swift`

- [ ] **Step 1: Replace ContentView.swift for LensIOS**

Write the complete file at `/Users/rich/Developer/lens/LensIOS/ContentView.swift`:

```swift
import SwiftUI

// Phase 1 placeholder — replaced by the real Timeline view in Phase 3.
// The platform label lets the human driver confirm the correct target
// launched on each destination (Simulator, device, Mac).
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Lens")
                .font(.largeTitle.bold())
            Text("iOS · Build verification")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
```

---

## Task 2: Write the macOS placeholder view

**(Agent)**

**Files:**
- Modify: `LensMac/ContentView.swift`

- [ ] **Step 1: Replace ContentView.swift for LensMac**

Write the complete file at `/Users/rich/Developer/lens/LensMac/ContentView.swift`:

```swift
import SwiftUI

// Phase 1 placeholder — replaced by the real Timeline view in Phase 3.
// Sets a minimum window size so the macOS window isn't a tiny square.
// The platform label confirms the correct target launched on Mac.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Lens")
                .font(.largeTitle.bold())
            Text("macOS · Build verification")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        // Minimum size prevents the window collapsing to nothing on launch.
        .frame(minWidth: 400, minHeight: 280)
    }
}

#Preview {
    ContentView()
}
```

---

## Task 3: Clean up framework stubs

**(Agent)**

Xcode generates a struct with a `text` property inside framework stubs. That's confusing noise — replace with intention-revealing comments and a bare import.

**Files:**
- Modify: `LensCore/LensCore.swift`
- Modify: `LensUI/LensUI.swift`
- Modify: `LensCoreTests/LensCoreTests.swift`

- [ ] **Step 1: Replace LensCore.swift**

Write the complete file at `/Users/rich/Developer/lens/LensCore/LensCore.swift`:

```swift
// LensCore — shared framework; no SwiftUI imports permitted here.
//
// This file satisfies the framework build target.
// All substantive types live in subdirectories:
//   Models/      — SwiftData entities (Feed, FeedItem, Category, …)
//   Persistence/ — ModelContainer setup, App Group config
//   Feeds/       — Fetch pipeline, parsers, feed factory
//   Events/      — Event bus types and EventBus actor
//   Theme/       — ThemeEngine, CSS composition
//   Routing/     — DeepLinkRouter
//
// Populated starting in Phase 2.
import Foundation
```

- [ ] **Step 2: Replace LensUI.swift**

Write the complete file at `/Users/rich/Developer/lens/LensUI/LensUI.swift`:

```swift
// LensUI — shared SwiftUI framework.
//
// This file satisfies the framework build target.
// Shared views are added here (or in subdirectories) starting in Phase 3.
// Platform branches use #if os(macOS) / #if os(iOS).
import SwiftUI
```

- [ ] **Step 3: Replace LensCoreTests.swift**

Write the complete file at `/Users/rich/Developer/lens/LensCoreTests/LensCoreTests.swift`:

```swift
// LensCoreTests — unit tests for LensCore.
//
// Uses Swift Testing throughout: @Test functions, #expect() assertions.
// The first real tests are introduced in Phase 2 alongside the first
// real LensCore types. This file exists now so Phase 2 can start
// writing tests immediately without extra Xcode target setup.
import Testing
@testable import LensCore
```

> **Why `@testable import LensCore` with no tests yet?** It confirms that the test target links against LensCore correctly at build time. If the framework or its bundle ID is mis-configured, this import will fail — making Phase 1 a useful early wiring check.

---

## Task 4: Commit Phase 1 source files

**(Both)** — Agent stages, human commits.

- [ ] **Step 1: Stage the five modified files**

```bash
cd /Users/rich/Developer/lens
git add \
  LensIOS/ContentView.swift \
  LensMac/ContentView.swift \
  LensCore/LensCore.swift \
  LensUI/LensUI.swift \
  LensCoreTests/LensCoreTests.swift
git status
```

Expected: five files staged, nothing else. If you see unexpected files (e.g. `.DS_Store`, Xcode `xcuserdata/` entries), verify `.gitignore` is catching them. Do not stage `xcuserdata/` or `DerivedData/`.

- [ ] **Step 2: Commit**

```bash
git commit -m "feat(phase-1): placeholder views and cleaned framework stubs"
```

Expected: `[main …] feat(phase-1): placeholder views and cleaned framework stubs  5 files changed`

---

## Task 5: iOS Simulator — clean build + run

**(Human)**

This is the primary verification step. Follow exactly.

- [ ] **Step 1: Select scheme and destination**

In the Xcode toolbar (centre, scheme/destination picker):
- **Scheme:** `LensIOS`
- **Destination:** any iPhone Simulator — e.g. `iPhone 16 Pro`

- [ ] **Step 2: Clean the build folder**

**Product → Clean Build Folder** (⇧⌘K).

Wait for the spinner to stop. This clears any stale artefacts from the pre-Phase-1 state.

- [ ] **Step 3: Build**

Press **⌘B**.

Expected: build succeeds with zero errors. The status bar shows `Build Succeeded`.

> **If errors appear:** Do not guess at a fix. Copy the **full error text + file:line** from the Issue Navigator (⌘5) and paste it here. Common first-build issues:
> - *"Could not find module 'LensCore'"* → LensCore framework not linked to LensIOS target (Phase 0 Task 9 may be incomplete).
> - *"@testable import LensCore: module not found"* → LensCoreTests not linked; check the test target's "Target Dependencies" in Build Phases.
> - Signing errors → follow [build strategy §7.1](../specs/2026-04-10-lens-build-strategy.md) to configure your team and provisioning profile.

- [ ] **Step 4: Run on Simulator**

Press **⌘R**.

Expected: the iOS Simulator launches and displays:

```
[radio waves icon]
Lens
iOS · Build verification
```

- [ ] **Step 5: Run the LensCoreTests scheme**

Change the scheme to **LensCoreTests**, destination stays on an iPhone Simulator.

Press **⌘U** (Product → Test).

Expected: `Test Succeeded — 0 tests passed, 0 failed`. Zero tests is correct for Phase 1.

> **If the test scheme doesn't appear** in the scheme picker, go to **Product → Scheme → Manage Schemes…** and confirm `LensCoreTests` is listed and has its checkbox ticked.

---

## Task 6: Physical iOS device — build + run

**(Human)**

- [ ] **Step 1: Connect device**

Connect your iPhone via USB. Unlock it. Tap **Trust** on the device if prompted. In Xcode, select your device by name in the destination picker (it will appear below the Simulators list).

> **First time on this device?** Follow [build strategy §7.1](../specs/2026-04-10-lens-build-strategy.md) to enable automatic signing and trust the developer certificate on the device (**Settings → General → VPN & Device Management → Developer App → Trust**).

- [ ] **Step 2: Scheme and destination**

- **Scheme:** `LensIOS`
- **Destination:** your connected iPhone (e.g. `Rich's iPhone 16 Pro`)

- [ ] **Step 3: Build**

⌘B. Expected: `Build Succeeded`.

> **"Provisioning profile" error?** Your Apple ID's free provisioning only covers a limited set of bundle IDs and expires after 7 days. If you have a paid developer account, signing should be automatic. Paste any exact error text here.

- [ ] **Step 4: Run**

⌘R. The app installs and launches on the physical device.

Expected: the same placeholder screen as the Simulator:

```
[radio waves icon]
Lens
iOS · Build verification
```

---

## Task 7: macOS — clean build + run

**(Human)**

- [ ] **Step 1: Select scheme and destination**

- **Scheme:** `LensMac`
- **Destination:** `My Mac`

- [ ] **Step 2: Clean the build folder**

⇧⌘K.

- [ ] **Step 3: Build**

⌘B. Expected: `Build Succeeded` with zero errors.

> **Common macOS-specific issues:**
> - *"Could not find module 'LensCore' for target 'x86_64-apple-macos26.0'"* → LensCore's macOS destination was not enabled (Phase 0 Task 8). Fix: select LensCore target → General → Supported Destinations → add macOS.
> - *"Sandbox: LensMac denied …"* → App Sandbox entitlement may need to be enabled for macOS. Go to LensMac target → Signing & Capabilities → + Capability → App Sandbox. Accept defaults.

- [ ] **Step 4: Run**

⌘R. A macOS window opens (minimum 400 × 280 pt).

Expected:

```
[radio waves icon]
Lens
macOS · Build verification
```

---

## Task 8: Update agent-orientation.md

**(Agent)**

- [ ] **Step 1: Update the Current state section**

In `docs/superpowers/2026-04-10-lens-agent-orientation.md`, replace the Phase 0 Current state block with:

```markdown
## Current state

**Phase 1 complete.** All three destinations build and run cleanly:

| Destination | Scheme | Verified |
|-------------|--------|---------|
| iOS Simulator (iPhone 16 Pro) | LensIOS | ✓ |
| Physical iPhone | LensIOS | ✓ |
| macOS (My Mac) | LensMac | ✓ |

`LensCoreTests` builds and runs 0 tests (correct for Phase 1).

**Project structure:**

| Target | Type | Source folder | Deployment target |
|--------|------|---------------|-------------------|
| `LensIOS` | iOS App | `LensIOS/` | iOS 26.0 |
| `LensMac` | macOS App | `LensMac/` | macOS 26.0 |
| `LensCore` | iOS + macOS Framework | `LensCore/` | iOS 26.0 / macOS 26.0 |
| `LensUI` | iOS + macOS Framework | `LensUI/` | iOS 26.0 / macOS 26.0 |
| `LensCoreTests` | Unit Test (LensCore) | `LensCoreTests/` | iOS 26.0 |

`LensCore/` subdirectory scaffold: `Models/`, `Persistence/`, `Feeds/`, `Events/`, `Theme/`, `Routing/` — each with `.gitkeep`.

**App Group** `group.com.richardtape.lens` is documented; Xcode capability wired in Phase 2.

**Next:** Phase 2 — LensCore foundation (SwiftData, event bus, addon registry, minimal feed fetch).
```

---

## Task 9: Final commit

**(Human)**

- [ ] **Step 1: Stage and review**

```bash
cd /Users/rich/Developer/lens
git add docs/superpowers/2026-04-10-lens-agent-orientation.md
git status
```

Expected: one file staged. If Xcode wrote any `xcuserdata/` or `xcshareddata/` entries to the repo, verify they're gitignored before committing. If they're not caught:

```bash
echo "xcuserdata/" >> .gitignore
echo "*.xcuserstate" >> .gitignore
git rm -r --cached LensCore.xcodeproj/xcuserdata/ 2>/dev/null || true
```

Then `git add .gitignore` and stage again.

- [ ] **Step 2: Commit**

```bash
git commit -m "docs(phase-1): update agent orientation — Phase 1 verification complete"
```

---

## Phase 1 exit criteria

- [ ] `LensIOS` builds (⌘B) with zero errors on the Simulator.
- [ ] `LensIOS` runs (⌘R) on the Simulator and shows `iOS · Build verification`.
- [ ] `LensIOS` builds and runs on a **physical iPhone** and shows the same screen.
- [ ] `LensCoreTests` runs (⌘U) with `0 tests passed, 0 failed`.
- [ ] `LensMac` builds (⌘B) with zero errors targeting My Mac.
- [ ] `LensMac` runs (⌘R) on My Mac and shows `macOS · Build verification`.
- [ ] `agent-orientation.md` Current state reflects Phase 1 completion.
- [ ] `git log` shows three commits (baseline, phase-0, phase-1 code, phase-1 docs).

---

## What's next

**Phase 2** — Foundation, add-on shell, minimal ingestion:

- `LensCore` gets its first real types: SwiftData models (`Feed`, `FeedItem`, `Category`, `OfflineAsset`, `UserReadingPreferences`, `UserInterfacePreferences`), `ModelContainer` configured with the App Group URL, the event bus (`EventBus` actor + `LensEvent` enum), the addon registry, and minimal RSS/Atom parsing.
- Addons: remote zip download + `manifest.json` verification + macOS-only install path; one reference add-on hosted on your server.
- `ThemeEngine` and `DeepLinkRouter` scaffolded.
- Predefined categories seeded on first launch.
- Phase 2 is large — it will have its own detailed implementation plan with multiple tasks.
