// NewItemsBannerView.swift — Glass pill shown when new items arrive in the background.
//
// Anchored via safeAreaInset(edge: .top) in TimelineView so it floats above
// the list without displacing content. Tap scrolls to top and dismisses.
// GlassEffectContainer groups the capsule effect for GPU performance
// (Apple recommends grouping Liquid Glass effects — see adopting-liquid-glass.md).
import SwiftUI

struct NewItemsBannerView: View {
    let banner: NewItemsBanner
    let onTap: () -> Void

    var body: some View {
        GlassEffectContainer {
            Button(action: onTap) {
                Label("↑ \(banner.count) new \(banner.count == 1 ? "item" : "items")", systemImage: "arrow.up")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview {
    ZStack(alignment: .top) {
        #if os(iOS)
        Color(.systemGroupedBackground).ignoresSafeArea()
        #else
        Color(.windowBackgroundColor).ignoresSafeArea()
        #endif
        NewItemsBannerView(banner: NewItemsBanner(count: 12)) {}
            .padding(.top, 20)
    }
}
