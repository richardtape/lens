import SwiftUI

// Phase 1 placeholder — replaced by the real Timeline view in Phase 3.
// Sets a minimum window size so the macOS window isn't a tiny square.
// The platform label confirms the correct target launched on Mac.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Lens")
                .font(.largeTitle.bold())
            Text("macOS · Build verification")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        // Minimum size prevents the window collapsing to nothing on launch.
        .frame(minWidth: 400, minHeight: 280)
    }
}

#Preview {
    ContentView()
}
