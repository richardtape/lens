# Lens — Build strategy & Xcode workflow

**Status:** Active  
**Last updated:** 2026-04-10  
**Audience:** human drivers (Xcode / devices), coding agents, future contributors  
**Related:** [Product spec](./2026-04-09-lens-design.md) · [Build phases](./2026-04-10-lens-build-phases.md) · [Code rules for agents](../2026-04-10-lens-code-rules-for-agents.md)

---

## 1. Purpose

Lens is a native **iOS + macOS** app (see product spec). **Implementation code** is edited in this repo and code editor (often with agent assistance). **Building, running, signing, and on-device testing** happen in **Xcode** on a Mac.

This document defines that split so everyone works the same way and verification steps are predictable.

---

## 2. Roles

| Role | Where | Responsibility |
|------|--------|----------------|
| **Human driver** | Xcode | Create/open the project, choose schemes & destinations, **build** (⌘B), **run** (⌘R), manage signing & devices, report compile/runtime issues back to agents |
| **Agents / Cursor** | Repo + editor | Swift/SwiftUI and project file edits, SPM manifest changes, documentation; **cannot** press Xcode’s Build button on behalf of the human driver |

**Rule of thumb:** If it requires the Simulator, a physical device, or Apple’s build tools, the **human driver** runs it; agents prepare the code and tell the human driver **exactly** what to tap and what to look for.

---

## 3. Standard verification reminder (for agents)

Whenever an agent needs the human driver to confirm the app compiles or behaves correctly, the agent should include a short reminder like this (copy/paste friendly):

> **In Xcode:** Select the correct **scheme** and **destination** (Simulator or a connected device), then **Build** with **⌘B**, then **Run** with **⌘R**. Share any **build errors** (full message + file/line) or **runtime** issues (actions taken, expected result, actual result).

### Keyboard shortcuts (Xcode)

| Action | Shortcut | Notes |
|--------|-----------|--------|
| **Build** | **⌘B** | Compiles the active scheme. |
| **Run** | **⌘R** | Build if needed, then launch on the selected destination. |
| **Clean build folder** | **⇧⌘K** | Use when switching configs or after strange linker/cache issues. |
| **Stop** | **⌘.** | Stop the running app. |

*(Some people use **⌘⇧B** from other tools; in Xcode the everyday **build** shortcut is **⌘B**.)*

---

## 4. Xcode & platform versions

- **Xcode:** **26.3** (baseline documented for this repo). Agents should assume modern Swift/SwiftUI APIs available for **iOS 26** and **macOS 26** targets, per the product spec.
- If an agent suggests APIs that require a **newer** Xcode than 26.3, they must call that out so the human driver can update Xcode before trying again.

---

## 5. Opening the project (once it exists)

1. In Finder, open the folder that contains **`Lens.xcodeproj`** or **`Lens.xcworkspace`** (if the project adds CocoaPods or a workspace later—**SPM-only** projects often use `.xcodeproj` only).
2. Double-click the project/workspace, or in Xcode: **File → Open…** (**⌘O**), select the project.

**Agents** should refer to paths relative to the repo root (e.g. `Lens.xcodeproj`) so the human driver can find files quickly.

---

## 6. Schemes, targets, and destinations

### 6.1 Schemes

- The **scheme** selects *which target* builds and *which configuration* (Debug/Release) runs.
- **Product → Scheme** (or the scheme menu in the toolbar) — choose **Lens iOS** vs **Lens macOS** (exact names TBD when the project is created).

### 6.2 Destinations

- **iOS Simulator:** Pick a simulator device (e.g. iPhone) from the **destination** menu next to the scheme.
- **Physical iPhone/iPad:** Connect via USB or same-network debugging; select the device by name. First-time setup requires **trust** on the device and valid **signing** (below).

### 6.3 Multi-target layout (from product spec)

The project intends **shared modules + thin app shells** (names may vary):

- **LensCore** — models, persistence, networking, shared logic  
- **LensUI** — shared SwiftUI  
- **LensIOS** / **LensMac** — app entry points and platform-specific glue  

Agents should add new code to the **lowest** layer that makes sense (prefer shared **LensCore** / **LensUI** over duplicating in app targets).

---

## 7. Signing, capabilities, and App Groups

### 7.1 Signing (devices)

1. Select the **project** in the navigator, then the **app target** (iOS or macOS).
2. **Signing & Capabilities** tab.
3. Enable **Automatically manage signing** (typical for personal/small team).
4. Choose the **Team**. Xcode creates provisioning profiles as needed.

If signing fails, copy the **exact** error from the Issue navigator and the signing panel—agents need that text.

### 7.2 App Group (required by spec)

The product spec requires SwiftData in an **App Group** container (e.g. `group.com.richardtape.lens`) from day one.

**Steps (when the capability is added):**

1. Select the **app target** → **Signing & Capabilities**.
2. **+ Capability** → **App Groups**.
3. Check the group identifier (e.g. `group.com.richardtape.lens`) or add it if missing.
4. Repeat for **each** target that must share the store (iOS app, Mac app, and later extensions). **LensCore** may need the group only if code signing for embedded frameworks requires it—agents will document the exact checklist when the project exists.

---

## 8. Dependencies (Swift Package Manager)

This project defaults to **Swift Package Manager (SPM)** integrated in Xcode.

### 8.1 Add a package via Xcode UI

1. **File → Add Package Dependencies…**
2. Paste the package **URL** (GitHub or other git host).
3. Choose **version rule** (e.g. “Up to Next Major” from a tag).
4. Add the package **product** to the correct target (**LensCore** vs app target—agents should say which).

### 8.2 What to commit

- **SPM:** `Package.resolved` (if present) should be committed so everyone resolves the same versions.
- Agents should list new packages in the PR/summary: **name, URL, version rule, which target**, and **why**.

### 8.3 Forked or local packages

If a package is vendored under `Vendor/` or a local path dependency is used, this doc should gain a one-line pointer—agents update that section when it happens.

---

## 9. Device testing workflow

1. Connect the device; unlock it; trust the computer if prompted.
2. In Xcode, select the **device** as run destination.
3. **Run** (**⌘R**). If Xcode prompts for **developer mode** (iOS) or **notarized** issues (macOS), follow the on-screen steps.
4. For quick iteration, the **Simulator** is fine for UI; **physical devices** are required for real performance, Dynamic Type, haptics, and background behavior.

**Feedback loop:** When reporting issues, include **platform** (iOS/macOS), **device or simulator model**, **OS version**, and **steps to reproduce**.

---

## 10. What “done” means for a change

Before merging or moving on:

1. The **human driver** can **build** (**⌘B**) with zero errors for the affected scheme(s).
2. The **human driver** **runs** (**⌘R**) on at least one relevant destination (simulator and/or device, per the change).
3. Agents have not introduced unexplained warnings—if warnings are unavoidable, they should be called out in the summary.

---

## 11. Repository and Xcode layout (expectations)

- Source lives under the repo; Xcode project references files by path—**do not** duplicate the app outside the repo without updating references.
- Prefer **feature folders** inside targets (e.g. `LensCore/Feeds/…`) as the project grows; agents should match existing structure.

---

## 12. When this doc changes

Update this file when:

- Xcode or OS **minimum** versions change  
- **CI** is added that builds outside Xcode (document the command and who runs it)  
- **Dependency** strategy changes (e.g. add CocoaPods—would be a deliberate decision)  
- **Scheme/target names** are finalized after project creation  

---

## 13. Quick reference — agent checklist when requesting a human build

- [ ] Which **scheme** (iOS vs Mac)  
- [ ] Which **destination** (simulator model or a physical device name)  
- [ ] Whether **clean** (**⇧⌘K**) is worth trying  
- [ ] What to **click** or **type** to verify the fix  
- [ ] Reminder: **⌘B** then **⌘R**  

---

*This document is the companion to the code-style rules: [Code rules for agents](../2026-04-10-lens-code-rules-for-agents.md).*
