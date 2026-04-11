// AddonInstaller.swift — macOS-only pipeline: download → SHA-256 verify →
// unzip → parse manifest → register → emit event.
//
// Remote addon install is macOS-only in v1 (spec §5.1, §5.3).
// On iOS, `AddonInstaller` does not compile; use `#if os(macOS)` guards at
// any call site if you need to check availability.
//
// Install flow:
//   1. Download zip bytes via URLSession
//   2. Verify SHA-256 of downloaded bytes against caller-supplied expected hash
//   3. Write zip to a temp file
//   4. Extract to a temp staging directory using /usr/bin/unzip
//   5. Parse manifest.json from the staging root
//   6. Validate manifest (isValid check)
//   7. Move staging directory to permanent install path in Application Support
//   8. Build AddonRecord and register with AddonRegistry.shared
//   9. Emit .addonInstalled or .addonInstallFailed on EventBus.shared
#if os(macOS)
import CryptoKit
import Foundation

public actor AddonInstaller {

    // MARK: - Shared instance

    /// App-wide shared installer. Use a fresh `AddonInstaller()` in unit tests
    /// if you need to inject a custom URLSession or isolate registry state.
    public static let shared = AddonInstaller()

    // MARK: - Init

    public init() {}

    // MARK: - Public install API

    /// Downloads and installs an addon from a zip URL.
    ///
    /// - Parameters:
    ///   - zipURL: Direct HTTPS URL to the addon `.zip` file.
    ///   - expectedSHA256: Lowercase hex-encoded SHA-256 of the zip bytes.
    ///     The caller obtains this from the addon author's distribution page.
    /// - Returns: The registered `AddonRecord` on success.
    /// - Throws: `AddonError` describing the failure stage.
    @discardableResult
    public func install(from zipURL: URL, expectedSHA256: String) async throws -> AddonRecord {
        var addonId: String? = nil

        do {
            // 1. Download
            let zipData = try await download(from: zipURL)

            // 2. Verify SHA-256
            let actualHash = Self.sha256Hex(of: zipData)
            guard actualHash == expectedSHA256.lowercased() else {
                throw AddonError.sha256Mismatch(
                    expected: expectedSHA256.lowercased(),
                    actual: actualHash
                )
            }

            // 3. Write to temp file
            let tmpDir = FileManager.default.temporaryDirectory
            let tmpZip = tmpDir.appending(path: UUID().uuidString + ".zip")
            try zipData.write(to: tmpZip)
            defer { try? FileManager.default.removeItem(at: tmpZip) }

            // 4. Extract to staging directory
            let stagingDir = tmpDir.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try await extractZip(at: tmpZip, to: stagingDir)
            defer { try? FileManager.default.removeItem(at: stagingDir) }

            // 5 & 6. Parse and validate manifest
            let manifest = try parseManifest(in: stagingDir)
            guard manifest.isValid else {
                throw AddonError.invalidManifest
            }
            addonId = manifest.identifier

            // 7. Move to permanent install directory
            let installDir = try Self.installDirectory(for: manifest.identifier)
            if FileManager.default.fileExists(atPath: installDir.path) {
                try FileManager.default.removeItem(at: installDir)
            }
            // Copy rather than move: staging dir is temp; copy is safer across volumes.
            try FileManager.default.copyItem(at: stagingDir, to: installDir)

            // 8. Build and register record
            let record = AddonRecord(
                manifest: manifest,
                installedAt: Date(),
                installDirectoryURL: installDir
            )
            try await AddonRegistry.shared.register(record)

            // 9. Emit success event
            await EventBus.shared.emit(.addonInstalled(addonId: manifest.identifier))

            return record

        } catch let addonErr as AddonError {
            // Emit failure event before re-throwing so observers (UI, analytics) know what happened.
            await EventBus.shared.emit(
                .addonInstallFailed(addonId: addonId, error: addonErr.localizedDescription)
            )
            throw addonErr
        } catch {
            await EventBus.shared.emit(
                .addonInstallFailed(addonId: nil, error: error.localizedDescription)
            )
            throw error
        }
    }

    // MARK: - SHA-256 helper (public for testing)

    /// Returns the lowercase hex-encoded SHA-256 digest of `data`.
    ///
    /// This is the canonical integrity check used before accepting any addon zip.
    /// Exposed as `public static` so tests can call it without instantiating the actor.
    public static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Install directory

    /// Returns the permanent install directory for an addon identifier,
    /// creating intermediate directories as needed.
    ///
    /// Path: ~/Library/Application Support/Lens/Addons/<identifier>/
    public static func installDirectory(for identifier: String) throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AddonError.installDirectoryUnavailable
        }
        let dir = appSupport.appending(
            path: "Lens/Addons/\(identifier)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Private helpers

    private func download(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode
        // Treat anything outside 2xx as a failure — surface HTTP status for debugging.
        guard let status, (200..<300).contains(status) else {
            throw AddonError.downloadFailed(
                url: url,
                statusCode: (response as? HTTPURLResponse)?.statusCode
            )
        }
        return data
    }

    private func extractZip(at zipURL: URL, to destinationURL: URL) async throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        // Use /usr/bin/unzip (always present on macOS) to avoid a zip library dependency.
        // -q: quiet, -o: overwrite without prompting, -d: destination.
        // The zip must have no top-level directory — files at the archive root land
        // directly in destinationURL. See docs/reference-addon/README.md for packaging.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", "-o", zipURL.path, "-d", destinationURL.path]
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: AddonError.extractionFailed(terminationStatus: proc.terminationStatus)
                    )
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseManifest(in directory: URL) throws -> AddonManifest {
        let manifestURL = directory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw AddonError.manifestNotFound
        }
        let data = try Data(contentsOf: manifestURL)
        do {
            return try JSONDecoder().decode(AddonManifest.self, from: data)
        } catch {
            throw AddonError.manifestDecodingFailed(underlying: error.localizedDescription)
        }
    }
}
#endif
