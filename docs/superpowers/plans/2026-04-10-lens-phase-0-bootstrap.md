# Lens Phase 0 — Project Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a git baseline, create the Xcode multi-target project structure (LensCore, LensUI, LensIOS, LensMac), scaffold the LensCore source tree, write the README, and document the App Group setup — leaving the repo in a clean, committed state ready for Phase 1.

**Architecture:** A single `Lens.xcodeproj` with four targets. `LensCore` and `LensUI` are dynamic framework targets configured to support both iOS and macOS. `LensIOS` and `LensMac` are thin app shell targets that embed those frameworks. No logic is written in Phase 0 — only project structure, placeholder files, and documentation.

**Tech Stack:** Swift 6, SwiftUI, Xcode 26.3, no third-party packages.

---

## Phase 0 — Driver legend

Tasks below are tagged:

- **(Agent)** — the coding agent writes files; no Xcode interaction needed.
- **(Human)** — requires Xcode GUI or Finder; the agent gives you exact steps.
- **(Both)** — agent produces content, human runs a command.

---

## File structure

```
/Users/rich/Developer/lens/          ← repo root
├── .gitignore                        (Agent — Task 1)
├── README.md                         (Agent — Task 1)
├── Lens.xcodeproj/                   (Human creates — Task 3)
│   └── …Xcode internals…
├── Lens/                             ← initial iOS source folder; renamed to LensIOS/ in Task 4
│   ├── LensApp.swift                 (Xcode generates)
│   ├── ContentView.swift             (Xcode generates)
│   └── Assets.xcassets/             (Xcode generates)
├── LensIOS/                          ← after rename in Task 4
│   └── …same files…
├── LensMac/                          (Xcode generates — Task 5)
│   ├── LensMacApp.swift
│   └── ContentView.swift
├── LensCore/                         (Xcode generates — Task 6)
│   ├── LensCore.swift                (Xcode generates; keep as-is)
│   ├── Models/                       (Agent — Task 10)
│   │   └── .gitkeep
│   ├── Persistence/                  (Agent — Task 10)
│   │   └── .gitkeep
│   ├── Feeds/                        (Agent — Task 10)
│   │   └── .gitkeep
│   ├── Events/                       (Agent — Task 10)
│   │   └── .gitkeep
│   ├── Theme/                        (Agent — Task 10)
│   │   └── .gitkeep
│   └── Routing/                      (Agent — Task 10)
│       └── .gitkeep
├── LensCoreTests/                    (Xcode generates — Task 6)
│   └── LensCoreTests.swift           (Xcode generates; keep as-is)
└── LensUI/                           (Xcode generates — Task 7)
    └── LensUI.swift                  (Xcode generates; keep as-is)
```

---

## Task 1: Write .gitignore and README.md

**(Agent)**

- [ ] **Step 1: Write `.gitignore`**

Create `/Users/rich/Developer/lens/.gitignore`:

```gitignore
# Xcode user state — never commit
xcuserdata/
*.pbxuser
!default.pbxuser
*.mode1v3
!default.mode1v3
*.mode2v3
!default.mode2v3
*.perspectivev3
!default.perspectivev3
*.xccheckout
*.xcscmblueprint

# Build artefacts
DerivedData/
build/
*.ipa
*.dSYM.zip
*.dSYM

# Swift Package Manager — commit Package.resolved (locks dependency versions)
.build/
.swiftpm/xcode/xcuserdata/

# macOS noise
.DS_Store
.AppleDouble
.LSOverride
._*
.Spotlight-V100
.Trashes
.fseventsd
.VolumeIcon.icns
.com.apple.timemachine.donotpresent
```

- [ ] **Step 2: Write `README.md`**

Create `/Users/rich/Developer/lens/README.md`:

```markdown
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
```

---

## Task 2: Initialize git and commit baseline

**(Both)** — Agent has written the files; human runs the commands.

- [ ] **Step 1: Initialize git**

```bash
cd /Users/rich/Developer/lens
git init
```

Expected output: `Initialized empty Git repository in /Users/rich/Developer/lens/.git/`

- [ ] **Step 2: Stage and commit**

```bash
git add .gitignore README.md
git commit -m "chore: project baseline — gitignore and README"
```

Expected output: `[main (root-commit) …] chore: project baseline — gitignore and README`

---

## Task 3: Create Xcode project

**(Human)** — All steps are Xcode GUI.

- [ ] **Step 1: Open Xcode and start a new project**

Launch Xcode 26.3. Choose **File → New → Project…** (⇧⌘N).

- [ ] **Step 2: Pick the template**

- Platform tab: **iOS**
- Template: **App**
- Click **Next**

- [ ] **Step 3: Fill in project options**

| Field | Value |
|-------|-------|
| Product Name | `Lens` |
| Team | Your Apple developer team |
| Organization Identifier | `com.richardtape` |
| Bundle Identifier | `com.richardtape.lens` *(auto-filled)* |
| Interface | **SwiftUI** |
| Language | **Swift** |
| Storage | **None** *(SwiftData added in Phase 2)* |

Leave "Include Tests" **unchecked** — a test target for LensCore will be added in Task 6.

Click **Next**.

- [ ] **Step 4: Save into the repo**

In the save dialog:
- Navigate to `/Users/rich/Developer/lens`
- **Do not** create a new subfolder — save directly into the `lens/` directory.
- Source Control: **uncheck** "Create Git repository on my Mac" (we already have one).
- Click **Create**.

Xcode creates `Lens.xcodeproj` and a `Lens/` source folder at the repo root.

- [ ] **Step 5: Verify**

In the Xcode Project Navigator (left panel), you should see:

```
▶ Lens (project)
  ▶ Lens (target — iOS app)
  ▶ Lens.xcodeproj
  ▶ Products
```

---

## Task 4: Rename the iOS target and source folder to "LensIOS"

**(Human)** — Three sub-steps: rename the target, rename the Xcode group, fix disk paths.

- [ ] **Step 1: Rename the target**

In the Project Navigator, under **TARGETS**, **double-click** the target named `Lens`.
Type `LensIOS` and press **Return**.

Xcode shows a dialog: *"Rename associated scheme?"* — click **Rename**.

- [ ] **Step 2: Rename the source folder group in Xcode**

In the Project Navigator, find the **yellow folder group** named `Lens` (this represents the source folder on disk).

**Double-click** the group name → type `LensIOS` → press **Return**.

> **Note:** In Xcode 26, renaming a physical-folder group also renames the directory on disk automatically. After pressing Return, switch to Finder and confirm that `Lens/` has become `LensIOS/` at the repo root. If the files appear red (broken references) in Xcode, see the recovery step below.

- [ ] **Step 3 (if needed): Fix broken file references**

If source files appear in red after the group rename (meaning Xcode didn't move files on disk):

1. In Finder, manually rename `/Users/rich/Developer/lens/Lens/` → `LensIOS/`.
2. Back in Xcode, select each red file in the navigator.
3. In the **File Inspector** (right panel, first tab), click the folder icon next to the file path and navigate to the file's new location in `LensIOS/`.

Repeat until all files resolve (no red icons).

- [ ] **Step 4: Verify**

The Project Navigator should show:

```
▶ LensIOS (group — yellow folder)
    LensApp.swift
    ContentView.swift
    Assets.xcassets
```

The scheme menu (toolbar, centre) should read **LensIOS**.

---

## Task 5: Add the LensMac macOS app target

**(Human)**

- [ ] **Step 1: Add a new target**

**File → New → Target…**

- Platform: **macOS**
- Template: **App**
- Click **Next**

- [ ] **Step 2: Fill in options**

| Field | Value |
|-------|-------|
| Product Name | `LensMac` |
| Team | Same as LensIOS |
| Organization Identifier | `com.richardtape` |
| Bundle Identifier | `com.richardtape.lens.mac` |
| Interface | **SwiftUI** |
| Language | **Swift** |

Leave "Include Tests" **unchecked**.

Click **Finish**.

Xcode creates a `LensMac/` source folder with `LensMacApp.swift` and `ContentView.swift`.

- [ ] **Step 3: Verify**

Under **TARGETS** in Project Settings you should see: `LensIOS`, `LensMac`.

---

## Task 6: Add the LensCore framework target (with unit tests)

**(Human)**

- [ ] **Step 1: Add a new target**

**File → New → Target…**

- Platform: **iOS**
- Template: **Framework**
- Click **Next**

- [ ] **Step 2: Fill in options**

| Field | Value |
|-------|-------|
| Product Name | `LensCore` |
| Team | Same as app targets |
| Organization Identifier | `com.richardtape` |
| Bundle Identifier | `com.richardtape.lens.core` |
| Language | **Swift** |
| Include Tests | **Check this box** |

Click **Finish**.

Xcode creates a `LensCore/` source folder (with `LensCore.swift`) and a `LensCoreTests/` folder.

- [ ] **Step 3: Verify**

Under **TARGETS**: `LensIOS`, `LensMac`, `LensCore`, `LensCoreTests`.

---

## Task 7: Add the LensUI framework target

**(Human)**

- [ ] **Step 1: Add a new target**

**File → New → Target…**

- Platform: **iOS**
- Template: **Framework**
- Click **Next**

- [ ] **Step 2: Fill in options**

| Field | Value |
|-------|-------|
| Product Name | `LensUI` |
| Team | Same as other targets |
| Organization Identifier | `com.richardtape` |
| Bundle Identifier | `com.richardtape.lens.ui` |
| Language | **Swift** |
| Include Tests | **Unchecked** |

Click **Finish**.

Xcode creates a `LensUI/` source folder with `LensUI.swift`.

- [ ] **Step 3: Verify**

Under **TARGETS**: `LensIOS`, `LensMac`, `LensCore`, `LensCoreTests`, `LensUI`.

---

## Task 8: Enable macOS support for LensCore and LensUI

**(Human)**

Framework targets default to iOS-only. Both LensCore and LensUI must also support macOS so they can be linked into LensMac.

> **Why this matters:** LensCore has no SwiftUI — it's pure Swift. LensUI has SwiftUI but branches by platform with `#if os(macOS)`. Both must compile on macOS for LensMac to link against them.

- [ ] **Step 1: Add macOS destination to LensCore**

1. Select the **LensCore** target in the project editor.
2. Click the **General** tab.
3. Scroll to **Supported Destinations**.
4. Click the **+** button (bottom of the list).
5. Select **macOS** → Click **Add**.

- [ ] **Step 2: Add macOS destination to LensUI**

Repeat the same steps for the **LensUI** target.

- [ ] **Step 3: Verify**

Select LensCore → General → Supported Destinations should list: **iPhone**, **iPad**, **macOS** (or similar). Same for LensUI.

---

## Task 9: Link LensCore and LensUI into app targets, then set deployment targets

**(Human)** — Two sub-steps.

### Part A: Link frameworks

- [ ] **Step 1: Add frameworks to LensIOS**

1. Select the **LensIOS** target → **General** tab.
2. Scroll to **Frameworks, Libraries, and Embedded Content**.
3. Click **+**.
4. In the sheet, under the project heading, select **LensCore.framework** → **Add**.
5. Click **+** again → select **LensUI.framework** → **Add**.
6. Confirm both appear with **Embed & Sign**.

- [ ] **Step 2: Add frameworks to LensMac**

1. Select the **LensMac** target → **General** tab.
2. Click **+** in Frameworks, Libraries, and Embedded Content.
3. Add **LensCore.framework** → set to **Embed & Sign**.
4. Add **LensUI.framework** → set to **Embed & Sign**.

### Part B: Set deployment targets

- [ ] **Step 3: Set iOS targets to iOS 26**

For each of **LensIOS**, **LensCore**, **LensCoreTests**, **LensUI**:

1. Select the target → **General** tab → **Minimum Deployments**.
2. Set **iOS** to **26.0**.

- [ ] **Step 4: Set LensMac to macOS 26**

Select **LensMac** → **General** → **Minimum Deployments** → **macOS 26.0**.

> **Note:** LensCore and LensUI now support both iOS and macOS. In their target settings, set both the iOS minimum (26.0) and macOS minimum (26.0) fields.

---

## Task 10: Scaffold the LensCore subdirectory structure

**(Agent)**

Git does not track empty directories. The agent creates each subdirectory with a `.gitkeep` file so the structure is committed now and ready for Phase 2 Swift files.

- [ ] **Step 1: Create the subdirectories**

```bash
mkdir -p \
  /Users/rich/Developer/lens/LensCore/Models \
  /Users/rich/Developer/lens/LensCore/Persistence \
  /Users/rich/Developer/lens/LensCore/Feeds \
  /Users/rich/Developer/lens/LensCore/Events \
  /Users/rich/Developer/lens/LensCore/Theme \
  /Users/rich/Developer/lens/LensCore/Routing
```

- [ ] **Step 2: Add `.gitkeep` files**

```bash
touch \
  /Users/rich/Developer/lens/LensCore/Models/.gitkeep \
  /Users/rich/Developer/lens/LensCore/Persistence/.gitkeep \
  /Users/rich/Developer/lens/LensCore/Feeds/.gitkeep \
  /Users/rich/Developer/lens/LensCore/Events/.gitkeep \
  /Users/rich/Developer/lens/LensCore/Theme/.gitkeep \
  /Users/rich/Developer/lens/LensCore/Routing/.gitkeep
```

- [ ] **Step 3: Add the subdirectory groups to Xcode**

In Xcode, the new folders won't appear automatically. Add them:

1. In the Project Navigator, right-click the **LensCore** group (yellow folder).
2. Choose **Add Files to "Lens"…** (or drag the folders into the group from Finder).
3. Select the six new subdirectory folders (`Models`, `Persistence`, `Feeds`, `Events`, `Theme`, `Routing`).
4. In the dialog: **Create groups** (not folder references), uncheck "Copy items if needed" (they're already in place).
5. Click **Add**.

Each subfolder should now appear as a yellow group inside the LensCore group in the navigator.

---

## Task 11: Update agent-orientation.md

**(Agent)**

The next agent reads this document cold. Update it to reflect what was built.

- [ ] **Step 1: Update the `Current state` section**

Replace the existing "Current state" section with:

```markdown
## Current state

**Phase 0 complete.** `Lens.xcodeproj` exists at the repo root with four targets:

| Target | Type | Source folder |
|--------|------|---------------|
| `LensIOS` | iOS App | `LensIOS/` |
| `LensMac` | macOS App | `LensMac/` |
| `LensCore` | iOS + macOS Framework | `LensCore/` |
| `LensUI` | iOS + macOS Framework | `LensUI/` |

A `LensCoreTests` unit test target also exists (source: `LensCoreTests/`).

`LensCore/` has six scaffolded subdirectories (`Models/`, `Persistence/`, `Feeds/`, `Events/`, `Theme/`, `Routing/`) each with a `.gitkeep` placeholder. These are on disk but not yet added as groups in Xcode — add them when Phase 2 populates them with Swift files.

**App Group** `group.com.richardtape.lens` is documented in README and build-strategy §7.2. The Xcode capability is **not yet enabled** — this is wired in Phase 2 when the ModelContainer is created.

Phase 1 (hello-world build verification on iOS Simulator, physical device, and macOS) has not been run.
```

- [ ] **Step 2: Update the `Agent / human driver split` table**

Fill in the scheme names column:

```markdown
| You (agent) | Human driver (Xcode) |
|-------------|----------------------|
| Write and edit Swift, SwiftUI, SPM manifests, project file entries, documentation | Build (⌘B), Run (⌘R), manage signing, test on device/simulator |
| Cannot invoke the compiler or run the app | Owns all verification against a running build |

**Schemes:** `LensIOS` (iOS Simulator + device), `LensMac` (My Mac).

**When you need a build check:**
> **In Xcode:** Select scheme `LensIOS`, destination `iPhone 16 Pro Simulator` (or similar), then ⌘B. Paste any errors here (full message + file:line). For Mac: scheme `LensMac`, destination `My Mac`.
```

- [ ] **Step 3: Update the `Module layout` section**

Confirm the existing layout matches reality. Add `LensCoreTests/`:

```markdown
## Module layout

The project uses a multi-target structure. All new code goes in the **lowest** layer that can own it.

```
Lens.xcodeproj
├── LensCore/               # iOS + macOS framework target
│   ├── LensCore.swift      # Xcode stub — do not delete
│   ├── Models/             # SwiftData entities (Feed, FeedItem, Category, …)
│   ├── Persistence/        # ModelContainer setup, App Group config
│   ├── Feeds/              # Fetch pipeline, parsers, feed factory
│   ├── Events/             # Event bus types and EventBus actor
│   ├── Theme/              # ThemeEngine, CSS composition
│   └── Routing/            # DeepLinkRouter
├── LensCoreTests/          # Unit tests for LensCore (populated from Phase 2)
├── LensUI/                 # iOS + macOS framework; shared SwiftUI views
├── LensIOS/                # iOS app entry, scene lifecycle, tab bar
└── LensMac/                # macOS app entry, menus, window management
```

Rule: `LensCore` has no SwiftUI imports. `LensIOS`/`LensMac` are thin shells — scenes, app lifecycle, platform-specific wiring only.
```

---

## Task 12: Final commit

**(Human)**

- [ ] **Step 1: Stage everything**

```bash
cd /Users/rich/Developer/lens
git add .
git status
```

Review the staged files. You should see:
- `Lens.xcodeproj/` (all project files)
- `LensCore/` (stub Swift file + 6 subdirs with `.gitkeep`)
- `LensCoreTests/`
- `LensUI/`
- `LensIOS/`
- `LensMac/`
- `docs/superpowers/2026-04-10-lens-agent-orientation.md` (updated)
- `docs/superpowers/plans/2026-04-10-lens-phase-0-bootstrap.md` (this file)

> **Note:** Check `git status` for anything unexpected (e.g. DerivedData). If you see paths that belong in `.gitignore`, add them before committing.

- [ ] **Step 2: Commit**

```bash
git commit -m "feat(phase-0): Xcode project bootstrap — four targets, LensCore scaffold"
```

Expected: commit succeeds with a summary of added files.

---

## Phase 0 exit criteria

Before declaring Phase 0 done, confirm all of the following:

- [ ] `Lens.xcodeproj` exists at the repo root and opens in Xcode without errors.
- [ ] Four targets appear under TARGETS: `LensIOS`, `LensMac`, `LensCore`, `LensUI`.
- [ ] `LensCoreTests` unit test target exists, linked to `LensCore`.
- [ ] `LensCore` and `LensUI` list both iOS and macOS in Supported Destinations.
- [ ] `LensCore` and `LensUI` appear in Frameworks, Libraries, and Embedded Content for both `LensIOS` and `LensMac`.
- [ ] All four app/framework targets have deployment targets set: iOS 26.0 / macOS 26.0.
- [ ] `LensCore/` subdirectories (`Models/`, `Persistence/`, `Feeds/`, `Events/`, `Theme/`, `Routing/`) exist on disk and are committed.
- [ ] `agent-orientation.md` **Current state** section reflects Phase 0 completion.
- [ ] `git log` shows two clean commits (baseline + project bootstrap).

Phase 1 entry criterion (build verification on all three destinations) is explicitly **not** part of Phase 0 — that is Phase 1's job.

---

## What's next

**Phase 1** — Hello world and verification:
- Human: clean build (⇧⌘K) + ⌘B for `LensIOS` on iOS Simulator, on a physical device, and `LensMac` on Mac.
- Agent: adds trivial per-platform visible UI if needed (a label or placeholder) to confirm the view hierarchy renders on each destination.
- Exit: you can repeat the clean/build/run cycle confidently across all three destination types.
