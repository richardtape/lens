// AddonError.swift — Typed errors for every failure point in the addon pipeline.
//
// Each case maps to one stage: download, integrity check, extraction, manifest
// parsing, validation, or registration. Surface these inline — no modal dialogs
// (spec §8 reliability requirement).
import Foundation

public enum AddonError: Error, Equatable, Sendable {
    /// HTTP download failed. `statusCode` is nil if the error was non-HTTP (e.g. network timeout).
    case downloadFailed(url: URL, statusCode: Int?)
    /// SHA-256 digest of the downloaded zip does not match the provided expected value.
    case sha256Mismatch(expected: String, actual: String)
    /// `/usr/bin/unzip` exited with a non-zero status.
    case extractionFailed(terminationStatus: Int32)
    /// No manifest.json was found at the root of the extracted directory.
    case manifestNotFound
    /// manifest.json was found but could not be decoded as AddonManifest.
    case manifestDecodingFailed(underlying: String)
    /// Manifest decoded but failed `isValid` check (missing required fields).
    case invalidManifest
    /// An addon with this identifier is already registered.
    case duplicateIdentifier(String)
    /// The Application Support directory could not be resolved.
    case installDirectoryUnavailable
}

extension AddonError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let url, let code):
            if let code {
                return "Download failed for \(url.absoluteString) (HTTP \(code))"
            }
            return "Download failed for \(url.absoluteString)"
        case .sha256Mismatch(let expected, let actual):
            return "Integrity check failed — expected \(expected), got \(actual)"
        case .extractionFailed(let status):
            return "ZIP extraction failed with exit code \(status)"
        case .manifestNotFound:
            return "No manifest.json found in addon package"
        case .manifestDecodingFailed(let msg):
            return "Failed to parse manifest.json: \(msg)"
        case .invalidManifest:
            return "Addon manifest is missing required fields"
        case .duplicateIdentifier(let id):
            return "An addon with identifier '\(id)' is already registered"
        case .installDirectoryUnavailable:
            return "Could not access Application Support directory"
        }
    }
}
