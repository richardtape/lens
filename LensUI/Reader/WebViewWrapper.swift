// WebViewWrapper.swift — WKWebView bridge for SwiftUI (iOS and macOS).
//
// The Coordinator holds the navigation delegate and tracks the last-loaded
// HTML string to avoid redundant reloads on routine SwiftUI rerenders.
//
// Security:
//   allowsContentJavaScript = false  — defence-in-depth with HTMLSanitizer.
//   All link activations are intercepted and forwarded via onExternalLink;
//   the web view never navigates away from the injected HTML page.
//
// Appearance:
//   iOS: overrideUserInterfaceStyle syncs with AppearanceOverride preference.
//   macOS: webView.appearance is set to aqua / darkAqua / nil (system).
import SwiftUI
import WebKit
import LensCore

// MARK: - Shared coordinator (iOS + macOS)

/// WKNavigationDelegate implementation shared by both platform wrappers.
final class WebViewCoordinator: NSObject, WKNavigationDelegate {

    /// Called when the user taps a link. The web view cancels its own navigation;
    /// the host view is responsible for opening the URL appropriately.
    var onExternalLink: ((URL) -> Void)?

    /// Tracks the last HTML string loaded so updateUIView/updateNSView can skip
    /// redundant `loadHTMLString` calls when nothing has changed.
    var lastLoadedHTML: String = ""

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            return .allow
        }
        onExternalLink?(url)
        return .cancel
    }
}

// MARK: - WKWebViewConfiguration factory

private func makeWebViewConfiguration() -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    // Disable JavaScript — feed bodies should not require it.
    config.defaultWebpagePreferences.allowsContentJavaScript = false
    config.allowsAirPlayForMediaPlayback = false
    return config
}

// MARK: - iOS / iPadOS

#if os(iOS)
/// SwiftUI wrapper for WKWebView on iOS and iPadOS.
struct WebViewWrapper: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    let appearanceOverride: AppearanceOverride
    let onExternalLink: (URL) -> Void

    func makeCoordinator() -> WebViewCoordinator { WebViewCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: makeWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        // Let Safe Area insets adjust the scroll view automatically.
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        // Prevent swipe-back through the web history — we manage navigation ourselves.
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onExternalLink = onExternalLink
        applyAppearance(to: webView)
        guard context.coordinator.lastLoadedHTML != html else { return }
        context.coordinator.lastLoadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func applyAppearance(to webView: WKWebView) {
        switch appearanceOverride {
        case .system: webView.overrideUserInterfaceStyle = .unspecified
        case .light:  webView.overrideUserInterfaceStyle = .light
        case .dark:   webView.overrideUserInterfaceStyle = .dark
        @unknown default: webView.overrideUserInterfaceStyle = .unspecified
        }
    }
}

// MARK: - macOS

#else
/// SwiftUI wrapper for WKWebView on macOS.
struct WebViewWrapper: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let appearanceOverride: AppearanceOverride
    let onExternalLink: (URL) -> Void

    func makeCoordinator() -> WebViewCoordinator { WebViewCoordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: makeWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onExternalLink = onExternalLink
        applyAppearance(to: webView)
        guard context.coordinator.lastLoadedHTML != html else { return }
        context.coordinator.lastLoadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func applyAppearance(to webView: WKWebView) {
        // Override the web view's effective appearance to honour the user's
        // explicit light/dark preference independent of the system setting.
        switch appearanceOverride {
        case .system: webView.appearance = nil          // follows window / system
        case .light:  webView.appearance = NSAppearance(named: .aqua)
        case .dark:   webView.appearance = NSAppearance(named: .darkAqua)
        @unknown default: webView.appearance = nil
        }
    }
}
#endif
