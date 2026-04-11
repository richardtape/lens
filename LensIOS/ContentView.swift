import SwiftUI

// Phase 1 placeholder — replaced by the real Timeline view in Phase 3.
// The platform label lets the human driver confirm the correct target
// launched on each destination (Simulator, device, Mac).
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Lens")
                .font(.largeTitle.bold())
            Text("iOS · Build verification")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
