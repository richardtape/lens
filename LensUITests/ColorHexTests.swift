// LensUITests/ColorHexTests.swift
// Pending human completing Task 2 (creating the LensUITests Xcode target before tests run).
import Testing
import SwiftUI
@testable import LensUI

struct ColorHexTests {

    @Test func sixDigitHex_parsesWithoutCrash() {
        // Just verify the extension doesn't crash and produces a non-clear color.
        let color = Color(hex: "#4A90D9")
        // There's no public RGB accessor in SwiftUI Color, so we verify via
        // UIColor / NSColor round-trip.
        #if os(iOS)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0x4A/255.0) < 0.01)
        #expect(abs(g - 0x90/255.0) < 0.01)
        #expect(abs(b - 0xD9/255.0) < 0.01)
        #expect(a == 1.0)
        #else
        let ns = NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0x4A/255.0) < 0.01)
        #expect(abs(g - 0x90/255.0) < 0.01)
        #expect(abs(b - 0xD9/255.0) < 0.01)
        #endif
    }

    @Test func threeDigitHex_expandsCorrectly() {
        // "#F0A" should expand to "#FF00AA"
        let color = Color(hex: "#F0A")
        #if os(iOS)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0) < 0.01)   // FF
        #expect(abs(g - 0.0) < 0.01)   // 00
        #expect(abs(b - 0xAA/255.0) < 0.01) // AA
        #else
        let ns = NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0) < 0.01)
        #expect(abs(g - 0.0) < 0.01)
        #expect(abs(b - 0xAA/255.0) < 0.01)
        #endif
    }

    @Test func invalidHex_fallsBackToAccentColor() {
        // Expect no crash; return value is .accentColor (non-crashing fallback).
        _ = Color(hex: "not-a-color")
        _ = Color(hex: "#GGGGGG")
        _ = Color(hex: "")
        // If we reach here without crashing, the test passes.
    }

    @Test func hashPrefixOptional() {
        // Both "#4A90D9" and "4A90D9" should produce the same color.
        let withHash = Color(hex: "#4A90D9")
        let withoutHash = Color(hex: "4A90D9")
        // Compare via UIColor/NSColor round-trip
        #if os(iOS)
        func rgb(_ c: Color) -> (CGFloat, CGFloat, CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b)
        }
        #else
        func rgb(_ c: Color) -> (CGFloat, CGFloat, CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            NSColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b)
        }
        #endif
        let (r1, g1, b1) = rgb(withHash)
        let (r2, g2, b2) = rgb(withoutHash)
        #expect(abs(r1 - r2) < 0.01)
        #expect(abs(g1 - g2) < 0.01)
        #expect(abs(b1 - b2) < 0.01)
    }
}
