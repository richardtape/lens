# Reference addon — Lens Dark Pro

This directory contains the source files for the Phase 2D reference theme addon.
Its purpose is to prove the end-to-end macOS addon pipeline (download → SHA-256
verify → unzip → manifest parse → register).

## Files

| File | Role |
|------|------|
| `manifest.json` | Addon manifest (identifier, capabilities, asset list) |
| `theme.css` | CSS that overrides `--lens-*` custom properties |

## Packaging and hosting (human driver steps)

Run these once to create the distributable zip and get its hash.

### 1. Create the zip

```bash
cd /Users/rich/Developer/lens/docs/reference-addon
zip -j addon.zip manifest.json theme.css
```

`-j` (junk paths) ensures `manifest.json` and `theme.css` are at the **root** of
the archive with no subdirectory. `AddonInstaller` expects this layout.

### 2. Compute SHA-256

```bash
shasum -a 256 addon.zip
```

Copy the 64-character hex string. You will need it when calling `AddonInstaller.install(from:expectedSHA256:)`.

### 3. Host the zip

Upload `addon.zip` to your HTTPS server at a stable URL, e.g.:

```
https://addons.richardtape.com/reference-theme/1.0.0/addon.zip
```

Keep the URL and SHA-256 together in your notes — both are required to install.

## Running the integration test

Once the zip is hosted, verify the full pipeline from Swift:

```swift
// Paste into a macOS Playground or a temporary LensMac debug action.
import LensCore

let zipURL = URL(string: "https://addons.richardtape.com/reference-theme/1.0.0/addon.zip")!
let sha256  = "<paste the 64-char hex from shasum output>"

let record = try await AddonInstaller.shared.install(from: zipURL, expectedSHA256: sha256)
print("Installed: \(record.manifest.displayName) @ \(record.installDirectoryURL.path)")

let all = await AddonRegistry.shared.allAddons
print("Registry count: \(all.count)")
```

Expected output:
```
Installed: Lens Dark Pro @ /Users/<you>/Library/Containers/com.richardtape.lens.LensMac/Data/Library/Application Support/Lens/Addons/com.richardtape.lens.reference-theme
Registry count: 1
```

> The path goes through `Library/Containers/…` because LensMac runs in the macOS App Sandbox.
> `FileManager.urls(for: .applicationSupportDirectory)` resolves to the container automatically.

The EventBus will have emitted `.addonInstalled(addonId: "com.richardtape.lens.reference-theme")`.

## Updating the addon

Increment `version` in `manifest.json`, re-zip, re-host under a new URL, recompute SHA-256.
The identifier `com.richardtape.lens.reference-theme` is stable.
