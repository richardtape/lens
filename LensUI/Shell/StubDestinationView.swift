// StubDestinationView.swift — Shared placeholder for tabs/destinations not yet built.
// Intentionally minimal — no "coming soon" copy; this is internal scaffolding.
import SwiftUI

struct StubDestinationView: View {
    let name: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(name, systemImage: symbol)
    }
}

#Preview {
    StubDestinationView(name: "Feeds", symbol: "antenna.radiowaves.left.and.right")
}
