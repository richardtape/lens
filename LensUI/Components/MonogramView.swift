// MonogramView.swift — Feed icon: favicon if available, monogram if not.
//
// Shows the first letter of the feed name on a tinted accent background when
// no favicon URL is available (or while the favicon is loading).
// Favicons are loaded asynchronously and cached by AsyncImage.
// The whole view dims to 0.3 opacity when the item is read (caller's
// responsibility — MonogramView itself is always full-opacity for composability).
import SwiftUI
import LensCore

struct MonogramView: View {
    let feed: Feed?
    let accentColor: Color

    var body: some View {
        if let iconRef = feed?.iconRef, let url = URL(string: iconRef) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                default:
                    monogram
                }
            }
        } else {
            monogram
        }
    }

    // Letter + tinted background used when there is no usable favicon.
    private var monogram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor.opacity(0.2))
            Text(String(feed?.displayName.first ?? "?").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }
}

// MARK: - Preview

#Preview("Monogram — no favicon") {
    let color = Color(hex: "#4A90D9")
    MonogramView(feed: nil, accentColor: color)
        .frame(width: 17, height: 17)
        .padding()
}
